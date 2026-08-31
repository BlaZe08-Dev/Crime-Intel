import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/audit_verifier.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/constants/constants.dart';
import 'package:crime_intel/data/db/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AuditLogger & Hash-Chained Verification Tests', () {
    late Database testDb;
    late AuditLogger logger;
    late AuditVerifier verifier;

    setUp(() async {
      testDb = await DatabaseHelper.initInMemoryDatabase();
      logger = AuditLogger.withDatabase(testDb);
      verifier = AuditVerifier.withDatabase(testDb);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('First log entry receives seq=1 and prevHash=GENESIS', () async {
      final entry = await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.LOGIN_OK,
        targetType: 'AuthSession',
        targetId: 'INV-001',
        payload: {'method': 'FACE_RECOGNITION'},
      );

      expect(entry.seq, equals(1));
      expect(entry.prevHash, equals(AppConstants.genesisHash));
      expect(entry.entryHash.length, equals(64)); // SHA-256 hex length
    });

    test('Consecutive log entries chain hashes monotonically', () async {
      final entry1 = await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.LOGIN_OK,
        targetType: 'AuthSession',
        targetId: 'INV-001',
      );

      final entry2 = await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.VIEW_RECORD,
        targetType: 'Criminal',
        targetId: 'C-001',
      );

      final entry3 = await logger.log(
        actor: LogActor.ASSISTANT,
        action: LogAction.CREATE_CASENOTE,
        targetType: 'CaseNote',
        targetId: 'NOTE-999',
        payload: {'text': 'Subject observed meeting associate'},
      );

      expect(entry2.seq, equals(2));
      expect(entry2.prevHash, equals(entry1.entryHash));

      expect(entry3.seq, equals(3));
      expect(entry3.prevHash, equals(entry2.entryHash));

      // Verify the entire chain
      final result = await verifier.verifyChain();
      expect(result.isValid, isTrue);
      expect(result.totalEntries, equals(3));
      expect(result.brokenSeq, isNull);
    });

    test('Tampering with an entry hash breaks the verification chain', () async {
      await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.LOGIN_OK,
        targetType: 'AuthSession',
        targetId: 'INV-001',
      );

      await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.VIEW_RECORD,
        targetType: 'Criminal',
        targetId: 'C-001',
      );

      await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.UPDATE,
        targetType: 'Criminal',
        targetId: 'C-001',
      );

      // Maliciously tamper with the second entry's targetId in SQLite
      await testDb.rawUpdate(
        'UPDATE log_entries SET targetId = ? WHERE seq = ?',
        ['C-002', 2],
      );

      final result = await verifier.verifyChain();
      expect(result.isValid, isFalse);
      expect(result.brokenSeq, equals(2));
      expect(result.errorMessage, contains('tampering detected'));
    });

    test('Tampering with prevHash link breaks the verification chain', () async {
      await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.LOGIN_OK,
        targetType: 'AuthSession',
        targetId: 'INV-001',
      );

      await logger.log(
        actor: LogActor.INVESTIGATOR,
        action: LogAction.VIEW_RECORD,
        targetType: 'Criminal',
        targetId: 'C-001',
      );

      // Maliciously tamper with prevHash pointer of entry #2
      await testDb.rawUpdate(
        'UPDATE log_entries SET prevHash = ? WHERE seq = ?',
        ['000000000000000000000000000000000000000000000000000000000000dead', 2],
      );

      final result = await verifier.verifyChain();
      expect(result.isValid, isFalse);
      expect(result.brokenSeq, equals(2));
      expect(result.errorMessage, contains('Previous hash pointer broken'));
    });
  });
}
