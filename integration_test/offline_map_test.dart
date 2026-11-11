// On-device check that the bundled map really draws, at every zoom level and
// across the whole covered area.
//
// Run on a connected phone:
//
//   flutter test integration_test/offline_map_test.dart -d <device>
//
// For the offline test, put the phone in airplane mode (USB connection) and
// add `--dart-define=EXPECT_OFFLINE=true`. The test then first proves the
// phone has no internet, so a pass means the map was drawn from local data.
//
// It asks MapLibre which features it actually rendered, so it fails if tiles
// or label glyphs did not load, even though nothing crashes in that case.
// Lines starting with MAPSHOT mark moments worth a screenshot, and MAPCHECK
// lines carry the counts.

import 'dart:convert';
import 'dart:io';

import 'package:bu_bus_tracker/app.dart';
import 'package:bu_bus_tracker/core/constants/university_map_configuration.dart';
import 'package:bu_bus_tracker/core/services/preferences_service.dart';
import 'package:bu_bus_tracker/features/map/application/map_camera_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bool _expectOffline = bool.fromEnvironment('EXPECT_OFFLINE');

const _roadLayers = [
  'road-arterial',
  'road-major',
  'road-minor',
  'road-service',
  'road-path',
];
const _baseLayers = [
  'water',
  'waterway',
  'waterway-small',
  'landuse-residential',
  'landuse-farmland',
  'landuse-industrial',
  'landuse-education',
  'landuse-medical',
  'landuse-wetland',
  'landuse-grass',
  'landuse-wood',
  'landuse-park',
  ..._roadLayers,
];
const _buildingLayers = ['building', 'building-3d'];
const _labelLayers = [
  'label-place-city',
  'label-place-town',
  'label-place-village',
  'label-road-major',
  'label-road-minor',
  'label-water-line',
  'label-water-point',
  'label-poi',
  'label-poi-prominent',
];

class _Counts {
  const _Counts({
    required this.base,
    required this.roads,
    required this.buildings,
    required this.labels,
  });

  final int base;
  final int roads;
  final int buildings;
  final int labels;

  bool get hasMap => base > 0;

  Map<String, int> toJson() => {
    'base': base,
    'roads': roads,
    'buildings': buildings,
    'labels': labels,
  };
}

Future<bool> _hasInternet() async {
  try {
    final result = await InternetAddress.lookup('example.com')
        .timeout(const Duration(seconds: 8));
    return result.isNotEmpty;
  } on Object {
    return false;
  }
}

