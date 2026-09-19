import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/constants/constants.dart';
import 'package:crime_intel/core/di/app_services.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/models/case_note.dart';
import 'package:crime_intel/models/criminal.dart';
import 'package:crime_intel/models/media_item.dart';
import 'package:crime_intel/rag/rag_service.dart';
import 'package:crime_intel/sync/models/sync_models.dart';
import 'package:crime_intel/sync/network_checker.dart';
import 'package:crime_intel/sync/remote_sync_transport.dart';

import 'support/fake_llm_client.dart';

/// In-memory implementation of [RemoteSyncTransport] for deterministic multi-device testing.
class FakeRemoteSyncTransport implements RemoteSyncTransport {
  final Map<String, Criminal> criminals = {};
  final Map<String, CaseNote> caseNotes = {};
  final Map<String, MediaItem> mediaItems = {};
  final List<CanonicalAuditEntry> canonicalLogs = [];

  int currentServerTime = 10000;

  @override
  bool get isConfigured => true;

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<void> ensureSchema() async {}

  @override
  Future<int> pushBatch({
    required String deviceId,
    required List<PendingSyncItem> items,
  }) async {
    currentServerTime += 100;
    final serverTs = currentServerTime;

    for (final item in items) {
      final data = jsonDecode(item.payload) as Map<String, dynamic>;

      if (item.entityType == 'criminal') {
        criminals[item.entityId] = Criminal.fromMap(data);
      } else if (item.entityType == 'case_note') {
        caseNotes[item.entityId] = CaseNote.fromMap(data);
      } else if (item.entityType == 'media_item') {
        mediaItems[item.entityId] = MediaItem.fromMap(data);
      } else if (item.entityType == 'audit_entry') {
        final nextSeq = canonicalLogs.length + 1;
        final prevHash = canonicalLogs.isEmpty
            ? AppConstants.genesisHash
            : canonicalLogs.last.entryHash;

        final actor = LogActor.fromString(data['actor'] as String? ?? 'SYSTEM');
        final action = LogAction.fromString(data['action'] as String? ?? 'VIEW_RECORD');
        final targetType = data['targetType'] as String;
        final targetId = data['targetId'] as String;
        final payloadHash = data['payloadHash'] as String;
        final localSeq = (data['seq'] as num?)?.toInt() ?? 0;

        final entryHash = CanonicalAuditEntry.computeEntryHash(
          seq: nextSeq,
          deviceId: deviceId,
          actor: actor,
          action: action,
          targetType: targetType,
          targetId: targetId,
          payloadHash: payloadHash,
          localTs: item.localTs,
          serverTs: serverTs,
          prevHash: prevHash,
        );

        canonicalLogs.add(CanonicalAuditEntry(
          seq: nextSeq,
          deviceId: deviceId,
          localSeq: localSeq,
          actor: actor,
          action: action,
          targetType: targetType,
          targetId: targetId,
          payloadHash: payloadHash,
          localTs: item.localTs,
          serverTs: serverTs,
          prevHash: prevHash,
          entryHash: entryHash,
          payloadJson: item.payload,
        ));
      }
    }

    return serverTs;
  }

  @override
  Future<RemoteSyncPullResult> pullSince(
    int lastServerTs, {
    String? excludeDeviceId,
  }) async {
    return RemoteSyncPullResult(
      criminals: criminals.values.toList(),
      caseNotes: caseNotes.values.toList(),
      mediaItems: mediaItems.values.toList(),
      maxServerTs: currentServerTime,
    );
  }

  @override
  Future<List<CanonicalAuditEntry>> fetchCanonicalLogs({int limit = 50}) async {
    return canonicalLogs.reversed.take(limit).toList();
  }

