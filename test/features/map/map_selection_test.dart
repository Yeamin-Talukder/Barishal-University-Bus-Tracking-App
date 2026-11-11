import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:bu_bus_tracker/features/map/application/transport_map_layers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

BusStop _stop(String id) =>
    BusStop(id: id, name: 'Stop $id', position: const GeoPoint(22.66, 90.36));

BusRoute _route(String id, List<String> stops) => BusRoute(
  id: id,
  name: 'Route $id',
  colorHex: '#D94A38',
  startName: '',
  endName: '',
  path: const [GeoPoint(22.66, 90.36), GeoPoint(22.67, 90.35)],
  stopIds: stops,
  isActive: true,
);

final _network = TransportNetwork(
  origin: TransportDataOrigin.verified,
  stops: [_stop('a'), _stop('b'), _stop('c'), _stop('d')],
  routes: [
    _route('r1', ['a', 'b', 'c']),
    _route('r2', ['c', 'd']),
    _route('empty', []),
  ],
);

List<Object> _only(List<String> ids) => [
  'in',
  ['get', 'id'],
  ['literal', ids],
];

void main() {
  group('MapSelectionController', () {
    late ProviderContainer container;
    MapSelection selection() => container.read(mapSelectionProvider);
    MapSelectionController controller() =>
        container.read(mapSelectionProvider.notifier);

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('starts with nothing selected', () {
      expect(selection().isEmpty, isTrue);
    });

    test('selecting a route replaces a selected stop, and the reverse', () {
      controller().selectStop('a');
      controller().selectRoute('r1');
      expect(selection(), const MapSelection(routeId: 'r1'));

      controller().selectStop('b');
      expect(selection(), const MapSelection(stopId: 'b'));
    });

    test('following needs a selected bus', () {
      controller().setFollowingBus(true);
      expect(selection().isFollowingBus, isFalse);

      controller().selectBus('bus-1');
      controller().setFollowingBus(true);
      expect(
        selection(),
        const MapSelection(busId: 'bus-1', isFollowingBus: true),
      );

      controller().setFollowingBus(false);
      expect(selection(), const MapSelection(busId: 'bus-1'));
    });

    test('selecting something else stops following', () {
      controller().selectBus('bus-1');
      controller().setFollowingBus(true);

      controller().selectRoute('r1');

      expect(selection().isFollowingBus, isFalse);
      expect(selection().busId, isNull);
    });

    test('clear removes the selection', () {
      controller().selectRoute('r1');
      controller().clear();

      expect(selection().isEmpty, isTrue);
    });
  });

  group('TransportNetwork lookups', () {
    test('finds routes and stops by id', () {
      expect(_network.routeById('r2')?.name, 'Route r2');
      expect(_network.routeById('nope'), isNull);
    });

    test('lists a route’s stops in travel order, skipping unknown ids', () {
      final route = _route('x', ['c', 'ghost', 'a']);

      expect(_network.stopsOf(route).map((stop) => stop.id), ['c', 'a']);
    });

    test('lists the routes serving a stop', () {
      expect(_network.routesServing('c').map((route) => route.id), [
        'r1',
        'r2',
      ]);
      expect(_network.routesServing('d').map((route) => route.id), ['r2']);
      expect(_network.routesServing('nope'), isEmpty);
    });
  });

  group('TransportLayerFilters', () {
    test('with nothing selected, every route and stop is drawn', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        MapSelection.none,
      );

      expect(
        filters[TransportMapLayers.routeLineLayer],
        TransportLayerFilters.all,
      );
      expect(
        filters[TransportMapLayers.stopDotLayer],
        TransportLayerFilters.all,
      );
      expect(
        filters[TransportMapLayers.routeDimLayer],
        TransportLayerFilters.none,
      );
      expect(
        filters[TransportMapLayers.stopSelectedLayer],
        TransportLayerFilters.none,
      );
      expect(
        filters[TransportMapLayers.stopTerminalLayer],
        TransportLayerFilters.none,
      );
    });

    test('a selected route is drawn in full, the others dimmed', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        const MapSelection(routeId: 'r1'),
      );

      // The bold, glowing layers draw the selected route...
      for (final layer in [
        TransportMapLayers.routeFocusGlowLayer,
        TransportMapLayers.routeFocusCasingLayer,
        TransportMapLayers.routeFocusLineLayer,
      ]) {
        expect(filters[layer], _only(['r1']));
      }
      // ...the side-by-side layers draw nothing, and the rest is dimmed.
      expect(
        filters[TransportMapLayers.routeLineLayer],
        TransportLayerFilters.none,
      );
      expect(
        filters[TransportMapLayers.routeCasingLayer],
        TransportLayerFilters.none,
      );
      expect(filters[TransportMapLayers.routeDimLayer], [
        '!',
        _only(['r1']),
      ]);
    });

    test('with nothing selected no route is drawn bold', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        MapSelection.none,
      );

      for (final layer in [
        TransportMapLayers.routeFocusGlowLayer,
        TransportMapLayers.routeFocusCasingLayer,
        TransportMapLayers.routeFocusLineLayer,
      ]) {
        expect(filters[layer], TransportLayerFilters.none);
      }
    });

    test('routes that share a road get lanes side by side', () {
      // One route sits on the middle of the road.
      expect(TransportGeoJson.laneOf(0, 1), 0);
      // Two sit either side of it, three use the middle as well.
      expect(
        [for (var i = 0; i < 2; i++) TransportGeoJson.laneOf(i, 2)],
        [-0.5, 0.5],
      );
      expect(
        [for (var i = 0; i < 3; i++) TransportGeoJson.laneOf(i, 3)],
        [-1, 0, 1],
      );
      // However many routes there are, none strays far from the road.
      expect(TransportGeoJson.laneOf(0, 9), -2);
      expect(TransportGeoJson.laneOf(8, 9), 2);

      final lanes = [
        for (final feature
            in TransportGeoJson.routes(_network)['features'] as List)
          ((feature as Map)['properties'] as Map)['lane'],
      ];
      expect(lanes.toSet(), hasLength(_network.routes.length.clamp(1, 5)));
    });

    test('a selected route shows only its own stops and marks its ends', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        const MapSelection(routeId: 'r1'),
      );

      expect(filters[TransportMapLayers.stopDotLayer], _only(['a', 'b', 'c']));
      // The badge that replaces the dot closer in shows the same stops.
      expect(filters[TransportMapLayers.stopIconLayer], _only(['a', 'b', 'c']));
      expect(
        filters[TransportMapLayers.stopLabelLayer],
        _only(['a', 'b', 'c']),
      );
      expect(filters[TransportMapLayers.stopTerminalLayer], _only(['a', 'c']));
    });

    test('a route without stops marks no ends', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        const MapSelection(routeId: 'empty'),
      );

      expect(
        filters[TransportMapLayers.stopTerminalLayer],
        TransportLayerFilters.none,
      );
    });

    test('a selected stop is ringed and nothing is hidden', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        const MapSelection(stopId: 'c'),
      );

      expect(filters[TransportMapLayers.stopSelectedLayer], _only(['c']));
      expect(
        filters[TransportMapLayers.routeLineLayer],
        TransportLayerFilters.all,
      );
      expect(
        filters[TransportMapLayers.stopDotLayer],
        TransportLayerFilters.all,
      );
    });

    test('an id that no longer exists selects nothing', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        const MapSelection(routeId: 'gone'),
      );

      expect(
        filters,
        TransportLayerFilters.forSelection(_network, MapSelection.none),
      );
    });

    test('every transport layer gets a filter', () {
      final filters = TransportLayerFilters.forSelection(
        _network,
        MapSelection.none,
      );

      expect(filters.keys, {
        TransportMapLayers.routeDimLayer,
        TransportMapLayers.routeCasingLayer,
        TransportMapLayers.routeLineLayer,
        TransportMapLayers.routeFocusGlowLayer,
        TransportMapLayers.routeFocusCasingLayer,
        TransportMapLayers.routeFocusLineLayer,
        TransportMapLayers.stopDotLayer,
        TransportMapLayers.stopIconLayer,
        TransportMapLayers.stopLabelLayer,
        TransportMapLayers.stopTerminalLayer,
        TransportMapLayers.stopSelectedLayer,
      });
    });
  });
}
