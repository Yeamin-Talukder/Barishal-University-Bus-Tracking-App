import 'package:flutter/foundation.dart';

import '../../../core/constants/university_map_configuration.dart';

/// Where the offline map stands on this device.
enum OfflineMapStatus {
  /// Still finding out what is on the device.
  checking,

  /// No map data on the device. The map cannot be shown until it is
  /// installed from the copy bundled with the app.
  notInstalled,

  /// Map data is being copied into app storage.
  installing,

  /// An earlier install stopped part-way. Resuming copies only what is
  /// missing.
  interrupted,

  /// Installed and usable with no internet connection.
  ready,

  /// An older map version is installed and a newer one came with the app.
  needsUpdate,

  /// The last install or check failed.
  failed,
}

/// Result of comparing the installed map with what it should contain.
enum MapIntegrity { verified, damaged }

/// What the storage layer finds on the device.
@immutable
class MapInstallation {
  const MapInstallation({
    required this.status,
    this.installedVersion,
    this.bytesOnDevice = 0,
  });

  /// One of notInstalled, interrupted, ready or needsUpdate.
  final OfflineMapStatus status;
  final int? installedVersion;
  final int bytesOnDevice;
}

/// Describes the map archive bundled with the app
/// (`assets/map/barishal_basemap_v<n>.json`).
@immutable
class MapPackageManifest {
  const MapPackageManifest({
    required this.bytes,
    required this.sha256,
    required this.sourceBuild,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.bounds,
  });

  factory MapPackageManifest.fromJson(Map<String, dynamic> json) {
    return MapPackageManifest(
      bytes: (json['bytes'] as num).toInt(),
      sha256: json['sha256'] as String,
      sourceBuild: json['sourceBuild'] as String,
      minZoom: (json['minZoom'] as num).toInt(),
      maxZoom: (json['maxZoom'] as num).toInt(),
      tileCount: (json['tileCount'] as num).toInt(),
      bounds: GeoBounds(
        south: (json['bounds']['south'] as num).toDouble(),
        west: (json['bounds']['west'] as num).toDouble(),
        north: (json['bounds']['north'] as num).toDouble(),
        east: (json['bounds']['east'] as num).toDouble(),
      ),
    );
  }

  /// Size of the tile archive alone.
  final int bytes;

  /// SHA-256 of the tile archive, lower-case hex.
  final String sha256;

  /// The OpenStreetMap planet build the tiles were taken from, for example
  /// `20261110.pmtiles`.
  final String sourceBuild;

  final int minZoom;
  final int maxZoom;
  final int tileCount;

  /// The area the archive covers.
  final GeoBounds bounds;

  /// The date of the map data, read from [sourceBuild].
  DateTime? get dataDate {
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(sourceBuild);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
}

/// Everything the UI needs to show about the offline map.
@immutable
class OfflineMapState {
  const OfflineMapState({
    required this.status,
    required this.bundledVersion,
    this.canManage = true,
    this.manifest,
    this.installedVersion,
    this.bytesOnDevice = 0,
    this.progress = 0,
    this.errorMessage,
    this.integrity,
  });

  final OfflineMapStatus status;

  /// Version of the map package that ships with this build of the app.
  final int bundledVersion;

  /// False where the map is not stored by the app (the web preview), so
  /// there is nothing to install, check or remove.
  final bool canManage;

  final MapPackageManifest? manifest;
  final int? installedVersion;
  final int bytesOnDevice;

  /// Install progress from 0 to 1, meaningful while [status] is installing.
  final double progress;

  /// A message for the user when [status] is failed.
  final String? errorMessage;

  /// Result of the most recent integrity check in this session, if any.
  final MapIntegrity? integrity;

  bool get isReady => status == OfflineMapStatus.ready;

  static const Object _unset = Object();

  OfflineMapState copyWith({
    OfflineMapStatus? status,
    MapPackageManifest? manifest,
    Object? installedVersion = _unset,
    int? bytesOnDevice,
    double? progress,
    Object? errorMessage = _unset,
    Object? integrity = _unset,
  }) {
    return OfflineMapState(
      status: status ?? this.status,
      bundledVersion: bundledVersion,
      canManage: canManage,
      manifest: manifest ?? this.manifest,
      installedVersion: identical(installedVersion, _unset)
          ? this.installedVersion
          : installedVersion as int?,
      bytesOnDevice: bytesOnDevice ?? this.bytesOnDevice,
      progress: progress ?? this.progress,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      integrity: identical(integrity, _unset)
          ? this.integrity
          : integrity as MapIntegrity?,
    );
  }
}
