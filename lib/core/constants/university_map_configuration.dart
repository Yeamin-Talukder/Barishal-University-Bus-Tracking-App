import 'dart:math' as math;

import '../utils/geo_math.dart';

/// Geographic rectangle in WGS84 degrees.
class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(double latitude, double longitude) =>
      latitude >= south &&
      latitude <= north &&
      longitude >= west &&
      longitude <= east;

  /// North-south and east-west extent in kilometres.
  ({double northSouth, double eastWest}) get sizeKm => (
    northSouth: (north - south) * metersPerDegreeLatitude / 1000,
    eastWest:
        (east - west) *
        metersPerDegreeLatitude *
        math.cos(degreesToRadians((north + south) / 2)) /
        1000,
  );
}

/// Names of the bundled MapLibre styles. The style JSON files themselves live
/// in `assets/map_styles/` and are resolved by the map layer, never by UI code.
enum UniversityMapStyle { light, dark }

/// The single source of truth for where the map opens and how far the offline
/// map reaches.
///
/// Nothing else in the app may hardcode the university's coordinates. A future
/// release can build this from trusted remote configuration through
/// [UniversityMapConfiguration.new]; [version] tells cached map data which
/// configuration it was prepared for.
class UniversityMapConfiguration {
  const UniversityMapConfiguration({
    required this.universityName,
    required this.universityNameBangla,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.coverage,
    required this.initialZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.defaultStyle,
    required this.version,
  });

  /// University of Barishal, Karnakathi, Barishal-8254, Bangladesh.
  static const UniversityMapConfiguration barishal = UniversityMapConfiguration(
    universityName: 'University of Barishal',
    universityNameBangla: 'বরিশাল বিশ্ববিদ্যালয়',
    centerLatitude: 22.659967,
    centerLongitude: 90.363381,
    // The outline of the band of map kept around the three bus routes
    // (1.5 km on every side). Inside this rectangle but away from a route
    // there is no detailed map. Must match tools/map/extract_basemap.py.
    coverage: GeoBounds(
      south: 22.643,
      west: 90.331,
      north: 22.727,
      east: 90.385,
    ),
    initialZoom: 14,
    // Zoomed all the way out, a phone shows the routes with about as much
    // again on every side, and no further (owner's request).
    minZoom: 11.5,
    maxZoom: 18,
    defaultStyle: UniversityMapStyle.light,
    version: 4,
  );

  final String universityName;
  final String universityNameBangla;
  final double centerLatitude;
  final double centerLongitude;

  /// The area the offline map covers: where the buses run.
  ///
  /// Until version 2 this was a 15 km circle around the university. The
  /// buses use a small part of that, so the map was cut down to the routes.
  final GeoBounds coverage;

  final double initialZoom;
  final double minZoom;
  final double maxZoom;
  final UniversityMapStyle defaultStyle;

  /// Bump when the centre, coverage or zoom range changes, so that downloaded
  /// map data prepared for an older configuration can be detected.
  final int version;

  /// The covered rectangle. The camera cannot leave it.
  GeoBounds get coverageBounds => coverage;

  /// Whether a point lies inside the area the offline map covers.
  bool isWithinCoverage(double latitude, double longitude) =>
      coverage.contains(latitude, longitude);
}
