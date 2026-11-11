import 'dart:ui' show instantiateImageCodec;

import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/features/map/application/stop_map_layer.dart';
import 'package:bu_bus_tracker/features/map/presentation/university_map.dart';
import 'package:bu_bus_tracker/shared/widgets/stop_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _gate = BusStop(
  id: 'gate',
  name: 'Campus Gate',
  position: GeoPoint(22.66, 90.36),
);

Map<dynamic, dynamic> _properties(Map<String, dynamic> geoJson) =>
    ((geoJson['features'] as List).single as Map)['properties'] as Map;

void main() {
  group('The picked stop on the map', () {
    test('nothing is drawn while no stop is picked', () {
      expect(StopFocusLayer.geoJson(null)['features'], isEmpty);
    });

    test('the picked stop is drawn where the stop is', () {
      final geoJson = StopFocusLayer.geoJson(_gate);
      final feature = (geoJson['features'] as List).single as Map;

      expect(_properties(geoJson)['id'], 'gate');
      // GeoJSON order: longitude first.
      expect((feature['geometry'] as Map)['coordinates'], [90.36, 22.66]);
    });

    test('the badge pops up: small, a little too large, then settled', () {
      double at(int milliseconds) =>
          StopFocusLayer.popScale(Duration(milliseconds: milliseconds));
      final full = StopFocusLayer.popDuration.inMilliseconds;

      expect(at(0), closeTo(0.4, 1e-9));
      expect(at(full), closeTo(1, 1e-9));
      // Somewhere on the way it swells past its resting size.
      final largest = [for (var ms = 0; ms <= full; ms += 15) at(ms)]
          .reduce((a, b) => a > b ? a : b);
      expect(largest, greaterThan(1.05));
      expect(largest, lessThan(1.3));
      // Long after, it stays exactly at rest.
      expect(at(60000), closeTo(1, 1e-9));

      expect(StopFocusLayer.isPopping(Duration.zero), isTrue);
      expect(StopFocusLayer.isPopping(StopFocusLayer.popDuration), isFalse);
      expect(
        _properties(StopFocusLayer.geoJson(_gate))['scale'],
        closeTo(StopFocusLayer.restingScale, 1e-9),
      );
    });

    test('the ripple grows and fades away, again and again', () {
      Map<dynamic, dynamic> at(double ripple) =>
          _properties(StopFocusLayer.geoJson(_gate, ripple: ripple));

      expect(at(0)['rippleRadius'], 26);
      expect(
        at(0.8)['rippleRadius'],
        greaterThan(at(0.2)['rippleRadius'] as double),
      );
      expect(
        at(0.8)['rippleOpacity'],
        lessThan(at(0.2)['rippleOpacity'] as double),
      );
      expect(at(1)['rippleOpacity'], 0);
    });

    testWidgets('the stop badge is a real picture', (tester) async {
      final bytes = await tester.runAsync(
        () => paintStopBadge(
          body: const Color(0xFFFFFFFF),
          rim: const Color(0xFF1B1F1D),
          ink: const Color(0xFF1B1F1D),
        ),
      );

      // PNG signature.
      expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final image = await tester.runAsync(() async {
        final codec = await instantiateImageCodec(bytes);
        return (await codec.getNextFrame()).image;
      });
      // Several times the design size, so it stays sharp when large.
      expect(image!.width, StopFocusLayer.iconPixels * mapImageScale);
      expect(image.height, StopFocusLayer.iconPixels * mapImageScale);
    });
  });

  group('A tap near markers on the map', () {
    Map<String, dynamic> marker(String id, double latitude, double longitude) =>
        {
          'properties': {'id': id},
          'geometry': {
            'type': 'Point',
            'coordinates': [longitude, latitude],
          },
        };

    test('picks the nearest one', () {
      final features = [
        marker('far', 22.6610, 90.3600),
        marker('near', 22.6601, 90.3600),
      ];

      expect(nearestTappedId(features, 22.6600, 90.3600), 'near');
      expect(nearestTappedId(features, 22.6611, 90.3600), 'far');
    });

    test('picks nothing when nothing is near', () {
      expect(nearestTappedId(const [], 22.66, 90.36), isNull);
      // Things that are not markers are passed over.
      expect(
        nearestTappedId(
          const [
            'junk',
            {'properties': <String, dynamic>{}},
          ],
          22.66,
          90.36,
        ),
        isNull,
      );
    });
  });

  testWidgets('the stop badge in lists pops into place and then rests', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: StopBadge())),
    );

    double scale() => tester
        .widget<Transform>(
          find.descendant(
            of: find.byType(StopBadge),
            matching: find.byType(Transform),
          ),
        )
        .transform
        .entry(0, 0);

    expect(scale(), closeTo(0.6, 1e-6));
    // The animation ends by itself: nothing keeps running.
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 1e-6));
  });
}
