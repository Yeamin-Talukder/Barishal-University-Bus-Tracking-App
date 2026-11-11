import 'dart:math' as math;

import '../../data/models/geo_point.dart';
import 'geo_math.dart';

/// Where a point falls on a route.
class RouteProjection {
  const RouteProjection({
    required this.distanceAlongMeters,
    required this.offRouteMeters,
    required this.segmentBearingDegrees,
  });

  /// Distance from the start of the route to the nearest point on it,
  /// measured along the route.
  final double distanceAlongMeters;

  /// How far the point is from the route.
  final double offRouteMeters;

  /// Direction of the route at that place, clockwise from north, when
  /// travelling from its start to its end.
  final double segmentBearingDegrees;
}

/// A route's path measured along its length.
///
/// Distances are along the road the bus drives, not straight lines, which is
/// what arrival estimates need.
class RouteGeometry {
  RouteGeometry(this.path)
    : assert(path.length >= 2, 'A route needs at least two points.') {
    var total = 0.0;
    _cumulative.add(0);
    for (var i = 1; i < path.length; i++) {
      total += haversineDistanceMeters(
        path[i - 1].latitude,
        path[i - 1].longitude,
        path[i].latitude,
        path[i].longitude,
      );
      _cumulative.add(total);
    }
  }

  final List<GeoPoint> path;

  /// Distance from the start to each point of [path].
  final List<double> _cumulative = [];

  double get lengthMeters => _cumulative.last;

  /// The place [distanceAlongMeters] from the start, measured along the
  /// route, and the route's direction there (clockwise from north, when
  /// travelling from its start to its end). A distance before the start or
  /// past the end gives that end.
  ({GeoPoint position, double bearingDegrees}) locate(
    double distanceAlongMeters,
  ) {
    final along = distanceAlongMeters.clamp(0.0, lengthMeters);
    // The last stretch that starts at or before that distance.
    var low = 0;
    var high = path.length - 2;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_cumulative[middle] <= along) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    var segment = low;
    // A stretch of no length has no direction: use the next real one.
    while (segment < path.length - 2 &&
        _cumulative[segment + 1] <= _cumulative[segment]) {
      segment++;
    }
    final from = path[segment];
    final to = path[segment + 1];
    final length = _cumulative[segment + 1] - _cumulative[segment];
    final fraction = length <= 0
        ? 0.0
        : ((along - _cumulative[segment]) / length).clamp(0.0, 1.0);
    return (
      position: GeoPoint(
        from.latitude + (to.latitude - from.latitude) * fraction,
        from.longitude + (to.longitude - from.longitude) * fraction,
      ),
      bearingDegrees: bearingDegrees(from, to),
    );
  }

  /// The part of the route between two distances from its start, as points
  /// in order from the smaller distance to the larger. Both ends are placed
  /// exactly, so the part can start or stop in the middle of a stretch.
  /// Empty when the two distances are the same place.
  List<GeoPoint> slice(double fromMeters, double toMeters) {
    final from = fromMeters.clamp(0.0, lengthMeters);
    final to = toMeters.clamp(0.0, lengthMeters);
    final low = math.min(from, to);
    final high = math.max(from, to);
    if (high - low < 0.01) return const [];
    return [
      locate(low).position,
      for (var i = 0; i < path.length; i++)
        if (_cumulative[i] > low && _cumulative[i] < high) path[i],
      locate(high).position,
    ];
  }

  /// Finds the place on the route nearest to [point].
  ///
  /// Where a route passes the same place twice (a loop, or out and back
  /// along one road), the first of equally near places is returned.
  RouteProjection project(GeoPoint point) {
    var best = double.infinity;
    var bestAlong = 0.0;
    var bestSegment = 0;

    // Metres per degree at this latitude; the area is small enough to treat
    // as flat.
    final metersPerDegreeLongitude =
        metersPerDegreeLatitude * math.cos(degreesToRadians(point.latitude));

    for (var i = 0; i < path.length - 1; i++) {
      final start = path[i];
      final end = path[i + 1];
      final segmentX =
          (end.longitude - start.longitude) * metersPerDegreeLongitude;
      final segmentY =
          (end.latitude - start.latitude) * metersPerDegreeLatitude;
      final pointX =
          (point.longitude - start.longitude) * metersPerDegreeLongitude;
      final pointY =
          (point.latitude - start.latitude) * metersPerDegreeLatitude;

      final lengthSquared = segmentX * segmentX + segmentY * segmentY;
      final fraction = lengthSquared == 0
          ? 0.0
          : ((pointX * segmentX + pointY * segmentY) / lengthSquared).clamp(
              0.0,
              1.0,
            );
      final offsetX = pointX - segmentX * fraction;
      final offsetY = pointY - segmentY * fraction;
      final distance = math.sqrt(offsetX * offsetX + offsetY * offsetY);

      if (distance < best) {
        best = distance;
        bestSegment = i;
        bestAlong =
            _cumulative[i] + (_cumulative[i + 1] - _cumulative[i]) * fraction;
      }
    }

    return RouteProjection(
      distanceAlongMeters: bestAlong,
      offRouteMeters: best,
      segmentBearingDegrees: bearingDegrees(
        path[bestSegment],
        path[bestSegment + 1],
      ),
    );
  }
}

/// Initial compass bearing from [from] to [to], clockwise from north, in the
/// range 0 to 360.
double bearingDegrees(GeoPoint from, GeoPoint to) {
  final latitudeFrom = degreesToRadians(from.latitude);
  final latitudeTo = degreesToRadians(to.latitude);
  final longitudeDelta = degreesToRadians(to.longitude - from.longitude);
  final y = math.sin(longitudeDelta) * math.cos(latitudeTo);
  final x =
      math.cos(latitudeFrom) * math.sin(latitudeTo) -
      math.sin(latitudeFrom) * math.cos(latitudeTo) * math.cos(longitudeDelta);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// The smaller angle between two compass bearings, from 0 to 180.
double bearingDifferenceDegrees(double a, double b) {
  final difference = (a - b).abs() % 360;
  return difference > 180 ? 360 - difference : difference;
}
