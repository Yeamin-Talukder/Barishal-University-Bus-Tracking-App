import 'dart:math' as math;
import 'dart:typed_data';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/utils/geo_math.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/models/transport_network.dart';
import 'map_selection.dart';
import 'map_style_service.dart';
import 'stop_map_layer.dart' show mapImageScale;

/// Colours for the route and stop layers that depend on the map theme.
class TransportLayerColors {
  const TransportLayerColors({
    required this.routeCasing,
    required this.stopFill,
    required this.stopStroke,
    required this.selection,
    required this.label,
    required this.labelHalo,
    this.nearest,
  });

  /// Ring drawn around the stop nearest to the passenger. Defaults to
  /// [selection].
  final String? nearest;

  final String routeCasing;
  final String stopFill;
  final String stopStroke;

  /// Ring drawn around the selected stop.
  final String selection;
  final String label;
  final String labelHalo;
}

/// Builds GeoJSON for the transport layers. Kept apart from MapLibre so it
/// can be unit tested.
abstract final class TransportGeoJson {
  /// The lane of the route at [index] out of [count]: 0 is the middle of
  /// the road, -1 one line-width to the left, 1 one to the right.
  ///
  /// Routes that share a road are drawn side by side in their lanes, like
  /// on a transit map, so none of them hides another. Every route keeps
  /// its lane for its whole length.
  static double laneOf(int index, int count) =>
      (index - (count - 1) / 2).clamp(-2.0, 2.0);

  /// The pattern drawn down the middle of the route at [index], so routes
  /// can be told apart without relying on colour: 0 is a plain line, 1 has
  /// dashes, 2 has dots. With more than three routes the patterns repeat,
  /// each time with a different colour.
  static int patternOf(int index) => index % 3;

  /// A stub no longer than this is left out of the drawn line.
  static const double longestStubMeters = 25;

  /// [path] without its stubs: places where the line leaves the road for a
  /// few metres and comes straight back the same way.
  ///
  /// Road routing makes these where a stop sits just off the road. They
  /// are part of the saved path, but drawn they are only a blob on the
  /// line, and a spike once routes are set side by side. Only the drawing
  /// changes: the road the route follows, and everything worked out from
  /// the saved path, stays as it is. A real there-and-back along a road is
  /// far longer than a stub and is kept.
  static List<GeoPoint> withoutStubs(List<GeoPoint> path) {
    double between(GeoPoint a, GeoPoint b) => haversineDistanceMeters(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );

    var points = path;
    // Twice, so a stub with one bend in it goes too, but no more than
    // that: a long there-and-back must never be eaten from its tip.
    for (var pass = 0; pass < 2; pass++) {
      final kept = <GeoPoint>[];
      var i = 0;
      while (i < points.length) {
        final isStubTip =
            kept.isNotEmpty &&
            i + 1 < points.length &&
            between(kept.last, points[i + 1]) < 1 &&
            between(kept.last, points[i]) <= longestStubMeters;
        if (isStubTip) {
          // Skip the tip and the point that returns to where we were.
          i += 2;
        } else {
          kept.add(points[i]);
          i += 1;
        }
      }
      if (kept.length == points.length) break;
      points = kept;
    }
    return points;
  }

  static Map<String, dynamic> routes(TransportNetwork network) {
    final count = network.routes.length;
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final (index, route) in network.routes.indexed)
          {
            'type': 'Feature',
            'id': route.id,
            'properties': {
              'id': route.id,
              'name': route.name,
              'color': route.colorHex,
              'active': route.isActive,
              'lane': laneOf(index, count),
              'pattern': patternOf(index),
            },
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final point in withoutStubs(route.path)) point.toGeoJson(),
              ],
            },
          },
      ],
    };
  }

  static Map<String, dynamic> stops(TransportNetwork network) {
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final stop in network.stops)
          {
            'type': 'Feature',
            'id': stop.id,
            'properties': {'id': stop.id, 'name': stop.name},
            'geometry': {
              'type': 'Point',
              'coordinates': stop.position.toGeoJson(),
            },
          },
      ],
    };
  }
}

