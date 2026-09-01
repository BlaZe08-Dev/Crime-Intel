import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/audit_verifier.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/constants/constants.dart';
import 'package:crime_intel/core/security/actor_context.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(DatabaseHelper.initFfi);

  group('AuditLogger hash chain', () {
    late Database db;
    late AuditLogger logger;
    late AuditVerifier verifier;

    final investigator = InvestigatorContext.issueForSession(
      AuthSessionIssuer.issue(
        investigatorId: 'INV-001',
        sessionId: 'SESSION-TEST',
      ),
    );

    setUp(() async {
      db = await DatabaseHelper.openInMemory();
      logger = AuditLogger(db);
      verifier = AuditVerifier(db);
    });

    tearDown(() async => db.close());

    test('first entry starts at seq 1 with the genesis prevHash', () async {
      final entry = await logger.log(
        context: investigator,
        action: LogAction.LOGIN_OK,
        targetType: 'AuthSession',
        targetId: 'INV-001',
        payload: {'method': 'FACE_RECOGNITION'},
      );

      expect(entry.seq, 1);
      expect(entry.prevHash, AppConstants.genesisHash);
      expect(entry.entryHash.length, 64);
    });

    test('consecutive entries chain to their predecessor', () async {
      final first = await logger.log(
        context: investigator,
        action: LogAction.LOGIN_OK,
        targetType: 'AuthSession',
        targetId: 'INV-001',
      );
      final second = await logger.log(
        context: investigator,
        action: LogAction.VIEW_RECORD,
        targetType: 'Criminal',
        targetId: 'C-001',
      );
      final third = await logger.log(
        context: const AssistantContext(),
        action: LogAction.CREATE_CASENOTE,
        targetType: 'CaseNote',
        targetId: 'NOTE-999',
        payload: {'text': 'Subject observed meeting associate'},
      );

      expect(second.seq, 2);
      expect(second.prevHash, first.entryHash);
      expect(third.seq, 3);
      expect(third.prevHash, second.entryHash);

      final result = await verifier.verifyChain();
      expect(result.isValid, isTrue);
      expect(result.totalEntries, 3);
    });

    test('editing an entry breaks verification', () async {
      for (final action in [
        LogAction.LOGIN_OK,
        LogAction.VIEW_RECORD,
        LogAction.UPDATE,
      ]) {
        await logger.log(
          context: investigator,
          action: action,
          targetType: 'Criminal',
          targetId: 'C-001',
        );
      }

      await db.rawUpdate(
        'UPDATE log_entries SET targetId = ? WHERE seq = ?',
        ['C-002', 2],
      );

      final result = await verifier.verifyChain();
      expect(result.isValid, isFalse);
      expect(result.brokenSeq, 2);
      expect(result.errorMessage, contains('tampering detected'));
    });

    test('repointing prevHash breaks verification', () async {
      await logger.log(
        context: investigator,
        action: LogAction.LOGIN_OK,
        targetType: 'AuthSession',
        targetId: 'INV-001',
      );
      await logger.log(
        context: investigator,
        action: LogAction.VIEW_RECORD,
        targetType: 'Criminal',
        targetId: 'C-001',
      );

      await db.rawUpdate(
        'UPDATE log_entries SET prevHash = ? WHERE seq = ?',
        ['0' * 60 + 'dead', 2],
      );

      final result = await verifier.verifyChain();
      expect(result.isValid, isFalse);
      expect(result.brokenSeq, 2);
      expect(result.errorMessage, contains('Previous hash pointer broken'));
    });

    test('deleting an entry is detected as a sequence gap', () async {
      for (var i = 0; i < 3; i++) {
        await logger.log(
          context: investigator,
          action: LogAction.VIEW_RECORD,
          targetType: 'Criminal',
          targetId: 'C-00$i',
        );
      }

      // Nothing in the app can do this; the point is that if someone reached
      // the file directly, verification would still catch it.
      await db.rawDelete('DELETE FROM log_entries WHERE seq = ?', [2]);

      final result = await verifier.verifyChain();
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Sequence mismatch'));
    });

    test('actor is taken from the context type, not from the caller', () async {
      final assistantEntry = await logger.log(
        context: const AssistantContext(),
        action: LogAction.CREATE_CASENOTE,
        targetType: 'CaseNote',
        targetId: 'NOTE-1',
      );
      final systemEntry = await logger.log(
        context: const SystemContext(),
        action: LogAction.UPLOAD,
        targetType: 'Database',
        targetId: 'SEED',
      );

      expect(assistantEntry.actor, LogActor.ASSISTANT);
      expect(systemEntry.actor, LogActor.SYSTEM);
    });

    test('concurrent writes still produce a single unbroken chain', () async {
      // The write queue exists for this: without serialisation these would
      // race on "read the latest seq" and produce duplicates or a fork.
      await Future.wait([
        for (var i = 0; i < 25; i++)
          logger.log(
            context: investigator,
            action: LogAction.VIEW_RECORD,
            targetType: 'Criminal',
            targetId: 'C-$i',
          ),
      ]);

      final result = await verifier.verifyChain();
      expect(result.isValid, isTrue);
      expect(result.totalEntries, 25);
      expect(await logger.getLogCount(), 25);
    });
  });
}
