import 'package:flutter/foundation.dart';

import '../../../core/services/eta_service.dart';
import '../../../core/utils/route_geometry.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/models/transport_network.dart';
import '../../schedule/domain/bus_schedule.dart';

/// What a prediction rests on. Neither is a live position.
enum PredictionBasis {
  /// Where the bus was last really seen, carried forward along its route.
  lastSeen,

  /// A departure in the timetable, carried forward along the route.
  timetable,
}

/// How fast buses have been found to cover each route in each direction.
///
/// Learned from live buses while there is a connection, kept on the device,
/// and used when there is none. A speed here is distance along the route
/// divided by the time taken, stops and traffic included, so it turns a
/// distance into a travel time directly.
@immutable
class TravelProfile {
  const TravelProfile({this.speeds = const {}, this.samples = const {}});

  /// Metres per second, by [keyOf].
  final Map<String, double> speeds;

  /// How many observed stretches each speed rests on.
  final Map<String, int> samples;

  /// Used for a route and direction nothing has been learned about yet:
  /// 20 km/h, a town bus with its stops. An assumption, replaced by real
  /// figures as soon as buses are seen.
  static const double defaultSpeedMetersPerSecond = 20 / 3.6;

  /// Observed speeds outside this range are a GPS fault or a bus standing
  /// in a depot, not travel, and are not learned from.
  static const double slowestMetersPerSecond = 5 / 3.6;
  static const double fastestMetersPerSecond = 70 / 3.6;

  /// How far one new observation moves a learned speed towards itself.
  static const double learningRate = 0.2;

  static String keyOf(String routeId, TravelDirection direction) =>
      '$routeId|${direction.name}';

  bool hasLearned(String routeId, TravelDirection direction) =>
      speeds.containsKey(keyOf(routeId, direction));

  double speedFor(String routeId, TravelDirection direction) =>
      speeds[keyOf(routeId, direction)] ?? defaultSpeedMetersPerSecond;

  /// Total observations behind the profile.
  int get sampleCount => samples.values.fold(0, (sum, count) => sum + count);

  /// The profile after seeing a bus cover a stretch at [metersPerSecond].
  /// The first observation is taken as it is; later ones nudge the figure.
  TravelProfile withSample(
    String routeId,
    TravelDirection direction,
    double metersPerSecond,
  ) {
    if (metersPerSecond < slowestMetersPerSecond ||
        metersPerSecond > fastestMetersPerSecond) {
      return this;
    }
    final key = keyOf(routeId, direction);
    final known = speeds[key];
    final learned = known == null
        ? metersPerSecond
        : known + (metersPerSecond - known) * learningRate;
    return TravelProfile(
      speeds: {...speeds, key: learned},
      samples: {...samples, key: (samples[key] ?? 0) + 1},
    );
  }

  Map<String, dynamic> toJson() => {'speeds': speeds, 'samples': samples};

  /// Reads a saved profile. Anything unreadable is left out.
  factory TravelProfile.fromJson(Object? json) {
    if (json is! Map) return const TravelProfile();
    final speeds = <String, double>{};
    final samples = <String, int>{};
    final savedSpeeds = json['speeds'];
    final savedSamples = json['samples'];
    if (savedSpeeds is Map) {
      for (final MapEntry(:key, :value) in savedSpeeds.entries) {
        if (key is String &&
            value is num &&
            value >= slowestMetersPerSecond &&
            value <= fastestMetersPerSecond) {
          speeds[key] = value.toDouble();
          final count = savedSamples is Map ? savedSamples[key] : null;
          samples[key] = count is int && count > 0 ? count : 1;
        }
      }
    }
    return TravelProfile(speeds: speeds, samples: samples);
  }
}

/// Where a real bus was when it was last seen live. Saved on the device so
/// that, with no connection, the app still knows where each bus was and
/// which way it was going.
@immutable
class LastSeenBus {
  const LastSeenBus({
    required this.busId,
    required this.number,
    required this.routeId,
    required this.alongMeters,
    required this.seenAt,
    this.direction,
  });

  final String busId;
  final String number;
  final String routeId;

