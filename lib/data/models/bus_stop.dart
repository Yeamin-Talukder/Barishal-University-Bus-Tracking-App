import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// A place where university buses stop.
@immutable
class BusStop {
  const BusStop({
    required this.id,
    required this.name,
    required this.position,
    this.description,
  });

  final String id;
  final String name;
  final GeoPoint position;
  final String? description;
}
