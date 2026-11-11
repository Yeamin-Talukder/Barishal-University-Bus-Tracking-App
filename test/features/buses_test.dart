import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

// These tests feed the bus views fixed sample buses. The app itself has no
// source of buses until real-time tracking is built, and never invents any.

final _now = DateTime(2026, 11, 10, 12);

TrackedBus _bus(
  String id, {
  Duration? age,
  double? speed = 10,
  double? accuracy = 8,
  double? heading = 90,
  String? routeId = 'r1',
}) => TrackedBus(
  bus: Bus(
    id: id,
    number: id.toUpperCase(),
    name: 'Bus $id',
    routeId: routeId,
    isActive: true,
  ),
  location: age == null
      ? null
      : BusLocation(
          position: const GeoPoint(22.659967, 90.363381),
          updatedAt: _now.subtract(age),
          speedMetersPerSecond: speed,
          accuracyMeters: accuracy,
          headingDegrees: heading,
        ),
);

Future<void> _expandSheet(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -420));
  await tester.pumpAndSettle();
}

/// Opens the sheet far enough to reach the bus list, then taps a bus.
Future<void> _openBus(WidgetTester tester, String number) async {
  await _expandSheet(tester);
  await tester.tap(find.text('Bus $number'));
  await tester.pumpAndSettle();
}

void main() {
  group('Bus list on the home sheet', () {
    testWidgets('counts only buses with a fresh position as live', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [
          _bus('a1', age: const Duration(seconds: 5)),
          _bus('b2', age: const Duration(seconds: 40)),
          _bus('c3', age: const Duration(minutes: 9)),
        ],
      );

      expect(find.text('1 bus live'), findsOneWidget);
      expect(find.text('2 of 3 not reporting right now.'), findsOneWidget);
    });

    testWidgets('shows each bus with its route, status and last update', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [
          _bus('a1', age: const Duration(seconds: 5)),
          _bus('b2', age: const Duration(seconds: 40)),
          _bus('c3', age: const Duration(minutes: 9), routeId: null),
          _bus('d4'),
        ],
      );
      await _expandSheet(tester);

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Delayed'), findsOneWidget);
      expect(find.text('Offline'), findsNWidgets(2));
      expect(find.text('Sample route · Updated 5 seconds ago'), findsOneWidget);
      expect(
        find.text('Sample route · Updated 40 seconds ago'),
        findsOneWidget,
      );
      expect(
        find.text('No route assigned · Updated 9 minutes ago'),
        findsOneWidget,
      );
      expect(
        find.text('Sample route · No position received yet'),
        findsOneWidget,
      );
    });

    testWidgets('with no buses, says tracking is not available', (
      tester,
    ) async {
      await pumpApp(tester, now: _now);

      expect(find.text('No live buses'), findsOneWidget);
      expect(find.text('Live tracking is not available yet.'), findsOneWidget);
    });
  });

  group('Bus details', () {
    testWidgets('a live bus shows its speed and direction', (tester) async {
      await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [_bus('a1', age: const Duration(seconds: 5))],
      );
      await _openBus(tester, 'A1');

      expect(find.text('Bus a1'), findsOneWidget);
      expect(inSheet(find.text('Sample route')), findsOneWidget);
      expect(find.text('Updated 5 seconds ago'), findsOneWidget);
      expect(find.text('22.65997° N, 90.36338° E'), findsOneWidget);
      expect(find.text('36 km/h'), findsOneWidget);
      expect(find.text('Heading east'), findsOneWidget);
      expect(find.textContaining('last position'), findsNothing);
    });

    testWidgets('next stop and arrival are not invented for an off-route bus', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [_bus('a1', age: const Duration(seconds: 5))],
      );
      await _openBus(tester, 'A1');

      // The sample bus is some way from the sample route, so there is no
      // next stop, and the arrival row says why.
      expect(find.text('Not available'), findsOneWidget);
      expect(
        find.text('Not available: the bus is away from its route'),
        findsOneWidget,
      );
    });

    testWidgets('an old position is called old and hides speed', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [_bus('c3', age: const Duration(minutes: 9))],
      );
      await _openBus(tester, 'C3');

      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.textContaining('last position the bus reported'),
        findsOneWidget,
      );
      expect(find.text('36 km/h'), findsNothing);
      expect(find.text('Heading east'), findsNothing);
      // Speed, direction and next stop.
      expect(find.text('Not available'), findsNWidgets(3));
      expect(
        find.text('Not available: the position is out of date'),
        findsOneWidget,
      );
    });

    testWidgets('a poor GPS fix hides speed and direction', (tester) async {
      await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [_bus('a1', age: const Duration(seconds: 5), accuracy: 300)],
      );
      await _openBus(tester, 'A1');

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('36 km/h'), findsNothing);
    });

    testWidgets('following can be started and stopped', (tester) async {
      final container = await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [_bus('a1', age: const Duration(seconds: 5))],
      );
      await _openBus(tester, 'A1');

      await tester.ensureVisible(find.text('Follow this bus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow this bus'));
      await tester.pumpAndSettle();
      expect(container.read(mapSelectionProvider).isFollowingBus, isTrue);

      await tester.tap(find.text('Stop following'));
      await tester.pumpAndSettle();
      expect(container.read(mapSelectionProvider).isFollowingBus, isFalse);
    });

    testWidgets('a bus with no position cannot be followed', (tester) async {
      final container = await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [_bus('d4')],
      );
      await _openBus(tester, 'D4');

      expect(find.text('No position received yet'), findsOneWidget);
      await tester.ensureVisible(find.text('Follow this bus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow this bus'));
      await tester.pumpAndSettle();

      expect(container.read(mapSelectionProvider).isFollowingBus, isFalse);
    });

    testWidgets('closing returns to the bus list', (tester) async {
      final container = await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: _now,
        buses: [_bus('a1', age: const Duration(seconds: 5))],
      );
      await _openBus(tester, 'A1');

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(container.read(mapSelectionProvider).isEmpty, isTrue);
      expect(find.text('1 bus live'), findsOneWidget);
    });
  });
}