/// Works out which routes and stops each layer should draw for a selection.
///
/// Selection is expressed purely as layer filters, so changing it never
/// rebuilds the map or reloads its data.
abstract final class TransportLayerFilters {
  /// Matches every feature.
  static const List<Object> all = ['has', 'id'];

  /// Matches no feature.
  static const List<Object> none = ['!', all];

  static List<Object> _only(Iterable<String> ids) => [
    'in',
    ['get', 'id'],
    ['literal', ids.toList()],
  ];

  static List<Object> _pattern(int pattern) => [
    '==',
    ['get', 'pattern'],
    pattern,
  ];

  /// The filter for each transport layer, by layer id.
  ///
  /// [busRouteId] is the route of the bus that is picked, if one is. Its
  /// line is then drawn by the layer that shows how far the bus has come,
  /// so the plain line is left out here, and the other routes fade back.
  static Map<String, List<Object>> forSelection(
    TransportNetwork network,
    MapSelection selection, {
    String? busRouteId,
  }) {
    final route = selection.routeId == null
        ? null
        : network.routeById(selection.routeId!);
    final busRoute = route == null && busRouteId != null
        ? network.routeById(busRouteId)
        : null;

    if (busRoute != null) {
      final onlyRoute = _only([busRoute.id]);
      final routeStops = _only(busRoute.stopIds);
      final terminals = busRoute.stopIds.isEmpty
          ? none
          : _only({busRoute.stopIds.first, busRoute.stopIds.last});
      return {
        TransportMapLayers.routeDimLayer: ['!', onlyRoute],
        TransportMapLayers.routeCasingLayer: none,
        TransportMapLayers.routeLineLayer: none,
        TransportMapLayers.routeDashLayer: none,
        TransportMapLayers.routeDotLayer: none,
        TransportMapLayers.routeFocusGlowLayer: onlyRoute,
        TransportMapLayers.routeFocusCasingLayer: none,
        TransportMapLayers.routeFocusLineLayer: none,
        TransportMapLayers.routeFocusDashLayer: none,
        TransportMapLayers.routeFocusDotLayer: none,
        TransportMapLayers.stopDotLayer: routeStops,
        TransportMapLayers.stopIconLayer: routeStops,
        TransportMapLayers.stopLabelLayer: routeStops,
        TransportMapLayers.stopTerminalLayer: terminals,
        TransportMapLayers.stopSelectedLayer: none,
      };
    }
    final stop = selection.stopId == null
        ? null
        : network.stopById(selection.stopId!);

    if (route != null) {
      // One route in focus: it is drawn in full with its own stops, the
      // other routes fade back.
      final onlyRoute = _only([route.id]);
      final routeStops = _only(route.stopIds);
      final terminals = route.stopIds.isEmpty
          ? none
          : _only({route.stopIds.first, route.stopIds.last});
      return {
        TransportMapLayers.routeDimLayer: ['!', onlyRoute],
        TransportMapLayers.routeCasingLayer: none,
        TransportMapLayers.routeLineLayer: none,
        TransportMapLayers.routeDashLayer: none,
        TransportMapLayers.routeDotLayer: none,
        TransportMapLayers.routeFocusGlowLayer: onlyRoute,
        TransportMapLayers.routeFocusCasingLayer: onlyRoute,
        TransportMapLayers.routeFocusLineLayer: onlyRoute,
        TransportMapLayers.routeFocusDashLayer: ['all', onlyRoute, _pattern(1)],
        TransportMapLayers.routeFocusDotLayer: ['all', onlyRoute, _pattern(2)],
        TransportMapLayers.stopDotLayer: routeStops,
        TransportMapLayers.stopIconLayer: routeStops,
        TransportMapLayers.stopLabelLayer: routeStops,
        TransportMapLayers.stopTerminalLayer: terminals,
        TransportMapLayers.stopSelectedLayer: none,
      };
    }

    return {
      TransportMapLayers.routeDimLayer: none,
      TransportMapLayers.routeCasingLayer: all,
      TransportMapLayers.routeLineLayer: all,
      TransportMapLayers.routeDashLayer: _pattern(1),
      TransportMapLayers.routeDotLayer: _pattern(2),
      TransportMapLayers.routeFocusGlowLayer: none,
      TransportMapLayers.routeFocusCasingLayer: none,
      TransportMapLayers.routeFocusLineLayer: none,
      TransportMapLayers.routeFocusDashLayer: none,
      TransportMapLayers.routeFocusDotLayer: none,
      TransportMapLayers.stopDotLayer: all,
      TransportMapLayers.stopIconLayer: all,
      TransportMapLayers.stopLabelLayer: all,
      TransportMapLayers.stopTerminalLayer: none,
      TransportMapLayers.stopSelectedLayer: stop == null
          ? none
          : _only([stop.id]),
    };
  }
}

