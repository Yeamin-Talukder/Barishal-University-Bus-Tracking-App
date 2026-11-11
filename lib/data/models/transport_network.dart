import 'package:flutter/foundation.dart';

import 'bus_route.dart';
import 'bus_stop.dart';

/// Where a set of routes and stops came from.
enum TransportDataOrigin {
  /// Data confirmed by the university transport office.
  verified,

  /// Sample data for development. Never shown without a visible label.
  demo,

  /// Official stop names with positions that were looked up by name and have
  /// not been confirmed. For checking only; never shown without a visible
  /// label.
  unconfirmed,
}

/// The routes and stops the app knows about, plus anything that was rejected
/// while reading them.
@immutable
class TransportNetwork {
  const TransportNetwork({
    required this.routes,
    required this.stops,
    required this.origin,
    this.problems = const [],
  });

  static const TransportNetwork empty = TransportNetwork(
    routes: [],
    stops: [],
    origin: TransportDataOrigin.verified,
  );

  final List<BusRoute> routes;
  final List<BusStop> stops;
  final TransportDataOrigin origin;

  /// Human-readable descriptions of entries that were skipped as invalid.
  final List<String> problems;

  bool get isEmpty => routes.isEmpty && stops.isEmpty;
  bool get isDemo => origin == TransportDataOrigin.demo;
  bool get isUnconfirmed => origin == TransportDataOrigin.unconfirmed;

  /// True for anything other than verified data. Such data must always be
  /// shown with a label saying what it is.
  bool get needsNotice => origin != TransportDataOrigin.verified;

  /// This network with the transport office's own [official] stops.
  ///
  /// Official stops replace bundled stops with the same id and are added to
  /// the rest. Sample and unconfirmed data are left exactly as they are, so
  /// what their label says stays true.
  TransportNetwork withOfficialStops(List<BusStop>? official) {
    if (official == null || official.isEmpty) return this;
    if (origin != TransportDataOrigin.verified) return this;
    final officialIds = {for (final stop in official) stop.id};
    return TransportNetwork(
      routes: routes,
      stops: [
        ...official,
        for (final stop in stops)
          if (!officialIds.contains(stop.id)) stop,
      ],
      origin: origin,
      problems: problems,
    );
  }

  /// This network with the transport office's own [official] routes.
  ///
  /// Official routes replace bundled routes with the same id and are added
  /// to the rest. Sample and unconfirmed data are left exactly as they are.
  TransportNetwork withOfficialRoutes(List<BusRoute>? official) {
    if (official == null || official.isEmpty) return this;
    if (origin != TransportDataOrigin.verified) return this;
    final officialIds = {for (final route in official) route.id};
    return TransportNetwork(
      routes: [
        ...official,
        for (final route in routes)
          if (!officialIds.contains(route.id)) route,
      ],
      stops: stops,
      origin: origin,
      problems: problems,
    );
  }

  BusStop? stopById(String id) {
    for (final stop in stops) {
      if (stop.id == id) return stop;
    }
    return null;
  }

  BusRoute? routeById(String id) {
    for (final route in routes) {
      if (route.id == id) return route;
    }
    return null;
  }

  /// The stops of [route] in travel order. Ids the network does not know are
  /// left out.
  List<BusStop> stopsOf(BusRoute route) => [
    for (final id in route.stopIds) ?stopById(id),
  ];

  /// The routes that call at the stop with [stopId].
  List<BusRoute> routesServing(String stopId) => [
    for (final route in routes)
      if (route.stopIds.contains(stopId)) route,
  ];
}
