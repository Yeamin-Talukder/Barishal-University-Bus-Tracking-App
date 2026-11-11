import '../../data/models/bus.dart';

/// Thresholds that decide how a bus position is presented.
///
/// These are starting values, meant to be tuned once real buses are tracked.
class TrackingConfiguration {
  const TrackingConfiguration({
    this.liveWithin = const Duration(seconds: 20),
    this.delayedWithin = const Duration(seconds: 60),
    this.maxReliableAccuracyMeters = 50,
    this.minMovingSpeedMetersPerSecond = 1,
  });

  static const TrackingConfiguration standard = TrackingConfiguration();

  /// A position newer than this is live.
  final Duration liveWithin;

  /// A position older than [liveWithin] but newer than this is delayed;
  /// anything older is offline.
  final Duration delayedWithin;

  /// Speed and heading are only shown when the GPS fix is at least this good.
  final double maxReliableAccuracyMeters;

  /// Below this speed the bus is treated as standing still, where GPS heading
  /// is meaningless.
  final double minMovingSpeedMetersPerSecond;

  /// Status of a position last updated at [updatedAt], judged at [now].
  ///
  /// No position at all is offline. A timestamp in the future (a wrong clock
  /// on either device) is treated as just received rather than trusted.
  BusTrackingStatus statusOf(DateTime? updatedAt, DateTime now) {
    if (updatedAt == null) return BusTrackingStatus.offline;
    final age = now.difference(updatedAt);
    if (age <= liveWithin) return BusTrackingStatus.live;
    if (age <= delayedWithin) return BusTrackingStatus.delayed;
    return BusTrackingStatus.offline;
  }

  /// Whether [location]'s speed and heading can be shown to a passenger.
  bool hasReliableMotion(BusLocation location) {
    final accuracy = location.accuracyMeters;
    final speed = location.speedMetersPerSecond;
    return accuracy != null &&
        accuracy <= maxReliableAccuracyMeters &&
        speed != null &&
        speed >= minMovingSpeedMetersPerSecond;
  }
}