/// Draws bus routes and stops on the map as their own sources and layers,
/// separate from the base map.
///
/// MapLibre drops added sources and layers whenever the style changes, so
/// [attach] must run again after every style load.
class TransportMapLayers {
  static const String routeSource = 'bu-routes';
  static const String stopSource = 'bu-stops';

  static const String routeDimLayer = 'bu-route-dim';
  static const String routeCasingLayer = 'bu-route-casing';
  static const String routeLineLayer = 'bu-route-line';
  static const String routeFocusGlowLayer = 'bu-route-focus-glow';
  static const String routeFocusCasingLayer = 'bu-route-focus-casing';
  static const String routeFocusLineLayer = 'bu-route-focus-line';

  /// The pattern down the middle of a route: dashes or dots.
  static const String routeDashLayer = 'bu-route-dash';
  static const String routeDotLayer = 'bu-route-dot';
  static const String routeFocusDashLayer = 'bu-route-focus-dash';
  static const String routeFocusDotLayer = 'bu-route-focus-dot';

  /// A ring round the stop nearest to the passenger.
  static const String stopNearestLayer = 'bu-stop-nearest';
  static const String stopSelectedLayer = 'bu-stop-selected';
  static const String stopDotLayer = 'bu-stop-dot';
  static const String stopIconLayer = 'bu-stop-icon';
  static const String stopTerminalLayer = 'bu-stop-terminal';
  static const String stopLabelLayer = 'bu-stop-label';

  static const String stopIconImage = 'bu-stop-icon-plain';

  /// Below this zoom a stop is a dot; from here on it is a bus-stop badge.
  static const double stopIconsFromZoom = 13;

  /// Layers a tap on the map is tested against, stops first.
  static const List<String> tappableStopLayers = [
    stopTerminalLayer,
    stopIconLayer,
    stopDotLayer,
    stopLabelLayer,
  ];
  static const List<String> tappableRouteLayers = [
    routeFocusLineLayer,
    routeLineLayer,
    routeDimLayer,
  ];

  /// A number that grows with the zoom, through three fixed points.
  static List<Object> _byZoom(Object at10, Object at14, Object at18) => [
    'interpolate',
    ['exponential', 1.5],
    ['zoom'],
    10,
    at10,
    14,
    at14,
    18,
    at18,
  ];

  // With every route showing, each is a slim line in its own lane.
  // They stay thick enough to be seen from city level.
  static final List<Object> _laneWidth = _byZoom(2.8, 3.8, 6.0);
  static final List<Object> _laneCasingWidth = _byZoom(4.4, 6.2, 9.0);

  /// How far a lane sits from the middle of the road: the line's width
  /// plus a hairline of casing between neighbours.
  static final List<Object> _laneOffset = _byZoom(
    const [
      '*',
      ['get', 'lane'],
      3.4,
    ],
    const [
      '*',
      ['get', 'lane'],
      4.8,
    ],
    const [
      '*',
      ['get', 'lane'],
      7.4,
    ],
  );

  /// How far, in screen pixels, one lane is from the middle of the road at
  /// [zoom]: the same numbers the route lines are drawn with.
  static double laneOffsetPixels(double zoom) {
    const stops = [(10.0, 3.4), (14.0, 4.8), (18.0, 7.4)];
    if (zoom <= stops.first.$1) return stops.first.$2;
    if (zoom >= stops.last.$1) return stops.last.$2;
    final upper = stops.indexWhere((stop) => zoom < stop.$1);
    final (z0, v0) = stops[upper - 1];
    final (z1, v1) = stops[upper];
    // The map's own "exponential 1.5" interpolation.
    const base = 1.5;
    final t = (math.pow(base, zoom - z0) - 1) / (math.pow(base, z1 - z0) - 1);
    return v0 + (v1 - v0) * t;
  }

