import '../../../data/models/bus.dart';
import '../../../data/models/bus_route.dart';
import '../../schedule/domain/bus_schedule.dart';

/// Which buses one home-screen widget shows. Every widget on the home
/// screen has its own.
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

/// One departure of the timetable as the widget knows it.
class WidgetDeparture {
  const WidgetDeparture({
    required this.route,
    required this.colorHex,
    required this.from,
    required this.to,
    required this.minutes,
    required this.vehicles,
    this.groupId = '',
    this.towardsCampus = false,
    this.fromCampus = false,
  });

  final String groupId;
  final String route;
  final String colorHex;
  final String from;
  final String to;

  /// Minutes after midnight.
  final int minutes;

  /// The buses as the timetable names them, for example "Chitra". This is
  /// how passengers find their bus among the ones standing side by side,
  /// so the widget puts it first. Empty when the timetable names none.
  final String vehicles;

  final bool towardsCampus;
  final bool fromCampus;

  bool matches(WidgetChoice choice) {
    if (groupId != choice.groupId) return false;
    if (choice.route != WidgetChoice.allRoutes && route != choice.route) {
      return false;
    }
    return switch (choice.direction) {
      WidgetDirection.both => true,
      WidgetDirection.toUniversity => towardsCampus,
      WidgetDirection.fromUniversity => fromCampus,
    };
  }

  /// The words that tell a passenger which bus to get on: its names, or
  /// the route when the timetable names no bus.
  String get headline => vehicles.isNotEmpty ? vehicles : 'Route $route';

  Map<String, Object> toJson() => {
    'g': groupId,
    'r': route,
    'c': colorHex,
    'from': from,
    'to': to,
    'm': minutes,
    'veh': vehicles,
    'tc': towardsCampus,
    'fc': fromCampus,
  };

  static WidgetDeparture fromJson(Map<String, Object?> json) => WidgetDeparture(
    groupId: json['g'] as String? ?? '',
    route: json['r'] as String? ?? '',
    colorHex: json['c'] as String? ?? '#5FD4BC',
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    minutes: (json['m'] as num?)?.toInt() ?? 0,
    vehicles: json['veh'] as String? ?? '',
    towardsCampus: json['tc'] as bool? ?? false,
    fromCampus: json['fc'] as bool? ?? false,
  );
}

bool _isCampus(String name) {
  final n = name.toLowerCase();
  return n.contains('university') ||
      n.contains('campus') ||
      name.contains('বিশ্ববিদ্যালয়');
}

const List<String> _palette = [
  '#F2994A',
  '#6FA8FF',
  '#B79CFF',
  '#FF8FA3',
  '#E6C24C',
  '#4FC3F7',
];

/// Everything every widget needs: the passenger groups and all their
/// departures. The app writes it to the phone; each widget picks its own
/// choice out of it, and the widget's settings screen reads it too. It is
/// the timetable the app is using, official when the transport office has
/// published one.
class WidgetTimetable {
  const WidgetTimetable({required this.groups, required this.departures});

  /// Passenger groups in the timetable's order, id to name.
  final Map<String, String> groups;

  /// Every departure of every group, in time order.
  final List<WidgetDeparture> departures;

  static const WidgetTimetable empty = WidgetTimetable(
    groups: {},
    departures: [],
  );

  bool get isEmpty => departures.isEmpty;

  factory WidgetTimetable.fromSchedule(
    BusSchedule schedule, {
    Map<String, String> routeColors = const {},
  }) {
    final result = <WidgetDeparture>[];
    final groups = <String, String>{
      for (final g in schedule.groups) g.id: g.name,
    };
    for (final group in schedule.groups) {
      final timetables = schedule.timetablesFor(group.id);
      for (final (index, timetable) in timetables.indexed) {
        final color =
            routeColors[timetable.routeNumber] ??
            _palette[index % _palette.length];
        final ends = [
          if (timetable.stops.isNotEmpty) timetable.stops.first.primary,
          if (timetable.stops.length > 1) timetable.stops.last.primary,
        ];
        for (final point in timetable.departures) {
          final from = point.from.primary;
          // The other end of the route; failing that, the other departure
          // place.
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
          for (final trip in point.trips) {
            result.add(
              WidgetDeparture(
                groupId: group.id,
                route: timetable.routeNumber,
                colorHex: color,
                from: from,
                to: to,
                minutes: trip.minutes,
                vehicles: trip.vehicles.primary,
                towardsCampus: _isCampus(to) && !_isCampus(from),
                fromCampus: _isCampus(from),
              ),
            );
          }
        }
      }
    }
    result.sort((a, b) => a.minutes.compareTo(b.minutes));
    return WidgetTimetable(groups: groups, departures: result);
  }

  /// The departures one widget shows, in time order.
  List<WidgetDeparture> departuresFor(WidgetChoice choice) => [
    for (final d in departures)
      if (d.matches(choice)) d,
  ];

