import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/geo_math.dart';
import '../../../core/utils/route_geometry.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../map/application/transport_map_layers.dart';

/// A pretend bus for trying the app out. It exists only on this device.
@immutable
class TestBus {
  const TestBus({
    required this.number,
    required this.routeId,
    required this.towardsStart,
    required this.speedKmh,
    required this.startDelay,
  });

  /// 1 for "TEST 1", and so on.
  final int number;
  final String routeId;

  /// Whether it first drives from the route's end to its start. Otherwise
  /// it first drives from the start to the end.
  final bool towardsStart;
  final double speedKmh;

  /// How long after the test begins this bus sets off.
  final Duration startDelay;

  /// The id it has among the tracked buses. No real bus has an id like it.
  String get id => 'device-test-$number';
  String get label => 'TEST $number';
}

/// Where a test bus is at one moment.
@immutable
class TestBusPose {
  const TestBusPose({
    required this.position,
    required this.headingDegrees,
    required this.speedMetersPerSecond,
  });

  final GeoPoint position;
  final double headingDegrees;

  /// Zero while it waits at an end of the route.
  final double speedMetersPerSecond;
}

/// Where a bus driving along [path] at a steady speed is [sinceSetOff]
/// after leaving its first point.
///
/// It drives to the far end, waits there for [wait], drives back, waits,
/// and starts again, so a test can be left running. Returns null for a path
/// that cannot be driven or a speed that is not positive.
TestBusPose? poseOnPath(
  List<GeoPoint> path, {
  required double speedMetersPerSecond,
  required Duration sinceSetOff,
  Duration wait = const Duration(seconds: 20),
}) {
  if (path.length < 2 || speedMetersPerSecond <= 0 || sinceSetOff.isNegative) {
    return null;
  }
  final cumulative = <double>[0];
  for (var i = 1; i < path.length; i++) {
    cumulative.add(
      cumulative.last +
          haversineDistanceMeters(
            path[i - 1].latitude,
            path[i - 1].longitude,
            path[i].latitude,
            path[i].longitude,
          ),
    );
  }
  final length = cumulative.last;
  if (length <= 0) return null;

  final driving = length / speedMetersPerSecond;
  final waiting = wait.inMicroseconds / Duration.microsecondsPerSecond;
  final seconds =
      (sinceSetOff.inMicroseconds / Duration.microsecondsPerSecond) %
      (2 * (driving + waiting));

  // Distance from the path's first point, which way it faces, and whether
  // it is moving.
  final double along;
  final bool outward;
  final bool moving;
  if (seconds < driving) {
    along = seconds * speedMetersPerSecond;
    outward = true;
    moving = true;
  } else if (seconds < driving + waiting) {
    along = length;
    outward = true;
    moving = false;
  } else if (seconds < 2 * driving + waiting) {
    along = length - (seconds - driving - waiting) * speedMetersPerSecond;
    outward = false;
    moving = true;
  } else {
    along = 0;
    outward = false;
    moving = false;
  }

  // The stretch of the path that distance falls on.
  var segment = 0;
  while (segment < path.length - 2 && cumulative[segment + 1] < along) {
    segment++;
  }
  final from = path[segment];
  final to = path[segment + 1];
  final segmentLength = cumulative[segment + 1] - cumulative[segment];
  final fraction = segmentLength <= 0
      ? 0.0
      : ((along - cumulative[segment]) / segmentLength).clamp(0.0, 1.0);
  final bearing = bearingDegrees(from, to);

  return TestBusPose(
    position: GeoPoint(
      from.latitude + (to.latitude - from.latitude) * fraction,
      from.longitude + (to.longitude - from.longitude) * fraction,
    ),
    headingDegrees: outward ? bearing : (bearing + 180) % 360,
    speedMetersPerSecond: moving ? speedMetersPerSecond : 0,
  );
}

@immutable
class TestDriveState {
  const TestDriveState({this.buses = const [], this.isRunning = false});

  final List<TestBus> buses;
  final bool isRunning;
}

/// Runs pretend buses along the real routes, on this device only.
///
/// Nothing is written to the server and no other phone sees these buses:
/// they are worked out here and shown next to whatever real buses there
/// are. Each is named TEST and described as a test bus, so it can never be
/// taken for a real one, and they all vanish when the test is stopped.
class TestDriveController extends Notifier<TestDriveState> {
  /// How often the pretend buses report, like a driver's phone does.
  static const Duration reportEvery = Duration(seconds: 2);

  /// Enough to fill the map without slowing a phone down.
  static const int mostBuses = 12;

