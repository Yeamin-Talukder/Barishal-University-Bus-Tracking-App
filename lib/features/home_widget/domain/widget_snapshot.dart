import '../../../data/models/bus.dart';
import '../../../data/models/bus_route.dart';
import '../../schedule/domain/bus_schedule.dart';

/// Which buses the home-screen widget shows.
class WidgetChoice {
  const WidgetChoice({
    this.groupId = 'student',
    this.route = allRoutes,
    this.direction = WidgetDirection.both,
  });

  static const String allRoutes = 'all';

  final String groupId;

  /// A route number such as "01", or [allRoutes].
  final String route;
  final WidgetDirection direction;

  WidgetChoice copyWith({
    String? groupId,
    String? route,
    WidgetDirection? direction,
  }) => WidgetChoice(
    groupId: groupId ?? this.groupId,
    route: route ?? this.route,
    direction: direction ?? this.direction,
  );

  Map<String, Object> toJson() => {
    'group': groupId,
    'route': route,
    'direction': direction.name,
  };

  static WidgetChoice fromJson(Map<String, Object?> json) => WidgetChoice(
    groupId: json['group'] as String? ?? 'student',
    route: json['route'] as String? ?? allRoutes,
    direction: WidgetDirection.values.firstWhere(
      (d) => d.name == json['direction'],
      orElse: () => WidgetDirection.both,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is WidgetChoice &&
      other.groupId == groupId &&
      other.route == route &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(groupId, route, direction);
}

enum WidgetDirection {
  both('Both ways'),
  toUniversity('To campus'),
  fromUniversity('From campus');

  const WidgetDirection(this.label);
  final String label;
}

/// One departure as the widget shows it.
class WidgetDeparture {
  const WidgetDeparture({
    required this.route,
    required this.colorHex,
    required this.from,
    required this.to,
    required this.minutes,
    required this.vehicles,
  });

  final String route;
  final String colorHex;
  final String from;
  final String to;

  /// Minutes after midnight.
  final int minutes;
  final String vehicles;

  Map<String, Object> toJson() => {
    'r': route,
    'c': colorHex,
    'from': from,
    'to': to,
    'm': minutes,
    'veh': vehicles,
  };
}

bool _isCampus(String name) {
  final n = name.toLowerCase();
  return n.contains('university') ||
      n.contains('campus') ||
      name.contains('বিশ্ববিদ্যালয়');
}

/// Every departure the widget should know about, in time order. The widget
/// itself picks the ones still to come, so it stays right as the day goes
/// on without the app running.
List<WidgetDeparture> widgetDepartures(
  BusSchedule schedule,
  WidgetChoice choice, {
  Map<String, String> routeColors = const {},
  List<String> palette = const [
    '#F2994A',
    '#6FA8FF',
    '#B79CFF',
    '#FF8FA3',
    '#E6C24C',
    '#4FC3F7',
  ],
}) {
  final result = <WidgetDeparture>[];
  final timetables = schedule.timetablesFor(choice.groupId);
  for (final (index, timetable) in timetables.indexed) {
    if (choice.route != WidgetChoice.allRoutes &&
        timetable.routeNumber != choice.route) {
      continue;
    }
    final color =
        routeColors[timetable.routeNumber] ?? palette[index % palette.length];
    final ends = [
      if (timetable.stops.isNotEmpty) timetable.stops.first.primary,
      if (timetable.stops.length > 1) timetable.stops.last.primary,
    ];
    for (final point in timetable.departures) {
      final from = point.from.primary;
      // The other end of the route; failing that, the other departure place.
      var to = '';
      if (ends.length == 2) {
        to = ends.first == from
            ? ends.last
            : (ends.last == from ? ends.first : ends.last);
      }
      if (to.isEmpty || to == from) {
        to = timetable.departures
            .map((p) => p.from.primary)
            .firstWhere((p) => p != from, orElse: () => '');
      }
      final towardsCampus = _isCampus(to) && !_isCampus(from);
      if (choice.direction == WidgetDirection.toUniversity && !towardsCampus) {
        continue;
      }
      if (choice.direction == WidgetDirection.fromUniversity &&
          !_isCampus(from)) {
        continue;
      }
      for (final trip in point.trips) {
        result.add(
          WidgetDeparture(
            route: timetable.routeNumber,
            colorHex: color,
            from: from,
            to: to,
            minutes: trip.minutes,
            vehicles: trip.vehicles.primary,
          ),
        );
      }
    }
  }
  result.sort((a, b) => a.minutes.compareTo(b.minutes));
  return result;
}

/// The title the widget shows above the buses.
String widgetTitle(WidgetChoice choice) {
  final group = BusSchedule.standardGroups
      .firstWhere(
        (g) => g.id == choice.groupId,
        orElse: () => const PassengerGroup(id: '', name: 'Bus'),
      )
      .name;
  final route = choice.route == WidgetChoice.allRoutes
      ? 'All routes'
      : 'Route ${choice.route}';
  return '$group · $route';
}

/// Everything the widget reads, as JSON. [live] counts the buses on the
/// chosen routes sharing a live position when the app last looked.
Map<String, Object> widgetSnapshot({
  required WidgetChoice choice,
  required List<WidgetDeparture> departures,
  required int live,
  required DateTime now,
}) => {
  'v': 1,
  'title': widgetTitle(choice),
  'subtitle': choice.direction.label,
  'writtenAt': now.millisecondsSinceEpoch,
  'live': live,
  'departures': [for (final d in departures) d.toJson()],
};

/// Buses on the chosen routes with a live position now.
int liveBusCount(
  List<TrackedBus> buses,
  WidgetChoice choice,
  bool Function(BusLocation? location) isLive,
) => buses.where((b) {
  if (!isLive(b.location)) return false;
  if (choice.route == WidgetChoice.allRoutes) return true;
  return b.bus.routeId == choice.route;
}).length;

/// Route colours by route number, from the routes on the map.
Map<String, String> routeColorsOf(List<BusRoute> routes) => {
  for (final r in routes) r.id: r.colorHex,
};
