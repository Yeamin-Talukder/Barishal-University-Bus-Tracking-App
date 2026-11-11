import 'package:bu_bus_tracker/core/constants/tracking_configuration.dart';
import 'package:bu_bus_tracker/core/utils/formatting.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = TrackingConfiguration.standard;
  final now = DateTime(2026, 11, 10, 12);

  BusTrackingStatus statusAfter(Duration age) =>
      config.statusOf(now.subtract(age), now);

  group('statusOf', () {
    test('a position up to 20 seconds old is live', () {
      expect(statusAfter(Duration.zero), BusTrackingStatus.live);
      expect(statusAfter(const Duration(seconds: 20)), BusTrackingStatus.live);
    });

    test('between 20 and 60 seconds it is delayed', () {
      expect(
        statusAfter(const Duration(seconds: 21)),
        BusTrackingStatus.delayed,
      );
      expect(
        statusAfter(const Duration(seconds: 60)),
        BusTrackingStatus.delayed,
      );
    });

    test('older than 60 seconds it is offline, never live', () {
      expect(
        statusAfter(const Duration(seconds: 61)),
        BusTrackingStatus.offline,
      );
      expect(statusAfter(const Duration(hours: 3)), BusTrackingStatus.offline);
    });

    test('no position at all is offline', () {
      expect(config.statusOf(null, now), BusTrackingStatus.offline);
    });

    test('a timestamp from a fast clock counts as just received', () {
      expect(
        config.statusOf(now.add(const Duration(seconds: 5)), now),
        BusTrackingStatus.live,
      );
    });

    test('the thresholds can be changed', () {
      const strict = TrackingConfiguration(
        liveWithin: Duration(seconds: 5),
        delayedWithin: Duration(seconds: 10),
      );

      expect(
        strict.statusOf(now.subtract(const Duration(seconds: 8)), now),
        BusTrackingStatus.delayed,
      );
      expect(
        strict.statusOf(now.subtract(const Duration(seconds: 11)), now),
        BusTrackingStatus.offline,
      );
    });
  });

  group('hasReliableMotion', () {
    BusLocation location({double? accuracy, double? speed}) => BusLocation(
      position: const GeoPoint(22.66, 90.36),
      updatedAt: now,
      accuracyMeters: accuracy,
      speedMetersPerSecond: speed,
    );

    test('a good fix on a moving bus is reliable', () {
      expect(config.hasReliableMotion(location(accuracy: 8, speed: 9)), isTrue);
    });

    test('a poor fix is not', () {
      expect(
        config.hasReliableMotion(location(accuracy: 120, speed: 9)),
        isFalse,
      );
    });

    test('a bus standing still is not', () {
      expect(
        config.hasReliableMotion(location(accuracy: 8, speed: 0.2)),
        isFalse,
      );
    });

    test('missing accuracy or speed is not', () {
      expect(config.hasReliableMotion(location(speed: 9)), isFalse);
      expect(config.hasReliableMotion(location(accuracy: 8)), isFalse);
    });
  });

  group('formatting', () {
    test('coordinates', () {
      expect(
        formatCoordinates(22.659967, 90.363381),
        '22.65997° N, 90.36338° E',
      );
      expect(formatCoordinates(-1.5, -2.25), '1.50000° S, 2.25000° W');
    });

    test('age', () {
      expect(formatAge(const Duration(seconds: 2)), 'just now');
      expect(formatAge(const Duration(seconds: 12)), '12 seconds ago');
      expect(formatAge(const Duration(minutes: 1)), '1 minute ago');
      expect(formatAge(const Duration(minutes: 5)), '5 minutes ago');
      expect(formatAge(const Duration(hours: 2)), '2 hours ago');
      expect(formatAge(const Duration(days: 1)), '1 day ago');
    });

    test('heading', () {
      expect(formatHeading(0), 'north');
      expect(formatHeading(44), 'north-east');
      expect(formatHeading(90), 'east');
      expect(formatHeading(200), 'south');
      expect(formatHeading(359), 'north');
      expect(formatHeading(-90), 'west');
    });

    test('speed', () {
      expect(formatSpeed(10), '36 km/h');
    });

    test('bytes and dates', () {
      expect(formatBytes(900), '900 B');
      expect(formatBytes(15309209), '14.6 MB');
      expect(formatDate(DateTime(2026, 11, 10)), '10 November 2026');
    });
  });
}
