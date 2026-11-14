import 'package:bu_bus_tracker/core/services/location_service.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/features/map/application/map_camera_controller.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:bu_bus_tracker/features/map/application/my_location_mode.dart';
import 'package:bu_bus_tracker/features/map/domain/offline_map_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Drags the bottom sheet up so its full content is on screen.
Future<void> _expandSheet(WidgetTester tester) async {
  await tester.drag(find.text('No live buses'), const Offset(0, -420));
  await tester.pumpAndSettle();
}

void main() {
  group('Home screen', () {
    testWidgets('shows the map, its controls and the data credit', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.byKey(fakeMapKey), findsOneWidget);
      expect(find.byTooltip('University'), findsOneWidget);
      expect(find.byTooltip('My location'), findsOneWidget);
      expect(find.text('© OpenStreetMap'), findsOneWidget);
    });

    testWidgets('says plainly that there are no live buses or routes', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.text('No live buses'), findsOneWidget);
      expect(find.text('Live tracking is not available yet.'), findsOneWidget);

      await _expandSheet(tester);
      expect(find.textContaining('No routes have been added yet'), findsOne);
      expect(find.textContaining('Demo data'), findsNothing);
    });

    testWidgets('labels demo data and lists its routes', (tester) async {
      await pumpApp(tester, network: sampleDemoNetwork);

      expect(find.text('Demo data, not official routes'), findsOneWidget);

      await _expandSheet(tester);
      expect(inSheet(find.text('Sample route')), findsOneWidget);
      expect(find.text('Stop A to Stop B · 2 stops'), findsOneWidget);
    });

    testWidgets('tapping the credit shows the licence note', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('© OpenStreetMap'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Open Database Licence'), findsOneWidget);
    });
  });

  testWidgets('hides the map buttons and credit while there is no map', (
    tester,
  ) async {
    await pumpApp(
      tester,
      mapTileRepository: FakeMapTileRepository(
        installation: const MapInstallation(
          status: OfflineMapStatus.notInstalled,
        ),
        installError: Exception('disk full'),
      ),
    );

    expect(find.byTooltip('University'), findsNothing);
    expect(find.byTooltip('My location'), findsNothing);
    expect(find.text('© OpenStreetMap'), findsNothing);
    // The rest of the home screen is still there.
    expect(find.text('No live buses'), findsOneWidget);
  });

  group('Connection label', () {
    testWidgets('is hidden while the device is connected', (tester) async {
      await pumpApp(tester);

      expect(find.textContaining('No connection'), findsNothing);
    });

    testWidgets('appears and disappears as the connection changes', (
      tester,
    ) async {
      final connectivity = FakeConnectivityService();
      await pumpApp(tester, connectivityService: connectivity);

      connectivity.setConnected(false);
      await tester.pumpAndSettle();
      expect(
        find.text('No connection. The map still works offline.'),
        findsOneWidget,
      );
      // The map itself stays on screen.
      expect(find.byKey(fakeMapKey), findsOneWidget);

      connectivity.setConnected(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('No connection'), findsNothing);
    });

    testWidgets('is shown when the app starts without a connection', (
      tester,
    ) async {
      await pumpApp(
        tester,
        connectivityService: FakeConnectivityService(connected: false),
      );

      expect(find.textContaining('No connection'), findsOneWidget);
    });
  });

  group('My location', () {
    testWidgets('shows the position on the map when it is found', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        locationService: FakeLocationService(
          const LocationFound(GeoPoint(22.6601, 90.3630), accuracyMeters: 8),
        ),
      );
      expect(container.read(userLocationVisibleProvider), isFalse);

      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();

      expect(container.read(userLocationVisibleProvider), isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the button follows, then turns with the phone, then back', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        locationService: FakeLocationService(
          const LocationFound(GeoPoint(22.6601, 90.3630), accuracyMeters: 8),
        ),
      );
      MyLocationMode mode() => container.read(myLocationModeProvider);
      expect(mode(), MyLocationMode.free);

      // The first tap finds the passenger and keeps up with them.
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(mode(), MyLocationMode.following);

      // The next turns the map with the phone, and says so once.
      await tester.tap(find.byTooltip(RegExp('^Following you')));
      await tester.pumpAndSettle();
      expect(mode(), MyLocationMode.compass);
      expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
      expect(
        find.textContaining('The map now turns with your phone'),
        findsOneWidget,
      );

      // The one after goes back to north-up.
      await tester.tap(find.byTooltip(RegExp('^Turning with your phone')));
      await tester.pumpAndSettle();
      expect(mode(), MyLocationMode.following);
      expect(find.byIcon(Icons.explore_rounded), findsNothing);
    });

    testWidgets('following a bus lets go of the passenger, and the reverse', (
      tester,
    ) async {
      // Wide, so the bus's panel is beside the map buttons, not over them.
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = await pumpApp(
        tester,
        locationService: FakeLocationService(
          const LocationFound(GeoPoint(22.6601, 90.3630), accuracyMeters: 8),
        ),
      );
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(container.read(myLocationModeProvider), MyLocationMode.following);

      final selection = container.read(mapSelectionProvider.notifier)
        ..selectBus('bus')
        ..setFollowingBus(true);
      await tester.pumpAndSettle();
      expect(container.read(myLocationModeProvider), MyLocationMode.free);

      // Asking for one's own position stops following the bus.
      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();
      expect(container.read(mapSelectionProvider).isFollowingBus, isFalse);
      expect(container.read(mapSelectionProvider).busId, 'bus');
      expect(container.read(myLocationModeProvider), MyLocationMode.following);
      selection.clear();
    });

    test('where the map cannot turn with the phone, it only follows', () {
      expect(
        nextMyLocationMode(MyLocationMode.free, hasCompassMode: false),
        MyLocationMode.following,
      );
      expect(
        nextMyLocationMode(MyLocationMode.following, hasCompassMode: false),
        MyLocationMode.following,
      );
      expect(
        nextMyLocationMode(MyLocationMode.following, hasCompassMode: true),
        MyLocationMode.compass,
      );
      expect(
        nextMyLocationMode(MyLocationMode.compass, hasCompassMode: true),
        MyLocationMode.following,
      );
    });

    testWidgets('explains when the position is outside the map area', (
      tester,
    ) async {
      await pumpApp(
        tester,
        // Dhaka, far outside the 15 km coverage.
        locationService: FakeLocationService(
          const LocationFound(GeoPoint(23.8103, 90.4125), accuracyMeters: 8),
        ),
      );

      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();

      expect(
        find.text('You are outside the area this map covers.'),
        findsOneWidget,
      );
    });

    testWidgets('explains a blocked permission and offers settings', (
      tester,
    ) async {
      final service = FakeLocationService(
        const LocationUnavailable(LocationProblem.permissionDeniedForever),
      );
      final container = await pumpApp(tester, locationService: service);

      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission is blocked'), findsOneWidget);
      expect(container.read(userLocationVisibleProvider), isFalse);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(service.openedSettingsFor, [
        LocationProblem.permissionDeniedForever,
      ]);
    });

    testWidgets('a simple refusal has no settings shortcut', (tester) async {
      await pumpApp(
        tester,
        locationService: FakeLocationService(
          const LocationUnavailable(LocationProblem.permissionDenied),
        ),
      );

      await tester.tap(find.byTooltip('My location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission is needed'), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
    });
  });
}
