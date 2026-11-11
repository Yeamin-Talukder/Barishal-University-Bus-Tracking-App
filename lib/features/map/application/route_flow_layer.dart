import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/utils/route_geometry.dart';
import '../../../data/models/geo_point.dart';
import 'map_style_service.dart';
import 'stop_map_layer.dart' show mapImageScale;

/// What the map draws about travel along one route: the way it runs, and
/// for a picked bus, how far it has come.
class RouteFlow {
  const RouteFlow({
    required this.color,
    required this.ahead,
    this.done = const [],
    this.drawLines = false,
    this.arrows = true,
    this.name,
  });

  /// The route's colour, as `#RRGGBB`.
  final String color;

  /// The part still to be driven, in the order it is driven. Arrows are
  /// drawn along it.
  final List<GeoPoint> ahead;

  /// The part the bus has already covered. Empty when no bus is picked.
  final List<GeoPoint> done;

  /// Whether this layer draws the line itself (for a picked bus), or only
  /// the arrows on a line something else draws (for a picked route).
  final bool drawLines;

  /// The route's name, written along the line.
  final String? name;

  /// Whether arrows are drawn along [ahead]. Off when the direction of
  /// travel is not known: an arrow would claim one.
  final bool arrows;

  /// The flow for a bus [alongMeters] from the start of [track], going
  /// forwards (start to end) or backwards. The covered part is behind the
  /// bus, the rest ahead.
  factory RouteFlow.forBus({
    required RouteGeometry track,
    required double alongMeters,
    required bool forwards,
    required String color,
    String? name,
  }) {
    final behind = track.slice(0, alongMeters);
    final beyond = track.slice(alongMeters, track.lengthMeters);
    return RouteFlow(
      color: color,
      name: name,
      drawLines: true,
      // Each part in the order the bus drives it.
      done: forwards ? behind : beyond.reversed.toList(),
      ahead: forwards ? beyond : behind.reversed.toList(),
    );
  }
}

/// A stop the picked bus has still to reach, with the minutes until then.
typedef StopTime = ({GeoPoint position, String text});

/// Builds GeoJSON for [RouteFlowLayer]. Kept apart from MapLibre so it can
/// be unit tested.
abstract final class RouteFlowGeoJson {
  static Map<String, dynamic> _line(
    String kind,
    List<GeoPoint> points,
    RouteFlow flow,
  ) => {
    'type': 'Feature',
    'properties': {
      'kind': kind,
      'color': flow.color,
      'draw': flow.drawLines,
      'arrows': flow.arrows,
      'name': ?flow.name,
    },
    'geometry': {
      'type': 'LineString',
      'coordinates': [for (final point in points) point.toGeoJson()],
    },
  };

  static Map<String, dynamic> lines(RouteFlow? flow) => {
    'type': 'FeatureCollection',
    'features': [
      if (flow != null && flow.done.length >= 2) _line('done', flow.done, flow),
      if (flow != null && flow.ahead.length >= 2)
        _line('ahead', flow.ahead, flow),
    ],
  };

  static Map<String, dynamic> times(List<StopTime> times) => {
    'type': 'FeatureCollection',
    'features': [
      for (final time in times)
        {
          'type': 'Feature',
          'properties': {'text': time.text},
          'geometry': {
            'type': 'Point',
            'coordinates': time.position.toGeoJson(),
          },
        },
    ],
  };

  /// Minutes to a stop as written on the map. It is an estimate, so it is
  /// marked "~".
  static String timeText(Duration travelTime) {
    if (travelTime.inSeconds < 60) return '~1 min';
    return '~${(travelTime.inSeconds / 60).round()} min';
  }
}

