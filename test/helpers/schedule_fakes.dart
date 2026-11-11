import 'dart:async';

import 'package:bu_bus_tracker/features/schedule/data/bus_schedule_repository.dart';
import 'package:bu_bus_tracker/features/schedule/domain/bus_schedule.dart';

/// An in-memory stand-in for the `timetables` collection.
class FakeTimetableRepository implements TimetableRepository {
  FakeTimetableRepository([List<RouteTimetable> initial = const []]) {
    for (final timetable in initial) {
      _put(timetable);
    }
  }

  final Map<String, RouteTimetable> timetables = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// When set, every change is refused with this, as the security rules
  /// would refuse someone who is not an admin.
  ScheduleWriteFailure? failWith;

  void _put(RouteTimetable timetable) {
    final id = timetable.id.isEmpty ? timetableIdFor(timetable) : timetable.id;
    timetables[id] = timetable.copyWith(id: id);
  }

  @override
  Stream<List<RouteTimetable>> watchTimetables() async* {
    yield timetables.values.toList();
    yield* _changes.stream.map((_) => timetables.values.toList());
  }

  @override
  Future<void> saveTimetable(RouteTimetable timetable) async {
    final failure = failWith;
    if (failure != null) throw failure;
    _put(timetable);
    _changes.add(null);
  }

  @override
  Future<void> saveAll(List<RouteTimetable> all) async {
    final failure = failWith;
    if (failure != null) throw failure;
    all.forEach(_put);
    _changes.add(null);
  }

  @override
  Future<void> deleteTimetable(String id) async {
    final failure = failWith;
    if (failure != null) throw failure;
    timetables.remove(id);
    _changes.add(null);
  }
}