  /// Distance from the start of the route, along it.
  final double alongMeters;
  final DateTime seenAt;

  /// Null when the bus was seen but its direction could not be told.
  final TravelDirection? direction;

  Map<String, dynamic> toJson() => {
    'busId': busId,
    'number': number,
    'routeId': routeId,
    'along': alongMeters,
    'seenAt': seenAt.millisecondsSinceEpoch,
    'direction': direction?.name,
  };

  static LastSeenBus? fromJson(Object? json) {
    if (json is! Map) return null;
    final busId = json['busId'];
    final number = json['number'];
    final routeId = json['routeId'];
    final along = json['along'];
    final seenAt = json['seenAt'];
    if (busId is! String ||
        number is! String ||
        routeId is! String ||
        along is! num ||
        seenAt is! int) {
      return null;
    }
    return LastSeenBus(
      busId: busId,
      number: number,
      routeId: routeId,
      alongMeters: along.toDouble(),
      seenAt: DateTime.fromMillisecondsSinceEpoch(seenAt),
      direction: TravelDirection.values
          .where((direction) => direction.name == json['direction'])
          .firstOrNull,
    );
  }
}

/// A real bus that is live right now, as far as predictions care: they are
/// never made for a bus, or a route and direction, that has live data.
@immutable
class LiveBusOnRoute {
  const LiveBusOnRoute({
    required this.busId,
    required this.routeId,
    this.direction,
  });

  final String busId;
  final String routeId;
  final TravelDirection? direction;
}

/// Where a bus is predicted to be. It is not a position anyone reported.
@immutable
class PredictedBus {
  const PredictedBus({
    required this.id,
    required this.label,
    required this.routeId,
    required this.routeName,
    required this.direction,
    required this.position,
    required this.lineBearingDegrees,
    required this.alongMeters,
    required this.basis,
    required this.basedOn,
    required this.fromName,
    required this.toName,
    required this.usesLearnedSpeed,
    this.vehicles,
    this.nextStopName,
    this.nextStopAt,
  });

  final String id;

  /// The bus's number when it is a bus that was seen; otherwise the route.
  final String label;
  final String routeId;
  final String routeName;
  final TravelDirection direction;
  final GeoPoint position;

  /// The direction of the route's line here, from its start to its end.
  final double lineBearingDegrees;
  final double alongMeters;
  final PredictionBasis basis;

  /// When the bus was last seen, or when the timetable says it left.
  final DateTime basedOn;
  final String fromName;
  final String toName;

  /// False while the default speed is being assumed for this route.
  final bool usesLearnedSpeed;

  /// The vehicles the timetable names for this departure, if any.
  final String? vehicles;
  final String? nextStopName;
  final DateTime? nextStopAt;

  /// The way the bus faces, clockwise from north.
  double get headingDegrees => direction == TravelDirection.forward
      ? lineBearingDegrees
      : (lineBearingDegrees + 180) % 360;
}

/// When a bus is predicted to reach a stop.
@immutable
class PredictedArrival {
  const PredictedArrival({
    required this.routeId,
    required this.routeName,
    required this.fromName,
    required this.toName,
    required this.at,
    required this.basis,
    this.label,
    this.vehicles,
  });

  final String routeId;
  final String routeName;
  final String fromName;
  final String toName;
  final DateTime at;
  final PredictionBasis basis;

  /// The bus's number, when the prediction is for a bus that was seen.
  final String? label;
  final String? vehicles;
}

/// One departure in the timetable, placed on a route of the map.
class _Run {
  _Run({
    required this.route,
    required this.direction,
    required this.departure,
    required this.vehicles,
  });

  final BusRoute route;
  final TravelDirection direction;
  final DateTime departure;
  final String vehicles;
}

/// Works out where buses probably are and when they will probably reach a
/// stop, from what is on the device: the timetable, the routes, the speeds
/// learned from real buses, and where each bus was last seen.
///
/// It needs no connection. It never produces a live position: everything
/// it returns is marked with its [PredictionBasis], and nothing is
/// predicted for a bus, or a route and direction, that has live data.
class PredictionEngine {
  const PredictionEngine({
    this.forgetLastSeenAfter = const Duration(minutes: 45),
    this.lingerAtEnd = const Duration(minutes: 2),
  });

