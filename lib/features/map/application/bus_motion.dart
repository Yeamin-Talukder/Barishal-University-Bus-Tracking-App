import '../../../core/utils/geo_math.dart';
import '../../../core/utils/route_geometry.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/geo_point.dart';

/// Where a bus marker is drawn at one instant.
class BusPose {
  const BusPose(this.position, this.headingDegrees, {this.trackBearingDegrees});

  final GeoPoint position;

  /// Direction of travel, clockwise from north, when one is known.
  final double? headingDegrees;

  /// The direction of the bus's route line at [position], from the route's
  /// start towards its end, when the marker is being drawn on that line.
  /// Null when the bus is drawn where it reported, away from its route.
  final double? trackBearingDegrees;
}

class _Glide {
  _Glide({
    required this.reported,
    required this.from,
    required this.to,
    required this.fromHeading,
    required this.toHeading,
    required this.start,
    required this.duration,
    required this.reportedAt,
    this.track,
    this.fromAlong = 0,
    this.toAlong = 0,
  });

  /// The position the bus reported, before it was placed on its route.
  final GeoPoint reported;
  final GeoPoint from;
  final GeoPoint to;
  final double? fromHeading;
  final double? toHeading;
  final DateTime start;
  final Duration duration;

  /// When the phone learned of [to].
  final DateTime reportedAt;

  /// The route line the marker travels along, with where on it the glide
  /// starts and ends. Null for a glide in a straight line.
  final RouteGeometry? track;
  final double fromAlong;
  final double toAlong;

