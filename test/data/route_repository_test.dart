import 'dart:async';
import 'dart:convert';

import 'package:bu_bus_tracker/data/datasources/transport_geojson_parser.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/data/repositories/route_repository.dart';
import 'package:bu_bus_tracker/data/repositories/stop_repository.dart';
import 'package:bu_bus_tracker/data/repositories/transport_network_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stop_fakes.dart';

Map<String, dynamic> _document({
  Object? name = 'Route 01',
  Object? color = '#d94a38',
  Object? path,
  Object? stopIds = const ['a', 'b'],
  Object? isActive = true,
}) => {
  'name': name,
  'color': color,
  'startLocation': 'Barishal Club',
  'endLocation': 'University',
  'path':
      path ??
      [
        {'latitude': 22.69, 'longitude': 90.36},
        {'latitude': 22.68, 'longitude': 90.35},
        {'latitude': 22.66, 'longitude': 90.36},
      ],
  'stopIds': stopIds,
  'isActive': isActive,
};

class _FixedRoutes implements RouteRepository {
  _FixedRoutes(this._controller);

  final StreamController<List<BusRoute>> _controller;

  @override
  Stream<List<BusRoute>> watchRoutes() => _controller.stream;
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    utf8.encode('{"type":"FeatureCollection","features":[]}'),
  );
}

void main() {
  group('Route documents', () {
    test('a stored route is read with its path and stops in order', () {
      final route = routeFromMap('01', _document())!;

      expect(route.id, '01');
      expect(route.name, 'Route 01');
      expect(route.colorHex, '#D94A38');
      expect(route.startName, 'Barishal Club');
      expect(route.endName, 'University');
      expect(route.path, const [
        GeoPoint(22.69, 90.36),
        GeoPoint(22.68, 90.35),
        GeoPoint(22.66, 90.36),
      ]);
      expect(route.stopIds, ['a', 'b']);
      expect(route.isActive, isTrue);
    });

    test('a route with no stop list still draws', () {
      expect(routeFromMap('01', _document(stopIds: null))!.stopIds, isEmpty);
    });

    test('running must be said explicitly', () {
      expect(routeFromMap('01', _document(isActive: null))!.isActive, isFalse);
      expect(routeFromMap('01', _document(isActive: 'yes'))!.isActive, isFalse);
    });

    test('a route that cannot be drawn is skipped, never guessed at', () {
      expect(routeFromMap('x', _document(name: ' ')), isNull);
      expect(routeFromMap('x', _document(color: 'red')), isNull);
      expect(routeFromMap('x', _document(path: 'a line')), isNull);
      expect(
        routeFromMap(
          'x',
          _document(
            path: [
              {'latitude': 22.69, 'longitude': 90.36},
            ],
          ),
        ),
        isNull,
      );
      expect(
        routeFromMap(
          'x',
          _document(
            path: [
              {'latitude': 22.69, 'longitude': 90.36},
              {'latitude': '22.68', 'longitude': 90.35},
            ],
          ),
        ),
        isNull,
      );
      expect(
        routeFromMap(
          'x',
          _document(
            path: [
              {'latitude': 22.69, 'longitude': 90.36},
              {'latitude': 122.0, 'longitude': 90.35},
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('TransportNetwork.withOfficialRoutes', () {
    final official = routeFromMap('01', _document())!;
    const bundled = TransportNetwork(
      routes: [],
      stops: [],
      origin: TransportDataOrigin.verified,
    );

    test('adds the official routes', () {
      expect(bundled.withOfficialRoutes([official]).routes.single.id, '01');
    });

    test('changes nothing when there are none', () {
      expect(bundled.withOfficialRoutes(null), same(bundled));
      expect(bundled.withOfficialRoutes(const []), same(bundled));
    });

    test('never mixes official routes into sample or unconfirmed data', () {
      for (final origin in [
        TransportDataOrigin.demo,
        TransportDataOrigin.unconfirmed,
      ]) {
        final labelled = TransportNetwork(
          routes: const [],
          stops: const [],
          origin: origin,
        );
        expect(labelled.withOfficialRoutes([official]), same(labelled));
      }
    });
  });

  group('transportNetworkProvider', () {
    test('joins the saved routes to the saved stops', () async {
      final routes = StreamController<List<BusRoute>>();
      final container = ProviderContainer(
        overrides: [
          transportRepositoryProvider.overrideWithValue(
            AssetTransportRepository(
              bundle: _EmptyBundle(),
              origin: TransportDataOrigin.verified,
              parser: const TransportGeoJsonParser(
                fallbackRouteColors: ['#111111'],
              ),
            ),
          ),
          stopRepositoryProvider.overrideWithValue(
            FakeStopRepository(const [
              BusStop(id: 'a', name: 'Club', position: GeoPoint(22.69, 90.36)),
              BusStop(id: 'b', name: 'Gate', position: GeoPoint(22.66, 90.36)),
            ]),
          ),
          routeRepositoryProvider.overrideWithValue(_FixedRoutes(routes)),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(routes.close);
      container.listen(transportNetworkProvider, (previous, next) {});

      routes.add([routeFromMap('01', _document())!]);
      // The stops and the routes arrive separately; wait for both.
      for (var i = 0; i < 100; i++) {
        final network = container.read(transportNetworkProvider).value;
        if (network != null &&
            network.routes.isNotEmpty &&
            network.stops.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final network = container.read(transportNetworkProvider).value!;
      final route = network.routeById('01')!;
      expect(
        [for (final stop in network.stopsOf(route)) stop.name],
        ['Club', 'Gate'],
      );
      expect(network.routesServing('a').single.id, '01');
    });
  });
}
