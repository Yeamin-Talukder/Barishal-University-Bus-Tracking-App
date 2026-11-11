import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/eta_service.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/transport_network.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';

/// Which way a bus is going along its route, as "From → To": for example
/// "University → Barishal Club", or the other way round.
///
/// Null when it cannot be told: the bus has no route drawn on the map, its
/// position is not live, it is away from its route, or it is not moving in
/// a clear direction. Nothing is guessed.
String? busJourney({
  required EtaService eta,
  required TransportNetwork? network,
  required TrackedBus tracked,
  required BusTrackingStatus status,
}) {
  final location = tracked.location;
  final routeId = tracked.bus.routeId;
  if (network == null ||
      location == null ||
      routeId == null ||
      status != BusTrackingStatus.live) {
    return null;
  }
  final route = network.routeById(routeId);
  if (route == null || route.path.length < 2) return null;
  final stops = network.stopsOf(route);

  final start = route.startName.isNotEmpty
      ? route.startName
      : stops.firstOrNull?.name;
  final end = route.endName.isNotEmpty ? route.endName : stops.lastOrNull?.name;
  if (start == null || end == null) return null;

  final direction = eta
      .progress(route: route, stops: stops, location: location)
      .direction;
  return switch (direction) {
    TravelDirection.forward => '$start → $end',
    TravelDirection.backward => '$end → $start',
    null => null,
  };
}

/// [busJourney] for [tracked] right now.
String? busJourneyNow(WidgetRef ref, TrackedBus tracked) {
  final status = ref
      .watch(trackingConfigurationProvider)
      .statusOf(tracked.location?.updatedAt, ref.watch(clockProvider)());
  return busJourney(
    eta: ref.watch(etaServiceProvider),
    network: ref.watch(transportNetworkProvider).value,
    tracked: tracked,
    status: status,
  );
}
