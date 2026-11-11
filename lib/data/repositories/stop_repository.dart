import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide GeoPoint;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_bootstrap.dart';
import '../models/bus_stop.dart';
import '../models/geo_point.dart';

/// A change to the stops that could not be made, with a message that can be
/// shown to the admin as it is.
class StopWriteFailure implements Exception {
  const StopWriteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The stops the transport office keeps in the database.
///
/// Anyone may read them. Only an admin may change them: the database's
/// security rules refuse everyone else, whatever the app shows.
abstract interface class StopRepository {
  /// The stops, sorted by name, and again whenever they change.
  Stream<List<BusStop>> watchStops();

  /// Adds [stop] when its id is empty, otherwise replaces the stop with
  /// that id. Throws [StopWriteFailure].
  Future<void> saveStop(BusStop stop);

  /// Removes a stop for good. Throws [StopWriteFailure].
  Future<void> deleteStop(String id);
}

/// Stops in the `stops` collection of Cloud Firestore.
class FirestoreStopRepository implements StopRepository {
  FirestoreStopRepository(this._firestore);

  final FirebaseFirestore _firestore;

  /// How long to wait for the server to accept a change. A change made
  /// offline is kept on the device and sent later, so this is not a failure
  /// of the change itself.
  static const Duration _serverWait = Duration(seconds: 12);

  CollectionReference<Map<String, dynamic>> get _stops =>
      _firestore.collection('stops');

  @override
  Stream<List<BusStop>> watchStops() => _stops.snapshots().map((snapshot) {
    final stops = <BusStop>[
      for (final document in snapshot.docs)
        ?stopFromMap(document.id, document.data()),
    ];
    stops.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return stops;
  });

  @override
  Future<void> saveStop(BusStop stop) {
    final document = stop.id.isEmpty ? _stops.doc() : _stops.doc(stop.id);
    return _send(document.set(stopToMap(stop)));
  }

  @override
  Future<void> deleteStop(String id) => _send(_stops.doc(id).delete());

  Future<void> _send(Future<void> write) async {
    try {
      await write.timeout(_serverWait);
    } on TimeoutException {
      throw const StopWriteFailure(
        'No answer from the server. The change is kept on this device and '
        'will be sent when the connection is back.',
      );
    } on FirebaseException catch (error) {
      debugPrint('Stop change refused: ${error.code}');
      throw StopWriteFailure(switch (error.code) {
        'permission-denied' =>
          'Only a transport office admin can change the stops.',
        'unavailable' => 'No connection. Check the internet and try again.',
        _ => 'The change could not be saved. Try again.',
      });
    }
  }
}

/// Reads a stop document. Returns null for one that is not a usable stop,
/// so a damaged document can never put a stop in the wrong place.
BusStop? stopFromMap(String id, Map<String, dynamic> data) {
  final name = data['name'];
  final latitude = data['latitude'];
  final longitude = data['longitude'];
  final description = data['description'];
  if (name is! String || name.trim().isEmpty) return null;
  if (latitude is! num || longitude is! num) return null;
  final position = GeoPoint(latitude.toDouble(), longitude.toDouble());
  if (!position.isValid) return null;
  return BusStop(
    id: id,
    name: name.trim(),
    position: position,
    description: description is String && description.trim().isNotEmpty
        ? description.trim()
        : null,
  );
}

/// The document stored for [stop]. Only the fields the security rules allow.
Map<String, dynamic> stopToMap(BusStop stop) {
  final description = stop.description?.trim();
  return {
    'name': stop.name.trim(),
    'latitude': stop.position.latitude,
    'longitude': stop.position.longitude,
    if (description != null && description.isNotEmpty)
      'description': description,
  };
}

/// Used when the app is not connected to the tracking service.
class UnavailableStopRepository implements StopRepository {
  const UnavailableStopRepository();

  static const StopWriteFailure _failure = StopWriteFailure(
    'This build is not connected to the tracking service.',
  );

  @override
  Stream<List<BusStop>> watchStops() => Stream.value(const []);

  @override
  Future<void> saveStop(BusStop stop) => throw _failure;

  @override
  Future<void> deleteStop(String id) => throw _failure;
}

final stopRepositoryProvider = Provider<StopRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableStopRepository();
  }
  return FirestoreStopRepository(FirebaseFirestore.instance);
});

/// The stops kept by the transport office, live.
final officialStopsProvider = StreamProvider<List<BusStop>>(
  (ref) => ref.watch(stopRepositoryProvider).watchStops(),
);
