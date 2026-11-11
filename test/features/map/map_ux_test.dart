import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/features/map/application/map_camera_controller.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('Where the camera looks', () {
    const bus = GeoPoint(22.7000, 90.3600);

    GeoPoint centre({required double bearing, double bottom = 300}) =>
        MapCameraController.centreFor(
          bus,
          zoom: 16,
          bearingDegrees: bearing,
          coveredTop: 0,
          coveredBottom: bottom,
        );

    test('with nothing covering the map it looks straight at the point', () {
      expect(centre(bearing: 0, bottom: 0), bus);
      expect(centre(bearing: 137, bottom: 0), bus);
    });

    test('facing north with a sheet open, it looks further south', () {
      final target = centre(bearing: 0);

      expect(target.latitude, lessThan(bus.latitude));
      expect(target.longitude, closeTo(bus.longitude, 1e-9));
    });

    test('turned to face east, "down the screen" is to the west', () {
      final target = centre(bearing: 90);

      expect(target.longitude, lessThan(bus.longitude));
      expect(target.latitude, closeTo(bus.latitude, 1e-9));
    });

    test('turned to face south, it looks further north', () {
      expect(centre(bearing: 180).latitude, greaterThan(bus.latitude));
    });

    test('the shift is the same distance whichever way the map is turned', () {
      final north = centre(bearing: 0);
      final east = centre(bearing: 90);
      final metersNorth = (bus.latitude - north.latitude) * 111320;
      final metersEast = (bus.longitude - east.longitude) * 111320 * 0.9225;

      expect(metersEast, closeTo(metersNorth, metersNorth * 0.01));
    });
  });

  group('Turning the map with the bus', () {
    test('it turns part of the way each time, the short way round', () {
      // From just west of north to just east of it: through north.
      expect(MapCameraController.turnTowards(350, 10, 0.5), closeTo(0, 1e-9));
      expect(MapCameraController.turnTowards(10, 350, 0.5), closeTo(0, 1e-9));
      expect(MapCameraController.turnTowards(0, 90, 0.1), closeTo(9, 1e-9));
    });

    test('a whole part reaches the heading; none leaves it where it was', () {
      expect(MapCameraController.turnTowards(40, 200, 1), closeTo(200, 1e-9));
      expect(MapCameraController.turnTowards(40, 200, 0), closeTo(40, 1e-9));
      // More than a whole part is a whole part.
      expect(MapCameraController.turnTowards(40, 200, 3), closeTo(200, 1e-9));
    });

    test('repeated, it settles on the heading without overshooting', () {
      var bearing = 0.0;
      for (var frame = 0; frame < 60; frame++) {
        final next = MapCameraController.turnTowards(bearing, 120, 0.12);
        expect(next, greaterThanOrEqualTo(bearing));
        expect(next, lessThanOrEqualTo(120));
        bearing = next;
      }
      expect(bearing, closeTo(120, 0.1));
    });
  });

  group('Map buttons', () {
    testWidgets('the map key explains every kind of marker', (tester) async {
      await pumpApp(tester, network: sampleDemoNetwork);

      await tester.tap(find.byTooltip('Map key'));
      await tester.pumpAndSettle();

      expect(find.text('Map key'), findsOneWidget);
      for (final title in [
        'Live bus',
        'Delayed',
        'Offline',
        'Predicted',
        'Bus stop',
        'Selected route',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      // A predicted bus is said plainly not to be a real position.
      expect(find.textContaining('Not a real position'), findsOneWidget);
    });

    testWidgets('"All routes" lets go of whatever was picked', (tester) async {
      final container = await pumpApp(tester, network: sampleDemoNetwork);
      container.read(mapSelectionProvider.notifier).selectRoute('r1');
      await tester.pumpAndSettle();
      // The open sheet covers the buttons: close it to reach them.
      await tester.drag(find.text('Sample route').last, const Offset(0, 500));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('All routes'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(container.read(mapSelectionProvider), MapSelection.none);
    });
  });

  group('Following a bus', () {
    final now = DateTime(2026, 11, 11, 9);
    final bus = TrackedBus(
      bus: const Bus(
        id: 'a1',
        number: 'A1',
        name: 'Bus A',
        routeId: 'r1',
        isActive: true,
      ),
      location: BusLocation(
        position: const GeoPoint(22.66, 90.36),
        updatedAt: now.subtract(const Duration(seconds: 5)),
      ),
    );

    testWidgets('the map says which bus it is following, and can stop', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: now,
        buses: [bus],
      );
      expect(find.textContaining('Following Bus'), findsNothing);

      container.read(mapSelectionProvider.notifier)
        ..selectBus('a1')
        ..setFollowingBus(true);
      await tester.pumpAndSettle();

      expect(find.text('Following Bus A1'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Stop'));
      await tester.pumpAndSettle();

      expect(container.read(mapSelectionProvider).isFollowingBus, isFalse);
      // The bus is still the one picked; only the following has ended.
      expect(container.read(mapSelectionProvider).busId, 'a1');
      expect(find.textContaining('Following Bus'), findsNothing);
    });
  });
}
