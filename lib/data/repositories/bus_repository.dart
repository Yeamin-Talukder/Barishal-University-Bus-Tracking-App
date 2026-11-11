import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_bootstrap.dart';
import '../models/bus.dart';
import 'live_tracking_repository.dart';
import 'tracking_mirror.dart';

/// A change to the buses that could not be made, with a message that can be
/// shown to the admin as it is.
class BusWriteFailure implements Exception {
  const BusWriteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The buses the transport office keeps in the database.
///
/// Anyone may read them. Only an admin may change them: the database's
/// security rules refuse everyone else, whatever the app shows.
abstract interface class BusRepository {
  /// Every registered bus, in service or not, sorted by number, and again
  /// whenever one changes.
  Stream<List<Bus>> watchBuses();

  /// Adds [bus] when its id is empty, otherwise replaces the bus with that
  /// id. Returns the bus's id. Throws [BusWriteFailure].
  Future<String> saveBus(Bus bus);

  /// Adds several new buses in one step: all of them, or none.
  Future<void> addAll(List<Bus> buses);

  /// Removes a bus for good. Throws [BusWriteFailure].
  Future<void> deleteBus(String id);
}

/// Reads a bus document. Returns null for one that is not a usable bus.
Bus? busFromMap(String id, Map<String, dynamic> data) {
  String? text(String key) {
    final value = data[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  final number = text('busNumber');
  final name = text('name');
  if (number == null || name == null) return null;
  return Bus(
    id: id,
    number: number,
    name: name,
    registrationNumber: text('registrationNumber'),
    routeId: text('routeId'),
    driverUid: text('driverUid'),
    // A bus is in service only when the database says so explicitly.
    isActive: data['isActive'] == true,
  );
}

/// The document stored for [bus]. Only the fields the security rules allow.
Map<String, dynamic> busToMap(Bus bus) {
  String? text(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  return {
    'busNumber': bus.number.trim(),
    'name': bus.name.trim(),
    'isActive': bus.isActive,
    'registrationNumber': ?text(bus.registrationNumber),
    'routeId': ?text(bus.routeId),
    'driverUid': ?text(bus.driverUid),
  };
}

/// Buses in the `buses` collection of Cloud Firestore.
class FirestoreBusRepository implements BusRepository {
  FirestoreBusRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const Duration _serverWait = Duration(seconds: 12);

  CollectionReference<Map<String, dynamic>> get _buses =>
      _firestore.collection('buses');

  @override
  Stream<List<Bus>> watchBuses() => _buses.snapshots().map((snapshot) {
    final buses = <Bus>[
      for (final document in snapshot.docs)
        ?busFromMap(document.id, document.data()),
    ];
    buses.sort(
      (a, b) => a.number.toLowerCase().compareTo(b.number.toLowerCase()),
    );
    return buses;
  });

  @override
  Future<String> saveBus(Bus bus) async {
    final document = bus.id.isEmpty ? _buses.doc() : _buses.doc(bus.id);
    await _send(document.set(busToMap(bus)));
    return document.id;
  }

  @override
  Future<void> addAll(List<Bus> buses) {
    final batch = _firestore.batch();
    for (final bus in buses) {
      batch.set(_buses.doc(), busToMap(bus));
    }
    return _send(batch.commit());
  }

  @override
  Future<void> deleteBus(String id) => _send(_buses.doc(id).delete());

  Future<void> _send(Future<void> write) async {
    try {
      await write.timeout(_serverWait);
    } on TimeoutException {
      throw const BusWriteFailure(
        'No answer from the server. The change is kept on this device and '
        'will be sent when the connection is back.',
      );
    } on FirebaseException catch (error) {
      debugPrint('Bus change refused: ${error.code}');
      throw BusWriteFailure(switch (error.code) {
        'permission-denied' =>
          'Only a transport office admin can change the buses.',
        'unavailable' => 'No connection. Check the internet and try again.',
        _ => 'The change could not be saved. Try again.',
      });
    }
  }
}

/// Used when the app is not connected to the tracking service.
class UnavailableBusRepository implements BusRepository {
  const UnavailableBusRepository();

  static const BusWriteFailure _failure = BusWriteFailure(
    'This build is not connected to the tracking service.',
  );

  @override
  Stream<List<Bus>> watchBuses() => Stream.value(const []);

  @override
  Future<String> saveBus(Bus bus) => throw _failure;

  @override
  Future<void> addAll(List<Bus> buses) => throw _failure;

  @override
  Future<void> deleteBus(String id) => throw _failure;
}

final busRepositoryProvider = Provider<BusRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableBusRepository();
  }
  return MirroringBusRepository(
    FirestoreBusRepository(FirebaseFirestore.instance),
    ref.watch(trackingAccessProvider),
  );
});

/// Every bus the transport office has registered, live.
final registeredBusesProvider = StreamProvider<List<Bus>>(
  (ref) => ref.watch(busRepositoryProvider).watchBuses(),
);
