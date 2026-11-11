import 'package:bu_bus_tracker/core/constants/university_map_configuration.dart';
import 'package:bu_bus_tracker/core/utils/geo_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = UniversityMapConfiguration.barishal;

  group('UniversityMapConfiguration.barishal', () {
    test('is centred on the University of Barishal', () {
      expect(config.centerLatitude, 22.659967);
      expect(config.centerLongitude, 90.363381);
      expect(config.universityName, 'University of Barishal');
    });

    test('shows zoom 11.5 to 18, opening at 14', () {
      // Fully zoomed out, the routes fill about a third of the screen each
      // way: the map and the same again around it, not the whole district.
      expect(config.minZoom, 11.5);
      expect(config.initialZoom, 14);
      expect(config.maxZoom, 18);
    });

    test('covers the bus routes, not a wide circle', () {
      final bounds = config.coverageBounds;
      final size = bounds.sizeKm;

      expect(bounds.south, 22.643);
      expect(bounds.north, 22.727);
      expect(bounds.west, 90.331);
      expect(bounds.east, 90.385);
      // About 10 by 6 km, where it used to be 30 by 30.
      expect(size.northSouth, closeTo(9.4, 0.3));
      expect(size.eastWest, closeTo(5.5, 0.3));
    });

    test('the university and the far end of each route are covered', () {
      expect(
        config.isWithinCoverage(config.centerLatitude, config.centerLongitude),
        isTrue,
      );
      // Barishal Club, Notun Bazar and Nathullabad.
      expect(config.isWithinCoverage(22.69765, 90.36948), isTrue);
      expect(config.isWithinCoverage(22.70961, 90.36239), isTrue);
      expect(config.isWithinCoverage(22.71320, 90.34967), isTrue);
    });

    test('places outside the rectangle are not covered', () {
      final bounds = config.coverageBounds;

      expect(config.isWithinCoverage(bounds.north + 0.001, 90.36), isFalse);
      expect(config.isWithinCoverage(bounds.south - 0.001, 90.36), isFalse);
      expect(config.isWithinCoverage(22.68, bounds.west - 0.001), isFalse);
      expect(config.isWithinCoverage(22.68, bounds.east + 0.001), isFalse);
      // Dhaka.
      expect(config.isWithinCoverage(23.8103, 90.4125), isFalse);
    });
  });

  group('haversineDistanceMeters', () {
    test('is zero for the same point', () {
      expect(haversineDistanceMeters(22.66, 90.36, 22.66, 90.36), 0);
    });

    test('measures one degree of latitude as about 111 km', () {
      expect(haversineDistanceMeters(22, 90, 23, 90), closeTo(111195, 100));
    });
  });
}
