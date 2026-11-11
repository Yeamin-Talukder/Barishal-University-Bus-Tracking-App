import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/preferences_service.dart';
import '../data/map_package.dart';
import '../data/map_tile_repository.dart';
import '../domain/offline_map_state.dart';

final mapTileRepositoryProvider = Provider<MapTileRepository>(
  (ref) => createMapTileRepository(),
);

final offlineMapServiceProvider =
    NotifierProvider<OfflineMapService, OfflineMapState>(OfflineMapService.new);

/// Manages the offline map on this device: installing it from the copy
/// bundled with the app, checking it, and removing it.
///
/// The map is installed automatically the first time the app runs, so it
/// works without the user doing anything. If the user removes it, it stays
/// removed until they install it again.
///
/// Nothing here uses the network. Newer map data arrives with app updates;
/// when an update brings a newer package, the status becomes
/// [OfflineMapStatus.needsUpdate] and it is installed on the next launch.
class OfflineMapService extends Notifier<OfflineMapState> {
  /// Set when the user removes the map, so it is not silently put back.
  static const String removedByUserKey = 'map.removedByUser';

  static const String _installFailedMessage =
      'The map could not be saved on this device. Free up some storage and '
      'try again.';

  bool _cancelRequested = false;
  bool _busy = false;

  MapTileRepository get _repository => ref.read(mapTileRepositoryProvider);

  @override
  OfflineMapState build() {
    final repository = ref.watch(mapTileRepositoryProvider);
    Future.microtask(_initialise);
    return OfflineMapState(
      status: OfflineMapStatus.checking,
      bundledVersion: MapPackage.version,
      canManage: repository.canManage,
    );
  }

  Future<void> _initialise() async {
    try {
      final manifest = await _repository.readManifest();
      _update((state) => state.copyWith(manifest: manifest));
      final installation = await _refreshInstallation();

      final removedByUser =
          ref.read(sharedPreferencesProvider).getBool(removedByUserKey) ??
          false;
      if (installation.status != OfflineMapStatus.ready && !removedByUser) {
        await install();
      }
    } catch (error) {
      debugPrint('Offline map check failed: $error');
      _fail(_installFailedMessage);
    }
  }

  /// Installs, resumes or updates the map from the bundled package.
  Future<void> install() async {
    if (_busy) return;
    _busy = true;
    _cancelRequested = false;
    _update(
      (state) => state.copyWith(
        status: OfflineMapStatus.installing,
        progress: 0,
        errorMessage: null,
        integrity: null,
      ),
    );

    try {
      var shown = 0.0;
      await for (final progress in _repository.install(
        isCancelled: () => _cancelRequested,
      )) {
        // Hundreds of small files are copied; only report visible steps.
        if (progress - shown >= 0.01 || progress >= 1) {
          shown = progress;
          _update((state) => state.copyWith(progress: progress));
        }
      }
      if (ref.mounted) {
        await ref
            .read(sharedPreferencesProvider)
            .setBool(removedByUserKey, false);
      }
      await _refreshInstallation();
    } on MapInstallCancelled {
      await _refreshInstallation();
    } catch (error) {
      debugPrint('Offline map install failed: $error');
      _fail(_installFailedMessage);
    } finally {
      _busy = false;
    }
  }

  /// Stops an install that is in progress. What was copied is kept, so a
  /// later install resumes from there.
  void cancelInstall() => _cancelRequested = true;

  /// Checks the installed map against its manifest.
  Future<MapIntegrity?> verify() async {
    if (_busy || !state.isReady) return null;
    _busy = true;
    try {
      final result = await _repository.verify();
      _update((state) => state.copyWith(integrity: result));
      return result;
    } catch (error) {
      debugPrint('Offline map check failed: $error');
      _update((state) => state.copyWith(integrity: MapIntegrity.damaged));
      return MapIntegrity.damaged;
    } finally {
      _busy = false;
    }
  }

  /// Deletes the map from this device. The map screen cannot be used until
  /// it is installed again.
  Future<void> remove() async {
    if (_busy) return;
    _busy = true;
    try {
      await _repository.delete();
      if (ref.mounted) {
        await ref
            .read(sharedPreferencesProvider)
            .setBool(removedByUserKey, true);
      }
      await _refreshInstallation();
    } catch (error) {
      debugPrint('Offline map removal failed: $error');
      _fail('The map could not be removed from this device.');
    } finally {
      _busy = false;
    }
  }

  /// Deletes the installed copy and installs it again, for a damaged map.
  Future<void> reinstall() async {
    if (_busy) return;
    try {
      await _repository.delete();
    } catch (error) {
      debugPrint('Offline map removal failed: $error');
    }
    await install();
  }

  Future<MapInstallation> _refreshInstallation() async {
    final installation = await _repository.inspect();
    _update(
      (state) => state.copyWith(
        status: installation.status,
        installedVersion: installation.installedVersion,
        bytesOnDevice: installation.bytesOnDevice,
        errorMessage: null,
        integrity: installation.status == OfflineMapStatus.ready
            ? state.integrity
            : null,
      ),
    );
    return installation;
  }

  void _fail(String message) {
    _update(
      (state) => state.copyWith(
        status: OfflineMapStatus.failed,
        errorMessage: message,
      ),
    );
  }

  void _update(OfflineMapState Function(OfflineMapState state) change) {
    if (ref.mounted) state = change(state);
  }
}
