import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/eta_service.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/utils/route_geometry.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/transport_network.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../domain/prediction.dart';

/// What the app has learned and remembered for predicting, as kept on the
/// device.
@immutable
class PredictionMemory {
  const PredictionMemory({
    this.profile = const TravelProfile(),
    this.lastSeen = const [],
    this.savedAt,
  });

  final TravelProfile profile;
  final List<LastSeenBus> lastSeen;

  /// When this was last written to the device.
  final DateTime? savedAt;
}

/// Keeps [PredictionMemory] in the device's own storage, so predictions go
/// on working with no connection and after the app is closed.
class PredictionStore {
  const PredictionStore(this._preferences);

  static const String profileKey = 'prediction.profile';
  static const String lastSeenKey = 'prediction.lastSeen';
  static const String savedAtKey = 'prediction.savedAt';
  static const String showKey = 'prediction.show';

  final SharedPreferences _preferences;

  PredictionMemory read() {
    Object? decoded(String key) {
      final text = _preferences.getString(key);
      if (text == null) return null;
      try {
        return jsonDecode(text);
      } on FormatException {
        // Unreadable: start again rather than fail.
        return null;
      }
    }

    final seen = decoded(lastSeenKey);
    final savedAt = _preferences.getInt(savedAtKey);
    return PredictionMemory(
      profile: TravelProfile.fromJson(decoded(profileKey)),
      lastSeen: [
        if (seen is List)
          for (final item in seen) ?LastSeenBus.fromJson(item),
      ],
      savedAt: savedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(savedAt),
    );
  }

  Future<void> save(PredictionMemory memory, DateTime now) async {
    await _preferences.setString(profileKey, jsonEncode(memory.profile));
    await _preferences.setString(
      lastSeenKey,
      jsonEncode([for (final bus in memory.lastSeen) bus.toJson()]),
    );
    await _preferences.setInt(savedAtKey, now.millisecondsSinceEpoch);
  }

  Future<void> clear() async {
    await _preferences.remove(profileKey);
    await _preferences.remove(lastSeenKey);
    await _preferences.remove(savedAtKey);
  }

  /// Whether predicted buses are shown. On unless switched off.
  bool get show => _preferences.getBool(showKey) ?? true;

  Future<void> setShow(bool value) => _preferences.setBool(showKey, value);
}

final predictionStoreProvider = Provider<PredictionStore>(
  (ref) => PredictionStore(ref.watch(sharedPreferencesProvider)),
);

/// A real bus being followed along its route, to learn how fast it goes.
class _Stretch {
  _Stretch({
    required this.direction,
    required this.fromAlong,
    required this.fromAt,
    required this.lastAlong,
    required this.lastAt,
  });

  TravelDirection direction;
  double fromAlong;
  DateTime fromAt;
  double lastAlong;
  DateTime lastAt;
}

/// Watches the real buses while they are live, and from them:
///
/// - learns how fast buses cover each route in each direction, and
/// - remembers where each bus was last seen and which way it was going.
///
/// Both are written to the device every few seconds, so that with no
/// connection the app can still say where a bus probably is. Only real,
/// live positions are learned from: never an old position, a test bus, or
/// a prediction.
class PredictionLearner extends Notifier<PredictionMemory> {
  /// Written to the device at most this often.
  static const Duration saveEvery = Duration(seconds: 10);

  /// A bus must cover at least this much of its route, taking at least
  /// this long, before its speed is taken as a sample.
  static const double stretchMeters = 300;
  static const Duration stretchTime = Duration(seconds: 45);

  /// A silence longer than this ends a stretch: what happened in between
  /// is not known.
  static const Duration longestGap = Duration(seconds: 60);

  /// A bus further than this from its route's line is not on it.
  static const double onRouteWithinMeters = 60;

  final Map<String, _Stretch> _stretches = {};
  final Map<String, RouteGeometry?> _geometries = {};
  TransportNetwork? _geometriesFor;
  bool _unsaved = false;

  @override
  PredictionMemory build() {
    ref.listen(reportedBusesProvider, (previous, next) {
      final buses = next.value;
      if (buses != null) observe(buses);
    });
    return ref.read(predictionStoreProvider).read();
  }

