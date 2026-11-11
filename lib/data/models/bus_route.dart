import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// A university bus route: a line on the map with an ordered list of stops.
@immutable
class BusRoute {
  const BusRoute({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.startName,
    required this.endName,
    required this.path,
    required this.stopIds,
    required this.isActive,
  });

  final String id;
  final String name;

  /// Route colour as `#RRGGBB`.
  final String colorHex;

  final String startName;
  final String endName;

  /// The route geometry in travel order, at least two points.
  final List<GeoPoint> path;

  /// Ids of the stops served, in travel order.
  final List<String> stopIds;

  final bool isActive;
}
