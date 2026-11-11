import 'dart:async';

import 'package:bu_bus_tracker/core/services/location_service.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/repositories/live_tracking_repository.dart';
import 'package:bu_bus_tracker/features/driver/application/driver_location_source.dart';

/// An in-memory stand-in for the tracking part of the Realtime Database.
/// It applies the same decisions the security rules make.
class FakeTracking implements LiveTrackingRepository, TrackingAccess {
  FakeTracking({this.now});

  /// The time stamped on a published position. Defaults to the real clock.
  DateTime Function()? now;

  final Map<String, String> busDrivers = {};
  final Set<String> admins = {};
  final Map<String, ActiveTrip> trips = {};
  final Map<String, BusLocation> locations = {};
  final List<PositionFix> published = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextTrip = 1;

  /// When set, the next position is refused with this.
  TrackingFailure? refusePositions;

  /// When set, copying admin changes across is refused with this.
  TrackingFailure? refuseAccessChanges;

  /// When set, ending a trip fails with this.
  TrackingFailure? refuseEnd;

  @override
  Stream<Map<String, BusLocation>> watchLocations() async* {
    yield Map.of(locations);
    yield* _changes.stream.map((_) => Map.of(locations));
  }

  @override
  Stream<Map<String, ActiveTrip>> watchActiveTrips() async* {
    yield Map.of(trips);
    yield* _changes.stream.map((_) => Map.of(trips));
  }

  @override
  Stream<ActiveTrip?> watchActiveTrip(String busId) async* {
    yield trips[busId];
    yield* _changes.stream.map((_) => trips[busId]);
  }

  @override
  Future<ActiveTrip> startTrip({
    required Bus bus,
    required String driverUid,
  }) async {
    if (busDrivers[bus.id] != driverUid) {
      throw const TrackingFailure('This bus is not assigned to you.');
    }
    final trip = ActiveTrip(
      busId: bus.id,
      tripId: 'trip-${_nextTrip++}',
      driverUid: driverUid,
      routeId: bus.routeId,
    );
    trips[bus.id] = trip;
    _changes.add(null);
    return trip;
  }

  @override
  Future<void> publishPosition(ActiveTrip trip, PositionFix fix) async {
    final refusal = refusePositions;
    if (refusal != null) throw refusal;
    final open = trips[trip.busId];
    if (open == null ||
        open.tripId != trip.tripId ||
        busDrivers[trip.busId] != trip.driverUid) {
      throw const TrackingFailure('The position was refused.');
    }
    published.add(fix);
    locations[trip.busId] = BusLocation(
      position: fix.position,
      updatedAt: (now ?? DateTime.now)(),
      headingDegrees: fix.headingDegrees,
      speedMetersPerSecond: fix.speedMetersPerSecond,
      accuracyMeters: fix.accuracyMeters,
      tripId: trip.tripId,
    );
    _changes.add(null);
  }

  @override
  Future<void> endTrip(String busId) async {
    final refusal = refuseEnd;
    if (refusal != null) throw refusal;
    trips.remove(busId);
    locations.remove(busId);
    _changes.add(null);
  }

  @override
  Future<void> setBusDrivers(Map<String, String?> driverByBusId) async {
    final refusal = refuseAccessChanges;
    if (refusal != null) throw refusal;
    for (final MapEntry(key: busId, value: driverUid)
        in driverByBusId.entries) {
      if (busDrivers[busId] == driverUid) continue;
      if (driverUid == null) {
        busDrivers.remove(busId);
      } else {
        busDrivers[busId] = driverUid;
      }
      // A bus whose driver changed has its trip ended.
      trips.remove(busId);
      locations.remove(busId);
    }
    _changes.add(null);
  }

  @override
  Future<void> setAdmin(String uid, {required bool isAdmin}) async {
    final refusal = refuseAccessChanges;
    if (refusal != null) throw refusal;
    isAdmin ? admins.add(uid) : admins.remove(uid);
  }
}

/// Stands in for the phone's GPS.
class FakeDriverLocationSource implements DriverLocationSource {
  /// What [prepare] reports. Null means location is ready to use.
  LocationProblem? problem;

  StreamController<PositionFix>? _controller;

  /// How many times the position stream has been started.
  int started = 0;

  /// Whether something is listening for positions right now.
  bool get isListening => _controller?.hasListener ?? false;

  @override
  Future<LocationProblem?> prepare() async => problem;

  @override
  Stream<PositionFix> positions() {
    started++;
    final controller = StreamController<PositionFix>();
    _controller = controller;
    return controller.stream;
  }

  /// Pretends the phone measured [fix].
  void emit(PositionFix fix) => _controller?.add(fix);

  /// Pretends the phone's location failed.
  void fail() => _controller?.addError(StateError('gps lost'));
}