  /// Buses made up for testing teach nothing.
  static bool _isTestBus(String id) =>
      id.startsWith('test-bus') || id.startsWith('device-test-');

  RouteGeometry? _geometryOf(TransportNetwork network, String routeId) {
    if (!identical(_geometriesFor, network)) {
      _geometriesFor = network;
      _geometries.clear();
    }
    return _geometries.putIfAbsent(routeId, () {
      final route = network.routeById(routeId);
      return route == null || route.path.length < 2
          ? null
          : RouteGeometry(route.path);
    });
  }

  /// Takes the latest real positions. Called whenever they change.
  void observe(List<TrackedBus> buses) {
    final network = ref.read(transportNetworkProvider).value;
    if (network == null) return;
    final tracking = ref.read(trackingConfigurationProvider);
    final now = ref.read(clockProvider)();

    var profile = state.profile;
    final lastSeen = {for (final bus in state.lastSeen) bus.busId: bus};
    var changed = false;

    for (final tracked in buses) {
      final location = tracked.location;
      final routeId = tracked.bus.routeId;
      if (location == null ||
          routeId == null ||
          _isTestBus(tracked.bus.id) ||
          tracking.statusOf(location.updatedAt, now) !=
              BusTrackingStatus.live) {
        continue;
      }
      final geometry = _geometryOf(network, routeId);
      if (geometry == null) continue;
      final projection = geometry.project(location.position);
      if (projection.offRouteMeters > onRouteWithinMeters) continue;
      final along = projection.distanceAlongMeters;
      final at = location.updatedAt;

      // Which way it is going: from how it has moved, else from its
      // heading when that can be trusted.
      TravelDirection? direction;
      final stretch = _stretches[tracked.bus.id];
      if (stretch != null &&
          at.difference(stretch.lastAt) <= longestGap &&
          (along - stretch.lastAlong).abs() >= 15) {
        direction = along > stretch.lastAlong
            ? TravelDirection.forward
            : TravelDirection.backward;
      } else if (stretch != null &&
          at.difference(stretch.lastAt) <= longestGap) {
        direction = stretch.direction;
      } else {
        final heading = location.headingDegrees;
        if (heading != null && tracking.hasReliableMotion(location)) {
          final difference = bearingDifferenceDegrees(
            heading,
            projection.segmentBearingDegrees,
          );
          if (difference <= 60) direction = TravelDirection.forward;
          if (difference >= 120) direction = TravelDirection.backward;
        }
      }

      if (direction != null) {
        if (stretch == null ||
            stretch.direction != direction ||
            at.difference(stretch.lastAt) > longestGap) {
          // A new stretch: it has just appeared, turned round, or been
          // silent too long to say what it did meanwhile.
          _stretches[tracked.bus.id] = _Stretch(
            direction: direction,
            fromAlong: along,
            fromAt: at,
            lastAlong: along,
            lastAt: at,
          );
        } else if (at.isAfter(stretch.lastAt)) {
          stretch
            ..lastAlong = along
            ..lastAt = at;
          final meters = (along - stretch.fromAlong).abs();
          final time = at.difference(stretch.fromAt);
          if (meters >= stretchMeters && time >= stretchTime) {
            profile = profile.withSample(
              routeId,
              direction,
              meters / (time.inMilliseconds / 1000),
            );
            // The next sample starts from here.
            stretch
              ..fromAlong = along
              ..fromAt = at;
          }
        }
      }

      final seen = lastSeen[tracked.bus.id];
      if (seen == null || at.isAfter(seen.seenAt)) {
        lastSeen[tracked.bus.id] = LastSeenBus(
          busId: tracked.bus.id,
          number: tracked.bus.number,
          routeId: routeId,
          alongMeters: along,
          seenAt: at,
          direction: direction ?? seen?.direction,
        );
        changed = true;
      }
    }

    if (!changed && identical(profile, state.profile)) return;
    _unsaved = true;
    final savedAt = state.savedAt;
    final dueToSave = savedAt == null || now.difference(savedAt) >= saveEvery;
    state = PredictionMemory(
      profile: profile,
      lastSeen: lastSeen.values.toList(),
      savedAt: dueToSave ? now : savedAt,
    );
    if (dueToSave) {
      _unsaved = false;
      // Not waited for: a failed write must not stop the tracking.
      ref
          .read(predictionStoreProvider)
          .save(state, now)
          .catchError(
            (Object error) => debugPrint('Could not save predictions: $error'),
          );
    }
  }

