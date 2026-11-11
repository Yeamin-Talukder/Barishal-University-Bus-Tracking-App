import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_bootstrap.dart';
import '../domain/bus_schedule.dart';
import 'bus_schedule_parser.dart';

/// Source of the schedule that ships inside the app.
abstract interface class BusScheduleRepository {
  Future<BusSchedule> fetchSchedule();
}

/// Reads the schedule bundled with the app, so it works offline.
class AssetBusScheduleRepository implements BusScheduleRepository {
  AssetBusScheduleRepository({
    required this._bundle,
    this._parser = const BusScheduleParser(),
  });

  static const String asset = 'assets/data/schedule.json';

  final AssetBundle _bundle;
  final BusScheduleParser _parser;

  @override
  Future<BusSchedule> fetchSchedule() async =>
      _parser.parse(await _bundle.loadString(asset));
}

/// A change to the schedule that could not be made, with a message that can
/// be shown to the admin as it is.
class ScheduleWriteFailure implements Exception {
  const ScheduleWriteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The timetables the transport office keeps in the database.
///
/// Anyone may read them. Only an admin may change them: the database's
/// security rules refuse everyone else, whatever the app shows.
abstract interface class TimetableRepository {
  /// The timetables, and again whenever they change.
  Stream<List<RouteTimetable>> watchTimetables();

  /// Adds the timetable when its id is empty, otherwise replaces the one
  /// with that id. Throws [ScheduleWriteFailure].
  Future<void> saveTimetable(RouteTimetable timetable);

  /// Saves several timetables in one step: all of them, or none.
  Future<void> saveAll(List<RouteTimetable> timetables);

  /// Removes a route's timetable for good.
  Future<void> deleteTimetable(String id);
}

/// The id a timetable gets when it is first saved.
String timetableIdFor(RouteTimetable timetable) {
  final route = timetable.routeNumber.trim().toLowerCase().replaceAll(
    RegExp('[^a-z0-9]+'),
    '-',
  );
  return '${timetable.groupId}-$route';
}

/// Timetables in the `timetables` collection of Cloud Firestore, one
/// document per route and passenger group.
class FirestoreTimetableRepository implements TimetableRepository {
  FirestoreTimetableRepository(
    this._firestore, [
    this._parser = const BusScheduleParser(),
  ]);

  final FirebaseFirestore _firestore;
  final BusScheduleParser _parser;

  static const Duration _serverWait = Duration(seconds: 12);

  CollectionReference<Map<String, dynamic>> get _timetables =>
      _firestore.collection('timetables');

  @override
  Stream<List<RouteTimetable>> watchTimetables() =>
      _timetables.snapshots().map((snapshot) {
        final timetables = <RouteTimetable>[];
        for (final document in snapshot.docs) {
          final data = document.data();
          final updatedAt = data['updatedAt'];
          try {
            timetables.add(
              _parser.timetableFromMap(
                data,
                id: document.id,
                updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
              ),
            );
          } on FormatException catch (error) {
            // A damaged document is left out rather than shown wrongly.
            debugPrint('Skipped timetable ${document.id}: ${error.message}');
          }
        }
        return timetables;
      });

  Map<String, dynamic> _document(RouteTimetable timetable) => {
    ..._parser.timetableToMap(timetable),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<void> saveTimetable(RouteTimetable timetable) {
    final id = timetable.id.isEmpty ? timetableIdFor(timetable) : timetable.id;
    return _send(_timetables.doc(id).set(_document(timetable)));
  }

  @override
  Future<void> saveAll(List<RouteTimetable> timetables) {
    final batch = _firestore.batch();
    for (final timetable in timetables) {
      final id = timetable.id.isEmpty
          ? timetableIdFor(timetable)
          : timetable.id;
      batch.set(_timetables.doc(id), _document(timetable));
    }
    return _send(batch.commit());
  }

  @override
  Future<void> deleteTimetable(String id) =>
      _send(_timetables.doc(id).delete());

  Future<void> _send(Future<void> write) async {
    try {
      await write.timeout(_serverWait);
    } on TimeoutException {
      throw const ScheduleWriteFailure(
        'No answer from the server. The change is kept on this device and '
        'will be sent when the connection is back.',
      );
    } on FirebaseException catch (error) {
      debugPrint('Schedule change refused: ${error.code}');
      throw ScheduleWriteFailure(switch (error.code) {
        'permission-denied' =>
          'Only a transport office admin can change the schedule.',
        'unavailable' => 'No connection. Check the internet and try again.',
        _ => 'The change could not be saved. Try again.',
      });
    }
  }
}

/// Used when the app is not connected to the tracking service.
class UnavailableTimetableRepository implements TimetableRepository {
  const UnavailableTimetableRepository();

  static const ScheduleWriteFailure _failure = ScheduleWriteFailure(
    'This build is not connected to the tracking service.',
  );

  @override
  Stream<List<RouteTimetable>> watchTimetables() => Stream.value(const []);

  @override
  Future<void> saveTimetable(RouteTimetable timetable) => throw _failure;

  @override
  Future<void> saveAll(List<RouteTimetable> timetables) => throw _failure;

  @override
  Future<void> deleteTimetable(String id) => throw _failure;
}

final busScheduleRepositoryProvider = Provider<BusScheduleRepository>(
  (ref) => AssetBusScheduleRepository(bundle: rootBundle),
);

final timetableRepositoryProvider = Provider<TimetableRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableTimetableRepository();
  }
  return FirestoreTimetableRepository(FirebaseFirestore.instance);
});

/// The schedule that ships inside the app.
///
/// Not retried automatically: it is a file inside the app, so a failure to
/// read it will not fix itself. The screen offers "Try again".
final bundledScheduleProvider = FutureProvider<BusSchedule>(
  (ref) => ref.watch(busScheduleRepositoryProvider).fetchSchedule(),
  retry: (retryCount, error) => null,
);

/// The timetables the transport office keeps in the database, live.
final officialTimetablesProvider = StreamProvider<List<RouteTimetable>>(
  (ref) => ref.watch(timetableRepositoryProvider).watchTimetables(),
);

/// Puts timetables in the order passengers see them: by group, then by
/// route number.
List<RouteTimetable> sortTimetables(Iterable<RouteTimetable> timetables) {
  int groupIndex(String id) {
    final index = BusSchedule.standardGroups.indexWhere(
      (group) => group.id == id,
    );
    return index < 0 ? BusSchedule.standardGroups.length : index;
  }

  return timetables.toList()..sort((a, b) {
    final byGroup = groupIndex(a.groupId).compareTo(groupIndex(b.groupId));
    return byGroup != 0 ? byGroup : a.routeNumber.compareTo(b.routeNumber);
  });
}

/// The schedule passengers see.
///
/// Once the transport office has put timetables in the database, those are
/// the schedule, and the copy inside the app is no longer shown. Until
/// then, or with no connection on a first run, the bundled copy is shown.
final busScheduleProvider = FutureProvider<BusSchedule>((ref) async {
  final official = ref.watch(officialTimetablesProvider).value;
  final bundled = await ref.watch(bundledScheduleProvider.future);
  if (official == null || official.isEmpty) return bundled;

  DateTime? lastChanged;
  for (final timetable in official) {
    final changed = timetable.updatedAt;
    if (changed != null &&
        (lastChanged == null || changed.isAfter(lastChanged))) {
      lastChanged = changed;
    }
  }
  return BusSchedule(
    source: 'University of Barishal transport office',
    recordedOn: lastChanged,
    notes: const [],
    groups: BusSchedule.standardGroups,
    timetables: sortTimetables(official),
  );
}, retry: (retryCount, error) => null);