  @override
  Future<bool> verifyCanonicalChain() async {
    var expectedSeq = 1;
    var expectedPrev = AppConstants.genesisHash;

    for (final entry in canonicalLogs) {
      if (entry.seq != expectedSeq) return false;
      if (entry.prevHash != expectedPrev) return false;

      final expectedHash = CanonicalAuditEntry.computeEntryHash(
        seq: entry.seq,
        deviceId: entry.deviceId,
        actor: entry.actor,
        action: entry.action,
        targetType: entry.targetType,
        targetId: entry.targetId,
        payloadHash: entry.payloadHash,
        localTs: entry.localTs,
        serverTs: entry.serverTs,
        prevHash: entry.prevHash,
      );

      if (expectedHash != entry.entryHash) return false;
      expectedSeq = entry.seq + 1;
      expectedPrev = entry.entryHash;
    }
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.initFfi();

  late Database db;
  late FakeRemoteSyncTransport transport;
  late NetworkAvailabilityChecker networkChecker;
  late AppServices services;

  setUp(() async {
    db = await DatabaseHelper.openInMemory();
    transport = FakeRemoteSyncTransport();
    networkChecker = NetworkAvailabilityChecker(
      probeOverride: () async => false, // Start offline
    );

    services = await AppServices.bootstrap(
      database: db,
      llmClient: FakeLlmClient(),
      syncTransport: transport,
      networkChecker: networkChecker,
      deviceId: 'DEV-TEST-001',
    );
    await services.completeLogin('INV-4412');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await services.dispose();
  });

  group('Offline-First Sync & Queue', () {
    test('local writes while offline persist in SQLite and queue into pending_sync', () async {
      expect(networkChecker.isOnline, isFalse);

      // 1. Create a criminal profile offline
      const criminal = Criminal(
        id: 'C-999',
        name: 'Offline Suspect',
        aliases: ['Shadow'],
        dob: '1990-01-01',
        gender: 'Male',
        knownFor: 'Offline Heist',
        status: CriminalStatus.UNDER_WATCH,
        lastKnownLoc: 'Sector 4',
        riskLevel: RiskLevel.MED,
        createdAt: 1000,
        updatedAt: 1000,
      );

      await services.records.addCriminal(
        context: services.session,
        criminal: criminal,
      );

      // 2. Write a case note offline
      await services.records.writeCaseNote(
        context: services.session,
        criminalId: 'C-999',
        text: 'Observed meeting at the docks.',
      );

      // Verify records are readable locally in SQLite
      final retrieved = await services.records.getCriminalById('C-999');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Offline Suspect');

      final notes = await services.records.getCaseNotesFor('C-999');
      expect(notes.length, 1);
      expect(notes.first.text, 'Observed meeting at the docks.');

      // Verify local audit chain has recorded these actions
      final localLogs = await services.audit.getAllLogs();
      expect(localLogs.any((l) => l.targetId == 'C-999'), isTrue);

      final localVerification = await services.verifier.verifyChain();
      expect(localVerification.isValid, isTrue);

      // Verify items are queued in pending_sync table
      final pendingCount = services.syncManager.status.pendingCount;
      expect(pendingCount, greaterThanOrEqualTo(2));
      expect(services.syncManager.status.label, contains('Offline'));
    });

    test('a pending item syncs to central store and is marked synced once online', () async {
      // Create local note while offline
      const criminal = Criminal(
        id: 'C-888',
        name: 'Synced Suspect',
        aliases: [],
        dob: '1985-05-05',
        gender: 'Female',
        knownFor: 'Fraud',
        status: CriminalStatus.AT_LARGE,
        lastKnownLoc: 'North Hub',
        riskLevel: RiskLevel.LOW,
        createdAt: 1000,
        updatedAt: 1000,
      );
      await services.records.addCriminal(
        context: services.session,
        criminal: criminal,
      );

      expect(services.syncManager.status.pendingCount, greaterThan(0));

      // Go online
      networkChecker.forceState(true);
      expect(networkChecker.isOnline, isTrue);

      // Run sync cycle
      final result = await services.syncManager.syncNow();
      expect(result.success, isTrue);
      expect(result.itemsPushed, greaterThan(0));

      // Pending queue should be drained
      expect(services.syncManager.status.pendingCount, 0);

      // Central store received the record
      expect(transport.criminals.containsKey('C-888'), isTrue);
      expect(transport.criminals['C-888']!.name, 'Synced Suspect');

      // Canonical audit log has recorded the entry
      expect(transport.canonicalLogs.isNotEmpty, isTrue);
      expect(await transport.verifyCanonicalChain(), isTrue);
    });
  });

  group('Two-Chain Cryptographic Integrity & Arrival Ordering', () {
    test('central chain assigns sequence strictly in server arrival order, not local creation order', () async {
      // Simulate Device A and Device B
      // Device A creates an action at local time t1 = 1000
      final itemA = PendingSyncItem(
        id: 'SYNC-A1',
        entityType: 'audit_entry',
        entityId: 'LOG-1',
        operation: 'INSERT',
        payload: jsonEncode({
          'seq': 1,
          'actor': 'INVESTIGATOR',
          'action': 'VIEW_RECORD',
          'targetType': 'Criminal',
          'targetId': 'C-001',
          'payloadHash': 'hash_a',
        }),
        localTs: 1000, // Created earlier locally
      );

      // Device B creates an action at local time t2 = 2000
      final itemB = PendingSyncItem(
        id: 'SYNC-B1',
        entityType: 'audit_entry',
        entityId: 'LOG-1',
        operation: 'INSERT',
        payload: jsonEncode({
          'seq': 1,
          'actor': 'INVESTIGATOR',
          'action': 'CREATE_CASENOTE',
          'targetType': 'CaseNote',
          'targetId': 'NOTE-001',
          'payloadHash': 'hash_b',
        }),
        localTs: 2000, // Created later locally
      );

      // Device B regains connectivity and pushes FIRST
      transport.currentServerTime = 5000;
      final serverTsB = await transport.pushBatch(
        deviceId: 'DEV-B',
        items: [itemB],
      );

      // Device A regains connectivity and pushes SECOND
      transport.currentServerTime = 6000;
      final serverTsA = await transport.pushBatch(
        deviceId: 'DEV-A',
        items: [itemA],
      );

      // Central chain must order by arrival order:
      // Entry 1 is from Device B (arrived first)
      // Entry 2 is from Device A (arrived second)
      expect(transport.canonicalLogs.length, 2);

      final entry1 = transport.canonicalLogs[0];
      final entry2 = transport.canonicalLogs[1];

      expect(entry1.seq, 1);
      expect(entry1.deviceId, 'DEV-B');
      expect(entry1.localTs, 2000);
      expect(entry1.serverTs, serverTsB);
      expect(entry1.prevHash, AppConstants.genesisHash);

      expect(entry2.seq, 2);
      expect(entry2.deviceId, 'DEV-A');
      expect(entry2.localTs, 1000); // Honest reflection of local creation time
      expect(entry2.serverTs, serverTsA);
      expect(entry2.prevHash, entry1.entryHash); // Links to entry 1!

      // Both entries form an unbroken cryptographic chain
      expect(await transport.verifyCanonicalChain(), isTrue);
    });
  });

  group('Inbound Pull & Anonymized Attribution', () {
    test('pulling contributions merges into local SQLite and never exposes peer investigator identity in RAG/UI', () async {
      // 1. Peer investigator on Device B contributes a criminal and note to Neon
      const peerCriminal = Criminal(
        id: 'C-001',
        name: 'Ravi Kumar',
        aliases: ['RK'],
        dob: '1985-05-12',
        gender: 'Male',
        knownFor: 'Syndicate',
        status: CriminalStatus.UNDER_WATCH,
        lastKnownLoc: 'Sector 5',
        riskLevel: RiskLevel.HIGH,
        createdAt: 1000,
        updatedAt: 1000,
      );
      transport.criminals[peerCriminal.id] = peerCriminal;

      const peerNote = CaseNote(
        id: 'NOTE-PEER-77',
        criminalId: 'C-001',
        author: NoteAuthor.INVESTIGATOR,
        text: 'Informant reports suspect relocated to Warehouse 9.',
        createdAt: 3000,
      );
      transport.caseNotes[peerNote.id] = peerNote;

      // 2. This device pulls from Neon
      networkChecker.forceState(true);
      final syncResult = await services.syncManager.syncNow();
      expect(syncResult.success, isTrue);

      // 3. The pulled note is now in this device's local database
      final localNotes = await services.records.getCaseNotesFor('C-001');
      expect(localNotes.any((n) => n.id == 'NOTE-PEER-77'), isTrue);

      // 4. Verify RAG indexer drafts do NOT include any investigator personal name
      final drafts = await services.indexer.collectDraftsForTest();
      final peerDraft = drafts.firstWhere((d) => d.sourceId == 'NOTE-PEER-77');

      // The text must state generic author role ("Investigator"), never a person's name or device ID
      expect(peerDraft.text, contains('[NOTE-PEER-77] CASE NOTE by Investigator'));
      expect(peerDraft.text, isNot(contains('DEV-B')));
      expect(peerDraft.text, isNot(contains('Vikram')));

      // 5. Verify system prompt rule 7 explicitly prohibits citing investigator identities
      expect(RagService.systemPrompt, contains('Anonymized Attribution'));
      expect(RagService.systemPrompt, contains('Never cite, name, or state which investigator'));
    });
  });

  group('Honest Sync Status Reporting', () {
    test('displays accurate and honest labels without false claims', () {
      // 1. Offline with pending items
      const offlinePending = SyncStatus(
        isConfigured: true,
        isOnline: false,
        isSyncing: false,
        pendingCount: 3,
        lastSyncTime: null,
      );
      expect(offlinePending.label, 'Offline — saved locally, will sync later');

      // 2. Online with pending items
      const onlinePending = SyncStatus(
        isConfigured: true,
        isOnline: true,
        isSyncing: false,
        pendingCount: 2,
        lastSyncTime: null,
      );
      expect(onlinePending.label, '2 items pending sync');

      // Single item singular formatting
      const singlePending = SyncStatus(
        isConfigured: true,
        isOnline: true,
        isSyncing: false,
        pendingCount: 1,
        lastSyncTime: null,
      );
      expect(singlePending.label, '1 item pending sync');

      // 3. Online with successful prior sync
      final now = DateTime.now();
      final onlineSynced = SyncStatus(
        isConfigured: true,
        isOnline: true,
        isSyncing: false,
        pendingCount: 0,
        lastSyncTime: now.subtract(const Duration(minutes: 5)),
      );
      expect(onlineSynced.label, 'Last synced 5m ago');

      // 4. Online with 0 pending but never synced yet (never claim synced when it isn't!)
      const onlineNeverSynced = SyncStatus(
        isConfigured: true,
        isOnline: true,
        isSyncing: false,
        pendingCount: 0,
        lastSyncTime: null,
      );
      expect(onlineNeverSynced.label, 'Awaiting initial sync');
      expect(onlineNeverSynced.label, isNot(contains('synced with Neon')));

      // 5. Sync in progress
      const syncing = SyncStatus(
        isConfigured: true,
        isOnline: true,
        isSyncing: true,
        pendingCount: 1,
        lastSyncTime: null,
      );
      expect(syncing.label, 'Syncing with Neon...');
    });
  });

  group('Add-Data UI & Storage via CrimeRepository', () {
    test('adding documents, photos, and free-text notes saves to SQLite immediately, logs locally, and enqueues for sync', () async {
      // Seed a criminal record first
      const criminal = Criminal(
        id: 'C-ADD-01',
        name: 'Target Subject',
        aliases: ['TS'],
        dob: '1992-04-10',
        gender: 'Male',
        knownFor: 'Smuggling',
        status: CriminalStatus.UNDER_WATCH,
        lastKnownLoc: 'Harbor Gate',
        riskLevel: RiskLevel.HIGH,
        createdAt: 1000,
        updatedAt: 1000,
      );
      await services.records.addCriminal(
        context: services.session,
        criminal: criminal,
      );

      final initialPending = services.syncManager.status.pendingCount;

      // 1. Add Document media item
      final docItem = MediaItem(
        id: 'DOC-001',
        criminalId: 'C-ADD-01',
        type: MediaType.DOCUMENT,
        filePath: '/storage/docs/seizure_manifest.pdf',
        caption: 'Investigator upload: seizure_manifest.pdf',
        isSynthetic: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await services.records.addMedia(
        context: services.session,
        item: docItem,
      );

      // Verify immediate local SQLite availability
      final mediaList = await services.records.getMediaFor('C-ADD-01');
      expect(mediaList.any((m) => m.id == 'DOC-001'), isTrue);
      expect(mediaList.firstWhere((m) => m.id == 'DOC-001').type, MediaType.DOCUMENT);

      // 2. Add free-text case note / detail
      final note = await services.records.writeCaseNote(
        context: services.session,
        criminalId: 'C-ADD-01',
        text: 'Informant confirmed vehicle registration number DL-04-AB-1234 at the scene.',
      );

      // Verify immediate local SQLite availability
      final notesList = await services.records.getCaseNotesFor('C-ADD-01');
      expect(notesList.any((n) => n.id == note.id), isTrue);
      expect(notesList.firstWhere((n) => n.id == note.id).text, contains('DL-04-AB-1234'));

      // 3. Verify local audit trail records both actions
      final recentLogs = await services.audit.getRecentLogs(limit: 10);
      expect(recentLogs.any((l) => l.targetId == 'DOC-001' && l.action == LogAction.UPLOAD), isTrue);
      expect(recentLogs.any((l) => l.targetId == note.id && l.action == LogAction.CREATE_CASENOTE), isTrue);

      // 4. Verify local hash chain is completely valid
      final verification = await services.verifier.verifyChain();
      expect(verification.isValid, isTrue);

      // 5. Verify pending queue incremented for outbound sync
      final updatedPending = services.syncManager.status.pendingCount;
      expect(updatedPending, greaterThan(initialPending));
    });
  });
}
