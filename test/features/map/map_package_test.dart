import 'dart:convert';
import 'dart:io';

import 'package:bu_bus_tracker/core/constants/university_map_configuration.dart';
import 'package:bu_bus_tracker/features/map/data/map_package.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks the bundled offline map package against its manifest and against
/// the app's map configuration, so the data and the code cannot drift apart.
void main() {
  const config = UniversityMapConfiguration.barishal;
  final manifest = jsonDecode(
    File(MapPackage.manifestAsset).readAsStringSync(),
  ) as Map<String, dynamic>;
  final archive = File(MapPackage.archiveAsset);

  test('the archive exists and matches the size in its manifest', () {
    expect(archive.existsSync(), isTrue);
    expect(archive.lengthSync(), manifest['bytes']);
    expect(manifest['file'], MapPackage.archiveAsset.split('/').last);
  });

  test('the archive is a PMTiles version 3 file', () {
    final header = archive.openSync().readSync(8);
    expect(utf8.decode(header.sublist(0, 7)), 'PMTiles');
    expect(header[7], 3);
  });

  test('the archive was built for the configured centre and coverage', () {
    expect(manifest['center']['latitude'], config.centerLatitude);
    expect(manifest['center']['longitude'], config.centerLongitude);

    final bounds = config.coverageBounds;
    expect(manifest['bounds']['south'], closeTo(bounds.south, 1e-9));
    expect(manifest['bounds']['west'], closeTo(bounds.west, 1e-9));
    expect(manifest['bounds']['north'], closeTo(bounds.north, 1e-9));
    expect(manifest['bounds']['east'], closeTo(bounds.east, 1e-9));
  });

  test('tile data covers every zoom the map can show', () {
    // Tiles stop at zoom 15; MapLibre overzooms them up to the map's
    // maximum zoom.
    expect(manifest['minZoom'], lessThanOrEqualTo(config.minZoom));
    expect(manifest['maxZoom'], 15);

    final stored = manifest['tilesPerZoom'] as Map<String, dynamic>;
    final needed = manifest['coverageTilesPerZoom'] as Map<String, dynamic>;
    // The covered rectangle is about 10 by 6 km: a handful of tiles at
    // zoom 14, a few dozen at zoom 15.
    expect(needed['10'] as int, inInclusiveRange(1, 4));
    expect(needed['14'] as int, inInclusiveRange(10, 30));
    expect(needed['15'] as int, inInclusiveRange(40, 80));
    // Every zoom holds at least the coverage, plus the margin kept around it
    // so the map does not end in a straight line at the edge.
    for (var zoom = config.minZoom.toInt(); zoom <= 15; zoom++) {
      expect(
        stored['$zoom'] as int,
        greaterThanOrEqualTo(needed['$zoom'] as int),
        reason: 'zoom $zoom',
      );
    }
    expect(stored['15'] as int, greaterThan(needed['15'] as int));
    expect(manifest['edgeMarginPixels'], greaterThan(0));
  });

  test('every bundled font has a file for all 256 glyph ranges', () {
    for (final font in MapPackage.fonts) {
      final files = Directory('${MapPackage.fontsAssetRoot}$font')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.pbf'));

      expect(files, hasLength(256), reason: font);
    }
  });

  test('the fonts keep the glyphs the map shows and drop the rest', () {
    for (final font in MapPackage.fonts) {
      int size(String range) =>
          File('${MapPackage.fontsAssetRoot}$font/$range.pbf').lengthSync();

      // Latin and general punctuation, in every font.
      expect(size('0-255'), greaterThan(10000), reason: font);
      expect(size('256-511'), greaterThan(10000), reason: font);
      expect(size('8192-8447'), greaterThan(1000), reason: font);
      // Blocks the map area never shows are empty placeholders: present, so
      // a request for them succeeds, but holding no glyphs.
      expect(size('1024-1279'), lessThan(64), reason: font);
      expect(size('19968-20223'), lessThan(64), reason: font);
    }
    // Bangla, in the fonts that have it.
    expect(
      File('${MapPackage.fontsAssetRoot}NotoSans-Regular/2304-2559.pbf')
          .lengthSync(),
      greaterThan(10000),
    );

    final total = MapPackage.fonts
        .expand(
          (font) =>
              Directory('${MapPackage.fontsAssetRoot}$font')
                  .listSync()
                  .whereType<File>(),
        )
        .fold<int>(0, (sum, file) => sum + file.lengthSync());
    expect(total, lessThan(1500000));
  });

  test('every font folder is declared as an asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final font in MapPackage.fonts) {
      expect(pubspec, contains('- ${MapPackage.fontsAssetRoot}$font/'));
    }
  });
}
