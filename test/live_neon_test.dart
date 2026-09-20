import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

import 'package:crime_intel/core/config/app_config.dart';
import 'package:crime_intel/sync/models/sync_models.dart';
import 'package:crime_intel/sync/neon_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Live Neon round-trip verification', () async {
    await AppConfig.load();
    final url = AppConfig.neonDatabaseUrl;

    if (url.isEmpty) {
      // ignore: avoid_print
      print('SKIPPING live Neon test: NEON_DATABASE_URL is not set.');
      return;
    }

    final client = NeonClient(connectionUrl: url);
    expect(client.isConfigured, isTrue);

    // ignore: avoid_print
    print('Testing live connection...');
    final connected = await client.testConnection();
    // ignore: avoid_print
    print('Connected: $connected');
    expect(connected, isTrue, reason: 'Must successfully connect to Neon instance');

    // ignore: avoid_print
    print('Ensuring schema...');
    await client.ensureSchema();
    // ignore: avoid_print
    print('Schema ensured.');

    // 3. Round-trip push of criminal, case note, media item, and audit entry
    // Per docs/TechSpec.md §8.4, test records against shared Neon must use the
    // __TEST__ prefix and be deleted immediately after verification.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final testDeviceId = '__TEST__-DEV-LIVE-${nowMs % 10000}';
    final testCrimId = '__TEST__-C-LIVE-${nowMs % 100000}';
    final testNoteId = '__TEST__-NOTE-LIVE-${nowMs % 100000}';
    final testMediaId = '__TEST__-MEDIA-LIVE-${nowMs % 100000}';
    final testAuditId = '__TEST__-LOG-LIVE-$nowMs';

    final criminalItem = PendingSyncItem(
      id: '__TEST__-SYNC-CRIM-$nowMs',
      entityType: 'criminal',
      entityId: testCrimId,
      operation: 'INSERT',
      payload: '{"id":"$testCrimId","name":"__TEST__ Live Verification Subject","aliases":"TLVS","dob":"1988-08-08","gender":"Male","knownFor":"Testing","status":"UNDER_WATCH","lastKnownLoc":"Sector 1","riskLevel":"HIGH","createdAt":$nowMs,"updatedAt":$nowMs}',
      localTs: nowMs,
    );

    final noteItem = PendingSyncItem(
      id: '__TEST__-SYNC-NOTE-$nowMs',
      entityType: 'case_note',
      entityId: testNoteId,
      operation: 'INSERT',
      payload: '{"id":"$testNoteId","criminalId":"$testCrimId","author":"INVESTIGATOR","text":"Live test note verified from terminal.","createdAt":$nowMs}',
      localTs: nowMs,
    );

    final mediaItem = PendingSyncItem(
      id: '__TEST__-SYNC-MEDIA-$nowMs',
      entityType: 'media_item',
      entityId: testMediaId,
      operation: 'INSERT',
      payload: '{"id":"$testMediaId","criminalId":"$testCrimId","type":"DOCUMENT","filePath":"/test/evidence.pdf","caption":"Investigator upload: evidence.pdf","isSynthetic":1,"createdAt":$nowMs}',
      localTs: nowMs,
    );

    final auditItem = PendingSyncItem(
      id: '__TEST__-SYNC-AUDIT-$nowMs',
      entityType: 'audit_entry',
      entityId: testAuditId,
      operation: 'INSERT',
      payload: '{"seq":1,"actor":"INVESTIGATOR","action":"CREATE_CASENOTE","targetType":"CaseNote","targetId":"$testNoteId","payloadHash":"hash_$nowMs"}',
      localTs: nowMs,
    );

    try {
      // ignore: avoid_print
      print('Pushing full batch (criminal, note, media, audit) for device $testDeviceId...');
      final serverTs = await client.pushBatch(
        deviceId: testDeviceId,
        items: [criminalItem, noteItem, mediaItem, auditItem],
      );
      // ignore: avoid_print
      print('Pushed batch. ServerTs: $serverTs');
      expect(serverTs, greaterThan(0));

      // 4. Inbound pull: read back from Neon and verify round-trip
      // ignore: avoid_print
      print('Pulling records back from Neon since timestamp ${nowMs - 60000}...');
      final pullResult = await client.pullSince(nowMs - 60000);
      // ignore: avoid_print
      print('Pulled ${pullResult.criminals.length} criminals, ${pullResult.caseNotes.length} notes, ${pullResult.mediaItems.length} media items.');

      expect(pullResult.criminals.any((c) => c.id == testCrimId), isTrue,
          reason: 'Pushed criminal must be readable from Neon');
      expect(pullResult.caseNotes.any((n) => n.id == testNoteId), isTrue,
          reason: 'Pushed case note must be readable from Neon');
      expect(pullResult.mediaItems.any((m) => m.id == testMediaId), isTrue,
          reason: 'Pushed media item must be readable from Neon');

      final pulledNote = pullResult.caseNotes.firstWhere((n) => n.id == testNoteId);
      expect(pulledNote.text, 'Live test note verified from terminal.');
      expect(pulledNote.author.displayName, 'Investigator',
          reason: 'Attribution must be anonymized role, never an investigator personal identity');

      // 5. Fetch canonical logs and verify central hash chain integrity
      // ignore: avoid_print
      print('Fetching canonical logs...');
      final logs = await client.fetchCanonicalLogs(limit: 10);
      // ignore: avoid_print
      print('Fetched ${logs.length} canonical logs.');
      expect(logs.isNotEmpty, isTrue);
      expect(logs.any((l) => l.deviceId == testDeviceId), isTrue);

      // ignore: avoid_print
      print('Verifying canonical chain...');
      final isChainValid = await client.verifyCanonicalChain();
      // ignore: avoid_print
      print('Canonical chain valid: $isChainValid');
      expect(isChainValid, isTrue, reason: 'Central Neon canonical chain must be unbroken');
    } finally {
      // Teardown: purge verification artifacts immediately so live DB remains clean
      // ignore: avoid_print
      print('Cleaning up test artifacts from Neon...');
      final uri = Uri.parse(url.trim());
      final userInfo = uri.userInfo.split(':');
      final endpoint = Endpoint(
        host: uri.host,
        port: uri.port == 0 ? 5432 : uri.port,
        database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'neondb',
        username: userInfo.isNotEmpty ? userInfo[0] : null,
        password: userInfo.length > 1 ? userInfo.sublist(1).join(':') : null,
      );

      Connection? cleanupConn;
      try {
        cleanupConn = await Connection.open(
          endpoint,
          settings: const ConnectionSettings(
            sslMode: SslMode.require,
            connectTimeout: Duration(seconds: 15),
            queryTimeout: Duration(seconds: 15),
          ),
        );
        await cleanupConn.execute(
          Sql.named('DELETE FROM shared_criminals WHERE id = @id'),
          parameters: {'id': testCrimId},
        );
        await cleanupConn.execute(
          Sql.named('DELETE FROM shared_case_notes WHERE id = @id'),
          parameters: {'id': testNoteId},
        );
        await cleanupConn.execute(
          Sql.named('DELETE FROM shared_media_items WHERE id = @id'),
          parameters: {'id': testMediaId},
        );
        await cleanupConn.execute(
          Sql.named('DELETE FROM central_audit_log WHERE device_id = @devId'),
          parameters: {'devId': testDeviceId},
        );
        await cleanupConn.execute(
          "SELECT setval(pg_get_serial_sequence('central_audit_log', 'seq'), (SELECT COALESCE(MAX(seq), 1) FROM central_audit_log))",
        );
        // ignore: avoid_print
        print('Teardown cleanup completed.');
      } catch (cleanupErr) {
        // ignore: avoid_print
        print('Warning: Teardown cleanup failed: $cleanupErr');
      } finally {
        await cleanupConn?.close();
      }
    }
  }, tags: ['neon'], timeout: const Timeout(Duration(minutes: 2)));
}
