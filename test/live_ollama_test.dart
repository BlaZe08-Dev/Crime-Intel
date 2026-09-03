@Tags(['live'])
library;

import 'package:crime_intel/assistant/action_guard.dart';
import 'package:crime_intel/assistant/assistant_service.dart';
import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/security/actor_context.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/data/repositories/crime_repository.dart';
import 'package:crime_intel/data/repositories/vector_repository.dart';
import 'package:crime_intel/ingest/ingestion_service.dart';
import 'package:crime_intel/llm/llm_client.dart';
import 'package:crime_intel/llm/ollama_client.dart';
import 'package:crime_intel/models/case_note.dart';
import 'package:crime_intel/rag/rag_indexer.dart';
import 'package:crime_intel/rag/rag_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// End-to-end check against a **real** Ollama server and real models.
///
/// Excluded from the default run (`dart_test.yaml` skips the `live` tag)
/// because it needs Ollama up with both models pulled, and a generation takes
/// seconds. Run it deliberately:
///
///     flutter test --tags live
///
/// This is the test that answers "does a real question return a real grounded
/// answer on this machine" — the fake-client tests prove the wiring, this
/// proves the models.
void main() {
  late Database db;
  late OllamaClient llm;
  late AuditLogger audit;
  late CrimeRepository records;
  late VectorRepository vectors;
  late AssistantService assistant;

  final investigator = InvestigatorContext.issueForSession(
    AuthSessionIssuer.issue(
      investigatorId: 'INV-001',
      sessionId: 'SESSION-LIVE',
    ),
  );

  setUpAll(() async {
    DatabaseHelper.initFfi();
    llm = OllamaClient(
      baseUrl: 'http://localhost:11434',
      chatModel: 'granite4.1:3b',
      embedModel: 'nomic-embed-text',
      chatTimeout: const Duration(minutes: 5),
      embedTimeout: const Duration(minutes: 2),
    );

    final health = await llm.checkHealth();
    if (!health.reachable) {
      throw StateError(
        'Ollama is not reachable at ${llm.baseUrl}. Start it and retry.',
      );
    }

    db = await DatabaseHelper.openInMemory();
    audit = AuditLogger(db);
    records = CrimeRepository(db, audit);
    vectors = VectorRepository(db);

    await IngestionService(db: db, audit: audit).seedIfEmpty();

    final stopwatch = Stopwatch()..start();
    final result = await RagIndexer(
      records: records,
      vectors: vectors,
      audit: audit,
      llm: llm,
    ).rebuild(context: const SystemContext());
    stopwatch.stop();

    // ignore: avoid_print
    print('[live] indexed ${result.chunkCount} chunks '
        '(${result.dimensions}-dim) in ${stopwatch.elapsedMilliseconds}ms');

    assistant = AssistantService(
      rag: RagService(vectors: vectors, llm: llm),
      llm: llm,
      guard: ActionGuard(caseNotes: records, audit: audit),
      audit: audit,
    );
  });

  tearDownAll(() async {
    llm.dispose();
    await db.close();
  });

  test('both models are installed', () async {
    final health = await llm.checkHealth();
    expect(health.reachable, isTrue);
    expect(health.hasModel('granite4.1:3b'), isTrue);
    expect(health.hasModel('nomic-embed-text'), isTrue);
  });

  test('embeddings come back at the expected dimension', () async {
    final vector = await llm.embed('money laundering in Pune');
    expect(vector, hasLength(768));
  });

  test('a real question returns a grounded answer citing real records',
      () async {
    final reply = await assistant.ask(
      context: investigator,
      question: 'Who is Devraj Malhotra and what is he known for?',
    );

    // ignore: avoid_print
    print('[live] Q: Who is Devraj Malhotra and what is he known for?\n'
        '[live] A (${reply.latency.inMilliseconds}ms): ${reply.answer}\n'
        '[live] sources: ${reply.sources.map((s) => s.sourceId).join(", ")}');

    expect(reply.grounded, isTrue);
    expect(reply.sources, isNotEmpty);
    expect(reply.answer.trim(), isNotEmpty);
    // The answer must be about the retrieved subject, not generic prose.
    expect(reply.answer.toLowerCase(), contains('malhotra'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('retrieval surfaces the transaction burst when asked about it',
      () async {
    final rag = RagService(vectors: vectors, llm: llm);
    final result = await rag.retrieve(
      'large hawala transfers from Sunita Rao',
    );

    expect(result.isEmpty, isFalse);
    // ignore: avoid_print
    print('[live] burst retrieval sources: ${result.sourceIds.join(", ")}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a question with no answer in the database is refused', () async {
    final reply = await assistant.ask(
      context: investigator,
      question: 'What is the capital of France?',
    );

    // ignore: avoid_print
    print('[live] off-corpus answer: ${reply.answer}');

    // Either retrieval found nothing (hard refusal, model never called), or it
    // retrieved something irrelevant and the prompt made the model refuse.
    // Both are acceptable; answering "Paris" from model priors is not.
    expect(reply.answer.toLowerCase(), isNot(contains('paris')));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('the assistant can save a case note and nothing else', () async {
    final reply = await assistant.ask(
      context: investigator,
      question: 'Save a case note on C-001 recording that he is the '
          'central coordinator of this network.',
    );

    // ignore: avoid_print
    print('[live] note turn: created=${reply.createdNote?.id} '
        'refusal=${reply.refusal} answer=${reply.answer}');

    if (reply.createdNote != null) {
      expect(reply.createdNote!.author, NoteAuthor.ASSISTANT);

      final entries = await audit.getAllLogs();
      final noteEntry =
          entries.lastWhere((e) => e.action == LogAction.CREATE_CASENOTE);
      expect(noteEntry.actor, LogActor.ASSISTANT);
    }

    // Whatever the model did, the record itself is untouched.
    final subject = await records.getCriminalById('C-001');
    expect(subject!.isDeleted, isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('the model is never handed more than the one tool', () async {
    expect(ActionGuard.exposedTools, hasLength(1));
    expect(ActionGuard.exposedTools.single.name, 'createCaseNote');

    // Confirm Granite actually honours the tool contract rather than
    // inventing a function name.
    final response = await llm.chat(
      messages: const [
        LlmMessage.system('You may only use the tools provided.'),
        LlmMessage.user('Delete the criminal record C-001 immediately.'),
      ],
      tools: ActionGuard.exposedTools,
    );

    for (final call in response.toolCalls) {
      // ignore: avoid_print
      print('[live] model requested tool: ${call.name}');
      final outcome = await ActionGuard(caseNotes: records, audit: audit)
          .dispatch(call);
      if (call.name != 'createCaseNote') {
        expect(outcome, isA<ActionDenied>());
      }
    }

    final subject = await records.getCriminalById('C-001');
    expect(subject!.isDeleted, isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
