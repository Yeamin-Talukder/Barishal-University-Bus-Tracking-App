import 'dart:io';

import 'package:bu_bus_tracker/features/map/data/map_package.dart';
import 'package:bu_bus_tracker/features/map/data/map_tile_repository.dart';
import 'package:bu_bus_tracker/features/map/data/map_tile_repository_io.dart';
import 'package:bu_bus_tracker/features/map/domain/offline_map_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the on-device map store against the real bundled map package,
/// writing into a temporary folder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;
  late InstalledMapTileRepository repository;

  Directory installed() =>
      Directory('${storage.path}/map/v${MapPackage.version}');
  File marker() =>
      File('${installed().path}/${InstalledMapTileRepository.markerFileName}');
  File archive() =>
      File('${installed().path}/${MapPackage.archiveAsset.split('/').last}');
  File glyph() => File('${installed().path}/fonts/NotoSans-Regular/0-255.pbf');

  Future<List<double>> install({bool Function()? isCancelled}) =>
      repository.install(isCancelled: isCancelled ?? () => false).toList();

  setUp(() {
    storage = Directory.systemTemp.createTempSync('bu_map_test');
    repository = InstalledMapTileRepository(
      bundle: rootBundle,
      storageDirectory: () async => storage,
    );
  });

  tearDown(() {
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  test('reads the bundled manifest', () async {
    final manifest = await repository.readManifest();

    expect(manifest.bytes, File(MapPackage.archiveAsset).lengthSync());
    expect(manifest.sha256, hasLength(64));
    expect(manifest.dataDate, isNotNull);
    expect(manifest.bounds.south, 22.643);
    expect(manifest.bounds.east, 90.385);
  });

  group('inspect', () {
    test('nothing on the device is not installed', () async {
      final installation = await repository.inspect();

      expect(installation.status, OfflineMapStatus.notInstalled);
      expect(installation.bytesOnDevice, 0);
    });

    test('a finished install is ready, with its size', () async {
      await install();

      final installation = await repository.inspect();

      expect(installation.status, OfflineMapStatus.ready);
      expect(installation.installedVersion, MapPackage.version);
      expect(
        installation.bytesOnDevice,
        inInclusiveRange(2 * 1024 * 1024, 6 * 1024 * 1024),
      );
    });

    test('a copy without its marker is interrupted', () async {
      await install();
      marker().deleteSync();

      expect((await repository.inspect()).status, OfflineMapStatus.interrupted);
    });

    test('only an older version on the device needs an update', () async {
      final old = Directory('${storage.path}/map/v0')
        ..createSync(recursive: true);
      File('${old.path}/${InstalledMapTileRepository.markerFileName}')
          .writeAsStringSync('0');

      final installation = await repository.inspect();

      expect(installation.status, OfflineMapStatus.needsUpdate);
      expect(installation.installedVersion, 0);
    });
  });

  group('install', () {
    test(
      'copies the archive and every glyph file, reporting progress',
      () async {
        final progress = await install();

        expect(progress.first, 0);
        expect(progress.last, 1);
        expect(progress, orderedEquals([...progress]..sort()));
        expect(
          archive().lengthSync(),
          File(MapPackage.archiveAsset).lengthSync(),
        );
        for (final font in MapPackage.fonts) {
          final glyphs = Directory('${installed().path}/fonts/$font')
              .listSync();
          expect(glyphs, hasLength(256), reason: font);
        }
        expect(marker().existsSync(), isTrue);
      },
    );

    test('resuming copies only what is missing or incomplete', () async {
      await install();
      marker().deleteSync();
      // One file lost, one cut short, one complete but altered.
      glyph().deleteSync();
      final cutShort = File(
        '${installed().path}/fonts/NotoSans-Medium/0-255.pbf',
      )..writeAsStringSync('partial');
      final untouched = File(
        '${installed().path}/fonts/NotoSans-Italic/0-255.pbf',
      );
      final sameLength = List<int>.filled(untouched.lengthSync(), 7);
      untouched.writeAsBytesSync(sameLength);

      await install();

      expect(glyph().lengthSync(), greaterThan(1000));
      expect(cutShort.lengthSync(), greaterThan(1000));
      // A file of the right size is not copied again.
      expect(untouched.readAsBytesSync(), sameLength);
      expect(marker().existsSync(), isTrue);
    });

    test('cancelling stops the copy and leaves it interrupted', () async {
      var checks = 0;

      await expectLater(
        install(isCancelled: () => ++checks > 5),
        throwsA(isA<MapInstallCancelled>()),
      );

      expect(marker().existsSync(), isFalse);
      expect((await repository.inspect()).status, OfflineMapStatus.interrupted);
    });

    test('removes map data left by an older version', () async {
      final old = Directory('${storage.path}/map/v0')
        ..createSync(recursive: true);
      File('${old.path}/old.pmtiles').writeAsStringSync('old');

      await install();

      expect(old.existsSync(), isFalse);
      expect(installed().existsSync(), isTrue);
    });
  });

  group('verify', () {
    test('a complete install is verified against the manifest hash', () async {
      await install();

      expect(await repository.verify(), MapIntegrity.verified);
    });

    test('an archive with altered contents is damaged', () async {
      await install();
      final bytes = archive().readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0xFF;
      archive().writeAsBytesSync(bytes);

      expect(await repository.verify(), MapIntegrity.damaged);
    });

    test('a missing glyph file is damaged', () async {
      await install();
      glyph().deleteSync();

      expect(await repository.verify(), MapIntegrity.damaged);
    });

    test('nothing installed is damaged', () async {
      expect(await repository.verify(), MapIntegrity.damaged);
    });
  });

  test('delete removes all map data', () async {
    await install();

    await repository.delete();

    expect(Directory('${storage.path}/map').existsSync(), isFalse);
    expect((await repository.inspect()).status, OfflineMapStatus.notInstalled);
  });

  test('returns local URLs in the form MapLibre expects', () async {
    await install();

    final resources = await repository.resources();

    expect(resources.basemapUrl, startsWith('pmtiles://file:///'));
    expect(resources.basemapUrl, endsWith('.pmtiles'));
    expect(resources.glyphsUrlTemplate, startsWith('file://'));
    expect(
      resources.glyphsUrlTemplate,
      endsWith('/fonts/{fontstack}/{range}.pbf'),
    );
  });
}
