import 'package:bu_bus_tracker/features/map/application/transport_map_layers.dart';
import 'package:bu_bus_tracker/core/utils/route_geometry.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/features/map/application/bus_motion.dart';
import 'package:flutter_test/flutter_test.dart';

const _bus = Bus(
  id: 'chitra',
  number: 'BU-01',
  name: 'Chitra',
  routeId: '01',
  isActive: true,
);

TrackedBus _at(double latitude, double longitude, DateTime when) => TrackedBus(
  bus: _bus,
  location: BusLocation(
    position: GeoPoint(latitude, longitude),
    updatedAt: when,
  ),
);

void main() {
  final start = DateTime(2026, 11, 11, 8, 30);
  DateTime after(int milliseconds) =>
      start.add(Duration(milliseconds: milliseconds));

  group('Bus movement on the map', () {
    test('a bus seen for the first time is drawn where it reported', () {
      final motion = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => 90);

      final pose = motion.poseOf('chitra', start)!;
      expect(pose.position, const GeoPoint(22.66, 90.36));
      expect(pose.headingDegrees, 90);
      expect(motion.isMoving(start), isFalse);
    });

    test('a new position is reached by gliding, not by jumping', () {
      final motion = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => null)
        // Three seconds later the bus reports a spot a little further on.
        ..update(
          [_at(22.6602, 90.3604, after(3000))],
          after(3000),
          headingOf: (_) => null,
        );

      // The moment the report arrives the marker has not moved yet.
      expect(
        motion.poseOf('chitra', after(3000))!.position,
        const GeoPoint(22.66, 90.36),
      );
      expect(motion.isMoving(after(3000)), isTrue);

      // Half-way through the glide it is half-way there.
      final middle = motion.poseOf('chitra', after(4500))!.position;
      expect(middle.latitude, closeTo(22.6601, 1e-9));
      expect(middle.longitude, closeTo(90.3602, 1e-9));

      // The glide lasts as long as the gap between the reports, then stops
      // exactly on the reported position: nothing is predicted beyond it.
      expect(
        motion.poseOf('chitra', after(6000))!.position,
        const GeoPoint(22.6602, 90.3604),
      );
      expect(
        motion.poseOf('chitra', after(60000))!.position,
        const GeoPoint(22.6602, 90.3604),
      );
      expect(motion.isMoving(after(6000)), isFalse);
    });

    test(
      'a report that arrives mid-glide continues from where it is drawn',
      () {
        final motion = BusMotionTracker()
          ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => null)
          ..update(
            [_at(22.6604, 90.36, after(4000))],
            after(4000),
            headingOf: (_) => null,
          );
        final midway = motion.poseOf('chitra', after(6000))!.position;
        expect(midway.latitude, closeTo(22.6602, 1e-9));

        motion.update(
          [_at(22.6606, 90.36, after(6000))],
          after(6000),
          headingOf: (_) => null,
        );

        // No jump back or forward at the hand-over.
        expect(
          motion.poseOf('chitra', after(6000))!.position.latitude,
          closeTo(22.6602, 1e-9),
        );
      },
    );

    test('the glide is never shorter or longer than its limits', () {
      final quick = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => null)
        ..update(
          [_at(22.6601, 90.36, after(100))],
          after(100),
          headingOf: (_) => null,
        );
      // Two reports 0.1 s apart still take the shortest glide.
      final shortest = BusMotionTracker.shortest.inMilliseconds;
      expect(quick.isMoving(after(100 + shortest - 1)), isTrue);
      expect(quick.isMoving(after(100 + shortest)), isFalse);

      final slow = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => null)
        ..update(
          [_at(22.6601, 90.36, after(40000))],
          after(40000),
          headingOf: (_) => null,
        );
      final longest = BusMotionTracker.longest.inMilliseconds;
      expect(slow.isMoving(after(40000 + longest - 1)), isTrue);
      expect(slow.isMoving(after(40000 + longest)), isFalse);
    });

    test('a far jump places the marker instead of sweeping across the map', () {
      final motion = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => null)
        // About 2 km away: not a drive between two reports.
        ..update(
          [_at(22.68, 90.36, after(3000))],
          after(3000),
          headingOf: (_) => null,
        );

      expect(
        motion.poseOf('chitra', after(3000))!.position,
        const GeoPoint(22.68, 90.36),
      );
      expect(motion.isMoving(after(3000)), isFalse);
    });

    test('the pointer turns the short way round', () {
      final motion = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => 350)
        ..update(
          [_at(22.6602, 90.36, after(2000))],
          after(2000),
          headingOf: (_) => 10,
        );

      // From 350 to 10 passes through north, not through south.
      expect(
        motion.poseOf('chitra', after(3000))!.headingDegrees,
        closeTo(0, 1e-9),
      );
      expect(motion.poseOf('chitra', after(4000))!.headingDegrees, 10);
    });

    test('a direction that stops being trustworthy is dropped', () {
      final motion = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => 90)
        ..update(
          [_at(22.6602, 90.36, after(2000))],
          after(2000),
          headingOf: (_) => null,
        );

      expect(motion.poseOf('chitra', after(2500))!.headingDegrees, isNull);
    });

    test('a bus that stops reporting loses its marker', () {
      final motion = BusMotionTracker()
        ..update([_at(22.66, 90.36, start)], start, headingOf: (_) => null)
        ..update(
          const [TrackedBus(bus: _bus)],
          after(3000),
          headingOf: (_) => null,
        );

      expect(motion.poseOf('chitra', after(3000)), isNull);
    });
  });

  group('A bus on its route line', () {
    // An L: 500 m north, then 500 m east.
    const corner = GeoPoint(22.7045, 90.3600);
    final line = RouteGeometry(const [
      GeoPoint(22.7000, 90.3600),
      corner,
      GeoPoint(22.7045, 90.3649),
    ]);

    BusMotionTracker tracker() => BusMotionTracker();
    void report(
      BusMotionTracker motion,
      double latitude,
      double longitude,
      int atMs, {
      double? heading = 0,
    }) => motion.update(
      [_at(latitude, longitude, after(atMs))],
      after(atMs),
      headingOf: (_) => heading,
      trackOf: (_) => line,
    );

    test('a report from beside the road is drawn on the line', () {
      // About 10 m east of the line.
      final motion = tracker();
      report(motion, 22.7020, 90.3601, 0);

      final pose = motion.poseOf('chitra', start)!;
      expect(pose.position.longitude, closeTo(90.3600, 1e-7));
      expect(pose.position.latitude, closeTo(22.7020, 1e-6));
      // The line runs north here.
      expect(pose.trackBearingDegrees, closeTo(0, 0.5));
    });

    test('between two reports it goes round the corner, not across it', () {
      final motion = tracker();
      // 100 m before the corner, then 100 m after it.
      report(motion, 22.7036, 90.3600, 0);
      report(motion, 22.7045, 90.36097, 4000, heading: 90);

      // Half-way through the glide it is at the corner itself. Cutting
      // across would put it south-east of the corner, off the road.
      final middle = motion.poseOf('chitra', after(6000))!.position;
      expect(middle.latitude, closeTo(corner.latitude, 0.00002));
      expect(middle.longitude, closeTo(corner.longitude, 0.00002));

      // A quarter of the way it is still on the northward stretch.
      final early = motion.poseOf('chitra', after(5000))!;
      expect(early.position.longitude, closeTo(90.3600, 1e-7));
      expect(early.headingDegrees, closeTo(0, 0.5));
      // Three quarters: on the eastward stretch, pointing east.
      final late = motion.poseOf('chitra', after(7000))!;
      expect(late.position.latitude, closeTo(corner.latitude, 1e-7));
      expect(late.headingDegrees, closeTo(90, 0.5));
    });

    test('driving the other way, the pointer faces the other way', () {
      final motion = tracker();
      report(motion, 22.7036, 90.3600, 0, heading: 180);
      report(motion, 22.7020, 90.3600, 4000, heading: 180);

      final pose = motion.poseOf('chitra', after(6000))!;
      expect(pose.headingDegrees, closeTo(180, 0.5));
      // The line's own direction is still south to north.
      expect(pose.trackBearingDegrees, closeTo(0, 0.5));
    });

    test('a bus that has left its route is drawn where it reported', () {
      // About 300 m east of the northward stretch.
      final motion = tracker();
      report(motion, 22.7020, 90.3630, 0);

      final pose = motion.poseOf('chitra', start)!;
      expect(pose.position, const GeoPoint(22.7020, 90.3630));
      expect(pose.trackBearingDegrees, isNull);
    });

    test('no direction is shown on the line unless one is trusted', () {
      final motion = tracker();
      report(motion, 22.7020, 90.3600, 0, heading: null);
      report(motion, 22.7030, 90.3600, 4000, heading: null);

      expect(motion.poseOf('chitra', after(6000))!.headingDegrees, isNull);
    });

    test('a place on the line is found by its distance from the start', () {
      expect(line.locate(0).position, const GeoPoint(22.7000, 90.3600));
      final onFirst = line.locate(250);
      expect(onFirst.position.longitude, 90.3600);
      expect(onFirst.bearingDegrees, closeTo(0, 0.5));
      final onSecond = line.locate(line.lengthMeters - 100);
      expect(onSecond.position.latitude, closeTo(corner.latitude, 1e-9));
      expect(onSecond.bearingDegrees, closeTo(90, 0.5));
      // Past either end is that end.
      expect(line.locate(-50).position, const GeoPoint(22.7000, 90.3600));
      expect(line.locate(1e9).position, const GeoPoint(22.7045, 90.3649));
    });
  });

  group('A bus in its route\'s lane', () {
    const onLine = GeoPoint(22.7000, 90.3600);

    test('lanes are as far apart as the lines are drawn', () {
      expect(TransportMapLayers.laneOffsetPixels(10), closeTo(3.4, 1e-9));
      expect(TransportMapLayers.laneOffsetPixels(14), closeTo(4.8, 1e-9));
      expect(TransportMapLayers.laneOffsetPixels(18), closeTo(7.4, 1e-9));
      // Between the fixed points, and never beyond the ends.
      expect(
        TransportMapLayers.laneOffsetPixels(16),
        inExclusiveRange(4.8, 7.4),
      );
      expect(TransportMapLayers.laneOffsetPixels(5), 3.4);
      expect(TransportMapLayers.laneOffsetPixels(22), 7.4);
    });

    test('the middle lane is the line itself', () {
      expect(
        TransportMapLayers.inLane(
          onLine,
          lineBearingDegrees: 0,
          lane: 0,
          zoom: 15,
        ),
        onLine,
      );
    });

    test('a lane to the right of a northbound line is to the east', () {
      final right = TransportMapLayers.inLane(
        onLine,
        lineBearingDegrees: 0,
        lane: 1,
        zoom: 16,
      );
      final left = TransportMapLayers.inLane(
        onLine,
        lineBearingDegrees: 0,
        lane: -1,
        zoom: 16,
      );

      expect(right.longitude, greaterThan(onLine.longitude));
      expect(left.longitude, lessThan(onLine.longitude));
      expect(right.latitude, closeTo(onLine.latitude, 1e-9));
      // At zoom 16 a lane is about 6 pixels, a little over a metre a pixel.
      final meters = (right.longitude - onLine.longitude) * 111320 * 0.9225;
      expect(meters, inInclusiveRange(4, 9));
    });

    test('zoomed in, the same lane is fewer metres from the line', () {
      double eastAt(double zoom) =>
          TransportMapLayers.inLane(
            onLine,
            lineBearingDegrees: 0,
            lane: 1,
            zoom: zoom,
          ).longitude -
          onLine.longitude;

      expect(eastAt(18), lessThan(eastAt(14)));
    });
  });
}
