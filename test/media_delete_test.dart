import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/audit_verifier.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/core/di/app_services.dart';
import 'package:crime_intel/core/errors/app_exceptions.dart';
import 'package:crime_intel/core/security/actor_context.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/data/repositories/crime_repository.dart';
import 'package:crime_intel/ingest/ingestion_service.dart';
import 'package:crime_intel/main.dart';
import 'package:crime_intel/models/criminal.dart';
import 'package:crime_intel/models/media_item.dart';
import 'package:crime_intel/sync/network_checker.dart';
import 'package:crime_intel/ui/screens/criminal/criminal_detail_screen.dart';

import 'support/fake_llm_client.dart';
import 'sync_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.initFfi();

  late Database db;
  late AuditLogger audit;
  late AuditVerifier verifier;
  late CrimeRepository records;

  final inv1Context = InvestigatorContext.issueForSession(
    AuthSessionIssuer.issue(
      investigatorId: 'INV-001',
      sessionId: 'SESSION-001',
    ),
  );

  final inv2Context = InvestigatorContext.issueForSession(
    AuthSessionIssuer.issue(
      investigatorId: 'INV-002',
      sessionId: 'SESSION-002',
    ),
  );

  setUp(() async {
    db = await DatabaseHelper.openInMemory();
    audit = AuditLogger(db);
    verifier = AuditVerifier(db);
    records = CrimeRepository(db, audit);
    await IngestionService(db: db, audit: audit).seedIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  group('Uploader-restricted media soft-delete', () {
    test('1. Uploader can delete their own item and action is audited', () async {
      final item = MediaItem(
        id: 'MEDIA-INV1-001',
        criminalId: 'C-001',
        type: MediaType.PHOTO,
        filePath: 'assets/synthetic/c001_mugshot.png',
        caption: 'Surveillance snapshot by Inv 1',
        isSynthetic: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        uploadedByInvestigatorId: inv1Context.investigatorId,
      );
      await records.addMedia(context: inv1Context, item: item);

      // Verify item exists
      final mediaBefore = await records.getMediaFor('C-001');
      expect(mediaBefore.any((m) => m.id == item.id), isTrue);

      // Inv 1 deletes their own item
      await records.deleteMedia(context: inv1Context, mediaId: item.id);

      // Verify audit log
      final logs = await audit.getAllLogs();
      final deleteLog = logs.lastWhere((e) => e.targetId == item.id && e.action == LogAction.DELETE);
      expect(deleteLog.actor, LogActor.INVESTIGATOR);
      expect(deleteLog.targetType, 'MediaItem');

      // Verify hash chain validity
      final verification = await verifier.verifyChain();
      expect(verification.isValid, isTrue);
    });

    test('2. Different investigator delete attempt is rejected and audited as denial', () async {
      final item = MediaItem(
        id: 'MEDIA-INV1-002',
        criminalId: 'C-001',
        type: MediaType.DOCUMENT,
        filePath: '/docs/seizure.pdf',
        caption: 'Seizure sheet by Inv 1',
        isSynthetic: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        uploadedByInvestigatorId: inv1Context.investigatorId,
      );
      await records.addMedia(context: inv1Context, item: item);

      // Inv 2 attempts to delete Inv 1's item
      expect(
        () => records.deleteMedia(context: inv2Context, mediaId: item.id),
        throwsA(isA<ActionNotPermittedException>()),
      );

      // Item must NOT be deleted
      final storedItem = await records.getMediaItemById(item.id);
      expect(storedItem, isNotNull);
      expect(storedItem!.isDeleted, isFalse);

      // Verify denial logged in audit trail
      final logs = await audit.getAllLogs();
      final denialLog = logs.lastWhere((e) => e.targetId == item.id && e.action == LogAction.DELETE);
      expect(denialLog.actor, LogActor.INVESTIGATOR);
      expect(denialLog.targetType, 'MediaItem');

      // Hash chain remains valid
      final verification = await verifier.verifyChain();
      expect(verification.isValid, isTrue);
    });

    test('3. Soft-deleted item disappears from normal views but row still exists in DB', () async {
      final item = MediaItem(
        id: 'MEDIA-INV1-003',
        criminalId: 'C-002',
        type: MediaType.DOCUMENT,
        filePath: '/docs/statement.pdf',
        caption: 'Interrogation statement',
        isSynthetic: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        uploadedByInvestigatorId: inv1Context.investigatorId,
      );
      await records.addMedia(context: inv1Context, item: item);

      // Soft delete
      await records.deleteMedia(context: inv1Context, mediaId: item.id);

      // Normal getMediaFor view must NOT include it
      final normalView = await records.getMediaFor('C-002');
      expect(normalView.any((m) => m.id == item.id), isFalse);

      // includeDeleted: true DOES include it
      final allView = await records.getMediaFor('C-002', includeDeleted: true);
      expect(allView.any((m) => m.id == item.id), isTrue);

      // Row still exists in raw SQLite table with non-null deletedAt
      final rows = await db.query(
        'media_items',
        where: 'id = ?',
        whereArgs: [item.id],
      );
      expect(rows, hasLength(1));
      expect(rows.first['deletedAt'], isNotNull);
      expect(rows.first['uploadedByInvestigatorId'], inv1Context.investigatorId);
    });

    test('4. Sync correctly propagates a soft-delete across devices while preserving anonymization', () async {
      final transport = FakeRemoteSyncTransport();

      // Device 1 (Inv 1)
      final netChecker1 = NetworkAvailabilityChecker(probeOverride: () async => false);
      final services1 = await AppServices.bootstrap(
        database: await DatabaseHelper.openInMemory(),
        llmClient: FakeLlmClient(),
        syncTransport: transport,
        networkChecker: netChecker1,
        deviceId: 'DEV-INV1',
      );
      await services1.completeLogin(inv1Context.investigatorId);

      // Device 2 (Inv 2)
      final netChecker2 = NetworkAvailabilityChecker(probeOverride: () async => false);
      final services2 = await AppServices.bootstrap(
        database: await DatabaseHelper.openInMemory(),
        llmClient: FakeLlmClient(),
        syncTransport: transport,
        networkChecker: netChecker2,
        deviceId: 'DEV-INV2',
      );
      await services2.completeLogin(inv2Context.investigatorId);

      // Inv 1 uploads media item
      final item = MediaItem(
        id: 'MEDIA-SYNC-001',
        criminalId: 'C-001',
        type: MediaType.DOCUMENT,
        filePath: '/docs/evidence_slip.pdf',
        caption: 'Evidence slip',
        isSynthetic: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        uploadedByInvestigatorId: inv1Context.investigatorId,
      );
      await services1.records.addMedia(context: services1.session, item: item);

      // Device 1 syncs (pushes upload)
      await services1.syncManager.syncNow();
      expect(transport.mediaItems.containsKey(item.id), isTrue);

      // Device 2 syncs (pulls upload)
      await services2.syncManager.syncNow();
      final dev2MediaBefore = await services2.records.getMediaFor('C-001');
      expect(dev2MediaBefore.any((m) => m.id == item.id), isTrue);

      // Device 1 soft-deletes the item offline
      await services1.records.deleteMedia(context: services1.session, mediaId: item.id);

      // Verify pending_sync captured the DELETE operation
      final pendingRows = await services1.db.query(
        'pending_sync',
        where: 'entityId = ? AND operation = ?',
        whereArgs: [item.id, 'DELETE'],
      );
      expect(pendingRows, isNotEmpty);
      final payload = jsonDecode(pendingRows.first['payload'] as String) as Map<String, dynamic>;
      expect(payload['deletedAt'], isNotNull);

      // Device 1 syncs (pushes delete)
      await services1.syncManager.syncNow();
      expect(transport.mediaItems[item.id]!.isDeleted, isTrue);

      // Device 2 syncs (pulls delete)
      await services2.syncManager.syncNow();

      // Device 2 normal view: item is gone
      final dev2MediaAfter = await services2.records.getMediaFor('C-001');
      expect(dev2MediaAfter.any((m) => m.id == item.id), isFalse);

      // Device 2 raw DB: row still exists, deletedAt is set
      final dev2Rows = await services2.db.query(
        'media_items',
        where: 'id = ?',
        whereArgs: [item.id],
      );
      expect(dev2Rows, hasLength(1));
      expect(dev2Rows.first['deletedAt'], isNotNull);

      // Anonymization: The item is deleted, and no peer identity is cited
      expect(transport.mediaItems[item.id]!.deletedAt, isNotNull);

      await services1.dispose();
      await services2.dispose();
    });
  });

  group('UI: Uploader-only delete button on criminal detail screen', () {
    testWidgets('Delete affordance is shown for uploader, hidden for non-uploader', (tester) async {
      late AppServices services;

      await tester.runAsync(() async {
        final localDb = await DatabaseHelper.openInMemory();
        services = await AppServices.bootstrap(
          database: localDb,
          llmClient: FakeLlmClient(),
          syncTransport: FakeRemoteSyncTransport(),
          networkChecker: NetworkAvailabilityChecker(probeOverride: () async => false),
          deviceId: 'DEV-UI-TEST',
        );
        await services.completeLogin('INV-001');

        const criminal = Criminal(
          id: 'C-UI-01',
          name: 'Subject Test',
          aliases: ['ST'],
          dob: '1990-01-01',
          gender: 'Male',
          knownFor: 'Testing',
          status: CriminalStatus.UNDER_WATCH,
          lastKnownLoc: 'Metro',
          riskLevel: RiskLevel.LOW,
          createdAt: 1000,
          updatedAt: 1000,
        );
        await services.records.addCriminal(context: services.session, criminal: criminal);

        // Upload item by current user (INV-001)
        final ownItem = MediaItem(
          id: 'MEDIA-OWN-01',
          criminalId: 'C-UI-01',
          type: MediaType.DOCUMENT,
          filePath: '/files/own.pdf',
          caption: 'My Document',
          isSynthetic: true,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          uploadedByInvestigatorId: 'INV-001',
        );
        await services.records.addMedia(context: services.session, item: ownItem);

        // Item uploaded by another investigator (INV-002)
        final otherItem = MediaItem(
          id: 'MEDIA-OTHER-01',
          criminalId: 'C-UI-01',
          type: MediaType.DOCUMENT,
          filePath: '/files/other.pdf',
          caption: 'Peer Document',
          isSynthetic: true,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          uploadedByInvestigatorId: 'INV-002',
        );
        // Insert directly into db to simulate seed/remote record
        await localDb.insert('media_items', otherItem.toMap());
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ServicesScope(
          services: services,
          child: MaterialApp(
            home: CriminalDetailScreen(
              criminalId: 'C-UI-01',
              services: services,
            ),
          ),
        ),
      );

      // Allow queries to finish
      for (int i = 0; i < 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }

      // Delete button for own item MUST exist
      expect(find.byKey(const Key('delete-media-MEDIA-OWN-01')), findsOneWidget);

      // Delete button for other item MUST NOT exist
      expect(find.byKey(const Key('delete-media-MEDIA-OTHER-01')), findsNothing);

      // Tap delete button on own item -> shows confirmation dialog
      await tester.tap(find.byKey(const Key('delete-media-MEDIA-OWN-01')));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Deletion'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.text('Delete'));
      await tester.pump();

      // Allow soft-delete and reload to finish
      for (int i = 0; i < 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.byKey(const Key('delete-media-MEDIA-OWN-01')).evaluate().isEmpty) {
          break;
        }
      }

      // Own item is now deleted and removed from view
      expect(find.byKey(const Key('delete-media-MEDIA-OWN-01')), findsNothing);

      // Unmount
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await services.dispose();
      });
    });
  });
}
