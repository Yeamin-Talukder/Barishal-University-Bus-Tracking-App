import 'dart:async';

import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:bu_bus_tracker/shared/widgets/skeleton_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Two routes sharing one stop, one of them not running.
const _network = TransportNetwork(
  origin: TransportDataOrigin.verified,
  stops: [
    BusStop(
      id: 'campus',
      name: 'Campus Gate',
      position: GeoPoint(22.659967, 90.363381),
      description: 'Beside the main gate',
    ),
    BusStop(id: 'bridge', name: 'Bridge', position: GeoPoint(22.6633, 90.354)),
    BusStop(id: 'town', name: 'Town Hall', position: GeoPoint(22.70, 90.37)),
    BusStop(id: 'lonely', name: 'Old Depot', position: GeoPoint(22.61, 90.33)),
  ],
  routes: [
    BusRoute(
      id: 'north',
      name: 'North Line',
      colorHex: '#2F6FED',
      startName: 'Campus Gate',
      endName: 'Town Hall',
      path: [GeoPoint(22.66, 90.36), GeoPoint(22.70, 90.37)],
      stopIds: ['campus', 'bridge', 'town'],
      isActive: true,
    ),
    BusRoute(
      id: 'short',
      name: 'Short Hop',
      colorHex: '#D94A38',
      startName: 'Campus Gate',
      endName: 'Bridge',
      path: [GeoPoint(22.66, 90.36), GeoPoint(22.6633, 90.354)],
      stopIds: ['campus', 'bridge'],
      isActive: false,
    ),
  ],
  problems: ['Route 3: geometry must be a LineString.'],
);

