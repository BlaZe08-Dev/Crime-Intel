import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crime_intel/core/di/app_services.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/main.dart';
import 'package:crime_intel/models/criminal.dart';
import 'package:crime_intel/sync/network_checker.dart';
import 'package:crime_intel/ui/screens/criminal/criminal_detail_screen.dart';
import 'package:crime_intel/ui/widgets/sync_status_badge.dart';

import 'sync_test.dart';
import 'support/fake_llm_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.initFfi();

  testWidgets('SyncStatusBadge builds without throwing when ServicesScope is above MaterialApp', (tester) async {
    late AppServices services;

    await tester.runAsync(() async {
      final db = await DatabaseHelper.openInMemory();
      final transport = FakeRemoteSyncTransport();
      final networkChecker = NetworkAvailabilityChecker(
        probeOverride: () async => false,
      );

      services = await AppServices.bootstrap(
        database: db,
        llmClient: FakeLlmClient(),
        syncTransport: transport,
        networkChecker: networkChecker,
        deviceId: 'DEV-TEST-WIDGET',
      );
      await services.completeLogin('INV-9999');

      const criminal = Criminal(
        id: 'C-WIDGET-01',
        name: 'Target Suspect With Very Long Detailed Display Name For Overflow Check',
        aliases: ['TS'],
        dob: '1990-01-01',
        gender: 'Male',
        knownFor: 'Cybercrime',
        status: CriminalStatus.UNDER_WATCH,
        lastKnownLoc: 'Metro Hub',
        riskLevel: RiskLevel.HIGH,
        createdAt: 1000,
        updatedAt: 1000,
      );
      await services.records.addCriminal(
        context: services.session,
        criminal: criminal,
      );
    });

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ServicesScope(
        services: services,
        child: MaterialApp(
          home: CriminalDetailScreen(
            criminalId: 'C-WIDGET-01',
            services: services,
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      // Allow _CriminalDetailScreenState._load SQLite queries to finish
      for (int i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(find.byType(SyncStatusBadge), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount before disposing services
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await services.dispose();
    });
  });

  testWidgets('SyncStatusBadge constrained width prevents RenderFlex overflow even on small width', (tester) async {
    late AppServices services;

    await tester.runAsync(() async {
      final db = await DatabaseHelper.openInMemory();
      final transport = FakeRemoteSyncTransport();
      final networkChecker = NetworkAvailabilityChecker(
        probeOverride: () async => false,
      );

      services = await AppServices.bootstrap(
        database: db,
        llmClient: FakeLlmClient(),
        syncTransport: transport,
        networkChecker: networkChecker,
        deviceId: 'DEV-TEST-WIDGET-2',
      );
      await services.completeLogin('INV-9999');
      // Allow audit login enqueue to complete
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    // Narrow width constraint to stress test horizontal row bounds
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ServicesScope(
        services: services,
        child: const MaterialApp(
          home: Scaffold(
            appBar: null,
            body: Row(
              children: [
                Expanded(child: Text('Dashboard Section Title')),
                SizedBox(
                  width: 200,
                  child: SyncStatusBadge(compact: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(SyncStatusBadge), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount before disposing services
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await services.dispose();
    });
  });
}
