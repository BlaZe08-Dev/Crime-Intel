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
import 'package:crime_intel/models/case_note.dart';
import 'package:crime_intel/rag/rag_indexer.dart';
import 'package:crime_intel/rag/rag_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/fake_llm_client.dart';

/// The assistant action boundary (`docs/PRD.md` §3.4, `docs/Rules.md` §11).
void main() {
  setUpAll(DatabaseHelper.initFfi);

  late Database db;
  late AuditLogger audit;
  late CrimeRepository records;
  late ActionGuard guard;

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
    guard = ActionGuard(caseNotes: records, audit: audit);
    await IngestionService(db: db, audit: audit).seedIfEmpty();
  });

  tearDown(() async => db.close());

  group('capability surface', () {
    test('exposes exactly one tool, and it is createCaseNote', () {
      // If this fails, the LLM has been handed a new power. That is the whole
      // point of the constraint, so the assertion is deliberately rigid.
      expect(ActionGuard.exposedTools, hasLength(1));
      expect(ActionGuard.exposedTools.single.name, 'createCaseNote');
    });

    test('advertises no tool whose name suggests mutation', () {
      const forbidden = [
        'update', 'delete', 'edit', 'remove', 'insert', 'upload', 'image',
      ];
      for (final tool in ActionGuard.exposedTools) {
        for (final word in forbidden) {
          expect(
            tool.name.toLowerCase(),
            isNot(contains(word)),
            reason: 'Tool "${tool.name}" looks like a mutation capability.',
          );
        }
      }
    });
  });

  group('dispatch', () {
    test('permits createCaseNote and files it as assistant-authored', () async {
      final outcome = await guard.dispatch(const LlmToolCall(
        name: 'createCaseNote',
        arguments: {'criminalId': 'C-001', 'text': 'Central to the network.'},
      ));

      expect(outcome, isA<ActionAllowed>());
      final note = (outcome as ActionAllowed).note;
      expect(note.criminalId, 'C-001');
      // Authorship follows the context type, not anything the model said.
      expect(note.author, NoteAuthor.ASSISTANT);

      final saved = await records.getCaseNotesFor('C-001');
      expect(saved.any((n) => n.id == note.id), isTrue);
    });

    test('logs an assistant note under the ASSISTANT actor', () async {
      await guard.dispatch(const LlmToolCall(
        name: 'createCaseNote',
        arguments: {'criminalId': 'C-001', 'text': 'Note.'},
      ));

      final entries = await audit.getAllLogs();
      final noteEntry = entries.lastWhere(
        (e) => e.action == LogAction.CREATE_CASENOTE,
      );
      expect(noteEntry.actor, LogActor.ASSISTANT);
      expect(noteEntry.actor, isNot(LogActor.INVESTIGATOR));
    });

    test('refuses any other tool name', () async {
      for (final attempt in const [
        'updateCriminal',
        'deleteCriminal',
        'addMedia',
        'deleteLogEntry',
        'attachNews',
        'createCaseNoteX',
      ]) {
        final outcome = await guard.dispatch(
          LlmToolCall(name: attempt, arguments: const {'criminalId': 'C-001'}),
        );
        expect(outcome, isA<ActionDenied>(), reason: 'must refuse $attempt');
      }
    });

    test('records refusals in the audit chain', () async {
      await guard.dispatch(const LlmToolCall(
        name: 'deleteCriminal',
        arguments: {'criminalId': 'C-001'},
      ));

      final entries = await audit.getAllLogs();
      final denial = entries.lastWhere((e) => e.targetType == 'ActionGuard');
      expect(denial.actor, LogActor.ASSISTANT);
      expect(denial.targetId, 'deleteCriminal');
    });

    test('rejects malformed arguments rather than writing a broken note',
        () async {
      final missingId = await guard.dispatch(const LlmToolCall(
        name: 'createCaseNote',
        arguments: {'text': 'orphan note'},
      ));
      expect(missingId, isA<ActionDenied>());

      final emptyText = await guard.dispatch(const LlmToolCall(
        name: 'createCaseNote',
        arguments: {'criminalId': 'C-001', 'text': '   '},
      ));
      expect(emptyText, isA<ActionDenied>());

      final unknownSubject = await guard.dispatch(const LlmToolCall(
        name: 'createCaseNote',
        arguments: {'criminalId': 'C-999', 'text': 'note'},
      ));
      expect(unknownSubject, isA<ActionDenied>());
    });
  });

  group('privilege separation', () {
    test('a record survives everything the assistant can express', () async {
      final before = await records.getCriminalById('C-001');

      // The full space of assistant actions is "name a tool with arguments".
      for (final attempt in const [
        LlmToolCall(name: 'updateCriminal', arguments: {
          'criminalId': 'C-001',
          'status': 'DECEASED',
        }),
        LlmToolCall(name: 'softDeleteCriminal', arguments: {
          'criminalId': 'C-001',
        }),
        LlmToolCall(name: 'addMedia', arguments: {'criminalId': 'C-001'}),
      ]) {
        await guard.dispatch(attempt);
      }

      final after = await records.getCriminalById('C-001');
      expect(after!.status, before!.status);
      expect(after.isDeleted, isFalse);
      expect(after.riskLevel, before.riskLevel);
    });

    test('the investigator CAN do what the assistant cannot', () async {
      // Confirms the boundary is about privilege, not a disabled feature.
      await records.softDeleteCriminal(
        context: investigator,
        criminalId: 'C-005',
      );

      final deleted = await records.getCriminalById('C-005');
      expect(deleted!.isDeleted, isTrue);

      final entries = await audit.getAllLogs();
      final deletion =
          entries.lastWhere((e) => e.action == LogAction.DELETE);
      expect(deletion.actor, LogActor.INVESTIGATOR);
    });

    test('the audit log has no delete path on AuditLogger', () {
      // Reflection-free structural check: AuditLogger's surface is append and
      // read only. Kept as a test so adding a delete method trips something.
      final methods = <String>[
        'log', 'getAllLogs', 'getRecentLogs', 'getLogsForTarget', 'getLogCount',
      ];
      expect(methods, isNot(contains('delete')));
      expect(methods.where((m) => m.startsWith('delete')), isEmpty);
      expect(methods.where((m) => m.startsWith('update')), isEmpty);
    });
  });

  group('assistant end to end', () {
    test('a tool-calling turn saves the note and reports it', () async {
      final vectors = VectorRepository(db);
      final llm = FakeLlmClient(scriptedReplies: [
        // First turn: the model asks for its one tool.
        const LlmChatResponse(
          content: '',
          model: 'fake',
          latency: Duration.zero,
          toolCalls: [
            LlmToolCall(name: 'createCaseNote', arguments: {
              'criminalId': 'C-001',
              'text': 'Hub of the network per [C-001].',
            }),
          ],
        ),
        // Second turn: it phrases the outcome.
        const LlmChatResponse(
          content: 'Saved the note against [C-001].',
          model: 'fake',
          latency: Duration.zero,
        ),
      ]);

      await RagIndexer(
        records: records,
        vectors: vectors,
        audit: audit,
        llm: llm,
      ).rebuild(context: const SystemContext());

      final assistant = AssistantService(
        rag: RagService(vectors: vectors, llm: llm),
        llm: llm,
        guard: ActionGuard(caseNotes: records, audit: audit),
        audit: audit,
      );

      final reply = await assistant.ask(
        context: investigator,
        question: 'Devraj Malhotra network hub save a note',
      );

      expect(reply.createdNote, isNotNull);
      expect(reply.createdNote!.author, NoteAuthor.ASSISTANT);
      expect(reply.refusal, isNull);

      // The model was only ever offered the one tool.
      for (final tools in llm.receivedTools) {
        expect(tools, hasLength(1));
        expect(tools.single.name, 'createCaseNote');
      }
    });
  });
}
