import 'dart:async';

import 'package:bu_bus_tracker/core/services/preferences_service.dart';
import 'package:bu_bus_tracker/features/map/application/offline_map_service.dart';
import 'package:bu_bus_tracker/features/map/data/map_package.dart';
import 'package:bu_bus_tracker/features/map/domain/offline_map_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fakes.dart';

const _notInstalled = MapInstallation(status: OfflineMapStatus.notInstalled);

Future<ProviderContainer> _container(
  FakeMapTileRepository repository, {
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      mapTileRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  // Keep the service alive for the whole test.
  container.listen(offlineMapServiceProvider, (_, _) {});
  return container;
}

/// Lets the service finish whatever it started.
Future<void> _settle() => pumpEventQueue();

OfflineMapState _state(ProviderContainer container) =>
    container.read(offlineMapServiceProvider);

OfflineMapService _service(ProviderContainer container) =>
    container.read(offlineMapServiceProvider.notifier);

bool? _removedByUser(ProviderContainer container) => container
    .read(sharedPreferencesProvider)
    .getBool(OfflineMapService.removedByUserKey);

void main() {
  group('at startup', () {
    test('starts in the checking state', () async {
      final container = await _container(FakeMapTileRepository());

      expect(_state(container).status, OfflineMapStatus.checking);
      expect(_state(container).bundledVersion, MapPackage.version);
    });

    test('an installed map is ready and is not installed again', () async {
      final repository = FakeMapTileRepository();
      final container = await _container(repository);
      await _settle();

      final state = _state(container);
      expect(state.status, OfflineMapStatus.ready);
      expect(state.installedVersion, MapPackage.version);
      expect(state.bytesOnDevice, installedMap.bytesOnDevice);
      expect(state.manifest?.tileCount, 1051);
      expect(repository.installCalls, 0);
    });

    test('installs the map automatically on first run', () async {
      final repository = FakeMapTileRepository(installation: _notInstalled);
      final container = await _container(repository);
      await _settle();

      expect(_state(container).status, OfflineMapStatus.ready);
      expect(repository.installCalls, 1);
    });

    test('resumes an interrupted install automatically', () async {
      final repository = FakeMapTileRepository(
        installation: const MapInstallation(
          status: OfflineMapStatus.interrupted,
        ),
      );
      final container = await _container(repository);
      await _settle();

      expect(_state(container).status, OfflineMapStatus.ready);
      expect(repository.installCalls, 1);
    });

    test('updates an older installed map automatically', () async {
      final repository = FakeMapTileRepository(
        installation: const MapInstallation(
          status: OfflineMapStatus.needsUpdate,
          installedVersion: 0,
        ),
      );
      final container = await _container(repository);
      await _settle();

      expect(_state(container).status, OfflineMapStatus.ready);
      expect(_state(container).installedVersion, MapPackage.version);
    });

    test('does not put back a map the user removed', () async {
      final repository = FakeMapTileRepository(installation: _notInstalled);
      final container = await _container(
        repository,
        preferences: {OfflineMapService.removedByUserKey: true},
      );
      await _settle();

      expect(_state(container).status, OfflineMapStatus.notInstalled);
      expect(repository.installCalls, 0);
    });

    test('reports where the map cannot be managed', () async {
      final container = await _container(
        FakeMapTileRepository(canManage: false),
      );
      await _settle();

      expect(_state(container).canManage, isFalse);
      expect(_state(container).isReady, isTrue);
    });
  });

  group('install', () {
    test('reports progress while installing', () async {
      final repository = FakeMapTileRepository(installation: _notInstalled)
        ..installGate = Completer<void>();
      final container = await _container(repository);
      await _settle();

      expect(_state(container).status, OfflineMapStatus.installing);
      expect(_state(container).progress, 0.5);

      repository.installGate!.complete();
      await _settle();
      expect(_state(container).status, OfflineMapStatus.ready);
    });

    test('a failure is reported with a message and can be retried', () async {
      final repository = FakeMapTileRepository(
        installation: _notInstalled,
        installError: Exception('disk full'),
      );
      final container = await _container(repository);
      await _settle();

      expect(_state(container).status, OfflineMapStatus.failed);
      expect(_state(container).errorMessage, contains('Free up some storage'));
      // The technical error is not shown to the user.
      expect(_state(container).errorMessage, isNot(contains('disk full')));

      repository.installError = null;
      await _service(container).install();

      expect(_state(container).status, OfflineMapStatus.ready);
      expect(_state(container).errorMessage, isNull);
    });

    test('cancelling leaves the install interrupted, then resumable', () async {
      final repository = FakeMapTileRepository(installation: _notInstalled)
        ..installGate = Completer<void>();
      final container = await _container(repository);
      await _settle();

      _service(container).cancelInstall();
      repository.installGate!.complete();
      await _settle();
      expect(_state(container).status, OfflineMapStatus.interrupted);

      repository.installGate = null;
      await _service(container).install();
      expect(_state(container).status, OfflineMapStatus.ready);
    });

    test('a second install while one is running is ignored', () async {
      final repository = FakeMapTileRepository(installation: _notInstalled)
        ..installGate = Completer<void>();
      final container = await _container(repository);
      await _settle();

      await _service(container).install();
      expect(repository.installCalls, 1);

      repository.installGate!.complete();
      await _settle();
    });
  });

  group('remove', () {
    test('deletes the map and remembers that the user chose to', () async {
      final repository = FakeMapTileRepository();
      final container = await _container(repository);
      await _settle();

      await _service(container).remove();

      expect(_state(container).status, OfflineMapStatus.notInstalled);
      expect(_state(container).bytesOnDevice, 0);
      expect(repository.deleteCalls, 1);
      expect(_removedByUser(container), isTrue);
    });

    test('installing again clears the removed flag', () async {
      final repository = FakeMapTileRepository();
      final container = await _container(repository);
      await _settle();
      await _service(container).remove();

      await _service(container).install();

      expect(_state(container).status, OfflineMapStatus.ready);
      expect(_removedByUser(container), isFalse);
    });
  });

  group('verify', () {
    test('records a complete map as verified', () async {
      final container = await _container(FakeMapTileRepository());
      await _settle();

      final result = await _service(container).verify();

      expect(result, MapIntegrity.verified);
      expect(_state(container).integrity, MapIntegrity.verified);
    });

    test('records a damaged map, and reinstalling repairs it', () async {
      final repository = FakeMapTileRepository(integrity: MapIntegrity.damaged);
      final container = await _container(repository);
      await _settle();

      expect(await _service(container).verify(), MapIntegrity.damaged);
      expect(_state(container).integrity, MapIntegrity.damaged);

      await _service(container).reinstall();

      expect(repository.deleteCalls, 1);
      expect(repository.installCalls, 1);
      expect(_state(container).status, OfflineMapStatus.ready);
      expect(_state(container).integrity, isNull);
    });

    test('does nothing when no map is installed', () async {
      final repository = FakeMapTileRepository(installation: _notInstalled);
      final container = await _container(
        repository,
        preferences: {OfflineMapService.removedByUserKey: true},
      );
      await _settle();

      expect(await _service(container).verify(), isNull);
      expect(repository.verifyCalls, 0);
    });
  });
}
