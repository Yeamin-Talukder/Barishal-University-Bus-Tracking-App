import 'dart:math' as math;

/// Mean Earth radius in metres (IUGG).
const double earthRadiusMeters = 6371008.8;

/// Length of the equator in metres.
const double earthCircumferenceMeters = 40075016.686;

/// Length of one degree of latitude in metres, close enough for the small
/// area this app covers.
const double metersPerDegreeLatitude = 111320;

double degreesToRadians(double degrees) => degrees * math.pi / 180;

/// Great-circle distance in metres between two WGS84 points.
double haversineDistanceMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  final latitudeDelta = degreesToRadians(latitudeB - latitudeA);
  final longitudeDelta = degreesToRadians(longitudeB - longitudeA);
  final a =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(degreesToRadians(latitudeA)) *
          math.cos(degreesToRadians(latitudeB)) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(a));
}
