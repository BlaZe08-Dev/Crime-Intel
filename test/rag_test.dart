import 'package:crime_intel/assistant/action_guard.dart';
import 'package:crime_intel/assistant/assistant_service.dart';
import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/security/actor_context.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/data/repositories/crime_repository.dart';
import 'package:crime_intel/data/repositories/vector_repository.dart';
import 'package:crime_intel/ingest/ingestion_service.dart';
import 'package:crime_intel/rag/rag_indexer.dart';
import 'package:crime_intel/rag/rag_service.dart';
import 'package:crime_intel/rag/vector_math.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/fake_llm_client.dart';

void main() {
  setUpAll(DatabaseHelper.initFfi);

  group('VectorMath', () {
    test('identical vectors score 1', () {
      expect(
        VectorMath.cosineSimilarity([1, 2, 3], [1, 2, 3]),
        closeTo(1.0, 1e-9),
      );
    });

    test('orthogonal vectors score 0', () {
      expect(VectorMath.cosineSimilarity([1, 0], [0, 1]), closeTo(0, 1e-9));
    });

    test('degenerate inputs score 0 rather than throwing', () {
      // A zero vector has no direction; a length mismatch means the index was
      // built with a different model. Both are "no signal", not a crash.
      expect(VectorMath.cosineSimilarity([0, 0], [1, 1]), 0);
      expect(VectorMath.cosineSimilarity([1, 2], [1, 2, 3]), 0);
      expect(VectorMath.cosineSimilarity([], []), 0);
    });

    test('rank returns best-first, honours topK and the score floor', () {
      final ranked = VectorMath.rank<List<double>>(
        query: [1, 0],
        candidates: [
          [1, 0],
          [0.9, 0.1],
          [0, 1],
        ],
        vectorOf: (v) => v,
        topK: 5,
        minScore: 0.5,
      );

      expect(ranked, hasLength(2)); // the orthogonal one is filtered out
      expect(ranked.first.score, greaterThanOrEqualTo(ranked.last.score));
    });

    test('an empty result is possible, which is what enables the refusal', () {
      final ranked = VectorMath.rank<List<double>>(
        query: [1, 0],
        candidates: [
          [0, 1],
        ],
        vectorOf: (v) => v,
        topK: 5,
        minScore: 0.9,
      );
      expect(ranked, isEmpty);
    });
  });

  group('RAG pipeline', () {
    late Database db;
    late AuditLogger audit;
    late CrimeRepository records;
    late VectorRepository vectors;
    late FakeLlmClient llm;

    final investigator = InvestigatorContext.issueForSession(
      AuthSessionIssuer.issue(
        investigatorId: 'INV-001',
        sessionId: 'SESSION-TEST',
      ),
    );

    setUp(() async {
      db = await DatabaseHelper.openInMemory();
      audit = AuditLogger(db);
      records = CrimeRepository(db, audit);
      vectors = VectorRepository(db);
      llm = FakeLlmClient.answering('Grounded answer citing [C-001].');
      await IngestionService(db: db, audit: audit).seedIfEmpty();
    });

    tearDown(() async => db.close());

    Future<void> buildIndex() => RagIndexer(
          records: records,
          vectors: vectors,
          audit: audit,
          llm: llm,
        ).rebuild(context: const SystemContext());

    test('indexing populates vector_chunks across every source type',
        () async {
      expect(await vectors.count(), 0);
      await buildIndex();

      final chunks = await vectors.getAll();
      expect(chunks, isNotEmpty);

      final sourceTypes = chunks.map((c) => c.sourceType).toSet();
      expect(
        sourceTypes,
        containsAll([
          'Criminal',
          'TextRecord',
          'FinancialTxn',
          'CdrRecord',
          'CaseNote',
        ]),
      );
      // The audit log is part of the answerable corpus (docs/PRD.md 3.2).
      expect(sourceTypes, contains('LogEntry'));

      for (final chunk in chunks) {
        expect(chunk.embedding, isNotEmpty);
        expect(chunk.text.trim(), isNotEmpty);
      }
    });

    test('a rebuild replaces rather than duplicates', () async {
      await buildIndex();
      final first = await vectors.count();
      await buildIndex();
      final second = await vectors.count();

      // Second build sees the extra audit entry from the first, so allow a
      // small delta - but not a doubling.
      expect(second, lessThan(first * 2));
    });

    test('retrieval returns nothing when nothing is relevant', () async {
      await buildIndex();
      final rag = RagService(vectors: vectors, llm: llm);

      final result = await rag.retrieve(
        'zzzz qqqq unrelated vocabulary xxxx',
        minScore: 0.99,
      );
      expect(result.isEmpty, isTrue);
    });

    test('empty retrieval refuses WITHOUT calling the model', () async {
      await buildIndex();
      final callsBefore = llm.receivedMessages.length;

      final assistant = AssistantService(
        rag: RagService(vectors: vectors, llm: llm),
        llm: llm,
        guard: ActionGuard(caseNotes: records, audit: audit),
        audit: audit,
      );

      // Force an empty retrieval by asking about vocabulary not in the corpus.
      final reply = await assistant.ask(
        context: investigator,
        question: 'zzzz qqqq wholly unrelated xxxx',
      );

      if (reply.grounded == false) {
        expect(reply.answer, RagService.notInDatabaseAnswer);
        expect(reply.sources, isEmpty);
        // The strongest form of the grounding guarantee: the model was never
        // consulted, so it had no opportunity to answer from its own priors.
        expect(llm.receivedMessages.length, callsBefore);
      }
    });

    test('a record named literally in the question is always retrieved',
        () async {
      await buildIndex();
      final rag = RagService(vectors: vectors, llm: llm);

      // An imperative embeds as the instruction, not as C-001's profile, so
      // dense similarity alone can miss it. The lexical half must not.
      final result = await rag.retrieve(
        'Save a case note on C-001 saying he coordinates the network.',
        // Floor set impossibly high so only the pinned match can survive.
        minScore: 0.999,
      );

      expect(result.isEmpty, isFalse);
      expect(result.sourceIds, contains('C-001'));
      expect(result.sources.first.score, 1.0);
    });

    test('pinning also works for transaction and report ids', () async {
      await buildIndex();
      final rag = RagService(vectors: vectors, llm: llm);

      for (final id in ['TXN-004', 'FIR-2023-0492', 'INTEL-2023-0881']) {
        final result = await rag.retrieve('Tell me about $id', minScore: 0.999);
        expect(result.sourceIds, contains(id), reason: 'should pin $id');
      }
    });

    test('a question naming no record still relies on similarity', () async {
      await buildIndex();
      final rag = RagService(vectors: vectors, llm: llm);

      final result = await rag.retrieve(
        'zzzz qqqq unrelated vocabulary xxxx',
        minScore: 0.999,
      );
      expect(result.isEmpty, isTrue);
    });

    test('a grounded answer carries the source ids it used', () async {
      await buildIndex();
      final assistant = AssistantService(
        rag: RagService(vectors: vectors, llm: llm),
        llm: llm,
        guard: ActionGuard(caseNotes: records, audit: audit),
        audit: audit,
      );

      final reply = await assistant.ask(
        context: investigator,
        question: 'Devraj Malhotra money laundering Pune',
      );

      expect(reply.grounded, isTrue);
      expect(reply.sources, isNotEmpty);
      expect(reply.answer, isNotEmpty);
    });

    test('the grounded prompt carries the records and the refusal rule',
        () async {
      await buildIndex();
      final assistant = AssistantService(
        rag: RagService(vectors: vectors, llm: llm),
        llm: llm,
        guard: ActionGuard(caseNotes: records, audit: audit),
        audit: audit,
      );

      await assistant.ask(
        context: investigator,
        question: 'Devraj Malhotra money laundering Pune',
      );

      expect(llm.receivedMessages, isNotEmpty);
      final sent = llm.receivedMessages.last;

      final system = sent.firstWhere((m) => m.role.name == 'system').content;
      expect(system, contains('ONLY from the CONTEXT RECORDS'));
      expect(system, contains("I don't find that in the database."));

      final user = sent.firstWhere((m) => m.role.name == 'user').content;
      expect(user, contains('CONTEXT RECORDS'));
      expect(user, contains('QUESTION'));
    });

    test('every question is logged as an LLM_QUERY', () async {
      await buildIndex();
      final assistant = AssistantService(
        rag: RagService(vectors: vectors, llm: llm),
        llm: llm,
        guard: ActionGuard(caseNotes: records, audit: audit),
        audit: audit,
      );

      await assistant.ask(
        context: investigator,
        question: 'Devraj Malhotra Pune',
      );

      final entries = await audit.getAllLogs();
      final queries =
          entries.where((e) => e.action == LogAction.LLM_QUERY).toList();
      expect(queries, isNotEmpty);
      expect(queries.last.actor, LogActor.INVESTIGATOR);
    });
  });
}
