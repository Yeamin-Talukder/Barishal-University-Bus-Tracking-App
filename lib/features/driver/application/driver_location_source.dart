import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/location_service.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/repositories/live_tracking_repository.dart';

/// The driver's phone as a source of the bus's position.
abstract interface class DriverLocationSource {
  /// Makes sure location is switched on and the app may use it, asking the
  /// driver if needed. Returns what is wrong, or null when ready.
  Future<LocationProblem?> prepare();

  /// The phone's position every few seconds, for as long as it is listened
  /// to, including while the app is in the background or the screen is off.
  Stream<PositionFix> positions();
}

/// Positions from the platform's location services.
///
/// On Android the stream runs inside a foreground service with a visible
/// notification, which is what keeps it alive in the background. It is not
/// a timer: the operating system delivers each position.
class GeolocatorDriverLocationSource implements DriverLocationSource {
  const GeolocatorDriverLocationSource({
    this.interval = const Duration(seconds: 5),
  });

  /// How often a position is wanted while the bus is on a trip.
  final Duration interval;

  @override
  Future<LocationProblem?> prepare() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationProblem.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return switch (permission) {
        LocationPermission.deniedForever =>
          LocationProblem.permissionDeniedForever,
        LocationPermission.denied => LocationProblem.permissionDenied,
        _ => null,
      };
    } catch (error) {
      debugPrint('Could not prepare location: $error');
      return LocationProblem.unknown;
    }
  }

  LocationSettings get _settings => switch (defaultTargetPlatform) {
    _ when kIsWeb => const LocationSettings(accuracy: LocationAccuracy.high),
    TargetPlatform.android => AndroidSettings(
      accuracy: LocationAccuracy.high,
      // By time, not distance: a bus waiting at a stop must keep reporting,
      // or it would look as if its phone had gone quiet.
      distanceFilter: 0,
      intervalDuration: interval,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: "Sharing this bus's position",
        notificationText:
            'BU Bus Tracker is sharing your location until you end the trip.',
        notificationChannelName: 'Trip in progress',
        enableWakeLock: true,
        setOngoing: true,
      ),
    ),
    TargetPlatform.iOS => AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    ),
    _ => const LocationSettings(accuracy: LocationAccuracy.high),
  };

  @override
  Stream<PositionFix> positions() =>
      Geolocator.getPositionStream(locationSettings: _settings).map(
        (position) => PositionFix(
          position: GeoPoint(position.latitude, position.longitude),
          // The platform reports "unknown" as a negative number or NaN.
          headingDegrees: _known(position.heading),
          speedMetersPerSecond: _known(position.speed),
          accuracyMeters: _known(position.accuracy),
        ),
      );

  static double? _known(double value) =>
      value.isFinite && value >= 0 ? value : null;
}

final driverLocationSourceProvider = Provider<DriverLocationSource>(
  (ref) => const GeolocatorDriverLocationSource(),
);
