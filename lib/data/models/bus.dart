import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// A university bus, as registered by the transport office.
@immutable
class Bus {
  const Bus({
    required this.id,
    required this.number,
    required this.name,
    required this.isActive,
    this.registrationNumber,
    this.routeId,
    this.driverUid,
  });

  final String id;

  /// The number passengers know the bus by.
  final String number;
  final String name;
  final String? registrationNumber;

  /// The route the bus is assigned to, if any.
  final String? routeId;

  /// The account of the driver assigned to the bus, if any.
  final String? driverUid;

  /// Whether the bus is in service. One that is not is hidden from
  /// passengers.
  final bool isActive;
}

/// One GPS report from a bus.
@immutable
class BusLocation {
  const BusLocation({
    required this.position,
    required this.updatedAt,
    this.headingDegrees,
    this.speedMetersPerSecond,
    this.accuracyMeters,
    this.tripId,
  });

  final GeoPoint position;

  /// When the position was reported.
  final DateTime updatedAt;

  /// Direction of travel, clockwise from north.
  final double? headingDegrees;
  final double? speedMetersPerSecond;

  /// Radius of uncertainty of [position].
  final double? accuracyMeters;
  final String? tripId;
}

/// How fresh a bus's position is. An old position is never called live.
enum BusTrackingStatus { live, delayed, offline }

/// A bus together with its latest known position, if it has one.
@immutable
class TrackedBus {
  const TrackedBus({required this.bus, this.location});

  final Bus bus;
  final BusLocation? location;
}