  /// A bus not seen for this long is no longer predicted from where it was.
  final Duration forgetLastSeenAfter;

  /// How long a predicted bus stays shown at the end of its route.
  final Duration lingerAtEnd;

  /// Which way a bus leaving [fromName] travels along [route]: buses that
  /// set off from the route's end run backward along it.
  static TravelDirection directionFrom(BusRoute route, String fromName) {
    bool same(String a, String b) {
      final x = a.trim().toLowerCase();
      final y = b.trim().toLowerCase();
      return x.isNotEmpty && y.isNotEmpty && (x.contains(y) || y.contains(x));
    }

    if (same(fromName, route.endName)) return TravelDirection.backward;
    if (same(fromName, route.startName)) return TravelDirection.forward;
    // Every route ends at the university.
    return fromName.toLowerCase().contains('university')
        ? TravelDirection.backward
        : TravelDirection.forward;
  }

  static RouteGeometry? _geometry(BusRoute route) =>
      route.path.length < 2 ? null : RouteGeometry(route.path);

  /// The timetable's departures on [day] for routes that are on the map.
  List<_Run> _runs(
    BusSchedule? schedule,
    TransportNetwork network,
    DateTime day,
  ) {
    if (schedule == null) return const [];
    final seen = <String>{};
    final runs = <_Run>[];
    for (final timetable in schedule.timetables) {
      final route = network.routeById(timetable.routeNumber);
      if (route == null || route.path.length < 2) continue;
      for (final point in timetable.departures) {
        final direction = directionFrom(route, point.from.primary);
        for (final trip in point.trips) {
          // Two groups' timetables can name the same departure.
          if (!seen.add('${route.id}|${direction.name}|${trip.minutes}')) {
            continue;
          }
          runs.add(
            _Run(
              route: route,
              direction: direction,
              departure: DateTime(
                day.year,
                day.month,
                day.day,
              ).add(Duration(minutes: trip.minutes)),
              vehicles: trip.vehicles.primary,
            ),
          );
        }
      }
    }
    return runs;
  }

  static ({String from, String to}) _ends(
    BusRoute route,
    TravelDirection direction,
  ) => direction == TravelDirection.forward
      ? (from: route.startName, to: route.endName)
      : (from: route.endName, to: route.startName);

  /// The first stop still ahead of a bus [along] the route, and how far.
  static ({BusStop stop, double meters})? _nextStop(
    RouteGeometry geometry,
    List<BusStop> stops,
    double along,
    TravelDirection direction,
  ) {
    ({BusStop stop, double meters})? next;
    for (final stop in stops) {
      final stopAlong = geometry.project(stop.position).distanceAlongMeters;
      final ahead = direction == TravelDirection.forward
          ? stopAlong - along
          : along - stopAlong;
      if (ahead > 25 && (next == null || ahead < next.meters)) {
        next = (stop: stop, meters: ahead);
      }
    }
    return next;
  }

  PredictedBus _bus({
    required String id,
    required String label,
    required BusRoute route,
    required List<BusStop> stops,
    required RouteGeometry geometry,
    required TravelDirection direction,
    required double along,
    required double speed,
    required bool usesLearnedSpeed,
    required PredictionBasis basis,
    required DateTime basedOn,
    required DateTime now,
    String? vehicles,
  }) {
    final place = geometry.locate(along);
    final ends = _ends(route, direction);
    final next = _nextStop(geometry, stops, along, direction);
    return PredictedBus(
      id: id,
      label: label,
      routeId: route.id,
      routeName: route.name,
      direction: direction,
      position: place.position,
      lineBearingDegrees: place.bearingDegrees,
      alongMeters: along,
      basis: basis,
      basedOn: basedOn,
      fromName: ends.from,
      toName: ends.to,
      usesLearnedSpeed: usesLearnedSpeed,
      vehicles: vehicles,
      nextStopName: next?.stop.name,
      nextStopAt: next == null
          ? null
          : now.add(
              Duration(milliseconds: (next.meters / speed * 1000).round()),
            ),
    );
  }