void main() {
  group('Routes tab', () {
    testWidgets('lists each route with its facts', (tester) async {
      await pumpApp(tester, network: _network);
      await openMapRoutes(tester);

      expect(find.text('North Line'), findsOneWidget);
      expect(find.text('Campus Gate to Town Hall'), findsOneWidget);
      expect(find.text('3 stops · No live buses'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);

      expect(find.text('Short Hop'), findsOneWidget);
      expect(find.text('Not running'), findsOneWidget);
    });

    testWidgets('says how many entries were skipped as invalid', (
      tester,
    ) async {
      await pumpApp(tester, network: _network);
      await openMapRoutes(tester);

      expect(find.textContaining('1 entries in the route data'), findsOne);
    });

    testWidgets('does not label verified data as demo', (tester) async {
      await pumpApp(tester, network: _network);
      await openMapRoutes(tester);

      expect(find.textContaining('Demo data'), findsNothing);
    });

    testWidgets('labels demo data', (tester) async {
      await pumpApp(tester, network: sampleDemoNetwork);
      await openMapRoutes(tester);

      expect(find.text('Demo data, not official routes'), findsOneWidget);
    });

    testWidgets('labels unconfirmed stop positions as unconfirmed', (
      tester,
    ) async {
      await pumpApp(
        tester,
        network: const TransportNetwork(
          origin: TransportDataOrigin.unconfirmed,
          routes: [],
          stops: [
            BusStop(
              id: 'review-x',
              name: 'Somewhere',
              description: 'Position not confirmed.',
              position: GeoPoint(22.66, 90.36),
            ),
          ],
        ),
      );

      // On the map.
      expect(
        find.text('Unconfirmed stop positions, for checking only'),
        findsOneWidget,
      );

      // And on the list of stops.
      await openTab(tester, 'Stops');
      expect(find.text('Somewhere'), findsOneWidget);
      expect(
        find.text('Unconfirmed stop positions, for checking only'),
        findsWidgets,
      );
      expect(find.textContaining('Demo data'), findsNothing);
    });

    testWidgets('tapping a route opens it on the map with its stops', (
      tester,
    ) async {
      final container = await pumpApp(tester, network: _network);
      await openMapRoutes(tester);

      await tester.tap(find.text('North Line'));
      await tester.pumpAndSettle();

      expect(
        container.read(mapSelectionProvider),
        const MapSelection(routeId: 'north'),
      );
      // Back on the home tab, with the route's details in the sheet.
      expect(find.byKey(fakeMapKey), findsOneWidget);
      expect(find.text('Stops (3)'), findsOneWidget);
      expect(find.text('Campus Gate'), findsOneWidget);
      expect(find.text('Bridge'), findsOneWidget);
      expect(find.text('Town Hall'), findsOneWidget);
      expect(find.text('No live buses'), findsNothing);
    });

    testWidgets('shows a skeleton while loading, then the list', (
      tester,
    ) async {
      final load = Completer<TransportNetwork>();
      await pumpApp(tester, loadNetwork: () => load.future);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Routes'));
      await tester.pump();
      await tester.tap(find.widgetWithText(Tab, 'On the map'));
      // Not pumpAndSettle: the skeleton never stops pulsing.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.text('No routes on the map yet'), findsNothing);

      load.complete(_network);
      await tester.pumpAndSettle();

      expect(find.byType(SkeletonList), findsNothing);
      expect(find.text('North Line'), findsOneWidget);
    });

    testWidgets('a failed load explains itself and can be retried', (
      tester,
    ) async {
      var attempts = 0;
      await pumpApp(
        tester,
        loadNetwork: () async {
          attempts++;
          if (attempts == 1) throw const FormatException('bad file');
          return _network;
        },
      );
      await tester.pumpAndSettle();
      await openMapRoutes(tester);

      expect(find.text('This list could not be loaded'), findsOneWidget);
      expect(find.textContaining('bad file'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('North Line'), findsOneWidget);
    });
  });

  group('Stops tab', () {
    testWidgets('lists each stop with its place and routes', (tester) async {
      await pumpApp(tester, network: _network);
      await openTab(tester, 'Stops');

      expect(find.text('Campus Gate'), findsOneWidget);
      expect(find.text('Beside the main gate'), findsOneWidget);
      expect(find.text('22.65997° N, 90.36338° E'), findsOneWidget);
      // Campus Gate and Bridge are each on both routes; Town Hall on one.
      // Each route's name is also once on its filter chip at the top.
      expect(find.text('North Line'), findsNWidgets(3 + 1));
      expect(find.text('Short Hop'), findsNWidgets(2 + 1));
      expect(find.text('4 stops'), findsOneWidget);
    });

    testWidgets('the search box narrows the list by name', (tester) async {
      await pumpApp(tester, network: _network);
      await openTab(tester, 'Stops');

      await tester.enterText(find.byType(TextField), 'bri');
      await tester.pumpAndSettle();

      expect(find.text('Bridge'), findsOneWidget);
      expect(find.text('Campus Gate'), findsNothing);
      expect(find.text('1 stop found'), findsOneWidget);

      // What is said about the place counts too.
      await tester.enterText(find.byType(TextField), 'main gate');
      await tester.pumpAndSettle();
      expect(find.text('Campus Gate'), findsOneWidget);
      expect(find.text('Bridge'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('4 stops'), findsOneWidget);
      expect(find.text('Bridge'), findsOneWidget);
    });

    testWidgets('a route chip shows only that route\'s stops', (tester) async {
      await pumpApp(tester, network: _network);
      await openTab(tester, 'Stops');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Short Hop'));
      await tester.pumpAndSettle();

      expect(find.text('2 stops found'), findsOneWidget);
      expect(find.text('Campus Gate'), findsOneWidget);
      expect(find.text('Bridge'), findsOneWidget);
      expect(find.text('Town Hall'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All stops'));
      await tester.pumpAndSettle();
      expect(find.text('4 stops'), findsOneWidget);
    });

    testWidgets('says so when nothing matches, without calling it empty', (
      tester,
    ) async {
      await pumpApp(tester, network: _network);
      await openTab(tester, 'Stops');

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No stop matches'), findsOneWidget);
      expect(find.text('No stops yet'), findsNothing);
      // The search box is still there to change the search.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('says when no route calls at a stop', (tester) async {
      await pumpApp(tester, network: _network);
      await openTab(tester, 'Stops');
      await tester.scrollUntilVisible(
        find.text('Old Depot'),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('No route calls here yet'), findsOneWidget);
    });

    testWidgets('tapping a stop opens it on the map', (tester) async {
      final container = await pumpApp(tester, network: _network);
      await openTab(tester, 'Stops');

      await tester.tap(find.text('Bridge'));
      await tester.pumpAndSettle();

      expect(
        container.read(mapSelectionProvider),
        const MapSelection(stopId: 'bridge'),
      );
      expect(find.byKey(fakeMapKey), findsOneWidget);
      expect(find.text('Routes at this stop'), findsOneWidget);
      expect(inSheet(find.text('North Line')), findsOneWidget);
      expect(inSheet(find.text('Short Hop')), findsOneWidget);
    });

    testWidgets('an empty list keeps its plain explanation', (tester) async {
      await pumpApp(tester);
      await openTab(tester, 'Stops');

      expect(find.text('No stops yet'), findsOneWidget);
    });
  });

  group('Selection in the home sheet', () {
    testWidgets('a route picked from the sheet shows its stops', (
      tester,
    ) async {
      final container = await pumpApp(tester, network: _network);
      await tester.drag(find.text('No live buses'), const Offset(0, -420));
      await tester.pumpAndSettle();

      await tester.tap(inSheet(find.text('Short Hop')));
      await tester.pumpAndSettle();

      expect(
        container.read(mapSelectionProvider),
        const MapSelection(routeId: 'short'),
      );
      expect(find.text('Stops (2)'), findsOneWidget);
    });

    testWidgets('a stop on the route leads to that stop, and on to a route', (
      tester,
    ) async {
      final container = await pumpApp(tester, network: _network);
      container.read(mapSelectionProvider.notifier).selectRoute('north');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bridge'));
      await tester.pumpAndSettle();
      expect(find.text('Routes at this stop'), findsOneWidget);

      // The stop's page is taller than the half-open sheet: scroll to it.
      await tester.ensureVisible(inSheet(find.text('Short Hop')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Short Hop')));
      await tester.pumpAndSettle();
      expect(
        container.read(mapSelectionProvider),
        const MapSelection(routeId: 'short'),
      );
    });

    testWidgets('a chip above the map puts its route in focus', (tester) async {
      final container = await pumpApp(tester, network: _network);
      final chip = find.bySemanticsLabel('Show Short Hop on the map');
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        container.read(mapSelectionProvider),
        const MapSelection(routeId: 'short'),
      );
      expect(find.text('Stops (2)'), findsOneWidget);

      // The same chip again lets go of the route.
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(container.read(mapSelectionProvider), MapSelection.none);
    });

    testWidgets('the "All routes" chip returns to every route', (tester) async {
      final container = await pumpApp(tester, network: _network);
      container.read(mapSelectionProvider.notifier).selectRoute('north');
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Show all routes'));
      await tester.pumpAndSettle();

      expect(container.read(mapSelectionProvider), MapSelection.none);
      expect(find.text('No live buses'), findsOneWidget);
    });

    testWidgets('there are no chips while there are no routes', (tester) async {
      await pumpApp(tester);

      expect(find.bySemanticsLabel('Show all routes'), findsNothing);
    });

    testWidgets('clearing the selection returns to the overview', (
      tester,
    ) async {
      final container = await pumpApp(tester, network: _network);
      container.read(mapSelectionProvider.notifier).selectRoute('north');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pumpAndSettle();

      expect(container.read(mapSelectionProvider).isEmpty, isTrue);
      expect(find.text('No live buses'), findsOneWidget);
    });
  });
}