  /// Whether something has been learned since the last write.
  bool get hasUnsavedChanges => _unsaved;

  /// Forgets everything learned and remembered, here and on the device.
  Future<void> clear() async {
    _stretches.clear();
    _unsaved = false;
    state = const PredictionMemory();
    await ref.read(predictionStoreProvider).clear();
  }
}

final predictionLearnerProvider =
    NotifierProvider<PredictionLearner, PredictionMemory>(
      PredictionLearner.new,
    );

/// Whether predicted buses and arrivals are shown. The user's choice, kept
/// on the device.
class ShowPredictions extends Notifier<bool> {
  @override
  bool build() => ref.watch(predictionStoreProvider).show;

  Future<void> set(bool value) async {
    state = value;
    await ref.read(predictionStoreProvider).setShow(value);
  }
}

final showPredictionsProvider = NotifierProvider<ShowPredictions, bool>(
  ShowPredictions.new,
);

final predictionEngineProvider = Provider<PredictionEngine>(
  (ref) => const PredictionEngine(),
);

/// Ticks every few seconds so predicted buses keep moving while nothing
/// else changes. Replaced in tests, which must not leave timers running.
final predictionTickProvider = StreamProvider<int>(
  (ref) => Stream.periodic(const Duration(seconds: 2), (count) => count),
);

/// The real buses that are live now, with the way each is going.
final _liveBusesOnRoutesProvider = Provider<List<LiveBusOnRoute>>((ref) {
  final network = ref.watch(transportNetworkProvider).value;
  final buses = ref.watch(reportedBusesProvider).value ?? const <TrackedBus>[];
  final tracking = ref.watch(trackingConfigurationProvider);
  final eta = ref.watch(etaServiceProvider);
  final now = ref.watch(clockProvider)();
  if (network == null) return const [];

  return [
    for (final tracked in buses)
      if (tracked.location != null &&
          tracked.bus.routeId != null &&
          tracking.statusOf(tracked.location!.updatedAt, now) ==
              BusTrackingStatus.live)
        LiveBusOnRoute(
          busId: tracked.bus.id,
          routeId: tracked.bus.routeId!,
          direction: switch (network.routeById(tracked.bus.routeId!)) {
            final route? when route.path.length >= 2 =>
              eta
                  .progress(
                    route: route,
                    stops: network.stopsOf(route),
                    location: tracked.location!,
                  )
                  .direction,
            _ => null,
          },
        ),
  ];
});

/// The buses predicted right now. Empty when predictions are switched off
/// or there is nothing to predict from.
final predictedBusesProvider = Provider<List<PredictedBus>>((ref) {
  if (!ref.watch(showPredictionsProvider)) return const [];
  ref.watch(predictionTickProvider);
  final network = ref.watch(transportNetworkProvider).value;
  if (network == null) return const [];
  final memory = ref.watch(predictionLearnerProvider);

  return ref
      .watch(predictionEngineProvider)
      .predictBuses(
        network: network,
        schedule: ref.watch(busScheduleProvider).value,
        profile: memory.profile,
        lastSeen: memory.lastSeen,
        live: ref.watch(_liveBusesOnRoutesProvider),
        now: ref.watch(clockProvider)(),
      );
});

/// When buses are predicted to reach the stop with the given id.
final predictedArrivalsProvider =
    Provider.family<List<PredictedArrival>, String>((ref, stopId) {
      if (!ref.watch(showPredictionsProvider)) return const [];
      ref.watch(predictionTickProvider);
      final network = ref.watch(transportNetworkProvider).value;
      final stop = network?.stopById(stopId);
      if (network == null || stop == null) return const [];
      final memory = ref.watch(predictionLearnerProvider);

      return ref
          .watch(predictionEngineProvider)
          .arrivalsAt(
            stop: stop,
            network: network,
            schedule: ref.watch(busScheduleProvider).value,
            profile: memory.profile,
            lastSeen: memory.lastSeen,
            live: ref.watch(_liveBusesOnRoutesProvider),
            now: ref.watch(clockProvider)(),
          );
    });