  Timer? _timer;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// When each bus sets off, counted from the start of the test.
  final Map<String, Duration> _setsOffAt = {};

  @override
  TestDriveState build() {
    ref.onDispose(() => _timer?.cancel());
    return const TestDriveState();
  }

  DateTime _now() => ref.read(clockProvider)();

  bool get isFull => state.buses.length >= mostBuses;

  /// Adds a bus. One added while the test runs sets off [startDelay] from
  /// now.
  void addBus({
    required String routeId,
    required bool towardsStart,
    required double speedKmh,
    Duration startDelay = Duration.zero,
  }) {
    if (isFull) return;
    final used = {for (final bus in state.buses) bus.number};
    var number = 1;
    while (used.contains(number)) {
      number++;
    }
    final bus = TestBus(
      number: number,
      routeId: routeId,
      towardsStart: towardsStart,
      speedKmh: speedKmh,
      startDelay: startDelay,
    );
    if (state.isRunning) {
      _setsOffAt[bus.id] = _now().difference(_startedAt) + startDelay;
    }
    state = TestDriveState(
      buses: [...state.buses, bus],
      isRunning: state.isRunning,
    );
    if (state.isRunning) _report();
  }

  /// Adds one bus each way on up to three of [routes], each with its own
  /// speed and a start a few seconds after the one before.
  void addSampleBuses(List<BusRoute> routes) {
    const speeds = [40.0, 29.0, 47.0, 32.0, 50.0, 36.0];
    final drivable = [
      for (final route in routes)
        if (route.path.length >= 2) route,
    ].take(3).toList();
    var index = 0;
    for (final towardsStart in [true, false]) {
      for (final route in drivable) {
        addBus(
          routeId: route.id,
          towardsStart: towardsStart,
          speedKmh: speeds[index % speeds.length],
          startDelay: Duration(seconds: 8 * index),
        );
        index++;
      }
    }
  }

  void removeBus(String id) {
    _setsOffAt.remove(id);
    final left = [
      for (final bus in state.buses)
        if (bus.id != id) bus,
    ];
    state = TestDriveState(buses: left, isRunning: state.isRunning);
    if (left.isEmpty) {
      stop();
    } else if (state.isRunning) {
      _report();
    }
  }

  /// Sets the buses going.
  void start() {
    if (state.isRunning || state.buses.isEmpty) return;
    _startedAt = _now();
    _setsOffAt
      ..clear()
      ..addEntries([
        for (final bus in state.buses) MapEntry(bus.id, bus.startDelay),
      ]);
    state = TestDriveState(buses: state.buses, isRunning: true);
    _timer?.cancel();
    _timer = Timer.periodic(reportEvery, (_) => _report());
    _report();
  }

  /// Stops the test and takes every pretend bus off the map.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _setsOffAt.clear();
    if (state.isRunning) {
      state = TestDriveState(buses: state.buses);
    }
    ref.read(localTestBusesProvider.notifier).show(const []);
  }

  /// Works out where every bus is now and shows them.
  void _report() {
    final network = ref.read(transportNetworkProvider).value;
    if (!state.isRunning || network == null) return;
    final now = _now();
    final elapsed = now.difference(_startedAt);

    final tracked = <TrackedBus>[];
    for (final bus in state.buses) {
      final setsOffAt = _setsOffAt[bus.id];
      final route = network.routeById(bus.routeId);
      // Not off yet, or its route has gone or was never drawn.
      if (setsOffAt == null || elapsed < setsOffAt || route == null) continue;
      // The line as drawn on the map, without its stubs.
      final line = TransportGeoJson.withoutStubs(route.path);
      final pose = poseOnPath(
        bus.towardsStart ? line.reversed.toList() : line,
        speedMetersPerSecond: bus.speedKmh / 3.6,
        sinceSetOff: elapsed - setsOffAt,
      );
      if (pose == null) continue;
      tracked.add(
        TrackedBus(
          bus: Bus(
            id: bus.id,
            number: bus.label,
            name: 'Test bus, only on this phone',
            routeId: bus.routeId,
            isActive: true,
          ),
          location: BusLocation(
            position: pose.position,
            updatedAt: now,
            headingDegrees: pose.headingDegrees,
            speedMetersPerSecond: pose.speedMetersPerSecond,
            accuracyMeters: 8,
          ),
        ),
      );
    }
    ref.read(localTestBusesProvider.notifier).show(tracked);
  }
}

final testDriveProvider = NotifierProvider<TestDriveController, TestDriveState>(
  TestDriveController.new,
);
