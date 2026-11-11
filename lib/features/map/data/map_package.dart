/// The map data bundled with the app: one vector tile archive and the glyph
/// files its labels need.
///
/// The file names carry a version. When the archive is rebuilt with newer
/// OpenStreetMap data, bump the version here and in
/// `tools/map/extract_basemap.py` so installed copies are replaced.
abstract final class MapPackage {
  static const int version = 4;

  /// Everything under this folder is part of the package.
  static const String assetRoot = 'assets/map/';

  static const String archiveAsset =
      'assets/map/barishal_basemap_v$version.pmtiles';
  static const String manifestAsset =
      'assets/map/barishal_basemap_v$version.json';

  static const String fontsAssetRoot = 'assets/map/fonts/';

  /// Font folders in `assets/map/fonts/`. The styles' `text-font` values must
  /// come from this list.
  static const List<String> fonts = [
    'NotoSans-Regular',
    'NotoSans-Medium',
    'NotoSans-Italic',
  ];

  /// The short credit shown on the map. OpenStreetMap's attribution guideline
  /// only requires the name "OpenStreetMap" plus a way to reach the licence,
  /// which tapping the label gives (see [attributionDetail]).
  static const String attribution = '© OpenStreetMap';
  static const String attributionDetail =
      'Map data © OpenStreetMap contributors, available under the Open '
      'Database Licence. Tiles from the Protomaps basemap. Label fonts: Noto '
      'Sans, SIL Open Font Licence.';
}

/// Where MapLibre should read the map data from on this device.
class MapResources {
  const MapResources({
    required this.basemapUrl,
    required this.glyphsUrlTemplate,
  });

  /// URL of the vector tile archive, in the form MapLibre expects for a
  /// PMTiles source.
  final String basemapUrl;

  /// Glyph URL with MapLibre's `{fontstack}` and `{range}` tokens.
  final String glyphsUrlTemplate;
}
