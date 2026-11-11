import '../domain/offline_map_state.dart';
import 'map_package.dart';
import 'map_tile_repository_stub.dart'
    if (dart.library.io) 'map_tile_repository_io.dart'
    if (dart.library.js_interop) 'map_tile_repository_web.dart'
    as platform;

/// Thrown by [MapTileRepository.install] when the caller cancels it.
class MapInstallCancelled implements Exception {
  const MapInstallCancelled();
}

/// Stores the offline map data on the device and says where MapLibre can
/// read it.
///
/// On Android and iOS the native map engine cannot read files inside the
/// Flutter asset bundle, so the bundled package is copied to app storage and
/// read from there. On web (development preview only) it is read in place and
/// there is nothing to manage.
abstract interface class MapTileRepository {
  /// False on web, where the map is not stored by the app.
  bool get canManage;

  /// Reads the manifest of the map package bundled with the app.
  Future<MapPackageManifest> readManifest();

  /// Looks at what is installed on the device right now.
  Future<MapInstallation> inspect();

  /// Copies the bundled map package into app storage, reporting progress
  /// from 0 to 1.
  ///
  /// Files that are already present and complete are not copied again, so
  /// an interrupted install resumes where it stopped. [isCancelled] is
  /// checked between files; when it returns true the stream ends with
  /// [MapInstallCancelled] and what was copied so far is kept.
  Stream<double> install({required bool Function() isCancelled});

  /// Checks the installed archive against the manifest's SHA-256 and that
  /// every glyph file is present.
  Future<MapIntegrity> verify();

  /// Deletes all map data from app storage.
  Future<void> delete();

  /// Where MapLibre should read the installed map from. Only valid while
  /// the map is installed.
  Future<MapResources> resources();
}

MapTileRepository createMapTileRepository() =>
    platform.createMapTileRepository();
