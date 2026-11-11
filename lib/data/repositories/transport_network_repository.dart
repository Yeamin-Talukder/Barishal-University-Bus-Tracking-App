import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_environment.dart';
import '../../core/theme/app_colors.dart';
import '../datasources/transport_geojson_parser.dart';
import '../models/bus_route.dart';
import '../models/bus_stop.dart';
import '../models/transport_network.dart';
import 'route_repository.dart';
import 'stop_repository.dart';

/// Source of the bus routes.
abstract interface class BusRouteRepository {
  Future<List<BusRoute>> fetchRoutes();
}

/// Source of the bus stops.
abstract interface class BusStopRepository {
  Future<List<BusStop>> fetchStops();
}

/// Reads routes and stops from GeoJSON files bundled with the app.
///
/// Verified data lives in `assets/data/`. The labelled sample data in
/// `assets/demo/`, or the unconfirmed stop positions in `assets/review/`,
/// are read instead only when [origin] says so. They are never mixed.
class AssetTransportRepository
    implements BusRouteRepository, BusStopRepository {
  AssetTransportRepository({
    required this._bundle,
    required this.origin,
    required this._parser,
  });

  final AssetBundle _bundle;
  final TransportGeoJsonParser _parser;
  final TransportDataOrigin origin;

  Future<TransportNetwork>? _network;

  String get _folder => switch (origin) {
    TransportDataOrigin.verified => 'assets/data',
    TransportDataOrigin.demo => 'assets/demo',
    TransportDataOrigin.unconfirmed => 'assets/review',
  };

  /// Routes, stops and any import problems, read once and then cached.
  Future<TransportNetwork> fetchNetwork() => _network ??= _load();

  @override
  Future<List<BusRoute>> fetchRoutes() async => (await fetchNetwork()).routes;

  @override
  Future<List<BusStop>> fetchStops() async => (await fetchNetwork()).stops;

  Future<TransportNetwork> _load() async {
    final stops = _parser.parseStops(
      await _bundle.loadString('$_folder/stops.geojson'),
    );
    final routes = _parser.parseRoutes(
      await _bundle.loadString('$_folder/routes.geojson'),
    );

    final knownStopIds = {for (final stop in stops.items) stop.id};
    final unknownStops = <String>[
      for (final route in routes.items)
        for (final stopId in route.stopIds)
          if (!knownStopIds.contains(stopId))
            'Route ${route.id}: stop "$stopId" is not in stops.geojson.',
    ];

    return TransportNetwork(
      routes: routes.items,
      stops: stops.items,
      origin: origin,
      problems: [...stops.problems, ...routes.problems, ...unknownStops],
    );
  }
}

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

final transportRepositoryProvider = Provider<AssetTransportRepository>((ref) {
  return AssetTransportRepository(
    bundle: rootBundle,
    origin: AppEnvironment.useUnconfirmedStops
        ? TransportDataOrigin.unconfirmed
        : AppEnvironment.useDemoData
        ? TransportDataOrigin.demo
        : TransportDataOrigin.verified,
    parser: TransportGeoJsonParser(
      fallbackRouteColors: [
        for (final color in AppColors.routePalette) _hex(color.toARGB32()),
      ],
    ),
  );
});

final busRouteRepositoryProvider = Provider<BusRouteRepository>(
  (ref) => ref.watch(transportRepositoryProvider),
);

final busStopRepositoryProvider = Provider<BusStopRepository>(
  (ref) => ref.watch(transportRepositoryProvider),
);

/// The routes and stops to show on the map and in lists: the data bundled
/// with the app, plus the routes and stops the transport office keeps in
/// the database.
///
/// The database is optional. Without a connection, or before its first
/// answer, the bundled data is shown by itself.
///
/// Not retried automatically: the bundled data is a file inside the app, so
/// a failure to read it will not fix itself. The lists offer "Try again".
final transportNetworkProvider = FutureProvider<TransportNetwork>((ref) async {
  final stops = ref.watch(officialStopsProvider).value;
  final routes = ref.watch(officialRoutesProvider).value;
  final bundled = await ref.watch(transportRepositoryProvider).fetchNetwork();
  return bundled.withOfficialStops(stops).withOfficialRoutes(routes);
}, retry: (retryCount, error) => null);

/// Official stop names with positions found by name in OpenStreetMap and not
/// confirmed (`assets/review/`). Offered to an admin as starting points
/// only; never shown to passengers as stops.
final suggestedStopsProvider = FutureProvider<List<BusStop>>((ref) async {
  final repository = AssetTransportRepository(
    bundle: rootBundle,
    origin: TransportDataOrigin.unconfirmed,
    parser: const TransportGeoJsonParser(fallbackRouteColors: ['#000000']),
  );
  return repository.fetchStops();
}, retry: (retryCount, error) => null);
