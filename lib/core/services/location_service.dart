import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/models/geo_point.dart';

/// Why the device's position could not be read.
enum LocationProblem {
  /// Location is switched off for the whole device.
  serviceDisabled,

  /// The user declined this time and can be asked again.
  permissionDenied,

  /// The user declined permanently; only system settings can change it.
  permissionDeniedForever,

  /// No position arrived in time (for example indoors with no GPS fix).
  timeout,

  unknown,
}

sealed class LocationResult {
  const LocationResult();
}

class LocationFound extends LocationResult {
  const LocationFound(this.position, {required this.accuracyMeters});

  final GeoPoint position;
  final double accuracyMeters;
}

class LocationUnavailable extends LocationResult {
  const LocationUnavailable(this.problem);

  final LocationProblem problem;

  /// Text suitable for showing to the user.
  String get message => switch (problem) {
    LocationProblem.serviceDisabled =>
      'Location is turned off. Turn it on to see where you are.',
    LocationProblem.permissionDenied =>
      'Location permission is needed to show where you are.',
    LocationProblem.permissionDeniedForever =>
      'Location permission is blocked. Allow it in the app settings.',
    LocationProblem.timeout =>
      'Could not get your location. Try again in the open.',
    LocationProblem.unknown => 'Could not get your location.',
  };

  /// Whether opening a settings screen can fix the problem.
  bool get canFixInSettings =>
      problem == LocationProblem.serviceDisabled ||
      problem == LocationProblem.permissionDeniedForever;
}

/// Reads the passenger's own position, asking for permission when needed.
abstract interface class LocationService {
  Future<LocationResult> currentLocation();

  /// Opens the settings screen that can resolve [problem].
  Future<void> openSettingsFor(LocationProblem problem);
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({
    this.timeLimit = const Duration(seconds: 15),
  });

  final Duration timeLimit;

  @override
  Future<LocationResult> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationUnavailable(LocationProblem.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationUnavailable(
          LocationProblem.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const LocationUnavailable(LocationProblem.permissionDenied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      return LocationFound(
        GeoPoint(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
      );
    } on TimeoutException {
      return const LocationUnavailable(LocationProblem.timeout);
    } on LocationServiceDisabledException {
      return const LocationUnavailable(LocationProblem.serviceDisabled);
    } on PermissionDeniedException {
      return const LocationUnavailable(LocationProblem.permissionDenied);
    } catch (_) {
      return const LocationUnavailable(LocationProblem.unknown);
    }
  }

  @override
  Future<void> openSettingsFor(LocationProblem problem) async {
    if (problem == LocationProblem.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);
