import 'package:bu_bus_tracker/features/home/presentation/widgets/selection_details.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

// Sample buses on a straight north-south road, fed in by the tests. The app
// itself has no source of buses until real-time tracking is built.

final _now = DateTime(2026, 11, 10, 12);

const _network = TransportNetwork(
  origin: TransportDataOrigin.verified,
  stops: [
    BusStop(id: 's', name: 'South End', position: GeoPoint(22.00, 90)),
    BusStop(id: 'm', name: 'Middle', position: GeoPoint(22.01, 90)),
    BusStop(id: 'n', name: 'North End', position: GeoPoint(22.02, 90)),
  ],
  routes: [
    BusRoute(
      id: 'r',
      name: 'North Road',
      colorHex: '#2F6FED',
      startName: 'South End',
      endName: 'North End',
      path: [GeoPoint(22.00, 90), GeoPoint(22.01, 90), GeoPoint(22.02, 90)],
      stopIds: ['s', 'm', 'n'],
      isActive: true,
    ),
  ],
);

TrackedBus _bus(
  String id, {
  required double latitude,
  double longitude = 90,
  double heading = 0,
  double speed = 10,
  Duration age = const Duration(seconds: 3),
}) => TrackedBus(
  bus: Bus(
    id: id,
    number: id.toUpperCase(),
    name: 'Bus $id',
    routeId: 'r',
    isActive: true,
  ),
  location: BusLocation(
    position: GeoPoint(latitude, longitude),
    updatedAt: _now.subtract(age),
    headingDegrees: heading,
    speedMetersPerSecond: speed,
    accuracyMeters: 5,
  ),
);

Future<void> _openBus(WidgetTester tester, String number) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -420));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bus $number'));
  await tester.pumpAndSettle();
}

void main() {
  group('Bus details', () {
    testWidgets('names the next stop and estimates the arrival', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.005)],
      );
      await _openBus(tester, 'A1');

      expect(find.text('Middle'), findsOneWidget);
      expect(find.text('Less than a minute (estimate)'), findsOneWidget);
    });

    testWidgets('a bus heading back names the stop in that direction', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.015, heading: 180, speed: 5)],
      );
      await _openBus(tester, 'A1');

      expect(find.text('Middle'), findsOneWidget);
      expect(find.text('About 2 min (estimate)'), findsOneWidget);
    });

    testWidgets('a stopped bus gets no estimate, and is told why', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.005, speed: 0)],
      );
      await _openBus(tester, 'A1');

      expect(find.textContaining('(estimate)'), findsNothing);
      // Standing still, the GPS gives no direction either.
      expect(
        find.text('Not available: direction of travel not known yet'),
        findsOneWidget,
      );
    });

    testWidgets('a bus away from its route gets no estimate', (tester) async {
      await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.005, longitude: 90.01)],
      );
      await _openBus(tester, 'A1');

      expect(
        find.text('Not available: the bus is away from its route'),
        findsOneWidget,
      );
    });
  });

  group('Buses on the way to a stop', () {
    testWidgets('lists buses that can be estimated, soonest first', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('far', latitude: 22.001), _bus('near', latitude: 22.015)],
      );
      container.read(mapSelectionProvider.notifier).selectStop('n');
      await tester.pumpAndSettle();

      expect(find.text('Buses on the way'), findsOneWidget);
      final near = tester.getTopLeft(find.text('Bus NEAR'));
      final far = tester.getTopLeft(find.text('Bus FAR'));
      expect(near.dy, lessThan(far.dy));
      expect(find.text('Less than a minute (estimate)'), findsOneWidget);
      expect(find.text('About 4 min (estimate)'), findsOneWidget);
      // The soonest is marked, and each says how far it still has to come.
      expect(find.text('Next'), findsOneWidget);
      expect(find.textContaining(' away'), findsNWidgets(2));
      // Both are driving north: each card says where from and where to.
      expect(find.text('South End → North End'), findsNWidgets(2));
    });

    test('how far away a bus is, in round figures', () {
      expect(distanceAwayText(4), '10 m away');
      expect(distanceAwayText(447), '450 m away');
      expect(distanceAwayText(994), '990 m away');
      expect(distanceAwayText(1000), '1.0 km away');
      expect(distanceAwayText(2349), '2.3 km away');
    });

    testWidgets('leaves out buses that have passed or are not live', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [
          // Already north of the middle stop, still heading north.
          _bus('gone', latitude: 22.015),
          // Heading for it, but its position is ten minutes old.
          _bus('stale', latitude: 22.005, age: const Duration(minutes: 10)),
        ],
      );
      container.read(mapSelectionProvider.notifier).selectStop('m');
      await tester.pumpAndSettle();

      expect(find.text('Buses on the way'), findsOneWidget);
      expect(find.text('Bus GONE'), findsNothing);
      expect(find.text('Bus STALE'), findsNothing);
      expect(
        find.text('No bus can be estimated for this stop right now.'),
        findsOneWidget,
      );
    });

    testWidgets('the section is absent when no bus is tracked', (tester) async {
      final container = await pumpApp(tester, network: _network, now: _now);
      container.read(mapSelectionProvider.notifier).selectStop('m');
      await tester.pumpAndSettle();

      expect(find.text('Routes at this stop'), findsOneWidget);
      expect(find.text('Buses on the way'), findsNothing);
    });

    testWidgets('tapping an approaching bus opens that bus', (tester) async {
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.005)],
      );
      container.read(mapSelectionProvider.notifier).selectStop('n');
      await tester.pumpAndSettle();

      // The stop's page is taller than the half-open sheet: scroll to it.
      await tester.ensureVisible(find.text('Bus A1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bus A1'));
      await tester.pumpAndSettle();

      expect(
        container.read(mapSelectionProvider),
        const MapSelection(busId: 'a1'),
      );
      expect(find.text('Follow this bus'), findsOneWidget);
    });
  });
}
