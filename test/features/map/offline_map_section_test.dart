import 'dart:async';

import 'package:bu_bus_tracker/features/map/application/offline_map_service.dart';
import 'package:bu_bus_tracker/features/map/domain/offline_map_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Opens the Profile tab, where the offline map section lives.
Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a ready map with its details', (tester) async {
    await pumpApp(tester);
    await _openProfile(tester);

    expect(find.text('Offline map'), findsOneWidget);
    expect(find.text('Ready for offline use'), findsOneWidget);
    expect(find.text('The bus routes, about 10 by 6 km'), findsOneWidget);
    expect(find.text('OpenStreetMap, 10 November 2026'), findsOneWidget);
    expect(find.text('14.6 MB'), findsOneWidget);
  });

  testWidgets('checking a complete map says so', (tester) async {
    final repository = FakeMapTileRepository();
    await pumpApp(tester, mapTileRepository: repository);
    await _openProfile(tester);

    await _tap(tester, 'Check map');

    expect(repository.verifyCalls, 1);
    expect(find.text('The saved map is complete.'), findsOneWidget);
    expect(
      find.text('Checked just now: the saved map is complete.'),
      findsOneWidget,
    );
  });

  testWidgets('a damaged map offers to install it again', (tester) async {
    final repository = FakeMapTileRepository(integrity: MapIntegrity.damaged);
    await pumpApp(tester, mapTileRepository: repository);
    await _openProfile(tester);

    await _tap(tester, 'Check map');
    expect(find.text('The saved map is damaged'), findsOneWidget);
    expect(find.text('Check map'), findsNothing);

    await _tap(tester, 'Install again');

    expect(repository.deleteCalls, 1);
    expect(repository.installCalls, 1);
    expect(find.text('Ready for offline use'), findsOneWidget);
  });

  testWidgets('checking for an update explains how updates arrive', (
    tester,
  ) async {
    await pumpApp(tester);
    await _openProfile(tester);

    await _tap(tester, 'Check for update');

    expect(find.textContaining('arrives with app updates'), findsOneWidget);
  });

  testWidgets('removing asks first, and cancelling keeps the map', (
    tester,
  ) async {
    final repository = FakeMapTileRepository();
    await pumpApp(tester, mapTileRepository: repository);
    await _openProfile(tester);

    await _tap(tester, 'Remove');
    expect(find.text('Remove the map?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 0);
    expect(find.text('Ready for offline use'), findsOneWidget);
  });

  testWidgets('a removed map can be installed again', (tester) async {
    final repository = FakeMapTileRepository();
    final container = await pumpApp(tester, mapTileRepository: repository);
    await _openProfile(tester);

    await _tap(tester, 'Remove');
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 1);
    expect(find.text('Not on this device'), findsOneWidget);
    expect(find.text('Nothing'), findsOneWidget);

    await _tap(tester, 'Install map');

    expect(find.text('Ready for offline use'), findsOneWidget);
    expect(
      container.read(offlineMapServiceProvider).status,
      OfflineMapStatus.ready,
    );
  });

  testWidgets('shows progress while installing, and can be cancelled', (
    tester,
  ) async {
    final repository = FakeMapTileRepository(
      installation: const MapInstallation(
        status: OfflineMapStatus.notInstalled,
      ),
    )..installGate = Completer<void>();
    await pumpApp(tester, mapTileRepository: repository);
    await _openProfile(tester);

    expect(find.text('Installing the map'), findsOneWidget);
    expect(find.text('50% saved to this device.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await _tap(tester, 'Cancel');
    repository.installGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Installation interrupted'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('a failed install shows the reason and a retry', (tester) async {
    final repository = FakeMapTileRepository(
      installation: const MapInstallation(
        status: OfflineMapStatus.notInstalled,
      ),
      installError: Exception('disk full'),
    );
    await pumpApp(tester, mapTileRepository: repository);
    await _openProfile(tester);

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining('Free up some storage'), findsOneWidget);

    repository.installError = null;
    await _tap(tester, 'Try again');

    expect(find.text('Ready for offline use'), findsOneWidget);
  });

  testWidgets('offers no actions where the map cannot be managed', (
    tester,
  ) async {
    await pumpApp(
      tester,
      mapTileRepository: FakeMapTileRepository(canManage: false),
    );
    await _openProfile(tester);

    expect(find.text('Browser preview'), findsOneWidget);
    expect(find.text('Check map'), findsNothing);
    expect(find.text('Remove'), findsNothing);
  });
}
