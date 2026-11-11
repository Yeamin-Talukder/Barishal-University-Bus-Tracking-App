import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/location_service.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/live_tracking_repository.dart';
import 'driver_location_source.dart';

enum TripPhase {
  /// This phone is not sharing a position.
  idle,
  starting,

  /// This phone is sharing the bus's position.
  sharing,
  ending,
}

/// What the driver's phone is doing about a trip.
@immutable
class TripState {
  const TripState({
    this.phase = TripPhase.idle,
    this.trip,
    this.lastSentAt,
    this.lastAccuracyMeters,
    this.sentCount = 0,
    this.problem,
  });

  final TripPhase phase;

  /// The trip being shared, while [phase] is not idle.
  final ActiveTrip? trip;

  /// When the last position was accepted by the server.
  final DateTime? lastSentAt;
  final double? lastAccuracyMeters;
  final int sentCount;

  /// The latest thing that went wrong, in words the driver can act on.
  final String? problem;

  bool get isSharing => phase == TripPhase.sharing;
}

/// Starts and ends a trip, and publishes the phone's position while one is
/// running.
///
/// The server decides whether each write is allowed. This class only does
/// the driver's part and reports what the server said.
class TripController extends Notifier<TripState> {
  /// Never send more often than this, whatever the phone delivers. The
  /// security rules refuse more than one position a second.
  static const Duration minimumGap = Duration(seconds: 3);

  StreamSubscription<PositionFix>? _positions;
  DateTime? _lastAttempt;
  bool _sending = false;

  @override
  TripState build() {
    ref.onDispose(() => unawaited(_positions?.cancel()));
    return const TripState();
  }

  LiveTrackingRepository get _tracking =>
      ref.read(liveTrackingRepositoryProvider);
  DateTime get _now => ref.read(clockProvider)();

  static String _explain(LocationProblem problem) => switch (problem) {
    LocationProblem.serviceDisabled =>
      'Location is turned off on this phone. Turn it on to share the bus\'s '
          'position.',
    LocationProblem.permissionDenied =>
      'Location permission is needed to share the bus\'s position.',
    LocationProblem.permissionDeniedForever =>
      'Location permission is blocked. Allow it for this app in the phone\'s '
          'settings.',
    _ => 'The phone\'s location could not be used. Try again.',
  };

  /// Starts a trip on [bus] and begins sharing its position.
  Future<void> start(Bus bus, String driverUid) async {
    if (state.phase != TripPhase.idle) return;
    state = const TripState(phase: TripPhase.starting);

    final problem = await ref.read(driverLocationSourceProvider).prepare();
    if (problem != null) {
      state = TripState(problem: _explain(problem));
      return;
    }
    try {
      final trip = await _tracking.startTrip(bus: bus, driverUid: driverUid);
      _share(trip);
    } on TrackingFailure catch (failure) {
      state = TripState(problem: failure.message);
    }
  }

  /// Shares the position for a trip that is already open, for example after
  /// the app was closed and opened again mid-trip.
  Future<void> resume(ActiveTrip trip) async {
    if (state.phase != TripPhase.idle) return;
    state = TripState(phase: TripPhase.starting, trip: trip);

    final problem = await ref.read(driverLocationSourceProvider).prepare();
    if (problem != null) {
      state = TripState(problem: _explain(problem));
      return;
    }
    _share(trip);
  }

  void _share(ActiveTrip trip) {
    _lastAttempt = null;
    _sending = false;
    state = TripState(phase: TripPhase.sharing, trip: trip);
    _positions = ref
        .read(driverLocationSourceProvider)
        .positions()
        .listen(
          (fix) => unawaited(_publish(trip, fix)),
          onError: (Object error) {
            debugPrint('Position stream failed: $error');
            if (!state.isSharing) return;
            state = TripState(
              phase: TripPhase.sharing,
              trip: trip,
              lastSentAt: state.lastSentAt,
              lastAccuracyMeters: state.lastAccuracyMeters,
              sentCount: state.sentCount,
              problem:
                  'The phone stopped giving its position. Check that '
                  'location is on.',
            );
          },
        );
  }

  Future<void> _publish(ActiveTrip trip, PositionFix fix) async {
    if (!state.isSharing || _sending) return;
    final now = _now;
    final last = _lastAttempt;
    if (last != null && now.difference(last) < minimumGap) return;
    _lastAttempt = now;
    _sending = true;
    try {
      await _tracking.publishPosition(trip, fix);
      if (!state.isSharing) return;
      state = TripState(
        phase: TripPhase.sharing,
        trip: trip,
        lastSentAt: now,
        lastAccuracyMeters: fix.accuracyMeters,
        sentCount: state.sentCount + 1,
      );
    } on TrackingFailure catch (failure) {
      if (!state.isSharing) return;
      state = TripState(
        phase: TripPhase.sharing,
        trip: trip,
        lastSentAt: state.lastSentAt,
        lastAccuracyMeters: state.lastAccuracyMeters,
        sentCount: state.sentCount,
        problem: failure.message,
      );
    } finally {
      _sending = false;
    }
  }

  /// Stops sharing and ends the trip on [busId].
  Future<void> end(String busId) async {
    if (state.phase == TripPhase.ending) return;
    final trip = state.trip;
    state = TripState(phase: TripPhase.ending, trip: trip);
    // Stop the position stream first: this is what removes the notification
    // and lets the phone's GPS rest, whatever the server says next. Not
    // awaited, so a slow shutdown of the GPS cannot hold up ending the trip.
    unawaited(_positions?.cancel());
    _positions = null;
    try {
      await _tracking.endTrip(busId);
      state = const TripState();
    } on TrackingFailure catch (failure) {
      state = TripState(
        problem:
            'This phone has stopped sharing, but the trip could not be '
            'closed: ${failure.message}',
      );
    }
  }
}

final tripControllerProvider = NotifierProvider<TripController, TripState>(
  TripController.new,
);
