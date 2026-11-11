import 'dart:async';

import 'package:bu_bus_tracker/core/services/connectivity_service.dart';
import 'package:bu_bus_tracker/core/services/location_service.dart';
import 'package:bu_bus_tracker/core/constants/university_map_configuration.dart';
import 'package:bu_bus_tracker/features/map/data/map_package.dart';
import 'package:bu_bus_tracker/features/map/data/map_tile_repository.dart';
import 'package:bu_bus_tracker/features/map/domain/offline_map_state.dart';

const MapPackageManifest sampleManifest = MapPackageManifest(
  bytes: 4038841,
  sha256: 'abc123',
  sourceBuild: '20261110.pmtiles',
  minZoom: 8,
  maxZoom: 15,
  tileCount: 1051,
  bounds: GeoBounds(south: 22.638, west: 90.326, north: 22.732, east: 90.389),
);

const MapInstallation installedMap = MapInstallation(
  status: OfflineMapStatus.ready,
  installedVersion: MapPackage.version,
  bytesOnDevice: 15309209,
);

/// An in-memory stand-in for the on-device map store.
class FakeMapTileRepository implements MapTileRepository {
  FakeMapTileRepository({
    this.installation = installedMap,
    this.canManage = true,
    this.integrity = MapIntegrity.verified,
    this.installError,
  });

  MapInstallation installation;
  MapIntegrity integrity;

  /// When set, [install] fails with this error.
  Object? installError;

  /// When set, [install] waits for it before finishing, so a test can act
  /// while the install is in progress.
  Completer<void>? installGate;

  int installCalls = 0;
  int deleteCalls = 0;
  int verifyCalls = 0;

  @override
  final bool canManage;

  @override
  Future<MapPackageManifest> readManifest() async => sampleManifest;

  @override
  Future<MapInstallation> inspect() async => installation;

  @override
  Stream<double> install({required bool Function() isCancelled}) async* {
    installCalls++;
    final error = installError;
    if (error != null) throw error;

    yield 0;
    yield 0.5;
    await installGate?.future;
    if (isCancelled()) {
      installation = const MapInstallation(
        status: OfflineMapStatus.interrupted,
        bytesOnDevice: 7000000,
      );
      throw const MapInstallCancelled();
    }
    yield 1;
    installation = installedMap;
  }

  @override
  Future<MapIntegrity> verify() async {
    verifyCalls++;
    return integrity;
  }

  @override
  Future<void> delete() async {
    deleteCalls++;
    installation = const MapInstallation(status: OfflineMapStatus.notInstalled);
  }

  @override
  Future<MapResources> resources() async => const MapResources(
    basemapUrl: 'pmtiles://file:///map/barishal.pmtiles',
    glyphsUrlTemplate: 'file:///map/fonts/{fontstack}/{range}.pbf',
  );
}

/// A connection that tests can switch on and off.
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({this._connected = true});

  bool _connected;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  void setConnected(bool connected) {
    _connected = connected;
    _changes.add(connected);
  }

  @override
  Future<bool> hasConnection() async => _connected;

  @override
  Stream<bool> get onConnectionChanged => _changes.stream;
}

/// A location service that returns a fixed answer.
class FakeLocationService implements LocationService {
  FakeLocationService(this.result);

  LocationResult result;
  final List<LocationProblem> openedSettingsFor = [];

  @override
  Future<LocationResult> currentLocation() async => result;

  @override
  Future<void> openSettingsFor(LocationProblem problem) async {
    openedSettingsFor.add(problem);
  }
}
