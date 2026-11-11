import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/eta_service.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/models/transport_network.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../buses/presentation/bus_journey.dart';

/// A bus heading for a stop, with the estimate of when it gets there.
class ApproachingBus {
  const ApproachingBus({
    required this.bus,
    required this.routeName,
    required this.estimate,
    this.journey,
  });

  final TrackedBus bus;
  final String routeName;
  final ArrivalEstimated estimate;

  /// Which way the bus is going, as "From → To", when it can be told.
  final String? journey;
}

/// The buses that can be given an arrival estimate for [stop], soonest
/// first. A bus is only included when the estimate rests on a live
/// position, a known direction and a trustworthy speed.
List<ApproachingBus> approachingBuses({
  required EtaService eta,
  required DateTime now,
  required TransportNetwork network,
  required BusStop stop,
  required List<TrackedBus> buses,
}) {
  final routesHere = network.routesServing(stop.id);
  final arrivals = <ApproachingBus>[];
  for (final tracked in buses) {
    final route = routesHere
        .where((route) => route.id == tracked.bus.routeId)
        .firstOrNull;
    if (route == null) continue;
    final estimate = eta.estimateArrival(
      route: route,
      stops: network.stopsOf(route),
      stop: stop,
      location: tracked.location,
      now: now,
    );
    if (estimate is ArrivalEstimated) {
      arrivals.add(
        ApproachingBus(
          bus: tracked,
          routeName: route.name,
          estimate: estimate,
          // An estimate is only made for a live bus.
          journey: busJourney(
            eta: eta,
            network: network,
            tracked: tracked,
            status: BusTrackingStatus.live,
          ),
        ),
      );
    }
  }
  return arrivals
    ..sort((a, b) => a.estimate.travelTime.compareTo(b.estimate.travelTime));
}

/// [approachingBuses] for the stop with the given id, right now.
final stopArrivalsProvider = Provider.family<List<ApproachingBus>, String>((
  ref,
  stopId,
) {
  final network = ref.watch(transportNetworkProvider).value;
  final stop = network?.stopById(stopId);
  if (network == null || stop == null) return const [];
  return approachingBuses(
    eta: ref.watch(etaServiceProvider),
    now: ref.watch(clockProvider)(),
    network: network,
    stop: stop,
    buses: ref.watch(trackedBusesProvider).value ?? const [],
  );
});
