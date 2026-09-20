import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crime_intel/core/di/app_services.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/main.dart';
import 'package:crime_intel/sync/network_checker.dart';
import 'package:crime_intel/ui/screens/graph/graph_screen.dart';

import 'support/fake_llm_client.dart';
import 'sync_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.initFfi();

  testWidgets(
    'GraphScreen places selected node at the top of the side panel and deselects via close button',
    (tester) async {
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
          deviceId: 'DEV-TEST-GRAPH',
        );
        await services.prepareData();
        await services.completeLogin('INV-9999');
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ServicesScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: GraphScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Initial overview layout without any node selected
      expect(find.text('Network Analysis'), findsOneWidget);
      expect(find.text('KEY INDIVIDUALS (PAGERANK)'), findsOneWidget);
      expect(find.text('FLAGGED PATTERNS'), findsOneWidget);
      expect(find.text('SELECTED NODE'), findsNothing);

      // 2. Select Devraj Malhotra by tapping his row in Key Individuals
      final devrajRow = find.text('Devraj Malhotra');
      expect(devrajRow, findsOneWidget);
      await tester.tap(devrajRow);
      await tester.pumpAndSettle();

      // 3. Selected Node detail is now visible
      expect(find.text('SELECTED NODE'), findsOneWidget);
      expect(find.text('Devraj Malhotra'), findsWidgets);

      // 4. Prominent placement check: SELECTED NODE is positioned ABOVE KEY INDIVIDUALS
      final selectedNodeY = tester.getTopLeft(find.text('SELECTED NODE')).dy;
      final keyIndividualsY =
          tester.getTopLeft(find.text('KEY INDIVIDUALS (PAGERANK)')).dy;

      expect(
        selectedNodeY,
        lessThan(keyIndividualsY),
        reason: 'Selected node detail must appear above Key Individuals at the top of the panel',
      );

      // 5. Verify deselect / close button dismisses selected node
      final deselectButton = find.byTooltip('Deselect');
      expect(deselectButton, findsOneWidget);

      await tester.tap(deselectButton);
      await tester.pumpAndSettle();

      // 6. Selected node card is dismissed; returns to default layout where Key Individuals & Flagged Patterns are visible
      expect(find.text('SELECTED NODE'), findsNothing);
      expect(find.text('KEY INDIVIDUALS (PAGERANK)'), findsOneWidget);
      expect(find.text('FLAGGED PATTERNS'), findsOneWidget);
    },
  );
}
