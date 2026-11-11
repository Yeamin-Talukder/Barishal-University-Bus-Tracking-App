import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/offline_map_state.dart';
import 'map_package.dart';
import 'map_tile_repository.dart';

MapTileRepository createMapTileRepository() => InstalledMapTileRepository(
  bundle: rootBundle,
  storageDirectory: getApplicationSupportDirectory,
);

/// Keeps the map package in app storage, under `<storage>/map/v<version>/`.
///
/// A marker file is written last, so a copy that stopped half-way is seen as
/// interrupted rather than trusted.
class InstalledMapTileRepository implements MapTileRepository {
  InstalledMapTileRepository({
    required this._bundle,
    required this._storageDirectory,
  });

  static const String markerFileName = '.installed';
  static final RegExp _versionFolder = RegExp(r'^v(\d+)$');

  final AssetBundle _bundle;
  final Future<Directory> Function() _storageDirectory;

  @override
  bool get canManage => true;

  Future<Directory> _mapRoot() async =>
      Directory('${(await _storageDirectory()).path}/map');

  Directory _versionDirectory(Directory mapRoot) =>
      Directory('${mapRoot.path}/v${MapPackage.version}');

  File _marker(Directory versionDirectory) =>
      File('${versionDirectory.path}/$markerFileName');

  @override
  Future<MapPackageManifest> readManifest() async {
    final json = jsonDecode(await _bundle.loadString(MapPackage.manifestAsset));
    return MapPackageManifest.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<MapInstallation> inspect() async {
    final mapRoot = await _mapRoot();
    if (!mapRoot.existsSync()) {
      return const MapInstallation(status: OfflineMapStatus.notInstalled);
    }

    final bytes = await _sizeOf(mapRoot);
    final current = _versionDirectory(mapRoot);
    if (_marker(current).existsSync()) {
      return MapInstallation(
        status: OfflineMapStatus.ready,
        installedVersion: MapPackage.version,
        bytesOnDevice: bytes,
      );
    }
    if (current.existsSync()) {
      return MapInstallation(
        status: OfflineMapStatus.interrupted,
        bytesOnDevice: bytes,
      );
    }

    final older = await _installedOlderVersion(mapRoot);
    if (older != null) {
      return MapInstallation(
        status: OfflineMapStatus.needsUpdate,
        installedVersion: older,
        bytesOnDevice: bytes,
      );
    }
    return MapInstallation(
      status: OfflineMapStatus.notInstalled,
      bytesOnDevice: bytes,
    );
  }

  @override
  Stream<double> install({required bool Function() isCancelled}) async* {
    final mapRoot = await _mapRoot();
    final target = _versionDirectory(mapRoot);
    final assets = await _packageAssets();

    yield 0;
    for (var i = 0; i < assets.length; i++) {
      if (isCancelled()) throw const MapInstallCancelled();

      final data = await _bundle.load(assets[i]);
      final file = _targetFile(target, assets[i]);
      // Skip files a previous attempt already copied in full.
      final alreadyCopied =
          file.existsSync() && file.lengthSync() == data.lengthInBytes;
      if (!alreadyCopied) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      yield (i + 1) / assets.length;
    }

    await _marker(target).writeAsString('${MapPackage.version}');
    await _removeOtherVersions(mapRoot);
  }

  @override
  Future<MapIntegrity> verify() async {
    final target = _versionDirectory(await _mapRoot());
    if (!_marker(target).existsSync()) return MapIntegrity.damaged;

    final manifest = await readManifest();
    final archive = _targetFile(target, MapPackage.archiveAsset);
    if (!archive.existsSync() || archive.lengthSync() != manifest.bytes) {
      return MapIntegrity.damaged;
    }
    final archivePath = archive.path;
    final digest = await Isolate.run(
      () => sha256.convert(File(archivePath).readAsBytesSync()).toString(),
    );
    if (digest != manifest.sha256) return MapIntegrity.damaged;

    for (final asset in await _packageAssets()) {
      final file = _targetFile(target, asset);
      if (!file.existsSync() || file.lengthSync() == 0) {
        return MapIntegrity.damaged;
      }
    }
    return MapIntegrity.verified;
  }

  @override
  Future<void> delete() async {
    final mapRoot = await _mapRoot();
    if (mapRoot.existsSync()) await mapRoot.delete(recursive: true);
  }

  @override
  Future<MapResources> resources() async {
    final target = _versionDirectory(await _mapRoot());
    final archive = _targetFile(target, MapPackage.archiveAsset);
    final fonts = '${target.path}/${_relative(MapPackage.fontsAssetRoot)}';
    return MapResources(
      basemapUrl: 'pmtiles://${Uri.file(archive.path)}',
      // Built by hand: Uri would escape MapLibre's {fontstack}/{range} tokens.
      glyphsUrlTemplate: 'file://$fonts{fontstack}/{range}.pbf',
    );
  }

  /// Every bundled asset that belongs to the map package, in a stable order.
  Future<List<String>> _packageAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    return manifest
        .listAssets()
        .where((asset) => asset.startsWith(MapPackage.assetRoot))
        .toList()
      ..sort();
  }

  Future<int?> _installedOlderVersion(Directory mapRoot) async {
    int? newest;
    await for (final entry in mapRoot.list()) {
      final match = _versionFolder.firstMatch(_name(entry));
      if (entry is! Directory || match == null) continue;
      if (!_marker(entry).existsSync()) continue;
      final version = int.parse(match.group(1)!);
      if (newest == null || version > newest) newest = version;
    }
    return newest;
  }

  /// Deletes map folders left behind by other package versions.
  Future<void> _removeOtherVersions(Directory mapRoot) async {
    const current = 'v${MapPackage.version}';
    await for (final entry in mapRoot.list()) {
      if (entry is Directory && _name(entry) != current) {
        await entry.delete(recursive: true);
      }
    }
  }

  Future<int> _sizeOf(Directory directory) async {
    var total = 0;
    await for (final entry in directory.list(recursive: true)) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }

  /// Folder or file name. Compared by name because full paths can differ in
  /// separators.
  String _name(FileSystemEntity entry) =>
      entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);

  File _targetFile(Directory target, String asset) =>
      File('${target.path}/${_relative(asset)}');

  String _relative(String asset) =>
      asset.substring(MapPackage.assetRoot.length);
}
