import 'package:bu_bus_tracker/core/services/eta_service.dart';
import 'package:bu_bus_tracker/core/utils/route_geometry.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/features/buses/presentation/arrival_text.dart';
import 'package:flutter_test/flutter_test.dart';

// A route running due north for 0.02 degrees of latitude (about 2,224 m),
// with a stop at the start, the middle and the end.
const _south = BusStop(id: 's', name: 'South', position: GeoPoint(22.00, 90));
const _middle = BusStop(id: 'm', name: 'Middle', position: GeoPoint(22.01, 90));
const _north = BusStop(id: 'n', name: 'North', position: GeoPoint(22.02, 90));
const _stops = [_south, _middle, _north];

const _route = BusRoute(
  id: 'r',
  name: 'North Road',
  colorHex: '#D94A38',
  startName: 'South',
  endName: 'North',
  path: [GeoPoint(22.00, 90), GeoPoint(22.01, 90), GeoPoint(22.02, 90)],
  stopIds: ['s', 'm', 'n'],
  isActive: true,
);

final _now = DateTime(2026, 11, 10, 12);
const _service = EtaService();

/// Metres in 0.01 degrees of latitude on the sphere used by the app.
const _hundredth = 1111.95;

BusLocation _at(
  double latitude, {
  double longitude = 90,
  double? heading = 0,
  double? speed = 10,
  double? accuracy = 5,
  Duration age = const Duration(seconds: 3),
}) => BusLocation(
  position: GeoPoint(latitude, longitude),
  updatedAt: _now.subtract(age),
  headingDegrees: heading,
  speedMetersPerSecond: speed,
  accuracyMeters: accuracy,
);

ArrivalEstimate _estimate(
  BusLocation? location, {
  BusStop stop = _north,
  BusLocation? previous,
  EtaService service = _service,
}) => service.estimateArrival(
  route: _route,
  stops: _stops,
  stop: stop,
  location: location,
  now: _now,
  previous: previous,
);

EtaUnavailableReason _reason(ArrivalEstimate estimate) =>
    (estimate as ArrivalUnavailable).reason;

