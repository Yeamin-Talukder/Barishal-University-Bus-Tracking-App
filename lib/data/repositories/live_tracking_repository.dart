import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_bootstrap.dart';
import '../models/bus.dart';
import '../models/geo_point.dart';

/// A trip in progress: a driver sharing a bus's position.
@immutable
class ActiveTrip {
  const ActiveTrip({
    required this.busId,
    required this.tripId,
    required this.driverUid,
    this.routeId,
    this.startedAt,
  });

  final String busId;
  final String tripId;
  final String driverUid;
  final String? routeId;
  final DateTime? startedAt;
}

/// A position as the driver's phone measured it, before the server stamps
/// the time on it.
@immutable
class PositionFix {
  const PositionFix({
    required this.position,
    this.headingDegrees,
    this.speedMetersPerSecond,
    this.accuracyMeters,
  });

  final GeoPoint position;
  final double? headingDegrees;
  final double? speedMetersPerSecond;
  final double? accuracyMeters;
}

/// A tracking action that could not be done, with a message that can be
/// shown to the driver or admin as it is.
class TrackingFailure implements Exception {
  const TrackingFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Trips and live bus positions, kept in the Realtime Database.
///
/// Anyone may read them. The database's security rules decide who may
/// write: only the driver an admin assigned to a bus can start a trip on it,
/// and only the driver of that trip can publish its position.
abstract interface class LiveTrackingRepository {
  /// The latest reported position of every bus on a trip, by bus id.
  Stream<Map<String, BusLocation>> watchLocations();

  /// Every trip in progress, by bus id.
  Stream<Map<String, ActiveTrip>> watchActiveTrips();

  /// The trip in progress on [busId], or null.
  Stream<ActiveTrip?> watchActiveTrip(String busId);

  /// Starts a trip on [bus] for [driverUid]. Throws [TrackingFailure].
  Future<ActiveTrip> startTrip({required Bus bus, required String driverUid});

  /// Publishes where the bus is. The server sets the time. Throws
  /// [TrackingFailure].
  Future<void> publishPosition(ActiveTrip trip, PositionFix fix);

  /// Ends the trip on [busId] and removes its position. Throws
  /// [TrackingFailure].
  Future<void> endTrip(String busId);
}

/// What the Realtime Database needs to know to enforce the rules above. It
/// cannot see the Firestore profiles and buses, so an admin's changes there
/// are copied here.
abstract interface class TrackingAccess {
  /// Records which driver each bus is assigned to (null for none). A bus
  /// whose driver changed has any trip in progress ended.
  Future<void> setBusDrivers(Map<String, String?> driverByBusId);

  /// Records whether [uid] is an admin.
  Future<void> setAdmin(String uid, {required bool isAdmin});
}

/// Reads one stored position. Returns null for anything that is not a
/// usable position, so a damaged entry can never put a bus in a wrong place.
BusLocation? busLocationFromMap(Object? value) {
  if (value is! Map) return null;
  final latitude = value['latitude'];
  final longitude = value['longitude'];
  final updatedAt = value['updatedAt'];
  if (latitude is! num || longitude is! num || updatedAt is! num) return null;
  final position = GeoPoint(latitude.toDouble(), longitude.toDouble());
  if (!position.isValid) return null;

  double? number(String key) {
    final field = value[key];
    return field is num ? field.toDouble() : null;
  }

  final tripId = value['tripId'];
  return BusLocation(
    position: position,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt()),
    headingDegrees: number('heading'),
    speedMetersPerSecond: number('speed'),
    accuracyMeters: number('accuracy'),
    tripId: tripId is String ? tripId : null,
  );
}

/// The stored form of a position. Values outside what the security rules
/// accept are left out rather than sent and refused.
Map<String, Object?> positionToMap(ActiveTrip trip, PositionFix fix) {
  final heading = fix.headingDegrees;
  final speed = fix.speedMetersPerSecond;
  final accuracy = fix.accuracyMeters;
  return {
    'tripId': trip.tripId,
    'driverUid': trip.driverUid,
    'latitude': fix.position.latitude,
    'longitude': fix.position.longitude,
    if (heading != null && heading >= 0 && heading <= 360) 'heading': heading,
    if (speed != null && speed >= 0 && speed <= 60) 'speed': speed,
    if (accuracy != null && accuracy >= 0 && accuracy <= 5000)
      'accuracy': accuracy,
  };
}

ActiveTrip? activeTripFromMap(String busId, Object? value) {
  if (value is! Map) return null;
  final tripId = value['tripId'];
  final driverUid = value['driverUid'];
  if (tripId is! String || driverUid is! String) return null;
  if (value['status'] != 'active') return null;
  final routeId = value['routeId'];
  final startedAt = value['startedAt'];
  return ActiveTrip(
    busId: busId,
    tripId: tripId,
    driverUid: driverUid,
    routeId: routeId is String ? routeId : null,
    startedAt: startedAt is num
        ? DateTime.fromMillisecondsSinceEpoch(startedAt.toInt())
        : null,
  );
}

