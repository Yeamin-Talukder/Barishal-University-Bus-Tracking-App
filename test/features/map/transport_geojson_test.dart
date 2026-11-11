import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/features/map/application/transport_map_layers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  test('routes become line features carrying their colour', () {
    final geojson = TransportGeoJson.routes(sampleDemoNetwork);

    expect(geojson['type'], 'FeatureCollection');
    final feature = (geojson['features'] as List).single as Map;
    expect(feature['properties'], {
      'id': 'r1',
      'name': 'Sample route',
      'color': '#D94A38',
      'active': true,
      // The only route: it runs down the middle of the road.
      'lane': 0.0,
      // The first route is a plain line.
      'pattern': 0,
    });
    expect(feature['geometry'], {
      'type': 'LineString',
      // GeoJSON order: longitude, latitude.
      'coordinates': [
        [90.36, 22.66],
        [90.35, 22.67],
      ],
    });
  });

  test('stops become point features', () {
    final geojson = TransportGeoJson.stops(sampleDemoNetwork);

    final features = geojson['features'] as List;
    expect(features, hasLength(2));
    expect((features.first as Map)['properties'], {
      'id': 'a',
      'name': 'Stop A',
    });
    expect((features.first as Map)['geometry'], {
      'type': 'Point',
      'coordinates': [90.36, 22.66],
    });
  });

  test('an empty network gives empty, valid collections', () {
    expect(TransportGeoJson.routes(TransportNetwork.empty), {
      'type': 'FeatureCollection',
      'features': <Object>[],
    });
    expect(TransportGeoJson.stops(TransportNetwork.empty), {
      'type': 'FeatureCollection',
      'features': <Object>[],
    });
  });

  group('Stubs in a route path', () {
    // About 11 m per 0.0001 of latitude.
    const a = GeoPoint(22.7000, 90.3600);
    const b = GeoPoint(22.7010, 90.3600);
    const c = GeoPoint(22.7020, 90.3600);
    const tip = GeoPoint(22.7010, 90.3601); // ~10 m off the road at b

    test('a few metres off the road and straight back is not drawn', () {
      expect(TransportGeoJson.withoutStubs(const [a, b, tip, b, c]), [a, b, c]);
    });

    test('a stub with a bend in it is not drawn either', () {
      const bend = GeoPoint(22.70105, 90.3601);
      expect(
        TransportGeoJson.withoutStubs(const [a, b, tip, bend, tip, b, c]),
        [a, b, c],
      );
    });

    test('a real there-and-back along a road is kept', () {
      // 110 m out and 110 m back: the bus really drives this.
      const far = GeoPoint(22.7010, 90.3611);
      const path = [a, b, far, b, c];
      expect(TransportGeoJson.withoutStubs(path), path);
    });

    test('a path without stubs is drawn as it is', () {
      const path = [a, b, c];
      expect(TransportGeoJson.withoutStubs(path), path);
      expect(TransportGeoJson.withoutStubs(const []), isEmpty);
      expect(TransportGeoJson.withoutStubs(const [a]), [a]);
    });

    test('the saved path itself is not changed', () {
      final path = [a, b, tip, b, c];
      TransportGeoJson.withoutStubs(path);
      expect(path, hasLength(5));
    });
  });
}