  /// The buses that can be predicted at [now].
  ///
  /// A bus that was seen recently is carried forward from where it was. A
  /// departure in the timetable that should be on the road is shown too,
  /// unless a real or last-seen bus already covers that route and
  /// direction. Nothing is returned for anything in [live].
  List<PredictedBus> predictBuses({
    required TransportNetwork network,
    required BusSchedule? schedule,
    required TravelProfile profile,
    required List<LastSeenBus> lastSeen,
    required List<LiveBusOnRoute> live,
    required DateTime now,
  }) {
    final predicted = <PredictedBus>[];
    final liveIds = {for (final bus in live) bus.busId};
    // Route and direction pairs that already have a bus to show.
    final covered = <String>{
      for (final bus in live)
        if (bus.direction == null) ...[
          TravelProfile.keyOf(bus.routeId, TravelDirection.forward),
          TravelProfile.keyOf(bus.routeId, TravelDirection.backward),
        ] else
          TravelProfile.keyOf(bus.routeId, bus.direction!),
    };

    for (final seen in lastSeen) {
      final direction = seen.direction;
      final route = network.routeById(seen.routeId);
      final geometry = route == null ? null : _geometry(route);
      final age = now.difference(seen.seenAt);
      if (liveIds.contains(seen.busId) ||
          direction == null ||
          route == null ||
          geometry == null ||
          age.isNegative ||
          age > forgetLastSeenAfter) {
        continue;
      }
      final speed = profile.speedFor(route.id, direction);
      final travelled = speed * age.inMilliseconds / 1000;
      final length = geometry.lengthMeters;
      final raw = direction == TravelDirection.forward
          ? seen.alongMeters + travelled
          : seen.alongMeters - travelled;
      // Past the end of the route: it has arrived. Show it there for a
      // moment, then stop predicting, since what it does next is unknown.
      final overshoot = raw > length ? raw - length : (raw < 0 ? -raw : 0.0);
      if (overshoot / speed > lingerAtEnd.inSeconds) continue;

      predicted.add(
        _bus(
          id: 'seen-${seen.busId}',
          label: seen.number,
          route: route,
          stops: network.stopsOf(route),
          geometry: geometry,
          direction: direction,
          along: raw.clamp(0.0, length),
          speed: speed,
          usesLearnedSpeed: profile.hasLearned(route.id, direction),
          basis: PredictionBasis.lastSeen,
          basedOn: seen.seenAt,
          now: now,
        ),
      );
      covered.add(TravelProfile.keyOf(route.id, direction));
    }

    for (final run in _runs(schedule, network, now)) {
      final key = TravelProfile.keyOf(run.route.id, run.direction);
      final geometry = _geometry(run.route);
      final sinceDeparture = now.difference(run.departure);
      if (covered.contains(key) ||
          geometry == null ||
          sinceDeparture.isNegative) {
        continue;
      }
      final speed = profile.speedFor(run.route.id, run.direction);
      final length = geometry.lengthMeters;
      final travelled = speed * sinceDeparture.inMilliseconds / 1000;
      if ((travelled - length) / speed > lingerAtEnd.inSeconds) continue;
      final along = run.direction == TravelDirection.forward
          ? travelled.clamp(0.0, length)
          : (length - travelled).clamp(0.0, length);

      predicted.add(
        _bus(
          id:
              'timetable-${run.route.id}-${run.direction.name}-'
              '${run.departure.hour * 60 + run.departure.minute}',
          label: run.route.name,
          route: run.route,
          stops: network.stopsOf(run.route),
          geometry: geometry,
          direction: run.direction,
          along: along,
          speed: speed,
          usesLearnedSpeed: profile.hasLearned(run.route.id, run.direction),
          basis: PredictionBasis.timetable,
          basedOn: run.departure,
          now: now,
          vehicles: run.vehicles,
        ),
      );
      // One predicted bus for a route and direction is enough.
      covered.add(key);
    }
    return predicted;
  }

