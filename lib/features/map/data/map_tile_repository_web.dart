import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../domain/offline_map_state.dart';
import 'map_package.dart';
import 'map_tile_repository.dart';

MapTileRepository createMapTileRepository() => WebMapTileRepository();

@JS('pmtiles.Protocol')
extension type _PmTilesProtocol._(JSObject _) implements JSObject {
  external _PmTilesProtocol();
  external JSFunction get tile;
}

@JS('pmtiles')
external JSAny? get _pmTilesLibrary;

@JS('maplibregl.addProtocol')
external void _addProtocol(JSString scheme, JSFunction loader);

/// Web development preview: reads the map data straight from the app's asset
/// URLs, so there is nothing to install or remove. Needs the `pmtiles` script
/// that `web/index.html` loads.
class WebMapTileRepository implements MapTileRepository {
  Future<MapResources>? _resources;

  @override
  bool get canManage => false;

  @override
  Future<MapPackageManifest> readManifest() async {
    final json = jsonDecode(
      await rootBundle.loadString(MapPackage.manifestAsset),
    );
    return MapPackageManifest.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<MapInstallation> inspect() async => const MapInstallation(
    status: OfflineMapStatus.ready,
    installedVersion: MapPackage.version,
  );

  @override
  Stream<double> install({required bool Function() isCancelled}) async* {
    yield 1;
  }

  @override
  Future<MapIntegrity> verify() async => MapIntegrity.verified;

  @override
  Future<void> delete() async {}

  @override
  Future<MapResources> resources() => _resources ??= _register();

  Future<MapResources> _register() async {
    await MapLibreMap.ensureWebLibraryLoaded();
    if (_pmTilesLibrary == null) {
      throw StateError(
        'The pmtiles script is missing from web/index.html, so the map '
        'archive cannot be read.',
      );
    }
    _addProtocol('pmtiles'.toJS, _PmTilesProtocol().tile);

    return MapResources(
      basemapUrl: 'pmtiles://${_assetUrl(MapPackage.archiveAsset)}',
      glyphsUrlTemplate:
          '${_assetUrl(MapPackage.fontsAssetRoot)}{fontstack}/{range}.pbf',
    );
  }

  /// Flutter web serves the asset `a/b.c` at `<app base>/assets/a/b.c`.
  String _assetUrl(String asset) =>
      Uri.base.resolve('assets/$asset').toString();
}