  /// Where to draw something that is on a route's line at [onLine], so that
  /// it sits on the line as drawn in [lane] rather than on the middle of
  /// the road.
  ///
  /// [lineBearingDegrees] is the line's direction there, from the route's
  /// start to its end. A lane to the right of the middle is positive, as
  /// for the lines themselves.
  static GeoPoint inLane(
    GeoPoint onLine, {
    required double lineBearingDegrees,
    required double lane,
    required double zoom,
  }) {
    if (lane == 0) return onLine;
    final latitude = degreesToRadians(onLine.latitude);
    // The map's tiles are 512 pixels across.
    final metersPerPixel = 78271.51696 * math.cos(latitude) / math.pow(2, zoom);
    final meters = lane * laneOffsetPixels(zoom) * metersPerPixel;
    final toTheRight = degreesToRadians(lineBearingDegrees + 90);
    return GeoPoint(
      onLine.latitude + meters * math.cos(toTheRight) / metersPerDegreeLatitude,
      onLine.longitude +
          meters *
              math.sin(toTheRight) /
              (metersPerDegreeLatitude * math.cos(latitude)),
    );
  }

  // The route in focus is bold, on the middle of the road, with a glow.
  static final List<Object> _focusWidth = _byZoom(4.6, 6.0, 12.0);
  static final List<Object> _focusCasingWidth = _byZoom(7.0, 9.5, 17.0);
  static final List<Object> _focusGlowWidth = _byZoom(12.0, 20.0, 34.0);

  static const List<Object> _stopRadius = [
    'interpolate',
    ['linear'],
    ['zoom'],
    11,
    2.4,
    14,
    4.6,
    18,
    7.5,
  ];
  static const List<Object> _stopStrokeWidth = [
    'interpolate',
    ['linear'],
    ['zoom'],
    11,
    1.2,
    14,
    2.2,
    18,
    3,
  ];

  /// Size of a stop's badge by zoom. The numbers are fractions of the
  /// badge's design size, where the badge is about 70 pixels across: it
  /// grows from 25 pixels to 60 as the passenger zooms in.
  static const List<Object> _stopIconSize = [
    'interpolate',
    ['linear'],
    ['zoom'],
    13,
    0.36 / mapImageScale,
    15,
    0.54 / mapImageScale,
    17,
    0.74 / mapImageScale,
    18,
    0.86 / mapImageScale,
  ];
  static const List<Object> _terminalIconSize = [
    'interpolate',
    ['linear'],
    ['zoom'],
    11,
    0.4 / mapImageScale,
    13,
    0.5 / mapImageScale,
    15,
    0.7 / mapImageScale,
    18,
    1.0 / mapImageScale,
  ];

  /// How far below a stop its name sits, so it clears the badge at every
  /// size.
  static const List<Object> _stopLabelOffset = [
    'interpolate',
    ['linear'],
    ['zoom'],
    13,
    [
      'literal',
      [0, 1.35],
    ],
    15,
    [
      'literal',
      [0, 1.8],
    ],
    18,
    [
      'literal',
      [0, 2.7],
    ],
  ];

