import 'package:flutter/foundation.dart';

import '../../../core/services/eta_service.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/models/transport_network.dart';
import '../../prediction/domain/prediction.dart';
import '../../schedule/domain/bus_schedule.dart';

/// One departure of the timetable on a route of the map: when it leaves,
/// which way it goes, and the buses the timetable names for it.
///
/// This is what tells a passenger which bus to get on: the buses are known
/// by their names, and the timetable says which of them runs which route
/// at which time. Nothing here is a live position.
@immutable
class RouteDeparture {
  const RouteDeparture({
    required this.routeId,
    required this.routeName,
    required this.fromName,
    required this.toName,
    required this.reversed,
    required this.at,
    required this.buses,
  });

  final String routeId;
  final String routeName;

  /// Where it leaves from and where it goes, as the route names its ends.
  final String fromName;
  final String toName;

  /// Whether it runs from the route's end back to its start.
  final bool reversed;

  final DateTime at;

  /// The buses as the timetable writes them, for example "Chitra, BRTC-05".
  final String buses;
}

/// The timetable's departures on [route] on [day], in time order.
///
/// Two passenger groups' timetables can list the same departure; it is
/// given once, with every bus either of them names.
List<RouteDeparture> departuresOn({
  required BusSchedule schedule,
  required BusRoute route,
  required DateTime day,
}) {
  final midnight = DateTime(day.year, day.month, day.day);
  final found = <String, RouteDeparture>{};
  for (final timetable in schedule.timetables) {
    if (timetable.routeNumber != route.id) continue;
    for (final point in timetable.departures) {
      final reversed =
          PredictionEngine.directionFrom(route, point.from.primary) ==
          TravelDirection.backward;
      for (final trip in point.trips) {
        final buses = trip.vehicles.primary;
        if (buses.isEmpty) continue;
        final key = '$reversed|${trip.minutes}';
        final earlier = found[key];
        found[key] = RouteDeparture(
          routeId: route.id,
          routeName: route.name,
          fromName: reversed ? route.endName : route.startName,
          toName: reversed ? route.startName : route.endName,
          reversed: reversed,
          at: midnight.add(Duration(minutes: trip.minutes)),
          buses: earlier == null || earlier.buses == buses
              ? buses
              : '${earlier.buses}, $buses',
        );
      }
    }
  }
  return found.values.toList()..sort((a, b) => a.at.compareTo(b.at));
}

/// How long after its time a departure is still offered: the bus is often
/// still at the stand, taking passengers.
const Duration departureGrace = Duration(minutes: 2);

/// The next departures on [route], soonest first: today's that have not
/// left yet and, when today has too few left, tomorrow's first ones.
///
/// With [reversed] given, only departures going that way are returned.
/// The timetable does not say on which days it applies, so tomorrow's are
/// the same times again.
List<RouteDeparture> upcomingDepartures({
  required BusSchedule schedule,
  required BusRoute route,
  required DateTime now,
  bool? reversed,
  int count = 3,
}) {
  final upcoming = <RouteDeparture>[];
  for (final day in [now, now.add(const Duration(days: 1))]) {
    for (final departure in departuresOn(
      schedule: schedule,
      route: route,
      day: day,
    )) {
      if (reversed != null && departure.reversed != reversed) continue;
      if (departure.at.add(departureGrace).isBefore(now)) continue;
      upcoming.add(departure);
      if (upcoming.length == count) return upcoming;
    }
  }
  return upcoming;
}

/// The next departure of every route and direction that takes passengers
/// from [stop], soonest first. A direction that ends at the stop is left
/// out: nobody boards there.
List<RouteDeparture> upcomingDeparturesAt({
  required BusSchedule schedule,
  required TransportNetwork network,
  required BusStop stop,
  required DateTime now,
  int count = 4,
}) {
  final upcoming = <RouteDeparture>[];
  for (final route in network.routesServing(stop.id)) {
    final stops = network.stopsOf(route);
    if (stops.isEmpty) continue;
    for (final reversed in [false, true]) {
      final last = reversed ? stops.first : stops.last;
      if (last.id == stop.id) continue;
      upcoming.addAll(
        upcomingDepartures(
          schedule: schedule,
          route: route,
          now: now,
          reversed: reversed,
          count: 1,
        ),
      );
    }
  }
  upcoming.sort((a, b) => a.at.compareTo(b.at));
  return upcoming.take(count).toList();
}

/// How long until a departure, in words: "now", "in 12 min", "in 1 h 5 min"
/// or "tomorrow".
String departsInText(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (!at.isBefore(today.add(const Duration(days: 1)))) return 'tomorrow';
  final minutes = (at.difference(now).inSeconds / 60).ceil();
  if (minutes <= 0) return 'now';
  if (minutes < 60) return 'in $minutes min';
  final rest = minutes % 60;
  return rest == 0
      ? 'in ${minutes ~/ 60} h'
      : 'in ${minutes ~/ 60} h $rest min';
}
