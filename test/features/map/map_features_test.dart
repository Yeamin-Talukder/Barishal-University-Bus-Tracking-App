import 'package:bu_bus_tracker/core/services/eta_service.dart';
import 'package:bu_bus_tracker/core/utils/layout.dart';
import 'package:bu_bus_tracker/core/utils/route_geometry.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/features/alerts/application/arrival_alert.dart';
import 'package:bu_bus_tracker/features/alerts/presentation/arrival_alert_views.dart';
import 'package:bu_bus_tracker/features/home/application/nearest_stop.dart';
import 'package:bu_bus_tracker/features/home/presentation/home_screen.dart';
import 'package:bu_bus_tracker/features/home/presentation/widgets/home_sheet.dart';
import 'package:bu_bus_tracker/features/map/application/bus_grouping.dart';
import 'package:bu_bus_tracker/features/map/application/bus_map_layer.dart';
import 'package:bu_bus_tracker/features/map/application/map_camera_controller.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:bu_bus_tracker/features/map/application/map_view_state.dart';
import 'package:bu_bus_tracker/features/map/application/route_flow_layer.dart';
import 'package:bu_bus_tracker/features/map/application/transport_map_layers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

// A straight road running north, about 1.1 km between stops.
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
    BusRoute(
      id: 'q',
      name: 'Second Road',
      colorHex: '#F2994A',
      startName: 'South End',
      endName: 'Middle',
      path: [GeoPoint(22.00, 90), GeoPoint(22.01, 90)],
      stopIds: ['s', 'm'],
      isActive: true,
    ),
  ],
);

TrackedBus _bus(
  String id, {
  required double latitude,
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
    position: GeoPoint(latitude, 90),
    updatedAt: _now.subtract(age),
    headingDegrees: heading,
    speedMetersPerSecond: speed,
    accuracyMeters: 5,
  ),
);

const _colors = BusMarkerColors(
  live: '#00aa00',
  delayed: '#ffaa00',
  offline: '#888888',
  outline: '#ffffff',
  selection: '#0000ff',
  label: '#111111',
  labelHalo: '#ffffff',
);

