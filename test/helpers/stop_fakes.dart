import 'dart:async';

import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/repositories/stop_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// An in-memory stand-in for the `stops` collection.
class FakeStopRepository implements StopRepository {
  FakeStopRepository([List<BusStop> initial = const []]) {
    for (final stop in initial) {
      stops[stop.id] = stop;
    }
  }

  final Map<String, BusStop> stops = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  /// When set, every change is refused with this, as the security rules
  /// would refuse someone who is not an admin.
  StopWriteFailure? failWith;

  List<BusStop> get _sorted =>
      stops.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Stream<List<BusStop>> watchStops() async* {
    yield _sorted;
    yield* _changes.stream.map((_) => _sorted);
  }

  @override
  Future<void> saveStop(BusStop stop) async {
    final failure = failWith;
    if (failure != null) throw failure;
    final id = stop.id.isEmpty ? 'stop-${_nextId++}' : stop.id;
    stops[id] = BusStop(
      id: id,
      name: stop.name,
      position: stop.position,
      description: stop.description,
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteStop(String id) async {
    final failure = failWith;
    if (failure != null) throw failure;
    stops.remove(id);
    _changes.add(null);
  }
}

/// Key of the widget that stands in for the position-picking map.
const Key fakePickerKey = Key('fake-picker');

/// Key of the control that pretends the admin moved the map.
const Key fakePickerMoveKey = Key('fake-picker-move');

/// Where the fake picker says the map was moved to.
const GeoPoint fakePickerMovedTo = GeoPoint(22.6905, 90.3601);

/// Stands in for the native map in the stop editor. Tapping it reports that
/// the map was moved to [fakePickerMovedTo].
class FakeStopPicker extends StatelessWidget {
  const FakeStopPicker({
    required this.initial,
    required this.onMoved,
    required this.moveTo,
    super.key,
  });

  final GeoPoint initial;
  final ValueChanged<GeoPoint> onMoved;
  final ValueListenable<GeoPoint?> moveTo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: fakePickerKey,
      color: Colors.grey,
      child: Align(
        alignment: Alignment.topLeft,
        child: TextButton(
          key: fakePickerMoveKey,
          onPressed: () => onMoved(fakePickerMovedTo),
          child: const Text('move'),
        ),
      ),
    );
  }
}
