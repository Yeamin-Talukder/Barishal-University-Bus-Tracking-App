import 'dart:convert';
import 'dart:io';

import 'package:bu_bus_tracker/core/constants/university_map_configuration.dart';
import 'package:bu_bus_tracker/data/datasources/transport_geojson_parser.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/data/repositories/transport_network_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves strings by asset key and counts how often each is read.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, String> files;
  final List<String> loaded = [];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final content = files[key];
    if (content == null) throw FlutterError('Asset not found: $key');
    return ByteData.sublistView(utf8.encode(content));
  }
}

/// Serves the project's real asset files from disk.
class _ProjectBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

const _parser = TransportGeoJsonParser(fallbackRouteColors: ['#111111']);

const _stops = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"id":"a","name":"A"},
  "geometry":{"type":"Point","coordinates":[90.36,22.66]}}]}''';

const _routes = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"id":"r","name":"R","stops":["a","ghost"]},
  "geometry":{"type":"LineString","coordinates":[[90.36,22.66],[90.35,22.67]]}}]}''';

void main() {
  test('verified data is read from assets/data only', () async {
    final bundle = _FakeBundle({
      'assets/data/stops.geojson': _stops,
      'assets/data/routes.geojson': _routes,
    });
    final repository = AssetTransportRepository(
      bundle: bundle,
      origin: TransportDataOrigin.verified,
      parser: _parser,
    );

    final network = await repository.fetchNetwork();

    expect(network.isDemo, isFalse);
    expect(network.routes.single.id, 'r');
    expect(network.stops.single.id, 'a');
    expect(bundle.loaded, everyElement(startsWith('assets/data/')));
  });

  test('demo data is read from assets/demo only and marked as demo', () async {
    final bundle = _FakeBundle({
      'assets/demo/stops.geojson': _stops,
      'assets/demo/routes.geojson': _routes,
    });
    final repository = AssetTransportRepository(
      bundle: bundle,
      origin: TransportDataOrigin.demo,
      parser: _parser,
    );

    final network = await repository.fetchNetwork();

    expect(network.isDemo, isTrue);
    expect(bundle.loaded, everyElement(startsWith('assets/demo/')));
  });

  test(
    'unconfirmed stops are read from assets/review only and marked',
    () async {
      final bundle = _FakeBundle({
        'assets/review/stops.geojson': _stops,
        'assets/review/routes.geojson': _routes,
      });
      final repository = AssetTransportRepository(
        bundle: bundle,
        origin: TransportDataOrigin.unconfirmed,
        parser: _parser,
      );

      final network = await repository.fetchNetwork();

      expect(network.isUnconfirmed, isTrue);
      expect(network.needsNotice, isTrue);
      expect(network.isDemo, isFalse);
      expect(bundle.loaded, everyElement(startsWith('assets/review/')));
    },
  );

  test('reports a route that names a stop which does not exist', () async {
    final repository = AssetTransportRepository(
      bundle: _FakeBundle({
        'assets/data/stops.geojson': _stops,
        'assets/data/routes.geojson': _routes,
      }),
      origin: TransportDataOrigin.verified,
      parser: _parser,
    );

    final network = await repository.fetchNetwork();

    expect(network.problems.single, contains('"ghost"'));
    expect(network.stopById('a')?.name, 'A');
    expect(network.stopById('ghost'), isNull);
  });

  test('routes and stops come from one cached read', () async {
    final bundle = _FakeBundle({
      'assets/data/stops.geojson': _stops,
      'assets/data/routes.geojson': _routes,
    });
    final repository = AssetTransportRepository(
      bundle: bundle,
      origin: TransportDataOrigin.verified,
      parser: _parser,
    );

    expect(await repository.fetchRoutes(), hasLength(1));
    expect(await repository.fetchStops(), hasLength(1));
    expect(bundle.loaded, hasLength(2));
  });

  group('bundled data files', () {
    test('the verified data shipped with the app is empty', () async {
      final network = await AssetTransportRepository(
        bundle: _ProjectBundle(),
        origin: TransportDataOrigin.verified,
        parser: _parser,
      ).fetchNetwork();

      expect(network.isEmpty, isTrue);
      expect(network.problems, isEmpty);
    });

    test(
      'the unconfirmed stops are valid, marked, and inside the map',
      () async {
        final network = await AssetTransportRepository(
          bundle: _ProjectBundle(),
          origin: TransportDataOrigin.unconfirmed,
          parser: _parser,
        ).fetchNetwork();
        const coverage = UniversityMapConfiguration.barishal;

        expect(network.problems, isEmpty);
        // No route lines: the roads the routes follow are not known.
        expect(network.routes, isEmpty);
        expect(network.stops, hasLength(13));
        for (final stop in network.stops) {
          expect(stop.id, startsWith('review-'));
          expect(stop.description, contains('Position not confirmed.'));
          expect(
            coverage.isWithinCoverage(
              stop.position.latitude,
              stop.position.longitude,
            ),
            isTrue,
            reason: stop.name,
          );
        }
      },
    );

    test('the demo data is valid and every id is marked as demo', () async {
      final network = await AssetTransportRepository(
        bundle: _ProjectBundle(),
        origin: TransportDataOrigin.demo,
        parser: _parser,
      ).fetchNetwork();

      expect(network.problems, isEmpty);
      expect(network.routes, isNotEmpty);
      expect(network.stops, isNotEmpty);
      expect(
        network.routes.map((route) => route.id),
        everyElement(startsWith('demo-')),
      );
      expect(
        network.stops.map((stop) => stop.id),
        everyElement(startsWith('demo-')),
      );
    });
  });
}