void main() {
  group('Buses that overlap', () {
    const atGate = GeoPoint(22.66, 90.36);
    // Twenty metres north of the gate.
    const nearGate = GeoPoint(22.66018, 90.36);
    const farAway = GeoPoint(22.70, 90.36);
    const markers = [
      (id: 'a', position: atGate),
      (id: 'b', position: nearGate),
      (id: 'c', position: farAway),
    ];

    test('become one group when zoomed out, and split when zoomed in', () {
      final out = groupOverlappingBuses(markers, zoom: 13);
      expect(out, hasLength(1));
      expect(out.single.busIds, ['a', 'b']);
      // The group sits between its buses.
      expect(out.single.position.latitude, closeTo(22.66009, 1e-5));

      // At zoom 18 twenty metres is well over a badge's width.
      expect(groupOverlappingBuses(markers, zoom: 18), isEmpty);
    });

    test('the picked bus always keeps its own marker', () {
      expect(
        groupOverlappingBuses(markers, zoom: 13, keepApartId: 'a'),
        isEmpty,
      );
    });

    test('a group marker carries its count and the buses in it', () {
      final group = groupOverlappingBuses(markers, zoom: 13).single;
      final geoJson = BusMapLayer.groupsGeoJson([
        (group: group, status: BusTrackingStatus.live),
      ], colors: _colors);
      final properties =
          ((geoJson['features'] as List).single as Map)['properties'] as Map;
      expect(properties['count'], '2');
      expect(properties['label'], '2 buses');
      expect(properties['badge'], 'bu-bus-badge-live');
      expect(BusMapLayer.busIdsOfGroup(properties['id'] as String), ['a', 'b']);
      expect(BusMapLayer.busIdsOfGroup('a'), isNull);
    });

    test('buses in a group are left out of the single markers', () {
      final geoJson = BusMapLayer.geoJson(
        [_bus('a', latitude: 22.0), _bus('b', latitude: 22.0)],
        statusOf: (_) => BusTrackingStatus.live,
        headingOf: (_) => null,
        colors: _colors,
        hiddenIds: {'a'},
      );
      final ids = [
        for (final feature in geoJson['features'] as List)
          ((feature as Map)['properties'] as Map)['id'],
      ];
      expect(ids, ['b']);
    });
  });

  group('How fresh a bus is, on its marker', () {
    Map properties(BusTrackingStatus status, Duration age) {
      final geoJson = BusMapLayer.geoJson(
        [_bus('a', latitude: 22.0)],
        statusOf: (_) => status,
        headingOf: (_) => null,
        colors: _colors,
        routeColorOf: (_) => '#2F6FED',
        ageOf: (_) => age,
      );
      return ((geoJson['features'] as List).single as Map)['properties'] as Map;
    }

    test('a live bus is at full strength and says nothing about age', () {
      final live = properties(
        BusTrackingStatus.live,
        const Duration(seconds: 4),
      );
      expect(live['opacity'], 1.0);
      expect(live.containsKey('seen'), isFalse);
      // The ring round the badge is the colour of its route.
      expect(live['routeColor'], '#2F6FED');
    });

    test('a delayed bus is faded a little and says when it was seen', () {
      final delayed = properties(
        BusTrackingStatus.delayed,
        const Duration(seconds: 37),
      );
      expect(delayed['opacity'], lessThan(1.0));
      expect(delayed['seen'], 'seen 35 s ago');
      expect(delayed.containsKey('pulseRadius'), isFalse);
    });

    test('an offline bus is faded most', () {
      final offline = properties(
        BusTrackingStatus.offline,
        const Duration(minutes: 4, seconds: 20),
      );
      expect(
        offline['opacity'],
        lessThan(BusMapLayer.opacityOf(BusTrackingStatus.delayed)),
      );
      expect(offline['seen'], 'seen 4 min ago');
    });

    test('ages are short and steady', () {
      expect(seenAgoShort(const Duration(seconds: 2)), '5 s ago');
      expect(seenAgoShort(const Duration(seconds: 59)), '55 s ago');
      expect(seenAgoShort(const Duration(minutes: 59)), '59 min ago');
      expect(seenAgoShort(const Duration(hours: 5)), '5 h ago');
      expect(seenAgoShort(const Duration(days: 3)), '3 d ago');
    });
  });

  group('Route progress', () {
    final track = RouteGeometry(_network.routes.first.path);

    test('a part of a route starts and stops exactly where asked', () {
      final part = track.slice(500, track.lengthMeters - 500);
      // Both ends are new points; the middle stop's corner is kept.
      expect(part, hasLength(3));
      expect(part[1], const GeoPoint(22.01, 90));
      expect(part.first.latitude, greaterThan(22.0));
      expect(part.last.latitude, lessThan(22.02));
      expect(track.slice(700, 700), isEmpty);
    });

    test('going forwards, what is behind is covered', () {
      final flow = RouteFlow.forBus(
        track: track,
        alongMeters: 500,
        forwards: true,
        color: '#2F6FED',
      );
      // Covered: from the start up to the bus.
      expect(flow.done.first, const GeoPoint(22.0, 90));
      expect(flow.done.last.latitude, closeTo(22.0045, 2e-4));
      // Ahead: from the bus to the end, in the order it is driven.
      expect(flow.ahead.first.latitude, closeTo(22.0045, 2e-4));
      expect(flow.ahead.last, const GeoPoint(22.02, 90));
    });

    test('going backwards, the far end is covered and arrows turn round', () {
      final flow = RouteFlow.forBus(
        track: track,
        alongMeters: 500,
        forwards: false,
        color: '#2F6FED',
      );
      expect(flow.done.first, const GeoPoint(22.02, 90));
      // Ahead runs from the bus back to the start.
      expect(flow.ahead.first.latitude, closeTo(22.0045, 2e-4));
      expect(flow.ahead.last, const GeoPoint(22.0, 90));
    });

    test('the lines say which part is which', () {
      final geoJson = RouteFlowGeoJson.lines(
        RouteFlow.forBus(
          track: track,
          alongMeters: 500,
          forwards: true,
          color: '#2F6FED',
          name: 'North Road',
        ),
      );
      final kinds = [
        for (final feature in geoJson['features'] as List)
          ((feature as Map)['properties'] as Map)['kind'],
      ];
      expect(kinds, ['done', 'ahead']);
      expect((RouteFlowGeoJson.lines(null)['features'] as List), isEmpty);
    });

    test('with the direction unknown no arrows are asked for', () {
      final geoJson = RouteFlowGeoJson.lines(
        RouteFlow(
          color: '#2F6FED',
          ahead: track.path,
          drawLines: true,
          arrows: false,
        ),
      );
      final properties =
          ((geoJson['features'] as List).single as Map)['properties'] as Map;
      expect(properties['arrows'], isFalse);
      expect(properties['draw'], isTrue);
    });

    test('minutes at a stop are marked as an estimate', () {
      expect(RouteFlowGeoJson.timeText(const Duration(seconds: 20)), '~1 min');
      expect(
        RouteFlowGeoJson.timeText(const Duration(minutes: 4, seconds: 40)),
        '~5 min',
      );
    });

    test('a picked bus brings its route forward', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        const MapSelection(busId: 'a'),
        busRouteId: 'r',
      );
      // The other routes fade back; the plain line gives way to the one
      // that shows how far the bus has come.
      expect(
        filters[TransportMapLayers.routeLineLayer],
        TransportLayerFilters.none,
      );
      expect(
        filters[TransportMapLayers.routeFocusLineLayer],
        TransportLayerFilters.none,
      );
      expect(
        filters[TransportMapLayers.routeDimLayer],
        isNot(TransportLayerFilters.none),
      );
    });
  });

  group('Route patterns', () {
    test('neighbouring routes get different patterns', () {
      expect(
        [for (var i = 0; i < 4; i++) TransportGeoJson.patternOf(i)],
        [0, 1, 2, 0],
      );
      final features = TransportGeoJson.routes(_network)['features'] as List;
      expect(
        [
          for (final f in features)
            ((f as Map)['properties'] as Map)['pattern'],
        ],
        [0, 1],
      );
    });

    test('with every route showing, each pattern layer draws its routes', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        MapSelection.none,
      );
      expect(filters[TransportMapLayers.routeDashLayer], [
        '==',
        ['get', 'pattern'],
        1,
      ]);
      expect(
        filters[TransportMapLayers.routeFocusDashLayer],
        TransportLayerFilters.none,
      );
    });
  });

  group('Following', () {
    const bus = GeoPoint(22.66, 90.36);

    test('the bus is kept below the middle so the road ahead shows', () {
      final plain = MapCameraController.centreFor(
        bus,
        zoom: 16,
        bearingDegrees: 0,
        coveredTop: 0,
        coveredBottom: 0,
      );
      final ahead = MapCameraController.centreFor(
        bus,
        zoom: 16,
        bearingDegrees: 0,
        coveredTop: 0,
        coveredBottom: 0,
        lookAheadPixels: 80,
      );
      // Facing north, the camera looks north of the bus.
      expect(ahead.latitude, greaterThan(plain.latitude));
      expect(ahead.longitude, closeTo(plain.longitude, 1e-9));

      // Facing east, it looks east of the bus instead.
      final east = MapCameraController.centreFor(
        bus,
        zoom: 16,
        bearingDegrees: 90,
        coveredTop: 0,
        coveredBottom: 0,
        lookAheadPixels: 80,
      );
      expect(east.longitude, greaterThan(bus.longitude));
      expect(east.latitude, closeTo(bus.latitude, 1e-9));
    });

    test('a panel at the left moves what is shown to the right', () {
      final centre = MapCameraController.centreFor(
        bus,
        zoom: 16,
        bearingDegrees: 0,
        coveredTop: 0,
        coveredBottom: 0,
        coveredLeft: 400,
      );
      // The camera looks west of the point, so the point is right of the
      // middle of the screen.
      expect(centre.longitude, lessThan(bus.longitude));
      expect(centre.latitude, closeTo(bus.latitude, 1e-9));
    });

    testWidgets('the card names the bus, its next stop and its freshness', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.005)],
      );
      container.read(mapSelectionProvider.notifier).selectBus('a1');
      container.read(mapSelectionProvider.notifier).setFollowingBus(true);
      await tester.pumpAndSettle();

      expect(find.text('Following Bus A1'), findsOneWidget);
      expect(
        find.text('Next: Middle · Less than a minute (estimate)'),
        findsOneWidget,
      );
      // No Re-centre until the passenger has moved the map away.
      expect(find.text('Re-centre'), findsNothing);

      container.read(followPausedProvider.notifier).pause();
      await tester.pumpAndSettle();
      expect(find.text('Re-centre'), findsOneWidget);

      await tester.tap(find.text('Re-centre'));
      await tester.pumpAndSettle();
      expect(container.read(followPausedProvider), isFalse);
      expect(find.text('Re-centre'), findsNothing);
    });

    testWidgets('turning with the bus can be switched to north-up', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.005)],
      );
      container.read(mapSelectionProvider.notifier).selectBus('a1');
      container.read(mapSelectionProvider.notifier).setFollowingBus(true);
      await tester.pumpAndSettle();

      expect(container.read(followHeadingUpProvider), isTrue);
      await tester.tap(find.byTooltip('Keep the map north-up'));
      await tester.pumpAndSettle();
      expect(container.read(followHeadingUpProvider), isFalse);
      expect(find.byTooltip('Turn the map with the bus'), findsOneWidget);
    });

    testWidgets('picking another bus lets go of a paused follow', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.005), _bus('b2', latitude: 22.015)],
      );
      final select = container.read(mapSelectionProvider.notifier);
      select.selectBus('a1');
      select.setFollowingBus(true);
      await tester.pumpAndSettle();
      container.read(followPausedProvider.notifier).pause();
      select.selectBus('b2');
      await tester.pumpAndSettle();
      expect(container.read(followPausedProvider), isFalse);
    });
  });

  group('Nearest stop', () {
    test('is the closest in a straight line', () {
      final nearest = nearestStopTo(
        const GeoPoint(22.0105, 90),
        _network.stops,
      )!;
      expect(nearest.stop.id, 'm');
      expect(nearest.distanceMeters, closeTo(55.6, 1));
      expect(nearestStopTo(const GeoPoint(22, 90), const []), isNull);
    });

    test('the three nearest are given, nearest first', () {
      final near = nearestStopsTo(const GeoPoint(22.0105, 90), _network.stops);
      expect(near.map((n) => n.stop.id), ['m', 'n', 's']);
      expect(near[1].distanceMeters, greaterThan(near[0].distanceMeters));
      // No more than asked for, and no more than there are.
      expect(
        nearestStopsTo(
          const GeoPoint(22.0105, 90),
          _network.stops,
          count: 2,
        ).map((n) => n.stop.id),
        ['m', 'n'],
      );
      expect(nearestStopsTo(const GeoPoint(22, 90), const []), isEmpty);
    });

    test('the walk is longer than the straight line', () {
      // 650 m in a straight line: about eleven minutes at an easy pace.
      expect(walkingTimeFor(650).inSeconds, 650);
      expect(distanceText(346), '350 m');
      expect(distanceText(1440), '1.4 km');
    });

    test('says when to leave for a bus', () {
      const walk = Duration(minutes: 5);
      expect(
        leaveAdviceText(
          leaveAdvice(walk: walk, busIn: const Duration(minutes: 12)),
        ),
        'Leave in about 6 min.',
      );
      expect(
        leaveAdvice(walk: walk, busIn: const Duration(minutes: 6)).advice,
        LeaveAdvice.leaveNow,
      );
      expect(
        leaveAdvice(walk: walk, busIn: const Duration(minutes: 3)).advice,
        LeaveAdvice.tooLate,
      );
    });

    testWidgets('the card finds the stop, the next bus and when to leave', (
      tester,
    ) async {
      // The passenger stands about 55 m north of Middle; a bus is on its
      // way there from the south at 5 m/s.
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.002, speed: 5)],
      );
      expect(find.text('Stop nearest to you'), findsOneWidget);
      container
          .read(userPositionProvider.notifier)
          .set(const GeoPoint(22.0105, 90), _now);
      await tester.pumpAndSettle();

      // The three nearest stops are listed, nearest first.
      expect(find.text('Stops nearest to you'), findsOneWidget);
      expect(inSheet(find.text('Middle')), findsOneWidget);
      expect(inSheet(find.text('North End')), findsOneWidget);
      expect(inSheet(find.text('South End')), findsOneWidget);
      expect(
        tester.getTopLeft(inSheet(find.text('Middle'))).dy,
        lessThan(tester.getTopLeft(inSheet(find.text('North End'))).dy),
      );
      expect(
        tester.getTopLeft(inSheet(find.text('North End'))).dy,
        lessThan(tester.getTopLeft(inSheet(find.text('South End'))).dy),
      );
      expect(
        find.textContaining('60 m away · about 1 min on foot'),
        findsOneWidget,
      );
      expect(find.textContaining('Bus A1: About 3 min'), findsOneWidget);
      expect(find.textContaining('Leave in about'), findsWidgets);
      expect(
        find.textContaining('Distances are in a straight line.'),
        findsOneWidget,
      );

      // Tapping the card opens the stop. It is below the fold of the
      // closed sheet, so bring it up first.
      await tester.ensureVisible(inSheet(find.text('Middle')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Middle')));
      await tester.pumpAndSettle();
      expect(
        container.read(mapSelectionProvider),
        const MapSelection(stopId: 'm'),
      );

      // Any of the three opens its own stop.
      container.read(mapSelectionProvider.notifier).clear();
      await tester.pumpAndSettle();
      await tester.ensureVisible(inSheet(find.text('North End')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('North End')));
      await tester.pumpAndSettle();
      expect(
        container.read(mapSelectionProvider),
        const MapSelection(stopId: 'n'),
      );
    });
  });

  group('Arrival alert', () {
    test('is due once the bus is within the minutes asked for', () {
      ArrivalEstimate inMinutes(int minutes) => ArrivalEstimated(
        travelTime: Duration(minutes: minutes),
        arrivalTime: _now.add(Duration(minutes: minutes)),
        distanceMeters: 1000,
      );
      expect(checkAlert(minutes: 5, estimate: inMinutes(8)), isNull);
      expect(checkAlert(minutes: 5, estimate: inMinutes(5)), AlertOutcome.due);
      expect(checkAlert(minutes: 5, estimate: inMinutes(2)), AlertOutcome.due);
    });

    test('ends when the bus has passed, and waits when nothing is known', () {
      expect(
        checkAlert(
          minutes: 5,
          estimate: const ArrivalUnavailable(EtaUnavailableReason.stopNotAhead),
        ),
        AlertOutcome.passed,
      );
      for (final reason in [
        EtaUnavailableReason.busStopped,
        EtaUnavailableReason.positionTooOld,
        EtaUnavailableReason.directionUnknown,
      ]) {
        expect(
          checkAlert(minutes: 5, estimate: ArrivalUnavailable(reason)),
          isNull,
        );
      }
    });

    testWidgets(
      'set from a stop, it tells the passenger when the bus is near',
      (tester) async {
        // About 890 m south of Middle at 5 m/s: three minutes away.
        final container = await pumpApp(
          tester,
          network: _network,
          now: _now,
          buses: [_bus('a1', latitude: 22.002, speed: 5)],
        );
        container.read(mapSelectionProvider.notifier).selectStop('m');
        await tester.pumpAndSettle();

        final bell = find.byTooltip('Alert me when Bus A1 is near');
        await tester.ensureVisible(bell);
        await tester.pumpAndSettle();
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.text('Alert me about Bus A1'), findsOneWidget);
        expect(
          find.textContaining('works while the app is open'),
          findsOneWidget,
        );

        // Ten minutes: the bus is already nearer than that.
        await tester.tap(find.text('10 min'));
        await tester.pumpAndSettle();
        expect(find.text('Bus A1 is near'), findsOneWidget);
        expect(find.text('About 3 min to Middle (estimate).'), findsOneWidget);
        // Given once: nothing is left waiting.
        expect(container.read(arrivalAlertProvider).alert, isNull);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('an alert that is waiting is shown and can be cancelled', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        now: _now,
        buses: [_bus('a1', latitude: 22.002, speed: 5)],
      );
      container
          .read(arrivalAlertProvider.notifier)
          .set(
            const ArrivalAlert(
              busId: 'a1',
              busNumber: 'A1',
              stopId: 'm',
              stopName: 'Middle',
              minutes: 2,
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byType(ArrivalAlertLabel), findsOneWidget);
      expect(find.text('Alert: Bus A1, 2 min before Middle'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(container.read(arrivalAlertProvider).alert, isNull);
      expect(find.text('Alert: Bus A1, 2 min before Middle'), findsNothing);
    });
  });

  group('Wide screens', () {
    test('tablets and phones on their side count as wide', () {
      expect(isWideLayout(const Size(390, 844)), isFalse);
      expect(isWideLayout(const Size(800, 600)), isFalse);
      expect(isWideLayout(const Size(844, 390)), isTrue);
      expect(isWideLayout(const Size(740, 360)), isTrue);
      expect(isWideLayout(const Size(1280, 800)), isTrue);
    });

    testWidgets('the sheet becomes a panel beside the map', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpApp(tester, network: _network, now: _now);
      await tester.pumpAndSettle();

      // A rail at the side, not a bar along the bottom.
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      // The panel is at the left, as wide as it is meant to be, and does
      // not slide.
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      final panel = tester.getRect(find.byType(HomeSheet));
      expect(panel.width, HomeScreen.panelWidth);
      expect(panel.left, lessThan(200));
      expect(inSheet(find.text('North Road')), findsOneWidget);
    });
  });

  group('Route direction', () {
    testWidgets('switching it lists the stops the other way round', (
      tester,
    ) async {
      final container = await pumpApp(tester, network: _network, now: _now);
      container.read(mapSelectionProvider.notifier).selectRoute('r');
      await tester.pumpAndSettle();

      expect(find.text('South End → North End'), findsOneWidget);
      await tester.tap(find.byTooltip('Show the other direction'));
      await tester.pumpAndSettle();
      expect(find.text('North End → South End'), findsOneWidget);
      expect(container.read(routeShownReversedProvider), isTrue);

      // Another route starts the right way round again.
      container.read(mapSelectionProvider.notifier).selectRoute('q');
      await tester.pumpAndSettle();
      expect(container.read(routeShownReversedProvider), isFalse);
    });
  });
}