class RealtimeDatabaseTracking
    implements LiveTrackingRepository, TrackingAccess {
  RealtimeDatabaseTracking(this._database);

  final FirebaseDatabase _database;

  static const Duration _serverWait = Duration(seconds: 12);

  @override
  Stream<Map<String, BusLocation>> watchLocations() =>
      _database.ref('liveLocations').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <String, BusLocation>{};
        return {
          for (final MapEntry(:key, value: entry) in value.entries)
            if (key is String) key: ?busLocationFromMap(entry),
        };
      });

  @override
  Stream<Map<String, ActiveTrip>> watchActiveTrips() =>
      _database.ref('activeTrips').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is! Map) return const <String, ActiveTrip>{};
        return {
          for (final MapEntry(:key, value: entry) in value.entries)
            if (key is String) key: ?activeTripFromMap(key, entry),
        };
      });

  @override
  Stream<ActiveTrip?> watchActiveTrip(String busId) => _database
      .ref('activeTrips/$busId')
      .onValue
      .map((event) => activeTripFromMap(busId, event.snapshot.value));

  @override
  Future<ActiveTrip> startTrip({
    required Bus bus,
    required String driverUid,
  }) async {
    final tripId = _database.ref('activeTrips').push().key!;
    final routeId = bus.routeId;
    await _send(
      _database.ref('activeTrips/${bus.id}').set({
        'tripId': tripId,
        'driverUid': driverUid,
        'status': 'active',
        'startedAt': ServerValue.timestamp,
        if (routeId != null && routeId.length <= 20) 'routeId': routeId,
      }),
      refused: 'This bus is not assigned to you. Ask the transport office.',
    );
    return ActiveTrip(
      busId: bus.id,
      tripId: tripId,
      driverUid: driverUid,
      routeId: routeId,
      startedAt: DateTime.now(),
    );
  }

  @override
  Future<void> publishPosition(ActiveTrip trip, PositionFix fix) => _send(
    _database.ref('liveLocations/${trip.busId}').set({
      ...positionToMap(trip, fix),
      'updatedAt': ServerValue.timestamp,
    }),
    refused:
        'The position was refused. The trip may have been ended, or the bus '
        'given to someone else.',
  );

  @override
  Future<void> endTrip(String busId) => _send(
    _database.ref().update({
      'activeTrips/$busId': null,
      'liveLocations/$busId': null,
    }),
    refused: 'Only the driver of this bus or an admin can end its trip.',
  );

  @override
  Future<void> setBusDrivers(Map<String, String?> driverByBusId) async {
    if (driverByBusId.isEmpty) return;
    final current = await _database
        .ref('busDrivers')
        .get()
        .timeout(_serverWait, onTimeout: () => throw _noAnswer);
    final existing = current.value is Map ? current.value! as Map : const {};

    final changes = <String, Object?>{};
    for (final MapEntry(key: busId, value: driverUid)
        in driverByBusId.entries) {
      if (existing[busId] == driverUid) continue;
      changes['busDrivers/$busId'] = driverUid;
      // The bus has a new driver, or none: whatever trip was in progress
      // belongs to someone who no longer drives it.
      changes['activeTrips/$busId'] = null;
      changes['liveLocations/$busId'] = null;
    }
    if (changes.isEmpty) return;
    await _send(
      _database.ref().update(changes),
      refused:
          'Saved, but the tracking permissions could not be updated: this '
          'admin account is not yet set up for tracking.',
    );
  }

  @override
  Future<void> setAdmin(String uid, {required bool isAdmin}) => _send(
    isAdmin
        ? _database.ref('admins/$uid').set(true)
        : _database.ref('admins/$uid').remove(),
    refused:
        'Saved, but the tracking permissions could not be updated: this '
        'admin account is not yet set up for tracking.',
  );

  static const TrackingFailure _noAnswer = TrackingFailure(
    'No answer from the server. Check the internet and try again.',
  );

  Future<void> _send(Future<void> write, {required String refused}) async {
    try {
      await write.timeout(_serverWait);
    } on TimeoutException {
      throw _noAnswer;
    } on FirebaseException catch (error) {
      debugPrint('Tracking write refused: ${error.code}');
      throw TrackingFailure(
        error.code == 'permission-denied'
            ? refused
            : 'The tracking service could not be reached. Try again.',
      );
    }
  }
}

/// Used when the app is not connected to the tracking service.
class UnavailableTracking implements LiveTrackingRepository, TrackingAccess {
  const UnavailableTracking();

  static const TrackingFailure _failure = TrackingFailure(
    'This build is not connected to the tracking service.',
  );

  @override
  Stream<Map<String, BusLocation>> watchLocations() => Stream.value(const {});

  @override
  Stream<Map<String, ActiveTrip>> watchActiveTrips() => Stream.value(const {});

  @override
  Stream<ActiveTrip?> watchActiveTrip(String busId) => Stream.value(null);

  @override
  Future<ActiveTrip> startTrip({required Bus bus, required String driverUid}) =>
      throw _failure;

  @override
  Future<void> publishPosition(ActiveTrip trip, PositionFix fix) =>
      throw _failure;

  @override
  Future<void> endTrip(String busId) => throw _failure;

  @override
  Future<void> setBusDrivers(Map<String, String?> driverByBusId) async {}

  @override
  Future<void> setAdmin(String uid, {required bool isAdmin}) async {}
}

final _realtimeTrackingProvider = Provider<Object>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableTracking();
  }
  return RealtimeDatabaseTracking(FirebaseDatabase.instance);
});

final liveTrackingRepositoryProvider = Provider<LiveTrackingRepository>(
  (ref) => ref.watch(_realtimeTrackingProvider) as LiveTrackingRepository,
);

final trackingAccessProvider = Provider<TrackingAccess>(
  (ref) => ref.watch(_realtimeTrackingProvider) as TrackingAccess,
);

/// The trip in progress on one bus, live.
final activeTripProvider = StreamProvider.family<ActiveTrip?, String>(
  (ref, busId) =>
      ref.watch(liveTrackingRepositoryProvider).watchActiveTrip(busId),
);
