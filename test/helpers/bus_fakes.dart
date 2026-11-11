import 'dart:async';

import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/repositories/bus_repository.dart';

/// An in-memory stand-in for the `buses` collection.
class FakeBusRepository implements BusRepository {
  FakeBusRepository([List<Bus> initial = const []]) {
    for (final bus in initial) {
      buses[bus.id] = bus;
    }
  }

  final Map<String, Bus> buses = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  /// When set, every change is refused with this, as the security rules
  /// would refuse someone who is not an admin.
  BusWriteFailure? failWith;

  List<Bus> get _sorted => buses.values.toList()
    ..sort((a, b) => a.number.toLowerCase().compareTo(b.number.toLowerCase()));

  @override
  Stream<List<Bus>> watchBuses() async* {
    yield _sorted;
    yield* _changes.stream.map((_) => _sorted);
  }

  @override
  Future<String> saveBus(Bus bus) async {
    final failure = failWith;
    if (failure != null) throw failure;
    final id = bus.id.isEmpty ? 'bus-${_nextId++}' : bus.id;
    // Stored and read back, as the database would.
    buses[id] = busFromMap(id, busToMap(bus))!;
    _changes.add(null);
    return id;
  }

  @override
  Future<void> addAll(List<Bus> all) async {
    final failure = failWith;
    if (failure != null) throw failure;
    for (final bus in all) {
      final id = 'bus-${_nextId++}';
      buses[id] = busFromMap(id, busToMap(bus))!;
    }
    _changes.add(null);
  }

  @override
  Future<void> deleteBus(String id) async {
    final failure = failWith;
    if (failure != null) throw failure;
    buses.remove(id);
    _changes.add(null);
  }
}
