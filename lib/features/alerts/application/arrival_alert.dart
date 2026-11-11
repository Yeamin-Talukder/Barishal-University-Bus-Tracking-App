import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/eta_service.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';

/// A passenger's request: "tell me when this bus is [minutes] from this
/// stop".
@immutable
class ArrivalAlert {
  const ArrivalAlert({
    required this.busId,
    required this.busNumber,
    required this.stopId,
    required this.stopName,
    required this.minutes,
  });

  final String busId;
  final String busNumber;
  final String stopId;
  final String stopName;

  /// The alert is given when the bus is estimated to be this many minutes
  /// away, or fewer.
  final int minutes;

  bool isFor({required String busId, required String stopId}) =>
      this.busId == busId && this.stopId == stopId;
}

/// What became of an alert.
enum AlertOutcome {
  /// The bus is within the time asked for.
  due,

  /// The bus has gone past the stop, so the alert can never be given.
  passed,

  /// The bus is no longer in the list of buses.
  busGone,
}

/// Something to tell the passenger about their alert.
@immutable
class AlertNotice {
  const AlertNotice({
    required this.alert,
    required this.outcome,
    required this.serial,
    this.travelTime,
  });

  final ArrivalAlert alert;
  final AlertOutcome outcome;

  /// The estimate when the alert was given.
  final Duration? travelTime;

  /// Counts notices, so two alike in a row are still told apart.
  final int serial;
}

@immutable
class ArrivalAlertState {
  const ArrivalAlertState({this.alert, this.notice});

  /// The alert being waited for, if there is one. One at a time.
  final ArrivalAlert? alert;

  /// The latest thing to tell the passenger, if any.
  final AlertNotice? notice;
}

/// What an [estimate] means for an alert asking for [minutes]: the outcome
/// that ends it, or null to keep waiting.
///
/// With no estimate (bus stopped, position old, direction unknown) the
/// alert keeps waiting: saying nothing is better than a guess.
AlertOutcome? checkAlert({
  required int minutes,
  required ArrivalEstimate estimate,
}) {
  return switch (estimate) {
    ArrivalEstimated(:final travelTime) =>
      travelTime <= Duration(minutes: minutes) ? AlertOutcome.due : null,
    ArrivalUnavailable(reason: EtaUnavailableReason.stopNotAhead) =>
      AlertOutcome.passed,
    ArrivalUnavailable() => null,
  };
}

/// Holds the passenger's arrival alert and watches the buses for it.
///
/// It works while the app is open: the check runs each time bus positions
/// arrive. It cannot wake the phone or ring when the app is closed.
class ArrivalAlertController extends Notifier<ArrivalAlertState> {
  int _serial = 0;

  @override
  ArrivalAlertState build() {
    ref.listen(trackedBusesProvider, (previous, next) => _check());
    return const ArrivalAlertState();
  }

  void set(ArrivalAlert alert) {
    state = ArrivalAlertState(alert: alert, notice: state.notice);
    _check();
  }

  void cancel() => state = ArrivalAlertState(notice: state.notice);

  void _finish(ArrivalAlert alert, AlertOutcome outcome, {Duration? time}) {
    state = ArrivalAlertState(
      notice: AlertNotice(
        alert: alert,
        outcome: outcome,
        travelTime: time,
        serial: ++_serial,
      ),
    );
  }

  void _check() {
    final alert = state.alert;
    if (alert == null) return;
    final buses = ref.read(trackedBusesProvider).value;
    final network = ref.read(transportNetworkProvider).value;
    // Nothing to judge by yet.
    if (buses == null || network == null) return;

    final TrackedBus? tracked = buses
        .where((bus) => bus.bus.id == alert.busId)
        .firstOrNull;
    if (tracked == null) return _finish(alert, AlertOutcome.busGone);
    final route = tracked.bus.routeId == null
        ? null
        : network.routeById(tracked.bus.routeId!);
    final stop = network.stopById(alert.stopId);
    if (route == null || stop == null) return;

    final estimate = ref
        .read(etaServiceProvider)
        .estimateArrival(
          route: route,
          stops: network.stopsOf(route),
          stop: stop,
          location: tracked.location,
          now: ref.read(clockProvider)(),
        );
    final outcome = checkAlert(minutes: alert.minutes, estimate: estimate);
    if (outcome == null) return;
    _finish(
      alert,
      outcome,
      time: estimate is ArrivalEstimated ? estimate.travelTime : null,
    );
  }
}

final arrivalAlertProvider =
    NotifierProvider<ArrivalAlertController, ArrivalAlertState>(
      ArrivalAlertController.new,
    );
