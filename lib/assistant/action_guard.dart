import '../audit/audit_logger.dart';
import '../audit/models/log_entry.dart';
import '../core/security/actor_context.dart';
import '../data/repositories/crime_repository.dart';
import '../llm/llm_client.dart';
import '../models/case_note.dart';

/// Result of putting a model-requested action through the guard.
sealed class GuardOutcome {
  const GuardOutcome();
}

/// The action was allowed and performed.
final class ActionAllowed extends GuardOutcome {
  final CaseNote note;
  const ActionAllowed(this.note);
}

/// The action was refused. [reason] is written to be shown to the
/// investigator and fed back to the model as the tool result.
final class ActionDenied extends GuardOutcome {
  final String attemptedTool;
  final String reason;
  const ActionDenied({required this.attemptedTool, required this.reason});
}

/// The single chokepoint for everything the assistant is allowed to do
/// (`docs/Rules.md` §11, `docs/TechSpec.md` §7).
///
/// ## Why this is a real boundary and not a promise
///
/// Four independent things have to hold for the assistant to mutate a record,
/// and all four fail:
///
/// 1. **The advertised tool set has exactly one member.** [exposedTools] is
///    what gets sent to the model as its `tools` array, so `createCaseNote` is
///    the only function it is even aware of. There is no `updateRecord` or
///    `deleteImage` for it to name.
/// 2. **Dispatch is allow-listed, not deny-listed.** [dispatch] compares
///    against [caseNoteToolName] and refuses everything else, so a hallucinated
///    tool name fails closed rather than falling through.
/// 3. **This class cannot reach a mutation API.** Its dependency is typed
///    [CaseNoteSink] — an interface with one method. `CrimeRepository`'s
///    `updateCriminal`, `softDeleteCriminal`, `addMedia` and `attachNews` are
///    not on that interface, so they are not reachable from here at all.
/// 4. **It has no investigator privilege to borrow.** Those mutation methods
///    demand an [InvestigatorContext]; this class holds only
///    [AssistantContext], so such a call would not compile even if someone
///    widened the dependency in (3).
///
/// Refusals are logged, so an attempt to exceed the boundary is visible in the
/// audit chain rather than silently dropped.
class ActionGuard {
  /// The only actor this class ever acts as. Not a parameter, by design.
  static const AssistantContext _actor = AssistantContext();

  final CaseNoteSink _caseNotes;
  final AuditLogger _audit;

  ActionGuard({
    required CaseNoteSink caseNotes,
    required AuditLogger audit,
  })  : _caseNotes = caseNotes,
        _audit = audit;

  /// Name of the one permitted tool.
  static const String caseNoteToolName = 'createCaseNote';

  /// The complete capability surface advertised to the model.
  ///
  /// Adding an entry here grants the LLM a new power, so this list is the
  /// thing to look at in review. It must stay at length one unless the
  /// product constraint in `docs/PRD.md` §3.4 changes.
  static const List<LlmToolSpec> exposedTools = [
    LlmToolSpec(
      name: caseNoteToolName,
      description:
          'Save a short investigative case note against a criminal record. '
          'This is the only action you can perform. You cannot create, edit, '
          'or delete criminal records, images, or any other data.',
      parameters: {
        'type': 'object',
        'properties': {
          'criminalId': {
            'type': 'string',
            'description':
                'Id of the criminal the note belongs to, e.g. "C-001".',
          },
          'text': {
            'type': 'string',
            'description':
                'The note text. Must be grounded in the provided records.',
          },
        },
        'required': ['criminalId', 'text'],
      },
    ),
  ];

  /// Routes a model-requested tool call.
  ///
  /// Every path returns a [GuardOutcome]; nothing throws past this point, so
  /// a refusal becomes a message the investigator sees rather than a crash.
  Future<GuardOutcome> dispatch(LlmToolCall call) async {
    if (call.name != caseNoteToolName) {
      return _deny(
        call.name,
        'The assistant requested "${call.name}", which is not a permitted '
        'action. It may only create case notes.',
      );
    }

    final criminalId = call.arguments['criminalId'];
    final text = call.arguments['text'];

    if (criminalId is! String || criminalId.trim().isEmpty) {
      return _deny(call.name, 'The note was missing a valid criminal id.');
    }
    if (text is! String || text.trim().isEmpty) {
      return _deny(call.name, 'The note text was empty.');
    }

    try {
      final note = await _caseNotes.writeCaseNote(
        // Fixed actor: an assistant-written note is always filed as such.
        context: _actor,
        criminalId: criminalId.trim(),
        text: text.trim(),
      );
      return ActionAllowed(note);
    } catch (error) {
      return _deny(call.name, 'The note could not be saved: $error');
    }
  }

  /// Records a refused action in the audit chain, then reports it.
  ///
  /// Denials are logged because "the assistant tried to do X and was stopped"
  /// is exactly the evidence the boundary exists to produce.
  Future<ActionDenied> _deny(String tool, String reason) async {
    await _audit.log(
      context: _actor,
      action: LogAction.LLM_QUERY,
      targetType: 'ActionGuard',
      targetId: tool,
      payload: {
        'outcome': 'DENIED',
        'attemptedTool': tool,
        'reason': reason,
        'permittedTools': [caseNoteToolName],
      },
    );
    return ActionDenied(attemptedTool: tool, reason: reason);
  }
}
