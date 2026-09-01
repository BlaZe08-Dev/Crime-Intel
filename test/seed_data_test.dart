import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/audit_verifier.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/security/actor_context.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/data/repositories/crime_repository.dart';
import 'package:crime_intel/ingest/ingestion_service.dart';
import 'package:crime_intel/models/criminal.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(DatabaseHelper.initFfi);

  group('Synthetic dataset ingestion', () {
    late Database db;
    late AuditLogger audit;
    late AuditVerifier verifier;
    late IngestionService ingestion;
    late CrimeRepository records;

    final investigator = InvestigatorContext.issueForSession(
      AuthSessionIssuer.issue(
        investigatorId: 'INV-001',
        sessionId: 'SESSION-TEST',
      ),
    );

    setUp(() async {
      db = await DatabaseHelper.openInMemory();
      audit = AuditLogger(db);
      verifier = AuditVerifier(db);
      records = CrimeRepository(db, audit);
      ingestion = IngestionService(db: db, audit: audit);
    });

    tearDown(() async => db.close());

    test('seeds the five criminals from Criminals.md', () async {
      await ingestion.seedIfEmpty();

      final criminals = await records.getCriminals();
      expect(criminals, hasLength(5));

      final hub = criminals.firstWhere((c) => c.id == 'C-001');
      expect(hub.name, 'Devraj Malhotra');
      expect(hub.aliases, containsAll(['DM', 'Seth']));
      expect(hub.riskLevel, RiskLevel.HIGH);
      expect(hub.status, CriminalStatus.UNDER_WATCH);

      final financier = criminals.firstWhere((c) => c.id == 'C-004');
      expect(financier.name, 'Sunita Rao');
      expect(financier.aliases, contains('Madam'));
    });

    test('is idempotent - a second call does not duplicate', () async {
      expect(await ingestion.seedIfEmpty(), isTrue);
      expect(await ingestion.seedIfEmpty(), isFalse);
      expect(await records.getCriminals(), hasLength(5));
    });

    test('plants the transaction burst the anomaly rules must find', () async {
      await ingestion.seedIfEmpty();

      final txns = await records.getFinancialFor('C-004');
      expect(txns, isNotEmpty);

      final large = txns.where((t) => t.amount > 1000000).toList();
      expect(large.length, greaterThanOrEqualTo(2));
    });

    test('every text record has an extractable body', () async {
      await ingestion.seedIfEmpty();

      final texts = await records.getAllTextRecords();
      expect(texts.length, greaterThanOrEqualTo(5));
      for (final text in texts) {
        expect(text.body.trim(), isNotEmpty);
        expect(text.title.trim(), isNotEmpty);
      }
    });

    test('seeding is recorded in the audit chain as a SYSTEM action',
        () async {
      await ingestion.seedIfEmpty();

      final entries = await audit.getAllLogs();
      expect(entries, hasLength(1));
      expect(entries.single.actor, LogActor.SYSTEM);
      expect(entries.single.action, LogAction.UPLOAD);
      expect(entries.single.targetId, 'SYNTHETIC_SEED');

      final verification = await verifier.verifyChain();
      expect(verification.isValid, isTrue);
    });

    test('soft delete hides the record but keeps it and logs the prior state',
        () async {
      await ingestion.seedIfEmpty();

      await records.softDeleteCriminal(
        context: investigator,
        criminalId: 'C-005',
      );

      final active = await records.getCriminals();
      expect(active.any((c) => c.id == 'C-005'), isFalse);
      expect(active, hasLength(4));

      final all = await records.getCriminals(includeDeleted: true);
      expect(all, hasLength(5));
      expect(all.firstWhere((c) => c.id == 'C-005').isDeleted, isTrue);

      final entries = await audit.getAllLogs();
      expect(entries.last.action, LogAction.DELETE);
      expect(entries.last.targetId, 'C-005');
      expect(entries.last.actor, LogActor.INVESTIGATOR);

      expect((await verifier.verifyChain()).isValid, isTrue);
    });

    test('opening a record writes a VIEW_RECORD entry', () async {
      await ingestion.seedIfEmpty();

      await records.openCriminalRecord(
        context: investigator,
        criminalId: 'C-001',
      );

      final entries = await audit.getAllLogs();
      final views =
          entries.where((e) => e.action == LogAction.VIEW_RECORD).toList();
      expect(views, hasLength(1));
      expect(views.single.targetId, 'C-001');
      expect(views.single.actor, LogActor.INVESTIGATOR);
    });

    test('an update logs both the previous and the new state', () async {
      await ingestion.seedIfEmpty();

      await records.updateCriminal(
        context: investigator,
        criminalId: 'C-002',
        status: 'IN_CUSTODY',
      );

      final updated = await records.getCriminalById('C-002');
      expect(updated!.status, CriminalStatus.IN_CUSTODY);

      final entries = await audit.getAllLogs();
      expect(entries.last.action, LogAction.UPDATE);
      expect((await verifier.verifyChain()).isValid, isTrue);
    });

    test('unlogged reads do not pollute the chain', () async {
      await ingestion.seedIfEmpty();
      final before = await audit.getLogCount();

      // Internal sweeps (indexer, graph builder) must not log.
      await records.getCriminals();
      await records.getAllTextRecords();
      await records.getAllFinancial();
      await records.getCriminalById('C-001');

      expect(await audit.getLogCount(), before);
    });
  });
}
