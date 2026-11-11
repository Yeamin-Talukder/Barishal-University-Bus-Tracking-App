import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../data/models/geo_point.dart';
import '../../prediction/domain/prediction.dart';
import 'stop_map_layer.dart' show mapImageScale;

/// Paints the marker of a predicted bus: a badge with a broken ring and a
/// see-through middle, so it reads as "about here", never as a live bus.
Future<Uint8List> paintPredictedBadge({
  required Color color,
  required Color paper,
}) async {
  const size = PredictedBusLayer.iconPixels;
  const centre = ui.Offset(size / 2, size / 2);
  const radius = 30.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(mapImageScale);

  canvas
    // A veil of the map's own colour, so the pictogram can be read.
    ..drawCircle(centre, radius + 3, ui.Paint()..color = paper.withAlpha(215))
    ..drawCircle(centre, radius, ui.Paint()..color = color.withAlpha(46));

  // The ring, in twelve dashes.
  final ring = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 4.5
    ..strokeCap = ui.StrokeCap.round;
  const dashes = 12;
  for (var i = 0; i < dashes; i++) {
    canvas.drawArc(
      ui.Rect.fromCircle(center: centre, radius: radius),
      i * 2 * math.pi / dashes,
      2 * math.pi / dashes * 0.55,
      false,
      ring,
    );
  }

  // The bus, seen from the front, in outline colour.
  final ink = ui.Paint()..color = color;
  final gap = ui.Paint()..color = paper;
  canvas
    ..drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: centre.translate(0, -1),
          width: 28,
          height: 30,
        ),
        const ui.Radius.circular(7),
      ),
      ink,
    )
    ..drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: centre.translate(0, -6),
          width: 20,
          height: 10,
        ),
        const ui.Radius.circular(3),
      ),
      gap,
    )
    ..drawCircle(centre.translate(-7, 7), 2.4, gap)
    ..drawCircle(centre.translate(7, 7), 2.4, gap);

  final image = await recorder.endRecording().toImage(
    (size * mapImageScale).toInt(),
    (size * mapImageScale).toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The predicted buses on the map: where a bus probably is, from the
/// timetable or from where it was last seen. They are drawn under the live
/// buses, in their own style, and their label says "about".
class PredictedBusLayer {
  static const String source = 'bu-predicted-buses';
  static const String badgeLayer = 'bu-predicted-badge';
  static const String labelLayer = 'bu-predicted-label';
  static const String iconName = 'bu-predicted-icon';

  /// Side of the square image at its design size.
  static const double iconPixels = 128;

  /// Layers a tap is tested against.
  static const List<String> tappableLayers = [badgeLayer, labelLayer];

  static const Map<String, dynamic> _empty = {
    'type': 'FeatureCollection',
    'features': <Object>[],
  };

  /// The name under a predicted bus. The buses the timetable names for
  /// the departure, when they fit under a marker: passengers know a bus by
  /// its name. A long list ("one of these six") gives way to the route.
  static String markerName(PredictedBus bus) {
    final named = bus.vehicles?.trim() ?? '';
    return bus.basis == PredictionBasis.timetable &&
            named.isNotEmpty &&
            named.length <= 24
        ? named
        : bus.label;
  }

  /// The predicted buses as GeoJSON. [positionOf] lets the caller set a
  /// bus to the side of the road with its route's line.
  static Map<String, dynamic> geoJson(
    List<PredictedBus> buses, {
    GeoPoint Function(PredictedBus bus)? positionOf,
  }) {
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final bus in buses)
          {
            'type': 'Feature',
            'properties': {
              'id': bus.id,
              'routeId': bus.routeId,
              // "~" for "about": this is not where the bus was reported.
              'label': '~ ${markerName(bus)}',
            },
            'geometry': {
              'type': 'Point',
              'coordinates': (positionOf?.call(bus) ?? bus.position)
                  .toGeoJson(),
            },
          },
      ],
    };
  }

  /// Adds the image, the source and the layers. Call after every style
  /// load, before the live buses are added so they draw on top.
  Future<void> attach(
    MapLibreMapController map, {
    required Uint8List icon,
    required String labelColor,
    required String haloColor,
  }) async {
    await map.addImage(iconName, icon);
    await map.addGeoJsonSource(source, _empty);
    await map.addSymbolLayer(
      source,
      badgeLayer,
      const SymbolLayerProperties(
        iconImage: iconName,
        iconSize: 0.62 / mapImageScale,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      source,
      labelLayer,
      SymbolLayerProperties(
        textField: const ['get', 'label'],
        textFont: const ['NotoSans-Italic'],
        textSize: 12.5,
        textAnchor: 'top',
        textOffset: const [
          'literal',
          [0, 2.2],
        ],
        textColor: labelColor,
        textHaloColor: haloColor,
        textHaloWidth: 2,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
  }

  /// Replaces the markers.
  Future<void> update(
    MapLibreMapController map,
    Map<String, dynamic> geoJson,
  ) => map.setGeoJsonSource(source, geoJson);
}
