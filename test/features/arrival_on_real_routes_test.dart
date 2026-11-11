import 'dart:convert';
import 'dart:io';

import 'package:bu_bus_tracker/core/services/eta_service.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/repositories/bus_location_repository.dart';
import 'package:bu_bus_tracker/data/repositories/live_tracking_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/bus_fakes.dart';
import '../helpers/tracking_fakes.dart';

/// Route 01 as it was worked out for the real stops
/// (tools/data/routes_draft.json). The positions used below are points on
/// that path, standing in for a bus in a test. They are never shown.
({BusRoute route, List<BusStop> stops}) _route01() {
  final draft = jsonDecode(
    File('tools/data/routes_draft.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final data = draft['routes']['01'] as Map<String, dynamic>;
  final path = [
    for (final point in data['path'] as List)
      GeoPoint((point[0] as num).toDouble(), (point[1] as num).toDouble()),
  ];
  final ids = (data['stopIds'] as List).cast<String>();
  final names = (data['stopNames'] as List).cast<String>();
  return (
    route: BusRoute(
      id: '01',
      name: 'Route 01',
      colorHex: '#D94A38',
      startName: names.first,
      endName: names.last,
      path: path,
      stopIds: ids,
      isActive: true,
    ),
    // Each stop sits on the path: the nearest path point to it is used.
    stops: [
      for (var i = 0; i < ids.length; i++)
        BusStop(
          id: ids[i],
          name: names[i],
          position: path[((path.length - 1) * i / (ids.length - 1)).round()],
        ),
    ],
  );
}

void main() {
  const eta = EtaService();
  final now = DateTime(2026, 11, 11, 8, 30);

  test('a bus half way along route 01 gets a time to the university', () {
    final (:route, :stops) = _route01();
    final middle = route.path[route.path.length ~/ 2];
    final justBefore = route.path[route.path.length ~/ 2 - 3];
    final tracked = TrackedBus(
      bus: const Bus(id: 'b', number: 'BRTC-05', name: 'x', isActive: true),
      location: BusLocation(
        position: middle,
        updatedAt: now.subtract(const Duration(seconds: 4)),
        speedMetersPerSecond: 8,
        accuracyMeters: 8,
      ),
    );

    final estimate = eta.estimateArrival(
      route: route,
      stops: stops,
      stop: stops.last,
      location: tracked.location,
      previous: BusLocation(
        position: justBefore,
        updatedAt: now.subtract(const Duration(seconds: 12)),
      ),
      now: now,
    );

    expect(estimate, isA<ArrivalEstimated>());
    final arrival = estimate as ArrivalEstimated;
    // Route 01 is 7 km; from the middle at 8 m/s that is roughly 4 to 12
    // minutes, never an hour and never a few seconds.
    expect(arrival.travelTime.inMinutes, inInclusiveRange(4, 12));
    expect(arrival.distanceMeters, inInclusiveRange(2500, 4500));
  });

  test('a bus on a trip is on the route its driver chose', () async {
    const bus = Bus(
      id: 'chitra',
      number: 'Chitra',
      name: 'চিত্রা',
      driverUid: 'd1',
      isActive: true,
    );
    final tracking = FakeTracking()..busDrivers['chitra'] = 'd1';
    final repository = LiveBusLocationRepository(
      FakeBusRepository(const [bus]),
      tracking,
      refreshEvery: const Duration(hours: 1),
    );
    final seen = <List<TrackedBus>>[];
    final subscription = repository.watchBuses().listen(seen.add);
    addTearDown(subscription.cancel);
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 30));
    await settle();

    // The schedule uses this bus on several routes, so it has none of its
    // own.
    expect(seen.last.single.bus.routeId, isNull);

    await tracking.startTrip(
      bus: const Bus(
        id: 'chitra',
        number: 'Chitra',
        name: 'চিত্রা',
        routeId: '03',
        driverUid: 'd1',
        isActive: true,
      ),
      driverUid: 'd1',
    );
    await settle();
    expect(seen.last.single.bus.routeId, '03');

    await tracking.endTrip('chitra');
    await settle();
    expect(seen.last.single.bus.routeId, isNull);
  });

  test('a trip started with no route stays without one', () async {
    final tracking = FakeTracking()..busDrivers['b'] = 'd1';
    const bus = Bus(id: 'b', number: 'B', name: 'B', isActive: true);
    final trip = await tracking.startTrip(bus: bus, driverUid: 'd1');

    expect(trip.routeId, isNull);
    expect(
      positionToMap(
        trip,
        const PositionFix(position: GeoPoint(22.66, 90.36)),
      ).containsKey('routeId'),
      isFalse,
    );
  });
}
