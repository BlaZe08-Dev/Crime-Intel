import '../audit/audit_logger.dart';
import '../audit/models/log_entry.dart';
import '../core/errors/app_exceptions.dart';
import '../core/security/actor_context.dart';
import '../llm/llm_client.dart';
import '../models/case_note.dart';
import '../rag/rag_service.dart';
import 'action_guard.dart';

/// A completed assistant turn, with everything the UI needs to render it
/// honestly: the answer, what it was based on, and whether it was grounded.
class AssistantReply {
  final String answer;

  /// Records retrieved for this turn. Rendered as citations.
  final List<RetrievedSource> sources;

  /// False when retrieval found nothing and the refusal was returned instead
  /// of a generated answer.
  final bool grounded;

  /// Set when the assistant saved a case note this turn.
  final CaseNote? createdNote;

  /// Set when the assistant asked for something the guard refused.
  final String? refusal;

  final Duration latency;
  final String? model;

  const AssistantReply({
    required this.answer,
    required this.sources,
    required this.grounded,
    required this.latency,
    this.createdNote,
    this.refusal,
    this.model,
  });
}

/// Orchestrates a chat turn: retrieve, ground, generate, and route any tool
/// call through [ActionGuard].
///
/// This is the only class that holds both an [LlmClient] and an
/// [ActionGuard]. It deliberately does **not** hold a `CrimeRepository`, so
/// there is no record-mutating call reachable from the assistant's execution
/// path at all.
class AssistantService {
  final RagService _rag;
  final LlmClient _llm;
  final ActionGuard _guard;
  final AuditLogger _audit;

  AssistantService({
    required RagService rag,
    required LlmClient llm,
    required ActionGuard guard,
    required AuditLogger audit,
  })  : _rag = rag,
        _llm = llm,
        _guard = guard,
        _audit = audit;

  /// Answers [question] from the indexed database.
  ///
  /// [context] is the investigator asking. The assistant's own actions are
  /// attributed separately, inside the guard.
  Future<AssistantReply> ask({
    required InvestigatorContext context,
    required String question,
    String? scopeCriminalId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final retrieval = await _rag.retrieve(
      question,
      scopeCriminalId: scopeCriminalId,
    );

    // Grounding is enforced here, before inference. Asking a model to admit
    // ignorance is unreliable; not calling it at all is not.
    if (retrieval.isEmpty) {
      stopwatch.stop();
      await _logQuery(
        context: context,
        question: question,
        sourceIds: const [],
        grounded: false,
        latency: stopwatch.elapsed,
      );
      return AssistantReply(
        answer: RagService.notInDatabaseAnswer,
        sources: const [],
        grounded: false,
        latency: stopwatch.elapsed,
      );
    }

    final messages = <LlmMessage>[
      const LlmMessage.system(RagService.systemPrompt),
      LlmMessage.user(_rag.buildGroundedPrompt(
        question: question,
        sources: retrieval.sources,
      )),
    ];

    try {
      final response = await _llm.chat(
        messages: messages,
        tools: ActionGuard.exposedTools,
      );

      if (!response.hasToolCalls) {
        stopwatch.stop();
        await _logQuery(
          context: context,
          question: question,
          sourceIds: retrieval.sourceIds,
          grounded: true,
          latency: stopwatch.elapsed,
          model: response.model,
        );
        return AssistantReply(
          answer: response.content.isEmpty
              ? RagService.notInDatabaseAnswer
              : response.content,
          sources: retrieval.sources,
          grounded: true,
          latency: stopwatch.elapsed,
          model: response.model,
        );
      }

      // Awaited rather than returned directly: a bare `return future` inside
      // this try would escape the catch below, so an LLM failure during the
      // tool turn would bypass the failure logging.
      return await _runToolTurn(
        context: context,
        question: question,
        retrieval: retrieval,
        priorMessages: messages,
        response: response,
        stopwatch: stopwatch,
      );
    } on AppException catch (error) {
      stopwatch.stop();
      await _logQuery(
        context: context,
        question: question,
        sourceIds: retrieval.sourceIds,
        grounded: false,
        latency: stopwatch.elapsed,
        failure: error.runtimeType.toString(),
      );
      rethrow;
    }
  }

  /// Handles a turn where the model asked to use its one tool.
  Future<AssistantReply> _runToolTurn({
    required InvestigatorContext context,
    required String question,
    required RetrievalResult retrieval,
    required List<LlmMessage> priorMessages,
    required LlmChatResponse response,
    required Stopwatch stopwatch,
  }) async {
    CaseNote? created;
    String? refusal;
    final toolResults = <LlmMessage>[];

    for (final call in response.toolCalls) {
      final outcome = await _guard.dispatch(call);
      switch (outcome) {
        case ActionAllowed(note: final note):
          created = note;
          toolResults.add(LlmMessage.toolResult(
            tool: call.name,
            content: 'Case note ${note.id} saved against ${note.criminalId}.',
          ));
        case ActionDenied(reason: final reason):
          refusal = reason;
          toolResults.add(LlmMessage.toolResult(
            tool: call.name,
            content: 'REFUSED: $reason',
          ));
      }
    }

    // Give the model the tool outcome so it can phrase a final answer.
    final followUp = await _llm.chat(
      messages: [
        ...priorMessages,
        LlmMessage.assistant(response.content),
        ...toolResults,
      ],
      tools: ActionGuard.exposedTools,
    );

    stopwatch.stop();
    await _logQuery(
      context: context,
      question: question,
      sourceIds: retrieval.sourceIds,
      grounded: true,
      latency: stopwatch.elapsed,
      model: followUp.model,
      toolOutcome: created != null ? 'CASE_NOTE_CREATED' : 'DENIED',
    );

    final answer = followUp.content.trim().isNotEmpty
        ? followUp.content
        : (created != null
            ? 'Case note ${created.id} saved against ${created.criminalId}.'
            : (refusal ?? RagService.notInDatabaseAnswer));

    return AssistantReply(
      answer: answer,
      sources: retrieval.sources,
      grounded: true,
      createdNote: created,
      refusal: refusal,
      latency: stopwatch.elapsed,
      model: followUp.model,
    );
  }

  /// Writes the `LLM_QUERY` audit entry required by `docs/Rules.md` §3.
  ///
  /// The question text goes into the hashed payload rather than a stored
  /// column — the chain proves what was asked without the log itself becoming
  /// a second copy of the investigation.
  Future<void> _logQuery({
    required InvestigatorContext context,
    required String question,
    required List<String> sourceIds,
    required bool grounded,
    required Duration latency,
    String? model,
    String? failure,
    String? toolOutcome,
  }) {
    return _audit.log(
      context: context,
      action: LogAction.LLM_QUERY,
      targetType: 'AssistantQuery',
      targetId: sourceIds.isEmpty ? 'NO_MATCH' : sourceIds.first,
      payload: {
        'question': question,
        'grounded': grounded,
        'sourceIds': sourceIds,
        'latencyMs': latency.inMilliseconds,
        if (model != null) 'model': model,
        if (failure != null) 'failure': failure,
        if (toolOutcome != null) 'toolOutcome': toolOutcome,
      },
    );
  }
}
