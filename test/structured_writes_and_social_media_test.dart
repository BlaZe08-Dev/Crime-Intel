import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/audit_verifier.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/security/actor_context.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/data/repositories/crime_repository.dart';
import 'package:crime_intel/data/repositories/vector_repository.dart';
import 'package:crime_intel/graph/entity_extractor.dart';
import 'package:crime_intel/graph/models/graph_models.dart';
import 'package:crime_intel/ingest/ingestion_service.dart';
import 'package:crime_intel/models/criminal.dart';
import 'package:crime_intel/models/structured_records.dart';
import 'package:crime_intel/models/text_record.dart';
import 'package:crime_intel/rag/rag_indexer.dart';

import 'support/fake_llm_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.initFfi();

  late Database db;
  late AuditLogger audit;
  late AuditVerifier verifier;
  late CrimeRepository records;

  final investigator = InvestigatorContext.issueForSession(
    AuthSessionIssuer.issue(
      investigatorId: 'INV-007',
      sessionId: 'SESSION-TEST-007',
    ),
  );

  setUp(() async {
    db = await DatabaseHelper.openInMemory();
    audit = AuditLogger(db);
    verifier = AuditVerifier(db);
    records = CrimeRepository(db, audit);
  });

  tearDown(() async {
    await db.close();
  });

  group('Structured write methods and audit logging', () {
    setUp(() async {
      // Seed test criminal profile for structured write tests
      await records.addCriminal(
        context: investigator,
        criminal: const Criminal(
          id: 'C-001',
          name: 'Devraj Malhotra',
          aliases: ['DM', 'Seth'],
          dob: '1979-03-11',
          gender: 'M',
          knownFor: 'Money laundering',
          status: CriminalStatus.UNDER_WATCH,
          lastKnownLoc: 'Pune',
          riskLevel: RiskLevel.HIGH,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
    });
    test('addCdrRecord successfully persists and writes audit log entry', () async {
      const cdr = CdrRecord(
        id: 'CDR-TEST-001',
        criminalId: 'C-001',
        callerId: '+91-98100-99001',
        calleeId: '+91-98200-11223',
        ts: 1699900000000,
        durationSec: 145,
        cellSite: 'Pune-North-Cell-9',
      );

      final added = await records.addCdrRecord(
        context: investigator,
        record: cdr,
      );

      expect(added.id, cdr.id);
      expect(added.callerId, cdr.callerId);

      // Verify SQLite read back
      final criminalCalls = await records.getCdrFor('C-001');
      expect(criminalCalls, hasLength(1));
      expect(criminalCalls.first.id, 'CDR-TEST-001');
      expect(criminalCalls.first.cellSite, 'Pune-North-Cell-9');

      final allCalls = await records.getAllCdr();
      expect(allCalls, hasLength(1));
      expect(allCalls.first.id, 'CDR-TEST-001');

      // Verify Audit Log
      final logs = await audit.getAllLogs();
      final cdrLog = logs.firstWhere((l) => l.targetId == 'CDR-TEST-001');
      expect(cdrLog.actor, LogActor.INVESTIGATOR);
      expect(cdrLog.action, LogAction.UPLOAD);
      expect(cdrLog.targetType, 'CdrRecord');
      expect(cdrLog.payloadHash, isNotEmpty);

      final chainStatus = await verifier.verifyChain();
      expect(chainStatus.isValid, isTrue);
    });

    test('addFinancialTxn successfully persists and writes audit log entry', () async {
      const txn = FinancialTxn(
        id: 'TXN-TEST-001',
        criminalId: 'C-001',
        counterparty: 'Zenith Impex Ltd',
        amount: 850000.0,
        currency: 'INR',
        ts: 1699910000000,
        channel: 'Hawala / RTGS',
      );

      final added = await records.addFinancialTxn(
        context: investigator,
        txn: txn,
      );

      expect(added.id, txn.id);
      expect(added.amount, 850000.0);

      // Verify SQLite read back
      final criminalTxns = await records.getFinancialFor('C-001');
      expect(criminalTxns, hasLength(1));
      expect(criminalTxns.first.id, 'TXN-TEST-001');
      expect(criminalTxns.first.counterparty, 'Zenith Impex Ltd');

      final allTxns = await records.getAllFinancial();
      expect(allTxns, hasLength(1));
      expect(allTxns.first.id, 'TXN-TEST-001');

      // Verify Audit Log
      final logs = await audit.getAllLogs();
      final txnLog = logs.firstWhere((l) => l.targetId == 'TXN-TEST-001');
      expect(txnLog.actor, LogActor.INVESTIGATOR);
      expect(txnLog.action, LogAction.UPLOAD);
      expect(txnLog.targetType, 'FinancialTxn');
      expect(txnLog.payloadHash, isNotEmpty);

      final chainStatus = await verifier.verifyChain();
      expect(chainStatus.isValid, isTrue);
    });

    test('addCriminalHistory successfully persists and writes audit log entry', () async {
      const history = CriminalHistory(
        id: 'HIST-TEST-001',
        criminalId: 'C-001',
        offense: 'Organised Cyber Fraud Syndicate Operation',
        date: '2023-04-15',
        dispositionNote: 'Chargesheet filed under IPC 420; trial pending.',
      );

      final added = await records.addCriminalHistory(
        context: investigator,
        history: history,
      );

      expect(added.id, history.id);
      expect(added.offense, history.offense);

      // Verify SQLite read back
      final criminalHistory = await records.getHistoryFor('C-001');
      expect(criminalHistory, hasLength(1));
      expect(criminalHistory.first.id, 'HIST-TEST-001');
      expect(criminalHistory.first.offense, contains('Cyber Fraud'));

      final allHistory = await records.getAllHistory();
      expect(allHistory, hasLength(1));
      expect(allHistory.first.id, 'HIST-TEST-001');

      // Verify Audit Log
      final logs = await audit.getAllLogs();
      final histLog = logs.firstWhere((l) => l.targetId == 'HIST-TEST-001');
      expect(histLog.actor, LogActor.INVESTIGATOR);
      expect(histLog.action, LogAction.UPLOAD);
      expect(histLog.targetType, 'CriminalHistory');
      expect(histLog.payloadHash, isNotEmpty);

      final chainStatus = await verifier.verifyChain();
      expect(chainStatus.isValid, isTrue);
    });
  });

  group('Social media intelligence source type & entity extraction', () {
    test('TextRecordKind enum includes SOCIAL_MEDIA with proper displayName and parsing', () {
      expect(TextRecordKind.SOCIAL_MEDIA.displayName, 'Social Media Intelligence');
      expect(TextRecordKind.fromString('SOCIAL_MEDIA'), TextRecordKind.SOCIAL_MEDIA);
      expect(TextRecordKind.fromString('social_media'), TextRecordKind.SOCIAL_MEDIA);
    });

    test('EntityExtractor picks up entities from SOCIAL_MEDIA text records', () {
      final extractor = EntityExtractor();
      final criminals = [
        const Criminal(
          id: 'C-004',
          name: 'Sunita Rao',
          aliases: ['Madam'],
          dob: '1982-05-19',
          gender: 'F',
          knownFor: 'Hawala',
          status: CriminalStatus.AT_LARGE,
          lastKnownLoc: 'Mumbai',
          riskLevel: RiskLevel.HIGH,
          createdAt: 1000,
          updatedAt: 1000,
        ),
        const Criminal(
          id: 'C-005',
          name: 'Imran Shaikh',
          aliases: ['Chotu'],
          dob: '1997-09-30',
          gender: 'M',
          knownFor: 'Courier',
          status: CriminalStatus.AT_LARGE,
          lastKnownLoc: 'Thane',
          riskLevel: RiskLevel.LOW,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      ];

      const socialMediaRecord = TextRecord(
        id: 'SOC-TEST-001',
        criminalId: 'C-005',
        kind: TextRecordKind.SOCIAL_MEDIA,
        title: 'Social Media OSINT: Telegram Channel Intercept',
        body: 'Investigative OSINT alert: Imran Shaikh (alias Chotu) posted encrypted channel links '
            'referencing deliveries for Sunita Rao (Madam). Contact number +91-98765-43210 was displayed '
            'for pickup coordination in Thane.',
        createdAt: 1699920000000,
      );

      final result = extractor.extract(
        criminals: criminals,
        textRecords: [socialMediaRecord],
      );

      // Verify persons extracted
      final persons = result.entities.where((e) => e.type == EntityType.PERSON).toList();
      final personNames = persons.map((p) => p.value).toSet();
      expect(personNames, contains('Imran Shaikh'));
      expect(personNames, contains('Sunita Rao'));

      // Verify phone extracted
      final phones = result.entities.where((e) => e.type == EntityType.PHONE).toList();
      expect(phones.any((p) => p.value.contains('98765-43210') || p.value.contains('9876543210')), isTrue);

      // Verify mentions created for source record
      final mentions = result.mentionsIn('SOC-TEST-001');
      expect(mentions, isNotEmpty);
      expect(mentions.any((m) => m.value == 'Imran Shaikh'), isTrue);
      expect(mentions.any((m) => m.value == 'Sunita Rao'), isTrue);
    });

    test('Seed dataset includes synthetic SOCIAL_MEDIA record and feeds RAG indexing', () async {
      final ingestion = IngestionService(db: db, audit: audit);
      await ingestion.seedIfEmpty();

      final seededTexts = await records.getAllTextRecords();
      final socialMediaRecords = seededTexts
          .where((t) => t.kind == TextRecordKind.SOCIAL_MEDIA)
          .toList();

      expect(socialMediaRecords, isNotEmpty);
      final seedSoc = socialMediaRecords.first;
      expect(seedSoc.id, 'SOC-2023-0511');
      expect(seedSoc.kind.displayName, 'Social Media Intelligence');
      expect(seedSoc.body, contains('Imran Shaikh'));
      expect(seedSoc.body, contains('Sunita Rao'));

      // Verify RAG indexer builds chunks for all records including Social Media
      final vectors = VectorRepository(db);
      final indexer = RagIndexer(
        records: records,
        vectors: vectors,
        audit: audit,
        llm: FakeLlmClient(),
      );

      final indexResult = await indexer.rebuild(context: investigator);
      expect(indexResult.chunkCount, greaterThan(0));

      final chunks = await vectors.getAll();
      final socialMediaChunk = chunks.firstWhere(
        (c) => c.sourceId == 'SOC-2023-0511',
      );
      expect(socialMediaChunk.sourceType, 'TextRecord');
      expect(socialMediaChunk.text, contains('SOCIAL MEDIA INTELLIGENCE'));
    });
  });
}
