import 'package:flutter_test/flutter_test.dart';

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

    // 3. Round-trip push of a test audit entry to the central canonical chain
    final testDeviceId = 'DEV-LIVE-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final testItem = PendingSyncItem(
      id: 'SYNC-LIVE-${DateTime.now().millisecondsSinceEpoch}',
      entityType: 'audit_entry',
      entityId: 'LIVE-001',
      operation: 'INSERT',
      payload: '{"seq":1,"actor":"INVESTIGATOR","action":"LOGIN_OK","targetType":"System","targetId":"NEON_TEST","payloadHash":"test_hash"}',
      localTs: DateTime.now().millisecondsSinceEpoch,
    );

    // ignore: avoid_print
    print('Pushing batch for device $testDeviceId...');
    final serverTs = await client.pushBatch(
      deviceId: testDeviceId,
      items: [testItem],
    );
    // ignore: avoid_print
    print('Pushed batch. ServerTs: $serverTs');
    expect(serverTs, greaterThan(0));

    // 4. Fetch canonical logs and verify central hash chain integrity
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
  }, tags: ['neon'], timeout: const Timeout(Duration(minutes: 2)));
}