  /// Adds the sources and layers to a freshly loaded style.
  Future<void> attach(
    MapLibreMapController map,
    TransportNetwork network,
    MapSelection selection,
    TransportLayerColors colors, {
    required Uint8List stopIcon,
    String? busRouteId,
  }) async {
    final filters = TransportLayerFilters.forSelection(
      network,
      selection,
      busRouteId: busRouteId,
    );

    await map.addImage(stopIconImage, stopIcon);

    await map.addGeoJsonSource(routeSource, TransportGeoJson.routes(network));
    await map.addGeoJsonSource(stopSource, TransportGeoJson.stops(network));

    // Routes that are not the selected one: slim and faded, in their lanes.
    await map.addLineLayer(
      routeSource,
      routeDimLayer,
      LineLayerProperties(
        lineColor: const ['get', 'color'],
        lineWidth: _laneWidth,
        lineOffset: _laneOffset,
        lineCap: 'round',
        lineJoin: 'round',
        lineOpacity: 0.28,
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeDimLayer],
      enableInteraction: false,
    );
    // Every route side by side. All the casings go down first, so one
    // route's casing never covers its neighbour's colour.
    await map.addLineLayer(
      routeSource,
      routeCasingLayer,
      LineLayerProperties(
        lineColor: colors.routeCasing,
        lineWidth: _laneCasingWidth,
        lineOffset: _laneOffset,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeCasingLayer],
      enableInteraction: false,
    );
    await map.addLineLayer(
      routeSource,
      routeLineLayer,
      LineLayerProperties(
        lineColor: const ['get', 'color'],
        lineWidth: _laneWidth,
        lineOffset: _laneOffset,
        lineCap: 'round',
        lineJoin: 'round',
        // Routes that are not running stay visible but recede.
        lineOpacity: const [
          'case',
          ['get', 'active'],
          1.0,
          0.35,
        ],
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeLineLayer],
      enableInteraction: false,
    );
    // A pattern down the middle of every second and third route, in the
    // casing's colour, so routes differ by more than their colour.
    await map.addLineLayer(
      routeSource,
      routeDashLayer,
      LineLayerProperties(
        lineColor: colors.routeCasing,
        lineWidth: _byZoom(0.9, 1.25, 2.0),
        lineOffset: _laneOffset,
        lineDasharray: const [3.2, 3.2],
        lineCap: 'butt',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      minzoom: 11.5,
      filter: filters[routeDashLayer],
      enableInteraction: false,
    );
    await map.addLineLayer(
      routeSource,
      routeDotLayer,
      LineLayerProperties(
        lineColor: colors.routeCasing,
        lineWidth: _byZoom(1.2, 1.7, 2.6),
        lineOffset: _laneOffset,
        // A dash of almost no length with round ends is a dot.
        lineDasharray: const [0.01, 2.8],
        lineCap: 'round',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      minzoom: 11.5,
      filter: filters[routeDotLayer],
      enableInteraction: false,
    );
    // The selected route: a soft glow in its colour, a casing, the line.
    await map.addLineLayer(
      routeSource,
      routeFocusGlowLayer,
      LineLayerProperties(
        lineColor: const ['get', 'color'],
        lineWidth: _focusGlowWidth,
        lineBlur: _byZoom(6.0, 10.0, 16.0),
        lineCap: 'round',
        lineJoin: 'round',
        lineOpacity: 0.3,
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeFocusGlowLayer],
      enableInteraction: false,
    );
    await map.addLineLayer(
      routeSource,
      routeFocusCasingLayer,
      LineLayerProperties(
        lineColor: colors.routeCasing,
        lineWidth: _focusCasingWidth,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeFocusCasingLayer],
      enableInteraction: false,
    );
    await map.addLineLayer(
      routeSource,
      routeFocusLineLayer,
      LineLayerProperties(
        lineColor: const ['get', 'color'],
        lineWidth: _focusWidth,
        lineCap: 'round',
        lineJoin: 'round',
        lineOpacity: const [
          'case',
          ['get', 'active'],
          1.0,
          0.45,
        ],
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeFocusLineLayer],
      enableInteraction: false,
    );
    await map.addLineLayer(
      routeSource,
      routeFocusDashLayer,
      LineLayerProperties(
        lineColor: colors.routeCasing,
        lineWidth: _byZoom(1.4, 1.9, 3.8),
        lineDasharray: const [3.2, 3.2],
        lineCap: 'butt',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeFocusDashLayer],
      enableInteraction: false,
    );
    await map.addLineLayer(
      routeSource,
      routeFocusDotLayer,
      LineLayerProperties(
        lineColor: colors.routeCasing,
        lineWidth: _byZoom(1.8, 2.5, 4.8),
        lineDasharray: const [0.01, 2.8],
        lineCap: 'round',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: filters[routeFocusDotLayer],
      enableInteraction: false,
    );
    // A ring round the stop nearest to the passenger.
    await map.addCircleLayer(
      stopSource,
      stopNearestLayer,
      CircleLayerProperties(
        circleRadius: const [
          'interpolate',
          ['linear'],
          ['zoom'],
          11,
          9,
          14,
          17,
          18,
          30,
        ],
        circleColor: colors.nearest ?? colors.selection,
        circleOpacity: 0.14,
        circleStrokeColor: colors.nearest ?? colors.selection,
        circleStrokeWidth: 2.5,
      ),
      filter: _nearestFilter(),
      enableInteraction: false,
    );
    // A halo behind the selected stop.
    await map.addCircleLayer(
      stopSource,
      stopSelectedLayer,
      CircleLayerProperties(
        circleRadius: 20,
        circleColor: colors.selection,
        circleOpacity: 0.16,
      ),
      filter: filters[stopSelectedLayer],
      enableInteraction: false,
    );
    // Seen from far away a stop is a clean white dot with a dark ring,
    // readable on any route colour...
    await map.addCircleLayer(
      stopSource,
      stopDotLayer,
      CircleLayerProperties(
        circleRadius: _stopRadius,
        circleColor: colors.stopFill,
        circleStrokeColor: colors.stopStroke,
        circleStrokeWidth: _stopStrokeWidth,
      ),
      minzoom: 11,
      maxzoom: stopIconsFromZoom,
      filter: filters[stopDotLayer],
      enableInteraction: false,
    );
    // ...and closer in, a bus-stop badge.
    await map.addSymbolLayer(
      stopSource,
      stopIconLayer,
      const SymbolLayerProperties(
        iconImage: stopIconImage,
        iconSize: _stopIconSize,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      minzoom: stopIconsFromZoom,
      filter: filters[stopIconLayer],
      enableInteraction: false,
    );
    // The first and last stop of the selected route: a larger badge, at
    // every zoom.
    await map.addSymbolLayer(
      stopSource,
      stopTerminalLayer,
      const SymbolLayerProperties(
        iconImage: stopIconImage,
        iconSize: _terminalIconSize,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      filter: filters[stopTerminalLayer],
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      stopSource,
      stopLabelLayer,
      SymbolLayerProperties(
        textField: const ['get', 'name'],
        textFont: const ['NotoSans-Medium'],
        textSize: const [
          'interpolate',
          ['linear'],
          ['zoom'],
          13,
          11.5,
          16,
          13.5,
        ],
        textAnchor: 'top',
        textOffset: _stopLabelOffset,
        textMaxWidth: 8,
        textLetterSpacing: 0.01,
        textColor: colors.label,
        textHaloColor: colors.labelHalo,
        textHaloWidth: 2,
        textHaloBlur: 0.5,
      ),
      minzoom: 13,
      filter: filters[stopLabelLayer],
      enableInteraction: false,
    );
  }

  /// Replaces the data of already attached layers.
  Future<void> update(
    MapLibreMapController map,
    TransportNetwork network,
  ) async {
    await map.setGeoJsonSource(routeSource, TransportGeoJson.routes(network));
    await map.setGeoJsonSource(stopSource, TransportGeoJson.stops(network));
  }

  /// Shows [selection] by changing which features each layer draws.
  /// [busRouteId] is the route of the picked bus, if a bus is picked.
  Future<void> applySelection(
    MapLibreMapController map,
    TransportNetwork network,
    MapSelection selection, {
    String? busRouteId,
  }) async {
    final filters = TransportLayerFilters.forSelection(
      network,
      selection,
      busRouteId: busRouteId,
    );
    for (final MapEntry(key: layerId, value: filter) in filters.entries) {
      await map.setLayerFilter(layerId, filter);
    }
  }

  /// The stop that has the "nearest to you" ring, remembered so the ring
  /// comes back after the map's style is loaded again.
  String? _nearestStopId;

  List<Object> _nearestFilter() => _nearestStopId == null
      ? TransportLayerFilters.none
      : [
          '==',
          ['get', 'id'],
          _nearestStopId!,
        ];

  /// Rings the stop nearest to the passenger, or none when [stopId] is
  /// null. [attached] says whether the layers are on the map yet; if not,
  /// the ring is drawn when they are.
  Future<void> showNearestStop(
    MapLibreMapController? map,
    String? stopId, {
    required bool attached,
  }) async {
    _nearestStopId = stopId;
    if (map == null || !attached) return;
    await map.setLayerFilter(stopNearestLayer, _nearestFilter());
  }
}
