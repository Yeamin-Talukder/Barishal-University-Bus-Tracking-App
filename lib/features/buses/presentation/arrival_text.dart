import '../../../core/services/eta_service.dart';

/// How long until arrival, worded as the estimate it is.
String travelTimeText(Duration travelTime) {
  if (travelTime.inSeconds < 60) return 'Less than a minute';
  final minutes = (travelTime.inSeconds / 60).round();
  return 'About $minutes min';
}

/// An arrival estimate for display. An estimate is always labelled as one,
/// and a missing estimate says why it is missing.
String arrivalText(ArrivalEstimate estimate) => switch (estimate) {
  ArrivalEstimated(:final travelTime) =>
    '${travelTimeText(travelTime)} (estimate)',
  ArrivalUnavailable(:final reason) => switch (reason) {
    EtaUnavailableReason.noPosition => 'Not available: no position received',
    EtaUnavailableReason.positionTooOld =>
      'Not available: the position is out of date',
    EtaUnavailableReason.offRoute =>
      'Not available: the bus is away from its route',
    EtaUnavailableReason.directionUnknown =>
      'Not available: direction of travel not known yet',
    EtaUnavailableReason.busStopped => 'Not available while the bus is stopped',
    EtaUnavailableReason.speedUnreliable =>
      'Not available: the speed reading is unreliable',
    EtaUnavailableReason.stopNotAhead => 'Not available: no stop ahead',
    EtaUnavailableReason.tooFarAway =>
      'Not available: too far away to estimate',
  },
};
