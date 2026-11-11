import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  group('The card at the top of the Profile tab', () {
    testWidgets('says what the app is and that no account is needed', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Profile');

      expect(find.text('BU Bus Tracker'), findsOneWidget);
      expect(find.text('University of Barishal'), findsOneWidget);
      expect(find.text('Passenger · no account needed'), findsOneWidget);
    });

    testWidgets('counts the routes, the stops and the buses live now', (
      tester,
    ) async {
      final now = DateTime(2026, 11, 11, 9);
      await pumpApp(
        tester,
        network: sampleDemoNetwork,
        now: now,
        buses: [
          TrackedBus(
            bus: const Bus(
              id: 'a',
              number: 'A1',
              name: 'Bus A',
              routeId: 'r1',
              isActive: true,
            ),
            location: BusLocation(
              position: const GeoPoint(22.66, 90.36),
              updatedAt: now.subtract(const Duration(seconds: 5)),
            ),
          ),
          // In service but silent: not counted as live.
          const TrackedBus(
            bus: Bus(id: 'b', number: 'B1', name: 'Bus B', isActive: true),
          ),
        ],
      );
      await openTab(tester, 'Profile');

      String valueAbove(String label) {
        final column = find.ancestor(
          of: find.text(label),
          matching: find.byType(Column),
        );
        return tester
            .widgetList<Text>(
              find.descendant(of: column.first, matching: find.byType(Text)),
            )
            .first
            .data!;
      }

      // The sample network has one route and two stops.
      expect(valueAbove('routes'), '1');
      expect(valueAbove('stops'), '2');
      expect(valueAbove('live now'), '1');
    });

    testWidgets('fits a narrow phone without overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpApp(tester, network: sampleDemoNetwork);
      await openTab(tester, 'Profile');

      // An overflow would have been reported as an exception by now.
      expect(tester.takeException(), isNull);
      expect(find.text('BU Bus Tracker'), findsOneWidget);
    });

    testWidgets('the theme row says which theme is in use', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 'Profile');

      expect(find.text("Dark, the app's own look."), findsOneWidget);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(find.text('Light, on warm ivory.'), findsOneWidget);
    });
  });
}
