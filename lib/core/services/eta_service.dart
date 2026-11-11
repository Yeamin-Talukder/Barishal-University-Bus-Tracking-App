import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/bus.dart';
import '../../data/models/bus_route.dart';
import '../../data/models/bus_stop.dart';
import '../../data/repositories/bus_location_repository.dart';
import '../constants/tracking_configuration.dart';
import '../utils/route_geometry.dart';

/// Which way a bus is travelling along its route's path.
enum TravelDirection {
  /// From the route's start towards its end.
  forward,

  /// From the route's end back towards its start.
  backward,
}

/// Why no arrival estimate can be given. An estimate is only shown when it
/// rests on a current position, a known direction and a trustworthy speed.
enum EtaUnavailableReason {
  noPosition,
  positionTooOld,
  offRoute,
  directionUnknown,
  busStopped,
  speedUnreliable,
  stopNotAhead,
  tooFarAway,
}

/// Limits used when estimating arrivals. Starting values, to be tuned with
/// real trips.
class EtaConfiguration {
  const EtaConfiguration({
    this.maxOffRouteMeters = 120,
    this.minDirectionMoveMeters = 15,
    this.maxHeadingDifferenceDegrees = 60,
    this.atStopWithinMeters = 25,
    this.maxEstimate = const Duration(minutes: 90),
  });

  /// A bus further than this from its route is treated as off it.
  final double maxOffRouteMeters;

  /// Two positions must be at least this far apart along the route before
  /// they are taken to show a direction.
  final double minDirectionMoveMeters;

  /// A heading within this angle of the road's direction counts as
  /// travelling along it.
  final double maxHeadingDifferenceDegrees;

  /// A bus this close to a stop is at it, so the next stop is the one after.
  final double atStopWithinMeters;

  /// Estimates longer than this are not shown.
  final Duration maxEstimate;
}

/// Where a bus is on its route.
@immutable
class RouteProgress {
  const RouteProgress({
    required this.distanceAlongMeters,
    required this.offRouteMeters,
    required this.isOnRoute,
    this.direction,
    this.nextStop,
    this.distanceToNextStopMeters,
  });

  final double distanceAlongMeters;
  final double offRouteMeters;
  final bool isOnRoute;

  /// Null when the direction cannot be told yet.
  final TravelDirection? direction;

  /// The next stop in the direction of travel, when both are known.
  final BusStop? nextStop;

  /// Distance to [nextStop] along the route.
  final double? distanceToNextStopMeters;
}

/// An arrival estimate, or the reason there is none.
sealed class ArrivalEstimate {
  const ArrivalEstimate();
}

/// An estimate from distance along the route and the bus's current speed.
/// It is an estimate, never a confirmed time.
class ArrivalEstimated extends ArrivalEstimate {
  const ArrivalEstimated({
    required this.travelTime,
    required this.arrivalTime,
    required this.distanceMeters,
  });

  final Duration travelTime;
  final DateTime arrivalTime;

  /// Distance still to drive, along the route.
  final double distanceMeters;
}

class ArrivalUnavailable extends ArrivalEstimate {
  const ArrivalUnavailable(this.reason);

  final EtaUnavailableReason reason;
}

/// Works out where a bus is on its route and estimates when it will reach a
/// stop.
///
/// The estimate is distance along the route divided by the bus's current
/// speed. Straight-line distance is never used. When any input cannot be
/// trusted the answer is "unavailable" with a reason, not a guess.
class EtaService {
  const EtaService({
    this.tracking = TrackingConfiguration.standard,
    this.configuration = const EtaConfiguration(),
  });

  final TrackingConfiguration tracking;
  final EtaConfiguration configuration;

  /// Where the bus is on [route].
  ///
  /// [stops] are the route's stops in travel order. [previous] is an earlier
  /// position of the same bus, if one is known; the direction is taken from
  /// the movement between the two, falling back to the GPS heading.
  RouteProgress progress({
    required BusRoute route,
    required List<BusStop> stops,
    required BusLocation location,
    BusLocation? previous,
  }) {
    final geometry = RouteGeometry(route.path);
    final projection = geometry.project(location.position);
    final isOnRoute =
        projection.offRouteMeters <= configuration.maxOffRouteMeters;
    final direction = isOnRoute
        ? _direction(geometry, projection, location, previous)
        : null;

    BusStop? nextStop;
    double? distanceToNext;
    if (direction != null) {
      final along = projection.distanceAlongMeters;
      for (final stop in _inTravelOrder(stops, direction)) {
        final ahead = _distanceAhead(
          from: along,
          to: geometry.project(stop.position).distanceAlongMeters,
          direction: direction,
        );
        if (ahead > configuration.atStopWithinMeters) {
          nextStop = stop;
          distanceToNext = ahead;
          break;
        }
      }
    }

    return RouteProgress(
      distanceAlongMeters: projection.distanceAlongMeters,
      offRouteMeters: projection.offRouteMeters,
      isOnRoute: isOnRoute,
      direction: direction,
      nextStop: nextStop,
      distanceToNextStopMeters: distanceToNext,
    );
  }

