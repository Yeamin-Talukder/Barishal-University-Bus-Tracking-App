import 'dart:convert';
import 'dart:io';

import 'package:bu_bus_tracker/core/constants/university_map_configuration.dart';
import 'package:bu_bus_tracker/features/map/application/map_style_service.dart';
import 'package:bu_bus_tracker/features/map/data/map_package.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves the project's real asset files from disk.
class _ProjectBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

/// Layers the Protomaps basemap schema provides.
const _schemaLayers = {
  'earth',
  'water',
  'landuse',
  'landcover',
  'roads',
  'buildings',
  'boundaries',
  'places',
  'pois',
};

const _resources = MapResources(
  basemapUrl: 'pmtiles://file:///data/map/v1/barishal_basemap_v1.pmtiles',
  glyphsUrlTemplate: 'file:///data/map/v1/fonts/{fontstack}/{range}.pbf',
);

Map<String, dynamic> _template(UniversityMapStyle style) =>
    jsonDecode(File(MapStyleService.assetFor(style)).readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> _layers(Map<String, dynamic> style) =>
    (style['layers'] as List).cast<Map<String, dynamic>>();

void main() {
  final service = MapStyleService(bundle: _ProjectBundle());

  for (final style in UniversityMapStyle.values) {
    group('${style.name} style', () {
      final template = _template(style);
      final layers = _layers(template);

      test('is a version 8 style with one local vector source', () {
        expect(template['version'], 8);
        final sources = template['sources'] as Map<String, dynamic>;
        expect(sources.keys, ['basemap']);
        expect(sources['basemap']['type'], 'vector');
        expect(sources['basemap']['url'], MapStyleService.basemapPlaceholder);
        expect(template['glyphs'], MapStyleService.glyphsPlaceholder);
      });

      test('credits OpenStreetMap', () {
        expect(
          template['sources']['basemap']['attribution'],
          contains('OpenStreetMap'),
        );
      });

      test('needs no sprite and no network resource', () {
        expect(template.containsKey('sprite'), isFalse);
        expect(jsonEncode(template), isNot(contains('http')));
      });

      test('only uses fonts that are bundled with the app', () {
        final fonts = {
          for (final layer in layers)
            if (layer['layout'] case {'text-font': final List stack})
              ...stack.cast<String>(),
        };

        expect(fonts, isNotEmpty);
        expect(MapPackage.fonts, containsAll(fonts));
      });

      test('only reads layers that exist in the tile schema', () {
        final used = {
          for (final layer in layers)
            if (layer['source-layer'] case final String name) name,
        };

        expect(_schemaLayers, containsAll(used));
      });

      test('has every layer group the map needs', () {
        final ids = layers.map((layer) => layer['id'] as String).toSet();

        expect(
          ids,
          containsAll([
            'background',
            'water',
            'landuse-park',
            'building',
            'road-minor',
            'road-major',
            'road-arterial',
            'label-road-major',
            'label-place-city',
            MapStyleLayers.firstLabel,
          ]),
        );
      });

      test('layer ids are unique', () {
        final ids = layers.map((layer) => layer['id']).toList();
        expect(ids.toSet(), hasLength(ids.length));
      });

      test('resolves to a style that points at the local map data', () async {
        final resolved = jsonDecode(
          await service.loadStyle(style, _resources),
        ) as Map<String, dynamic>;

        expect(resolved['glyphs'], _resources.glyphsUrlTemplate);
        expect(resolved['sources']['basemap']['url'], _resources.basemapUrl);
        expect(jsonEncode(resolved), isNot(contains('{{')));
        expect(_layers(resolved), hasLength(layers.length));
      });
    });
  }

  test('light and dark have the same layers and differ only in colour', () {
    final light = _layers(_template(UniversityMapStyle.light));
    final dark = _layers(_template(UniversityMapStyle.dark));

    String shape(Map<String, dynamic> layer) => jsonEncode({
      'id': layer['id'],
      'type': layer['type'],
      'source-layer': layer['source-layer'],
      'filter': layer['filter'],
      'minzoom': layer['minzoom'],
      'layout': layer['layout'],
    });

    expect(light.map(shape).toList(), dark.map(shape).toList());
    expect(
      light.first['paint']['background-color'],
      isNot(dark.first['paint']['background-color']),
    );
  });
}
