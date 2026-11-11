import 'package:flutter/foundation.dart';

/// A piece of schedule text in Bangla, in English, or both.
///
/// In the schedule bundled with the app, [bn] is what the university wrote
/// and [en] is a transliteration added for display. An admin may fill in
/// either or both.
@immutable
class LocalizedText {
  const LocalizedText({this.bn = '', this.en = ''});

  final String bn;
  final String en;

  bool get isEmpty => bn.trim().isEmpty && en.trim().isEmpty;

  /// The text to show first: English when there is some, otherwise Bangla.
  String get primary => en.trim().isNotEmpty ? en.trim() : bn.trim();

  /// The Bangla text, when it adds something to [primary].
  String? get secondary {
    final bangla = bn.trim();
    return en.trim().isNotEmpty && bangla.isNotEmpty && bangla != en.trim()
        ? bangla
        : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LocalizedText && other.bn == bn && other.en == en;

  @override
  int get hashCode => Object.hash(bn, en);
}

/// One departure: a time of day and the vehicles named for it.
@immutable
class ScheduledTrip {
  const ScheduledTrip({required this.minutes, required this.vehicles});

  /// Minutes after midnight, local time.
  final int minutes;

  /// The vehicles as the schedule lists them, for example "Chitra, BRTC-05".
  final LocalizedText vehicles;
}

/// The departures from one place.
@immutable
class DeparturePoint {
  const DeparturePoint({required this.from, required this.trips});

  final LocalizedText from;
  final List<ScheduledTrip> trips;
}

/// The timetable of one route for one group of passengers.
@immutable
class RouteTimetable {
  const RouteTimetable({
    required this.groupId,
    required this.routeNumber,
    required this.stops,
    required this.departures,
    this.id = '',
    this.updatedAt,
  });

  /// Its document id in the database. Empty for a timetable that is bundled
  /// with the app or has not been saved yet.
  final String id;

  final String groupId;

  /// The route's number as the schedule writes it, for example "01".
  final String routeNumber;

  /// The stops in order. Empty when the schedule does not list them.
  final List<LocalizedText> stops;

  final List<DeparturePoint> departures;

  /// When the transport office last changed it. Null for bundled data.
  final DateTime? updatedAt;

  int get tripCount =>
      departures.fold(0, (count, point) => count + point.trips.length);

  RouteTimetable copyWith({
    String? id,
    String? groupId,
    String? routeNumber,
    List<LocalizedText>? stops,
    List<DeparturePoint>? departures,
  }) => RouteTimetable(
    id: id ?? this.id,
    groupId: groupId ?? this.groupId,
    routeNumber: routeNumber ?? this.routeNumber,
    stops: stops ?? this.stops,
    departures: departures ?? this.departures,
    updatedAt: updatedAt,
  );
}

/// Who a timetable is for: students, teachers or staff.
@immutable
class PassengerGroup {
  const PassengerGroup({required this.id, required this.name});

  final String id;
  final String name;
}

/// The university's official bus schedule.
@immutable
class BusSchedule {
  const BusSchedule({
    required this.source,
    required this.recordedOn,
    required this.notes,
    required this.groups,
    required this.timetables,
  });

  /// The groups every schedule has. The database's security rules accept
  /// timetables for these and no others.
  static const List<PassengerGroup> standardGroups = [
    PassengerGroup(id: 'student', name: 'Student'),
    PassengerGroup(id: 'teacher', name: 'Teacher'),
    PassengerGroup(id: 'staff', name: 'Staff'),
  ];

  /// Where the schedule came from.
  final String source;

  /// The day the schedule was recorded, or last changed.
  final DateTime? recordedOn;

  final List<String> notes;
  final List<PassengerGroup> groups;
  final List<RouteTimetable> timetables;

  bool get isEmpty => timetables.isEmpty;

  /// The timetables for one group, in the schedule's order.
  List<RouteTimetable> timetablesFor(String groupId) => [
    for (final timetable in timetables)
      if (timetable.groupId == groupId) timetable,
  ];
}
