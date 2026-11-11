import 'dart:convert';

import 'package:bu_bus_tracker/data/datasources/transport_geojson_parser.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

const _parser = TransportGeoJsonParser(
  fallbackRouteColors: ['#111111', '#222222'],
);

String _collection(List<Map<String, dynamic>> features) =>
    jsonEncode({'type': 'FeatureCollection', 'features': features});

Map<String, dynamic> _stop({
  Object? id = 'gate',
  Object? name = 'Main Gate',
  Object? coordinates = const [90.3634, 22.6600],
  String type = 'Point',
  String? description,
}) => {
  'type': 'Feature',
  'properties': {'id': id, 'name': name, 'description': ?description},
  'geometry': {'type': type, 'coordinates': coordinates},
};

Map<String, dynamic> _route({
  Object? id = 'r1',
  Object? name = 'Route 1',
  Object? coordinates = const [
    [90.3634, 22.6600],
    [90.3469, 22.6781],
  ],
  String type = 'LineString',
  Map<String, dynamic> extra = const {},
}) => {
  'type': 'Feature',
  'properties': {'id': id, 'name': name, ...extra},
  'geometry': {'type': type, 'coordinates': coordinates},
};

void main() {
  group('parseStops', () {
    test('reads a stop, converting GeoJSON order to latitude/longitude', () {
      final result = _parser.parseStops(
        _collection([_stop(description: 'Beside the bridge')]),
      );

      expect(result.problems, isEmpty);
      final stop = result.items.single;
      expect(stop.id, 'gate');
      expect(stop.name, 'Main Gate');
      expect(stop.position, const GeoPoint(22.6600, 90.3634));
      expect(stop.description, 'Beside the bridge');
    });

    test('an empty collection is valid and has no stops', () {
      final result = _parser.parseStops(_collection([]));

      expect(result.items, isEmpty);
      expect(result.problems, isEmpty);
    });

    test('skips and reports stops without an id or name', () {
      final result = _parser.parseStops(
        _collection([_stop(id: null), _stop(name: '  '), _stop(id: 'ok')]),
      );

      expect(result.items.map((stop) => stop.id), ['ok']);
      expect(result.problems, hasLength(2));
    });

    test('skips duplicate ids', () {
      final result = _parser.parseStops(_collection([_stop(), _stop()]));

      expect(result.items, hasLength(1));
      expect(result.problems.single, contains('duplicate id "gate"'));
    });

    test('skips coordinates that are out of range or not numbers', () {
      final result = _parser.parseStops(
        _collection([
          _stop(id: 'a', coordinates: [90.36, 122.66]),
          _stop(id: 'b', coordinates: [190.36, 22.66]),
          _stop(id: 'c', coordinates: ['90.36', '22.66']),
          _stop(id: 'd', coordinates: [90.36]),
        ]),
      );

      expect(result.items, isEmpty);
      expect(result.problems, hasLength(4));
    });

    test('skips a stop whose geometry is not a point', () {
      final result = _parser.parseStops(
        _collection([_stop(type: 'LineString')]),
      );

      expect(result.items, isEmpty);
      expect(result.problems.single, contains('must be a Point'));
    });

    test('reports invalid JSON instead of throwing', () {
      final result = _parser.parseStops('{not json');

      expect(result.items, isEmpty);
      expect(result.problems.single, contains('not valid JSON'));
    });

    test('reports a file that is not a FeatureCollection', () {
      final result = _parser.parseStops(jsonEncode({'type': 'Feature'}));

      expect(result.items, isEmpty);
      expect(result.problems.single, contains('FeatureCollection'));
    });
  });

  group('parseRoutes', () {
    test('reads a route with its properties', () {
      final result = _parser.parseRoutes(
        _collection([
          _route(
            extra: {
              'color': '#d94a38',
              'start': 'Campus',
              'end': 'Rupatoli',
              'stops': ['gate', 'rupatoli'],
              'active': false,
            },
          ),
        ]),
      );

      expect(result.problems, isEmpty);
      final route = result.items.single;
      expect(route.id, 'r1');
      expect(route.colorHex, '#D94A38');
      expect(route.startName, 'Campus');
      expect(route.endName, 'Rupatoli');
      expect(route.stopIds, ['gate', 'rupatoli']);
      expect(route.isActive, isFalse);
      expect(route.path.first, const GeoPoint(22.6600, 90.3634));
      expect(route.path.last, const GeoPoint(22.6781, 90.3469));
    });

    test('routes are active and take palette colours by default', () {
      final result = _parser.parseRoutes(
        _collection([_route(id: 'a'), _route(id: 'b'), _route(id: 'c')]),
      );

      expect(result.items.every((route) => route.isActive), isTrue);
      expect(result.items.map((route) => route.colorHex), [
        '#111111',
        '#222222',
        '#111111',
      ]);
    });

    test('an invalid colour is reported and replaced, the route kept', () {
      final result = _parser.parseRoutes(
        _collection([
          _route(extra: {'color': 'red'}),
        ]),
      );

      expect(result.items.single.colorHex, '#111111');
      expect(result.problems.single, contains('not #RRGGBB'));
    });

    test('skips a route with fewer than two points', () {
      final result = _parser.parseRoutes(
        _collection([
          _route(
            coordinates: [
              [90.36, 22.66],
            ],
          ),
        ]),
      );

      expect(result.items, isEmpty);
      expect(result.problems.single, contains('at least two points'));
    });

    test('skips a route if any point is invalid, rather than dropping it', () {
      final result = _parser.parseRoutes(
        _collection([
          _route(
            coordinates: [
              [90.36, 22.66],
              [90.35, 222.0],
              [90.34, 22.67],
            ],
          ),
        ]),
      );

      expect(result.items, isEmpty);
      expect(result.problems, hasLength(1));
    });

    test('skips a route whose geometry is not a line', () {
      final result = _parser.parseRoutes(_collection([_route(type: 'Point')]));

      expect(result.items, isEmpty);
      expect(result.problems.single, contains('must be a LineString'));
    });
  });
}