  double _fraction(DateTime now) {
    final total = duration.inMilliseconds;
    return total <= 0
        ? 1.0
        : (now.difference(start).inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// How far along [track] the marker is at [now].
  double alongAt(DateTime now) =>
      fromAlong + (toAlong - fromAlong) * _fraction(now);

  BusPose at(DateTime now) {
    final fraction = _fraction(now);
    final line = track;
    if (line != null) {
      // Along the road, bends and all, not across the corner.
      final place = line.locate(alongAt(now));
      double? heading;
      if (toHeading != null) {
        heading = toAlong == fromAlong
            ? _heading(fraction)
            // While it moves the pointer follows the road it is on.
            : (toAlong > fromAlong
                  ? place.bearingDegrees
                  : (place.bearingDegrees + 180) % 360);
      }
      return BusPose(
        place.position,
        heading,
        trackBearingDegrees: place.bearingDegrees,
      );
    }
    return BusPose(
      GeoPoint(
        from.latitude + (to.latitude - from.latitude) * fraction,
        from.longitude + (to.longitude - from.longitude) * fraction,
      ),
      _heading(fraction),
    );
  }

  double? _heading(double fraction) {
    final a = fromHeading;
    final b = toHeading;
    if (b == null) return null;
    if (a == null) return b;
    // Turn the short way round: from 350 to 10 goes through north.
    final turn = ((b - a + 540) % 360) - 180;
    return (a + turn * fraction + 360) % 360;
  }

  bool isFinished(DateTime now) => !now.isBefore(start.add(duration));
}

/// Turns the positions a bus reports every few seconds into smooth movement
/// for its marker.
///
/// A new position does not move the marker at once. The marker glides from
/// where it is drawn to the new position, taking about as long as the gap
/// between the last two reports, so it keeps a steady pace instead of
/// jumping. It only ever travels between positions the bus really reported:
/// nothing is predicted ahead of the last report.
///
/// A bus that reports from on or beside its route is drawn on the route's
/// line and glides along it, round the bends. A bus that is clearly away
/// from its route is drawn exactly where it reported.
class BusMotionTracker {
  /// A glide never takes less or more than this, however reports arrive.
  static const Duration shortest = Duration(milliseconds: 800);
  static const Duration longest = Duration(seconds: 7);

  /// A jump longer than this is not a drive between two reports (the bus
  /// was out of contact, or a new trip started somewhere else), so the
  /// marker is placed at the new position without sweeping across the map.
  static const double snapBeyondMeters = 600;

  /// A bus within this distance of its route's line is drawn on the line.
  /// It covers the width of the road and ordinary GPS error; further away
  /// than this the bus really is somewhere else.
  static const double onRouteWithinMeters = 40;

  final Map<String, _Glide> _glides = {};

  /// Takes the latest reported positions. [headingOf] gives the direction
  /// to show for a bus, or null when it cannot be trusted. [trackOf] gives
  /// the line of the bus's route as drawn on the map, if it has one.
  void update(
    List<TrackedBus> buses,
    DateTime now, {
    required double? Function(TrackedBus bus) headingOf,
    RouteGeometry? Function(TrackedBus bus)? trackOf,
  }) {
    final seen = <String>{};
    for (final tracked in buses) {
      final location = tracked.location;
      if (location == null) continue;
      final id = tracked.bus.id;
      seen.add(id);
      final reported = location.position;
      final heading = headingOf(tracked);
      final current = _glides[id];

      // Where on its route's line the report falls, if it is near it.
      final track = trackOf?.call(tracked);
      final projection = track?.project(reported);
      final isOnTrack =
          projection != null &&
          projection.offRouteMeters <= onRouteWithinMeters;
      final toAlong = isOnTrack ? projection.distanceAlongMeters : 0.0;
      final target = isOnTrack ? track!.locate(toAlong).position : reported;

      _Glide standing() => _Glide(
        reported: reported,
        from: target,
        to: target,
        fromHeading: heading,
        toHeading: heading,
        start: now,
        duration: Duration.zero,
        reportedAt: now,
        track: isOnTrack ? track : null,
        fromAlong: toAlong,
        toAlong: toAlong,
      );

      if (current == null) {
        _glides[id] = standing();
        continue;
      }
      if (current.reported == reported) {
        // Same place reported again; only the direction may have changed.
        if (current.toHeading != heading && current.isFinished(now)) {
          _glides[id] = standing();
        }
        continue;
      }

      final shown = current.at(now);
      final jump = haversineDistanceMeters(
        shown.position.latitude,
        shown.position.longitude,
        target.latitude,
        target.longitude,
      );
      if (jump > snapBeyondMeters) {
        _glides[id] = standing();
        continue;
      }
      final gap = now.difference(current.reportedAt);
      final duration = gap < shortest
          ? shortest
          : (gap > longest ? longest : gap);

      if (isOnTrack) {
        final fromAlong = identical(current.track, track)
            ? current.alongAt(now)
            : track!.project(shown.position).distanceAlongMeters;
        // Where a route passes one place twice, the nearest point on the
        // line can jump to the other pass. A drive along the road is about
        // as long as the straight line between its ends; much longer means
        // such a jump, and the marker crosses in a straight line instead.
        final alongTheRoad = (toAlong - fromAlong).abs();
        if (alongTheRoad <= jump * 3 + 30) {
          _glides[id] = _Glide(
            reported: reported,
            from: shown.position,
            to: target,
            fromHeading: shown.headingDegrees,
            toHeading: heading,
            start: now,
            duration: duration,
            reportedAt: now,
            track: track,
            fromAlong: fromAlong,
            toAlong: toAlong,
          );
          continue;
        }
      }
      _glides[id] = _Glide(
        reported: reported,
        from: shown.position,
        to: target,
        fromHeading: shown.headingDegrees,
        toHeading: heading,
        start: now,
        duration: duration,
        reportedAt: now,
      );
    }
    _glides.removeWhere((id, _) => !seen.contains(id));
  }

  /// Where to draw the bus with [busId] at [now], or null if it has not
  /// reported a position.
  BusPose? poseOf(String busId, DateTime now) => _glides[busId]?.at(now);

  /// Whether any marker is still on its way to its latest position.
  bool isMoving(DateTime now) =>
      _glides.values.any((glide) => !glide.isFinished(now));
}