  /// The route numbers of a group, in the timetable's order.
  List<String> routesFor(String groupId) {
    final seen = <String>{};
    return [
      for (final d in departures)
        if (d.groupId == groupId && seen.add(d.route)) d.route,
    ]..sort();
  }

  String colorOf(String route) => departures
      .firstWhere(
        (d) => d.route == route,
        orElse: () => const WidgetDeparture(
          route: '',
          colorHex: '#5FD4BC',
          from: '',
          to: '',
          minutes: 0,
          vehicles: '',
        ),
      )
      .colorHex;

  String titleFor(WidgetChoice choice) =>
      widgetTitle(choice, groupName: groups[choice.groupId]);

  Map<String, Object> toJson({
    required Map<String, int> liveByRoute,
    required DateTime now,
  }) => {
    'v': 2,
    'writtenAt': now.millisecondsSinceEpoch,
    'groups': [
      for (final e in groups.entries) {'id': e.key, 'name': e.value},
    ],
    'live': liveByRoute,
    'departures': [for (final d in departures) d.toJson()],
  };

  static WidgetTimetable fromJson(Map<String, Object?> json) {
    final groups = <String, String>{
      for (final g in (json['groups'] as List? ?? const []).cast<Map>())
        g['id'] as String: g['name'] as String? ?? '',
    };
    final departures = [
      for (final d in (json['departures'] as List? ?? const []).cast<Map>())
        WidgetDeparture.fromJson(d.cast<String, Object?>()),
    ]..sort((a, b) => a.minutes.compareTo(b.minutes));
    return WidgetTimetable(groups: groups, departures: departures);
  }
}

/// Every departure one widget shows, in time order.
List<WidgetDeparture> widgetDepartures(
  BusSchedule schedule,
  WidgetChoice choice, {
  Map<String, String> routeColors = const {},
}) => WidgetTimetable.fromSchedule(
  schedule,
  routeColors: routeColors,
).departuresFor(choice);

/// The title a widget shows above its buses.
String widgetTitle(WidgetChoice choice, {String? groupName}) {
  final group =
      groupName ??
      BusSchedule.standardGroups
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

/// One departure in a widget's list, and whether it is tomorrow's.
class UpcomingDeparture {
  const UpcomingDeparture(this.departure, {required this.tomorrow});
  final WidgetDeparture departure;
  final bool tomorrow;
}

/// Where the day stands for one widget: what to show next, and whether
/// the last bus of the day is near or gone.
///
/// The timetable does not say on which days it applies, so tomorrow's
/// buses are the same times again.
class WidgetDay {
  const WidgetDay({required this.upcoming, required this.leftToday});

  /// Today's departures still to come, then tomorrow's first ones to fill
  /// the list.
  final List<UpcomingDeparture> upcoming;

  /// How many of today's departures are still to come.
  final int leftToday;

  bool get isOverForToday => leftToday == 0 && upcoming.isNotEmpty;

  /// Today's last departure, while there still is one.
  WidgetDeparture? get lastToday =>
      leftToday == 0 ? null : upcoming[leftToday - 1].departure;

  /// What the next bus is: the only one left today, the first tomorrow,
  /// or simply the next one.
  String get nextLabel {
    if (isOverForToday) return 'No more buses today';
    if (leftToday == 1) return 'Last bus today';
    return 'Next bus';
  }

  static WidgetDay of(
    List<WidgetDeparture> departures,
    int nowMinutes, {
    int count = 4,
  }) {
    final today = [
      for (final d in departures)
        if (d.minutes >= nowMinutes) d,
    ];
    final upcoming = [
      for (final d in today.take(count)) UpcomingDeparture(d, tomorrow: false),
      for (final d in departures.take(count - today.take(count).length))
        UpcomingDeparture(d, tomorrow: true),
    ];
    return WidgetDay(upcoming: upcoming, leftToday: today.length);
  }
}

/// Buses with a live position now, counted by route number.
Map<String, int> liveCountsByRoute(
  List<TrackedBus> buses,
  bool Function(BusLocation? location) isLive,
) {
  final counts = <String, int>{};
  for (final b in buses) {
    final route = b.bus.routeId;
    if (route == null || !isLive(b.location)) continue;
    counts[route] = (counts[route] ?? 0) + 1;
  }
  return counts;
}

/// Live buses on the routes one widget shows.
int liveCountFor(Map<String, int> liveByRoute, WidgetChoice choice) =>
    choice.route == WidgetChoice.allRoutes
    ? liveByRoute.values.fold(0, (a, b) => a + b)
    : liveByRoute[choice.route] ?? 0;

/// Route colours by route number, from the routes on the map.
Map<String, String> routeColorsOf(List<BusRoute> routes) => {
  for (final r in routes) r.id: r.colorHex,
};