/// Tells whoever is holding the phone to leave it alone for a moment.
class _TestNotice extends StatelessWidget {
  const _TestNotice();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFB3261E),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'AUTOMATED MAP TEST RUNNING\n'
                'Please do not touch or close the app (about 1 minute)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('the bundled map draws at every zoom and across the coverage', (
    tester,
  ) async {
    const config = UniversityMapConfiguration.barishal;

    final online = await tester.runAsync(_hasInternet) ?? false;
    debugPrint('MAPCHECK ${jsonEncode({'step': 'network', 'online': online})}');
    if (_expectOffline) {
      expect(
        online,
        isFalse,
        reason: 'The phone still has internet; enable airplane mode first.',
      );
    }

    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    // Touches are ignored and a notice is shown while the test drives the
    // map, because a tap or a swipe during the sweep spoils the result.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              AbsorbPointer(child: BuBusTrackerApp()),
              _TestNotice(),
            ],
          ),
        ),
      ),
    );

    // The first launch copies the map package into app storage.
    MapLibreMapController? map;
    for (var i = 0; i < 240 && map == null; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      map = container.read(mapCameraControllerProvider).map;
    }
    expect(map, isNotNull, reason: 'The map was never created.');
    final controller = map!;

    final view = tester.view;
    // Query in both logical and physical pixels: platforms differ.
    final screen = Rect.fromLTWH(
      0,
      0,
      view.physicalSize.width,
      view.physicalSize.height,
    );

    Future<int> count(List<String> layers) async {
      final features = await controller.queryRenderedFeaturesInRect(
        screen,
        layers,
        null,
      );
      return features.length;
    }

    Future<_Counts> counts() async => _Counts(
      base: await count(_baseLayers),
      roads: await count(_roadLayers),
      buildings: await count(_buildingLayers),
      labels: await count(_labelLayers),
    );

    /// Moves the camera, waits for the map to draw, and reports what it drew.
    Future<_Counts> visit(String step, LatLng target, double zoom) async {
      await controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom),
        ),
      );
      var result = const _Counts(base: 0, roads: 0, buildings: 0, labels: 0);
      // Give tiles and labels time to load; stop early once they are in.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        result = await counts();
        if (i >= 2 && result.hasMap && (result.labels > 0 || i >= 7)) break;
      }
      debugPrint(
        'MAPCHECK ${jsonEncode({'step': step, 'zoom': zoom, ...result.toJson()})}',
      );
      debugPrint('MAPSHOT $step');
      // Hold the view still so a screenshot can be taken.
      await tester.pump(const Duration(milliseconds: 1800));
      return result;
    }

    final centre = LatLng(config.centerLatitude, config.centerLongitude);

    // Every zoom level the map allows, at the university.
    for (
      var zoom = config.minZoom.toInt();
      zoom <= config.maxZoom.toInt();
      zoom++
    ) {
      final result = await visit('zoom-$zoom', centre, zoom.toDouble());
      expect(result.hasMap, isTrue, reason: 'Nothing drawn at zoom $zoom.');
      if (zoom <= 16) {
        // Closer in, the screen shows only part of the campus, which need
        // not contain a road or a named feature.
        expect(result.roads, greaterThan(0), reason: 'No roads at zoom $zoom.');
        expect(
          result.labels,
          greaterThan(0),
          reason: 'No labels at zoom $zoom.',
        );
      }
      if (zoom >= 16) {
        expect(
          result.buildings,
          greaterThan(0),
          reason: 'No buildings at zoom $zoom.',
        );
      }
    }

    // Just inside the edge of the coverage in eight directions.
    final bounds = config.coverageBounds;
    final midLatitude = (bounds.south + bounds.north) / 2;
    final midLongitude = (bounds.west + bounds.east) / 2;
    const inset = 0.004;
    final edges = <String, LatLng>{
      'n': LatLng(bounds.north - inset, midLongitude),
      'ne': LatLng(bounds.north - inset, bounds.east - inset),
      'e': LatLng(midLatitude, bounds.east - inset),
      'se': LatLng(bounds.south + inset, bounds.east - inset),
      's': LatLng(bounds.south + inset, midLongitude),
      'sw': LatLng(bounds.south + inset, bounds.west + inset),
      'w': LatLng(midLatitude, bounds.west + inset),
      'nw': LatLng(bounds.north - inset, bounds.west + inset),
    };
    final names = edges.keys.toList();
    for (var i = 0; i < names.length; i++) {
      final target = edges[names[i]]!;
      final result = await visit('edge-${names[i]}', target, 14);
      expect(
        result.hasMap,
        isTrue,
        reason: 'Nothing drawn at the ${names[i]} edge of the coverage.',
      );
    }

    // A spot with place names that exist only in Bangla, to see how the map
    // draws them (checked by eye on the screenshot).
    await visit('bangla-labels', const LatLng(22.6786, 90.3470), 17);

    await visit('home', centre, config.initialZoom);

    // Make sure the phone did not come back online part-way through.
    final onlineAtEnd = await tester.runAsync(_hasInternet) ?? false;
    debugPrint(
      'MAPCHECK ${jsonEncode({'step': 'network-end', 'online': onlineAtEnd})}',
    );
    if (_expectOffline) {
      expect(
        onlineAtEnd,
        isFalse,
        reason: 'The phone came back online during the test.',
      );
    }
  });
}
