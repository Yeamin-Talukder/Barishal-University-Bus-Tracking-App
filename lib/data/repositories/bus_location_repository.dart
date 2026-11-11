import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/tracking_configuration.dart';
import '../models/bus.dart';
import 'bus_repository.dart';
import 'live_tracking_repository.dart';

/// Source of the buses and their latest positions.
abstract interface class BusLocationRepository {
  /// Emits the tracked buses whenever any of them changes.
  Stream<List<TrackedBus>> watchBuses();
}

/// There are no buses to report.
///
/// It reports an empty list rather than sample buses, because the app must
/// never show a bus position that did not come from a real bus.
class UnavailableBusLocationRepository implements BusLocationRepository {
  const UnavailableBusLocationRepository();

  @override
  Stream<List<TrackedBus>> watchBuses() => Stream.value(const []);
}

/// The buses in service, each with the position its driver last reported.
///
/// A bus that is not on a trip, or whose driver's phone has gone quiet, has
/// no position or an old one; the app shows that for what it is and never
/// fills the gap. The list is sent again every few seconds even when
/// nothing arrives, so a position that has stopped updating is seen to age.
class LiveBusLocationRepository implements BusLocationRepository {
  const LiveBusLocationRepository(
    this._buses,
    this._tracking, {
    this.refreshEvery = const Duration(seconds: 10),
  });

  final BusRepository _buses;
  final LiveTrackingRepository _tracking;
  final Duration refreshEvery;

  @override
  Stream<List<TrackedBus>> watchBuses() {
    late final StreamController<List<TrackedBus>> controller;
    StreamSubscription<List<Bus>>? busSubscription;
    StreamSubscription<Map<String, BusLocation>>? locationSubscription;
    Timer? refresh;
    StreamSubscription<Map<String, ActiveTrip>>? tripSubscription;
    List<Bus>? buses;
    var locations = const <String, BusLocation>{};
    var trips = const <String, ActiveTrip>{};

    // While a bus is on a trip it is on that trip's route, which the driver
    // chose when starting. That is what arrival estimates must follow.
    Bus onItsTrip(Bus bus) {
      final route = trips[bus.id]?.routeId;
      if (route == null || route == bus.routeId) return bus;
      return Bus(
        id: bus.id,
        number: bus.number,
        name: bus.name,
        registrationNumber: bus.registrationNumber,
        routeId: route,
        driverUid: bus.driverUid,
        isActive: bus.isActive,
      );
    }

    void emit() {
      final known = buses;
      if (known == null || controller.isClosed) return;
      controller.add([
        for (final bus in known)
          if (bus.isActive)
            TrackedBus(bus: onItsTrip(bus), location: locations[bus.id]),
      ]);
    }

    controller = StreamController<List<TrackedBus>>(
      onListen: () {
        busSubscription = _buses.watchBuses().listen((value) {
          buses = value;
          emit();
        }, onError: controller.addError);
        locationSubscription = _tracking.watchLocations().listen(
          (value) {
            locations = value;
            emit();
          },
          // Positions being unreachable must not hide the buses themselves.
          onError: (Object error) =>
              debugPrint('Live positions unavailable: $error'),
        );
        tripSubscription = _tracking.watchActiveTrips().listen(
          (value) {
            trips = value;
            emit();
          },
          onError: (Object error) =>
              debugPrint('Active trips unavailable: $error'),
        );
        refresh = Timer.periodic(refreshEvery, (_) => emit());
      },
      onCancel: () async {
        refresh?.cancel();
        await busSubscription?.cancel();
        await locationSubscription?.cancel();
        await tripSubscription?.cancel();
      },
    );
    return controller.stream;
  }
}

final busLocationRepositoryProvider = Provider<BusLocationRepository>(
  (ref) => LiveBusLocationRepository(
    ref.watch(busRepositoryProvider),
    ref.watch(liveTrackingRepositoryProvider),
  ),
);

final trackingConfigurationProvider = Provider<TrackingConfiguration>(
  (ref) => TrackingConfiguration.standard,
);

/// The current time. Overridden in tests so status and "last seen" text are
/// predictable.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The real buses, each with the position its driver last reported.
final reportedBusesProvider = StreamProvider<List<TrackedBus>>(
  (ref) => ref.watch(busLocationRepositoryProvider).watchBuses(),
);

/// Pretend buses made on this device by the "Test the system" screen.
///
/// Empty unless a test is running. They never leave the device: nothing
/// here is sent to the server or seen by anyone else.
class LocalTestBuses extends Notifier<List<TrackedBus>> {
  @override
  List<TrackedBus> build() => const [];

  void show(List<TrackedBus> buses) => state = buses;
}

final localTestBusesProvider =
    NotifierProvider<LocalTestBuses, List<TrackedBus>>(LocalTestBuses.new);

/// The buses the app shows right now: the real ones, and while a test is
/// running on this device, its pretend buses as well (listed first, and
/// each named TEST).
final trackedBusesProvider = Provider<AsyncValue<List<TrackedBus>>>((ref) {
  final reported = ref.watch(reportedBusesProvider);
  final testBuses = ref.watch(localTestBusesProvider);
  if (testBuses.isEmpty) return reported;
  return AsyncData([...testBuses, ...reported.value ?? const <TrackedBus>[]]);
});
