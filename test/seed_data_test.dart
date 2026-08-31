import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/audit_verifier.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/ingest/ingestion_service.dart';
import 'package:crime_intel/models/criminal.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Synthetic Dataset Ingestion & Network Topology Tests', () {
    late Database testDb;
    late AuditLogger logger;
    late AuditVerifier verifier;
    late IngestionService ingestionService;

    setUp(() async {
      testDb = await DatabaseHelper.initInMemoryDatabase();
      logger = AuditLogger.withDatabase(testDb);
      verifier = AuditVerifier.withDatabase(testDb);
      ingestionService = IngestionService.withDatabase(testDb, logger);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Seeds exactly 5 synthetic criminals from Criminals.md with C-001 hub', () async {
      await ingestionService.seedDatabaseIfEmpty();

      final criminals = await ingestionService.getCriminals();
      expect(criminals.length, equals(5));

      final c001 = criminals.firstWhere((c) => c.id == 'C-001');
      expect(c001.name, equals('Devraj Malhotra'));
      expect(c001.aliases, containsAll(['DM', 'Seth']));
      expect(c001.riskLevel, equals(RiskLevel.HIGH));
      expect(c001.status, equals(CriminalStatus.UNDER_WATCH));

      final c004 = criminals.firstWhere((c) => c.id == 'C-004');
      expect(c004.name, equals('Sunita Rao'));
      expect(c004.aliases, contains('Madam'));
    });

    test('Seeded financial transactions include baseline and planted burst anomaly', () async {
      await ingestionService.seedDatabaseIfEmpty();

      final txns = await ingestionService.getFinancialTxnsForCriminal('C-004');
      expect(txns.isNotEmpty, isTrue);

      // Check that large burst transactions exist (TXN-003: 2500000.0, TXN-004: 3200000.0)
      final burstTxns = txns.where((t) => t.amount > 1000000.0).toList();
      expect(burstTxns.length, greaterThanOrEqualTo(2));
    });

    test('Seeding event is logged in the hash-chained audit log with valid verification', () async {
      await ingestionService.seedDatabaseIfEmpty();

      final logs = await logger.getAllLogs();
      expect(logs.length, equals(1));
      expect(logs.first.actor, equals(LogActor.SYSTEM));
      expect(logs.first.action, equals(LogAction.UPLOAD));
      expect(logs.first.targetId, equals('SYNTHETIC_SEED'));

      final verification = await verifier.verifyChain();
      expect(verification.isValid, isTrue);
      expect(verification.totalEntries, equals(1));
    });

    test('Soft delete retains record history and logs deletion event', () async {
      await ingestionService.seedDatabaseIfEmpty();

      await ingestionService.softDeleteCriminal('C-005', actor: LogActor.INVESTIGATOR);

      // Default getCriminals excludes soft-deleted
      final active = await ingestionService.getCriminals(includeDeleted: false);
      expect(active.any((c) => c.id == 'C-005'), isFalse);
      expect(active.length, equals(4));

      // Included deleted returns all 5
      final all = await ingestionService.getCriminals(includeDeleted: true);
      expect(all.length, equals(5));

      final c005 = all.firstWhere((c) => c.id == 'C-005');
      expect(c005.isDeleted, isTrue);

      // Audit log has seed entry + delete entry
      final logs = await logger.getAllLogs();
      expect(logs.length, equals(2));
      expect(logs.last.action, equals(LogAction.DELETE));
      expect(logs.last.targetId, equals('C-005'));

      final verification = await verifier.verifyChain();
      expect(verification.isValid, isTrue);
    });
  });
}