void main() {
  group('RouteGeometry', () {
    final geometry = RouteGeometry(const [
      GeoPoint(22.00, 90.00),
      GeoPoint(22.01, 90.00),
      GeoPoint(22.01, 90.01),
    ]);

    test('measures length along the path, not corner to corner', () {
      // North leg, then an east leg shortened by the latitude.
      expect(geometry.lengthMeters, closeTo(_hundredth + 1030.9, 1));
    });

    test('projects a point beside the path onto it', () {
      final projection = geometry.project(const GeoPoint(22.005, 90.0005));

      expect(projection.distanceAlongMeters, closeTo(_hundredth / 2, 2));
      expect(projection.offRouteMeters, closeTo(51.6, 1));
      expect(projection.segmentBearingDegrees, closeTo(0, 0.1));
    });

    test('measures past a corner along both legs', () {
      final projection = geometry.project(const GeoPoint(22.01, 90.005));

      expect(projection.distanceAlongMeters, closeTo(_hundredth + 515.4, 2));
      expect(projection.offRouteMeters, closeTo(0, 0.5));
      expect(projection.segmentBearingDegrees, closeTo(90, 0.1));
    });

    test('a point beyond the end is pinned to the end', () {
      final projection = geometry.project(const GeoPoint(22.01, 90.02));

      expect(projection.distanceAlongMeters, closeTo(geometry.lengthMeters, 1));
      expect(projection.offRouteMeters, greaterThan(1000));
    });

    test('bearings', () {
      const origin = GeoPoint(22, 90);
      expect(bearingDegrees(origin, const GeoPoint(23, 90)), closeTo(0, 0.01));
      expect(bearingDegrees(origin, const GeoPoint(22, 91)), closeTo(90, 0.3));
      expect(
        bearingDegrees(origin, const GeoPoint(21, 90)),
        closeTo(180, 0.01),
      );
      expect(bearingDifferenceDegrees(350, 10), 20);
      expect(bearingDifferenceDegrees(10, 190), 180);
    });
  });

  group('progress along the route', () {
    test('finds the next stop ahead when travelling forward', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.005),
      );

      expect(progress.isOnRoute, isTrue);
      expect(progress.direction, TravelDirection.forward);
      expect(progress.nextStop, _middle);
      expect(progress.distanceToNextStopMeters, closeTo(_hundredth / 2, 2));
    });

    test('finds the stop behind on the map when travelling back', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.005, heading: 180),
      );

      expect(progress.direction, TravelDirection.backward);
      expect(progress.nextStop, _south);
    });

    test('a bus standing at a stop is heading for the one after', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.0101),
      );

      expect(progress.nextStop, _north);
    });

    test('at the end of the route there is no next stop', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.02),
      );

      expect(progress.nextStop, isNull);
    });

    test('movement between two positions beats the GPS heading', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        // The heading says north, but the bus has moved south.
        location: _at(22.005, heading: 0),
        previous: _at(22.007),
      );

      expect(progress.direction, TravelDirection.backward);
    });

    test('a tiny movement is not taken as a direction', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.00500, heading: null),
        previous: _at(22.00505),
      );

      expect(progress.direction, isNull);
      expect(progress.nextStop, isNull);
    });

    test('a heading across the road gives no direction', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.005, heading: 90),
      );

      expect(progress.direction, isNull);
    });

    test('a heading from a poor fix is not trusted', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.005, accuracy: 200),
      );

      expect(progress.direction, isNull);
    });

    test('a bus far from the route is off it', () {
      final progress = _service.progress(
        route: _route,
        stops: _stops,
        location: _at(22.005, longitude: 90.003),
      );

      expect(progress.isOnRoute, isFalse);
      expect(progress.offRouteMeters, closeTo(309.6, 3));
      expect(progress.nextStop, isNull);
    });
  });

  group('arrival estimate', () {
    test('is the distance along the route divided by the speed', () {
      final estimate = _estimate(_at(22.005)) as ArrivalEstimated;

      // One and a half hundredths of a degree at 10 m/s.
      expect(estimate.distanceMeters, closeTo(_hundredth * 1.5, 3));
      expect(estimate.travelTime.inSeconds, closeTo(167, 1));
      expect(estimate.arrivalTime, _now.add(estimate.travelTime));
    });

    test('follows the road around a corner, not the straight line', () {
      const corner = BusRoute(
        id: 'c',
        name: 'Corner',
        colorHex: '#D94A38',
        startName: '',
        endName: '',
        path: [
          GeoPoint(22.00, 90.00),
          GeoPoint(22.01, 90.00),
          GeoPoint(22.01, 90.01),
        ],
        stopIds: ['e'],
        isActive: true,
      );
      const end = BusStop(
        id: 'e',
        name: 'End',
        position: GeoPoint(22.01, 90.01),
      );

      final estimate = _service.estimateArrival(
        route: corner,
        stops: const [end],
        stop: end,
        location: _at(22.0),
        now: _now,
      ) as ArrivalEstimated;

      // Both legs (about 2,143 m), not the 1,516 m diagonal.
      expect(estimate.distanceMeters, closeTo(_hundredth + 1030.9, 3));
    });

    test('halves when the bus goes twice as fast', () {
      final slow = _estimate(_at(22.005, speed: 5)) as ArrivalEstimated;
      final fast = _estimate(_at(22.005, speed: 10)) as ArrivalEstimated;

      expect(
        slow.travelTime.inSeconds,
        closeTo(fast.travelTime.inSeconds * 2, 1),
      );
    });

    test('works for a bus travelling back down the route', () {
      final estimate = _estimate(
        _at(22.015, heading: 180),
        stop: _south,
      ) as ArrivalEstimated;

      expect(estimate.distanceMeters, closeTo(_hundredth * 1.5, 3));
    });

    test('is unavailable with no position', () {
      expect(_reason(_estimate(null)), EtaUnavailableReason.noPosition);
    });

    test('is unavailable from a position that is not live', () {
      expect(
        _reason(_estimate(_at(22.005, age: const Duration(seconds: 40)))),
        EtaUnavailableReason.positionTooOld,
      );
      expect(
        _reason(_estimate(_at(22.005, age: const Duration(minutes: 10)))),
        EtaUnavailableReason.positionTooOld,
      );
    });

    test('is unavailable when the bus is off the route', () {
      expect(
        _reason(_estimate(_at(22.005, longitude: 90.003))),
        EtaUnavailableReason.offRoute,
      );
    });

    test('is unavailable when the direction is not known', () {
      expect(
        _reason(_estimate(_at(22.005, heading: null))),
        EtaUnavailableReason.directionUnknown,
      );
    });

    test('is unavailable while the bus is stopped', () {
      // Direction is known from the earlier position; the bus has halted.
      final estimate = _estimate(
        _at(22.005, speed: 0.1),
        previous: _at(22.004),
      );

      expect(_reason(estimate), EtaUnavailableReason.busStopped);
    });

    test('is unavailable when the speed cannot be trusted', () {
      final estimate = _estimate(
        _at(22.005, accuracy: 200),
        previous: _at(22.004),
      );

      expect(_reason(estimate), EtaUnavailableReason.speedUnreliable);
    });

    test('is unavailable for a stop the bus has passed', () {
      expect(
        _reason(_estimate(_at(22.015), stop: _south)),
        EtaUnavailableReason.stopNotAhead,
      );
    });

    test('is unavailable when it would be longer than the limit', () {
      const strict = EtaService(
        configuration: EtaConfiguration(maxEstimate: Duration(minutes: 2)),
      );

      expect(
        _reason(_estimate(_at(22.005, speed: 2), service: strict)),
        EtaUnavailableReason.tooFarAway,
      );
    });
  });

  group('next stop estimate', () {
    test('names the next stop and estimates its arrival', () {
      final result = _service.estimateNextStop(
        route: _route,
        stops: _stops,
        location: _at(22.005),
        now: _now,
      );

      expect(result.nextStop, _middle);
      expect((result.estimate as ArrivalEstimated).travelTime.inSeconds, 56);
    });

    test('gives no next stop from an out-of-date position', () {
      final result = _service.estimateNextStop(
        route: _route,
        stops: _stops,
        location: _at(22.005, age: const Duration(minutes: 5)),
        now: _now,
      );

      expect(result.nextStop, isNull);
      expect(_reason(result.estimate), EtaUnavailableReason.positionTooOld);
    });

    test('says why when the next stop cannot be worked out', () {
      final result = _service.estimateNextStop(
        route: _route,
        stops: _stops,
        location: _at(22.005, longitude: 90.003),
        now: _now,
      );

      expect(result.nextStop, isNull);
      expect(_reason(result.estimate), EtaUnavailableReason.offRoute);
    });
  });

  group('wording', () {
    test('an estimate is always labelled as one', () {
      expect(
        arrivalText(
          ArrivalEstimated(
            travelTime: const Duration(seconds: 167),
            arrivalTime: _now,
            distanceMeters: 1668,
          ),
        ),
        'About 3 min (estimate)',
      );
      expect(
        arrivalText(
          ArrivalEstimated(
            travelTime: const Duration(seconds: 40),
            arrivalTime: _now,
            distanceMeters: 400,
          ),
        ),
        'Less than a minute (estimate)',
      );
    });

    test('every reason has its own explanation', () {
      final texts = {
        for (final reason in EtaUnavailableReason.values)
          arrivalText(ArrivalUnavailable(reason)),
      };

      expect(texts, hasLength(EtaUnavailableReason.values.length));
      expect(texts, everyElement(startsWith('Not available')));
    });
  });
}
