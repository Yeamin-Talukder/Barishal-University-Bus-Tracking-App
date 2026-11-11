import 'dart:convert';

import '../domain/bus_schedule.dart';

/// Reads the schedule file (`assets/data/schedule.json`, written by
/// `tools/data/build_schedule.py`).
///
/// The file is official data, so nothing is guessed or repaired: anything
/// malformed throws a [FormatException] naming what is wrong.
class BusScheduleParser {
  const BusScheduleParser();

  BusSchedule parse(String source) {
    final Object? root;
    try {
      root = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('The schedule is not valid JSON: ${error.message}');
    }
    final map = _map(root, 'the schedule');

    final groups = [
      for (final item in _list(map['groups'], 'groups'))
        _group(_map(item, 'a group')),
    ];
    final groupIds = {for (final group in groups) group.id};

    final timetables = <RouteTimetable>[];
    for (final item in _list(map['timetables'], 'timetables')) {
      final timetable = timetableFromMap(_map(item, 'a timetable'));
      if (!groupIds.contains(timetable.groupId)) {
        throw FormatException(
          'Route ${timetable.routeNumber} is for the unknown group '
          '"${timetable.groupId}".',
        );
      }
      timetables.add(timetable);
    }

    final recordedOn = map['recordedOn'];
    return BusSchedule(
      source: map['source'] is String ? map['source'] as String : '',
      recordedOn: recordedOn is String ? DateTime.tryParse(recordedOn) : null,
      notes: [
        for (final note in (map['notes'] as List<dynamic>? ?? const []))
          if (note is String) note,
      ],
      groups: groups,
      timetables: timetables,
    );
  }

  PassengerGroup _group(Map<String, dynamic> map) => PassengerGroup(
    id: _text(map['id'], 'a group id'),
    name: _text(map['name'], 'a group name'),
  );

  /// Reads one route's timetable, from the schedule file or from a database
  /// document (both use the same shape).
  RouteTimetable timetableFromMap(
    Map<String, dynamic> map, {
    String id = '',
    DateTime? updatedAt,
  }) {
    final route = _text(map['route'], 'a route number');
    final departures = [
      for (final item in _list(map['departures'], 'departures of route $route'))
        _departure(_map(item, 'a departure place of route $route'), route),
    ];
    if (departures.isEmpty) {
      throw FormatException('Route $route has no departures.');
    }
    return RouteTimetable(
      id: id,
      updatedAt: updatedAt,
      groupId: _text(map['group'], 'the group of route $route'),
      routeNumber: route,
      stops: [
        for (final stop in _list(map['stops'], 'stops of route $route'))
          _localized(stop, 'a stop of route $route'),
      ],
      departures: departures,
    );
  }

  DeparturePoint _departure(Map<String, dynamic> map, String route) {
    final trips = [
      for (final item in _list(map['trips'], 'trips of route $route'))
        _trip(_map(item, 'a trip of route $route'), route),
    ];
    if (trips.isEmpty) {
      throw FormatException('A departure place of route $route has no trips.');
    }
    return DeparturePoint(
      from: _localized(map['from'], 'a departure place of route $route'),
      trips: trips,
    );
  }

  ScheduledTrip _trip(Map<String, dynamic> map, String route) => ScheduledTrip(
    minutes: _minutes(map['time'], route),
    vehicles: _localized(map['vehicles'], 'the vehicles of route $route'),
  );

  /// Reads "HH:mm" (24-hour) as minutes after midnight.
  int _minutes(Object? value, String route) {
    final match = value is String
        ? RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value)
        : null;
    final hour = match == null ? -1 : int.parse(match[1]!);
    final minute = match == null ? -1 : int.parse(match[2]!);
    if (hour < 0 || hour > 23 || minute > 59) {
      throw FormatException('Route $route has the invalid time "$value".');
    }
    return hour * 60 + minute;
  }

  /// Bangla, English or both. At least one of them must say something.
  LocalizedText _localized(Object? value, String what) {
    final map = _map(value, what);
    final bn = map['bn'];
    final en = map['en'];
    final text = LocalizedText(
      bn: bn is String ? bn.trim() : '',
      en: en is String ? en.trim() : '',
    );
    if (text.isEmpty) throw FormatException('Expected $what to have text.');
    return text;
  }

  /// The stored form of a timetable: what [timetableFromMap] reads.
  Map<String, dynamic> timetableToMap(RouteTimetable timetable) {
    Map<String, dynamic> text(LocalizedText value) => {
      'bn': value.bn.trim(),
      'en': value.en.trim(),
    };
    String time(int minutes) =>
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';

    return {
      'group': timetable.groupId,
      'route': timetable.routeNumber.trim(),
      'stops': [for (final stop in timetable.stops) text(stop)],
      'departures': [
        for (final point in timetable.departures)
          {
            'from': text(point.from),
            'trips': [
              for (final trip in point.trips)
                {'time': time(trip.minutes), 'vehicles': text(trip.vehicles)},
            ],
          },
      ],
    };
  }

  Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    // A database document's inner maps are not always typed by key.
    if (value is Map && value.keys.every((key) => key is String)) {
      return Map<String, dynamic>.from(value);
    }
    throw FormatException('Expected $what to be an object.');
  }

  List<dynamic> _list(Object? value, String what) {
    if (value is List<dynamic>) return value;
    throw FormatException('Expected $what to be a list.');
  }

  String _text(Object? value, String what) {
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Expected $what to be text.');
  }
}