  /// Estimates when the bus will reach [stop].
  ArrivalEstimate estimateArrival({
    required BusRoute route,
    required List<BusStop> stops,
    required BusStop stop,
    required BusLocation? location,
    required DateTime now,
    BusLocation? previous,
  }) {
    if (location == null) {
      return const ArrivalUnavailable(EtaUnavailableReason.noPosition);
    }
    // An estimate from an old position would be an estimate of the past.
    if (tracking.statusOf(location.updatedAt, now) != BusTrackingStatus.live) {
      return const ArrivalUnavailable(EtaUnavailableReason.positionTooOld);
    }

    final geometry = RouteGeometry(route.path);
    final projection = geometry.project(location.position);
    if (projection.offRouteMeters > configuration.maxOffRouteMeters) {
      return const ArrivalUnavailable(EtaUnavailableReason.offRoute);
    }
    final direction = _direction(geometry, projection, location, previous);
    if (direction == null) {
      return const ArrivalUnavailable(EtaUnavailableReason.directionUnknown);
    }

    final speed = location.speedMetersPerSecond;
    if (speed == null || !tracking.hasReliableMotion(location)) {
      final isStopped =
          speed != null && speed < tracking.minMovingSpeedMetersPerSecond;
      return ArrivalUnavailable(
        isStopped
            ? EtaUnavailableReason.busStopped
            : EtaUnavailableReason.speedUnreliable,
      );
    }

    final distance = _distanceAhead(
      from: projection.distanceAlongMeters,
      to: geometry.project(stop.position).distanceAlongMeters,
      direction: direction,
    );
    if (distance < 0) {
      return const ArrivalUnavailable(EtaUnavailableReason.stopNotAhead);
    }

    final travelTime = Duration(seconds: (distance / speed).round());
    if (travelTime > configuration.maxEstimate) {
      return const ArrivalUnavailable(EtaUnavailableReason.tooFarAway);
    }
    return ArrivalEstimated(
      travelTime: travelTime,
      arrivalTime: now.add(travelTime),
      distanceMeters: distance,
    );
  }

  /// Estimates when the bus will reach its next stop, and says which stop
  /// that is.
  ({BusStop? nextStop, ArrivalEstimate estimate}) estimateNextStop({
    required BusRoute route,
    required List<BusStop> stops,
    required BusLocation? location,
    required DateTime now,
    BusLocation? previous,
  }) {
    if (location == null) {
      return (
        nextStop: null,
        estimate: const ArrivalUnavailable(EtaUnavailableReason.noPosition),
      );
    }
    // Where an out-of-date position was heading says nothing about now.
    if (tracking.statusOf(location.updatedAt, now) != BusTrackingStatus.live) {
      return (
        nextStop: null,
        estimate: const ArrivalUnavailable(EtaUnavailableReason.positionTooOld),
      );
    }
    final nextStop = progress(
      route: route,
      stops: stops,
      location: location,
      previous: previous,
    ).nextStop;
    if (nextStop == null) {
      // Let estimateArrival name the reason, using any stop of the route.
      final reason = stops.isEmpty
          ? const ArrivalUnavailable(EtaUnavailableReason.stopNotAhead)
          : estimateArrival(
              route: route,
              stops: stops,
              stop: stops.first,
              location: location,
              now: now,
              previous: previous,
            );
      return (
        nextStop: null,
        estimate: reason is ArrivalUnavailable
            ? reason
            : const ArrivalUnavailable(EtaUnavailableReason.stopNotAhead),
      );
    }
    return (
      nextStop: nextStop,
      estimate: estimateArrival(
        route: route,
        stops: stops,
        stop: nextStop,
        location: location,
        now: now,
        previous: previous,
      ),
    );
  }

  TravelDirection? _direction(
    RouteGeometry geometry,
    RouteProjection projection,
    BusLocation location,
    BusLocation? previous,
  ) {
    // Movement between two positions is the most direct evidence.
    if (previous != null) {
      final before = geometry.project(previous.position);
      final moved = projection.distanceAlongMeters - before.distanceAlongMeters;
      if (before.offRouteMeters <= configuration.maxOffRouteMeters &&
          moved.abs() >= configuration.minDirectionMoveMeters) {
        return moved > 0 ? TravelDirection.forward : TravelDirection.backward;
      }
    }

    // Otherwise the GPS heading, but only from a good fix on a moving bus.
    final heading = location.headingDegrees;
    if (heading == null || !tracking.hasReliableMotion(location)) return null;
    final difference = bearingDifferenceDegrees(
      heading,
      projection.segmentBearingDegrees,
    );
    if (difference <= configuration.maxHeadingDifferenceDegrees) {
      return TravelDirection.forward;
    }
    if (difference >= 180 - configuration.maxHeadingDifferenceDegrees) {
      return TravelDirection.backward;
    }
    // Roughly across the road: turning, or not really on this route.
    return null;
  }

  Iterable<BusStop> _inTravelOrder(
    List<BusStop> stops,
    TravelDirection direction,
  ) => direction == TravelDirection.forward ? stops : stops.reversed;

  /// Distance from [from] to [to] along the route in the direction of
  /// travel. Negative when [to] is behind.
  double _distanceAhead({
    required double from,
    required double to,
    required TravelDirection direction,
  }) => direction == TravelDirection.forward ? to - from : from - to;
}

final etaServiceProvider = Provider<EtaService>(
  (ref) => EtaService(tracking: ref.watch(trackingConfigurationProvider)),
);