/// Paints the arrow drawn along a route: a small chevron pointing right,
/// which the map turns to follow the line.
Future<Uint8List> paintRouteArrow({
  required ui.Color ink,
  required ui.Color rim,
}) async {
  const size = RouteFlowLayer.arrowPixels;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(mapImageScale);
  final chevron = ui.Path()
    ..moveTo(size * 0.34, size * 0.22)
    ..lineTo(size * 0.68, size * 0.5)
    ..lineTo(size * 0.34, size * 0.78);
  ui.Paint stroke(ui.Color color, double width) => ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  canvas
    ..drawPath(chevron, stroke(rim, size * 0.3))
    ..drawPath(chevron, stroke(ink, size * 0.16));
  final image = await recorder.endRecording().toImage(
    (size * mapImageScale).toInt(),
    (size * mapImageScale).toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Draws which way a route runs and how far a picked bus has come.
///
/// For a picked route: arrows and the route's name along its line, in the
/// direction being shown. For a picked bus: the covered part of its route
/// faded, the part ahead bold with arrows, and the estimated minutes at
/// each stop still to come.
class RouteFlowLayer {
  static const String lineSource = 'bu-flow-lines';
  static const String timeSource = 'bu-flow-times';

  static const String doneLayer = 'bu-flow-done';
  static const String aheadCasingLayer = 'bu-flow-ahead-casing';
  static const String aheadLayer = 'bu-flow-ahead';
  static const String arrowLayer = 'bu-flow-arrows';
  static const String nameLayer = 'bu-flow-name';
  static const String timeLayer = 'bu-flow-times';

  static const String arrowImage = 'bu-flow-arrow';

  /// Side of the arrow's square image at its design size.
  static const double arrowPixels = 32;

  static List<Object> _byZoom(double at10, double at14, double at18) => [
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

  static const List<Object> _isAhead = [
    '==',
    ['get', 'kind'],
    'ahead',
  ];
  static const List<Object> _isDrawnAhead = [
    'all',
    _isAhead,
    [
      '==',
      ['get', 'draw'],
      true,
    ],
  ];

  /// Adds the sources and layers. Call after every style load, after the
  /// route layers and before the stop and bus layers are needed on top.
  Future<void> attach(
    MapLibreMapController map, {
    required Uint8List arrow,
    required String casingColor,
    required String labelColor,
    required String labelHaloColor,
    required String timeColor,
  }) async {
    await map.addImage(arrowImage, arrow);
    await map.addGeoJsonSource(lineSource, RouteFlowGeoJson.lines(null));
    await map.addGeoJsonSource(timeSource, RouteFlowGeoJson.times(const []));

    // Where the bus has been: still there, but out of the way.
    await map.addLineLayer(
      lineSource,
      doneLayer,
      LineLayerProperties(
        lineColor: const ['get', 'color'],
        lineWidth: _byZoom(2.6, 4.4, 8.0),
        lineCap: 'round',
        lineJoin: 'round',
        lineOpacity: 0.32,
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: const [
        '==',
        ['get', 'kind'],
        'done',
      ],
      enableInteraction: false,
    );
    // Where it is going: bold, like a picked route.
    await map.addLineLayer(
      lineSource,
      aheadCasingLayer,
      LineLayerProperties(
        lineColor: casingColor,
        lineWidth: _byZoom(6.5, 9.5, 17.0),
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: _isDrawnAhead,
      enableInteraction: false,
    );
    await map.addLineLayer(
      lineSource,
      aheadLayer,
      LineLayerProperties(
        lineColor: const ['get', 'color'],
        lineWidth: _byZoom(4.2, 6.0, 12.0),
        lineCap: 'round',
        lineJoin: 'round',
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      filter: _isDrawnAhead,
      enableInteraction: false,
    );
    // Arrows along the way ahead, turned by the map to follow the line.
    await map.addSymbolLayer(
      lineSource,
      arrowLayer,
      const SymbolLayerProperties(
        symbolPlacement: 'line',
        symbolSpacing: 110,
        iconImage: arrowImage,
        iconSize: [
          'interpolate',
          ['linear'],
          ['zoom'],
          11,
          0.3 / mapImageScale,
          14,
          0.42 / mapImageScale,
          18,
          0.72 / mapImageScale,
        ],
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      belowLayerId: MapStyleLayers.firstLabel,
      minzoom: 11,
      filter: const [
        'all',
        _isAhead,
        [
          '==',
          ['get', 'arrows'],
          true,
        ],
      ],
      enableInteraction: false,
    );
    // The route's name along its line, between the arrows.
    await map.addSymbolLayer(
      lineSource,
      nameLayer,
      SymbolLayerProperties(
        symbolPlacement: 'line',
        symbolSpacing: 420,
        textField: const ['get', 'name'],
        textFont: const ['NotoSans-Medium'],
        textSize: 12.5,
        textLetterSpacing: 0.02,
        // Beside the line, not on it, so the arrows stay clear.
        textOffset: const [
          'literal',
          [0, 1.25],
        ],
        textColor: labelColor,
        textHaloColor: labelHaloColor,
        textHaloWidth: 2,
        textKeepUpright: true,
      ),
      minzoom: 12.5,
      filter: const [
        'all',
        _isAhead,
        ['has', 'name'],
      ],
      enableInteraction: false,
    );
    // Minutes to each stop still to come, above the stop.
    await map.addSymbolLayer(
      timeSource,
      timeLayer,
      SymbolLayerProperties(
        textField: const ['get', 'text'],
        textFont: const ['NotoSans-Medium'],
        textSize: 12.5,
        textAnchor: 'bottom',
        textOffset: const [
          'interpolate',
          ['linear'],
          ['zoom'],
          11,
          [
            'literal',
            [0, -0.9],
          ],
          15,
          [
            'literal',
            [0, -1.5],
          ],
          18,
          [
            'literal',
            [0, -2.3],
          ],
        ],
        textColor: timeColor,
        textHaloColor: labelHaloColor,
        textHaloWidth: 2.2,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      minzoom: 11,
      enableInteraction: false,
    );
  }

  /// Replaces the lines and arrows.
  Future<void> update(MapLibreMapController map, RouteFlow? flow) =>
      map.setGeoJsonSource(lineSource, RouteFlowGeoJson.lines(flow));

  /// Replaces the minutes shown at the stops ahead.
  Future<void> updateTimes(MapLibreMapController map, List<StopTime> times) =>
      map.setGeoJsonSource(timeSource, RouteFlowGeoJson.times(times));
}