  /// When buses are predicted to reach [stop], soonest first.
  ///
  /// Counts buses last seen on their way to it and the timetable's
  /// departures, up to [within] ahead. A route and direction with a live
  /// bus is left to the live estimate.
  List<PredictedArrival> arrivalsAt({
    required BusStop stop,
    required TransportNetwork network,
    required BusSchedule? schedule,
    required TravelProfile profile,
    required List<LastSeenBus> lastSeen,
    required List<LiveBusOnRoute> live,
    required DateTime now,
    Duration within = const Duration(minutes: 90),
    int limit = 5,
  }) {
    final arrivals = <PredictedArrival>[];
    final liveIds = {for (final bus in live) bus.busId};
    // Route and direction pairs with a bus already on the road, live or
    // last seen: the timetable's departure that bus is running is theirs.
    final onTheRoad = <String>{
      for (final bus in live)
        if (bus.direction == null) ...[
          TravelProfile.keyOf(bus.routeId, TravelDirection.forward),
          TravelProfile.keyOf(bus.routeId, TravelDirection.backward),
        ] else
          TravelProfile.keyOf(bus.routeId, bus.direction!),
    };

    double? stopAlongOn(BusRoute route, RouteGeometry geometry) =>
        route.stopIds.contains(stop.id)
        ? geometry.project(stop.position).distanceAlongMeters
        : null;

    for (final seen in lastSeen) {
      final direction = seen.direction;
      final route = network.routeById(seen.routeId);
      final geometry = route == null ? null : _geometry(route);
      final age = now.difference(seen.seenAt);
      if (liveIds.contains(seen.busId) ||
          direction == null ||
          route == null ||
          geometry == null ||
          age.isNegative ||
          age > forgetLastSeenAfter) {
        continue;
      }
      final stopAlong = stopAlongOn(route, geometry);
      if (stopAlong == null) continue;
      final ahead = direction == TravelDirection.forward
          ? stopAlong - seen.alongMeters
          : seen.alongMeters - stopAlong;
      if (ahead < 0) continue;
      final speed = profile.speedFor(route.id, direction);
      final at = seen.seenAt.add(
        Duration(milliseconds: (ahead / speed * 1000).round()),
      );
      if (at.isBefore(now) || at.isAfter(now.add(within))) continue;
      onTheRoad.add(TravelProfile.keyOf(route.id, direction));
      final ends = _ends(route, direction);
      arrivals.add(
        PredictedArrival(
          routeId: route.id,
          routeName: route.name,
          fromName: ends.from,
          toName: ends.to,
          at: at,
          basis: PredictionBasis.lastSeen,
          label: seen.number,
        ),
      );
    }

    for (final run in _runs(schedule, network, now)) {
      final geometry = _geometry(run.route);
      if (geometry == null) continue;
      final stopAlong = stopAlongOn(run.route, geometry);
      if (stopAlong == null) continue;
      // A departure already on the road, where a bus is known on that
      // route and direction, is that bus: do not count it twice.
      if (!run.departure.isAfter(now) &&
          onTheRoad.contains(
            TravelProfile.keyOf(run.route.id, run.direction),
          )) {
        continue;
      }
      final fromOrigin = run.direction == TravelDirection.forward
          ? stopAlong
          : geometry.lengthMeters - stopAlong;
      final speed = profile.speedFor(run.route.id, run.direction);
      final at = run.departure.add(
        Duration(milliseconds: (fromOrigin / speed * 1000).round()),
      );
      if (at.isBefore(now) || at.isAfter(now.add(within))) continue;
      final ends = _ends(run.route, run.direction);
      arrivals.add(
        PredictedArrival(
          routeId: run.route.id,
          routeName: run.route.name,
          fromName: ends.from,
          toName: ends.to,
          at: at,
          basis: PredictionBasis.timetable,
          vehicles: run.vehicles,
        ),
      );
    }

    arrivals.sort((a, b) => a.at.compareTo(b.at));
    return arrivals.take(limit).toList();
  }
}
