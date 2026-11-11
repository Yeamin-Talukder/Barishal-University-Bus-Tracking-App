import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../data/models/bus_stop.dart';

/// Draws the bus-stop sign: a pole with a plate on it, and a small bus on
/// the plate. The same drawing is used on the map and in the app's lists.
///
/// [unit] is the size of one design unit: the sign is drawn for a badge 60
/// units across, centred on [centre]. [cutout] is the badge's own colour,
/// used for the bus on the plate.
void drawStopSign(
  ui.Canvas canvas,
  ui.Offset centre,
  double unit, {
  required Color ink,
  required Color cutout,
}) {
  ui.RRect box(double left, double top, double right, double bottom, double r) {
    return ui.RRect.fromLTRBR(
      centre.dx + left * unit,
      centre.dy + top * unit,
      centre.dx + right * unit,
      centre.dy + bottom * unit,
      ui.Radius.circular(r * unit),
    );
  }

  final inkPaint = ui.Paint()
    ..color = ink
    ..isAntiAlias = true;
  final cutPaint = ui.Paint()
    ..color = cutout
    ..isAntiAlias = true;

  canvas
    // The pole and its foot.
    ..drawRRect(box(-16, -19, -11, 19, 2.5), inkPaint)
    ..drawRRect(box(-21, 15, -6, 20, 2.5), inkPaint)
    // The plate.
    ..drawRRect(box(-13, -19, 19, 6, 5), inkPaint)
    // The bus on the plate: a windscreen and two headlights.
    ..drawRRect(box(-7, -14, 13, -5, 2.5), cutPaint)
    ..drawCircle(centre.translate(-4 * unit, 0.5 * unit), 2.2 * unit, cutPaint)
    ..drawCircle(centre.translate(10 * unit, 0.5 * unit), 2.2 * unit, cutPaint);
}

/// How many image pixels the map's marker pictures have for each pixel of
/// their design size. The map is told to draw them that much smaller.
const double mapImageScale = 3;

/// Paints a stop's badge for the map: a rounded square in [body] with a
/// [rim] around it, a soft shadow, and the bus-stop sign in [ink].
Future<Uint8List> paintStopBadge({
  required Color body,
  required Color rim,
  required Color ink,
}) async {
  const size = StopFocusLayer.iconPixels;
  const centre = ui.Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  // Drawn at several times its size, so it stays sharp on a phone's dense
  // screen and when the map shows it large.
  final canvas = ui.Canvas(recorder)..scale(mapImageScale);

  ui.RRect square(double side, double radius, [double dy = 0]) =>
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: centre.translate(0, dy),
          width: side,
          height: side,
        ),
        ui.Radius.circular(radius),
      );

  canvas
    ..drawRRect(
      square(70, 23, 3),
      ui.Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    )
    ..drawRRect(square(70, 23), ui.Paint()..color = rim)
    ..drawRRect(square(60, 18), ui.Paint()..color = body);
  drawStopSign(canvas, centre, 1, ink: ink, cutout: body);

  final image = await recorder.endRecording().toImage(
    (size * mapImageScale).toInt(),
    (size * mapImageScale).toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The stop the passenger picked, drawn on top of the ordinary stops: its
/// badge pops up to a larger size, and a ring keeps rippling out from it.
class StopFocusLayer {
  static const String source = 'bu-stop-focus';
  static const String rippleLayer = 'bu-stop-focus-ripple';
  static const String iconLayer = 'bu-stop-focus-icon';
  static const String iconName = 'bu-stop-icon-selected';

  /// Side of the square badge images at their design size. The pictures
  /// themselves are [mapImageScale] times larger.
  static const double iconPixels = 128;

  /// How long the badge takes to pop up when a stop is picked.
  static const Duration popDuration = Duration(milliseconds: 450);

  /// How long one ripple takes.
  static const int ripplePeriodMs = 1800;

  /// The picked stop's badge at rest, as a fraction of its design size.
  static const double restingScale = 0.92;

  /// How large the badge is [sinceSelected] after the stop was picked, as a
  /// fraction of its resting size: it starts small, swells a little past
  /// full size and settles.
  static double popScale(Duration sinceSelected) {
    final t = (sinceSelected.inMicroseconds / popDuration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    const overshoot = 2.4;
    final eased =
        1 +
        (overshoot + 1) * math.pow(t - 1, 3) +
        overshoot * math.pow(t - 1, 2);
    return 0.4 + 0.6 * eased;
  }

  /// Whether the badge is still popping up.
  static bool isPopping(Duration sinceSelected) => sinceSelected < popDuration;

  static const Map<String, dynamic> _empty = {
    'type': 'FeatureCollection',
    'features': <Object>[],
  };

  /// The picked [stop] as GeoJSON, or nothing when no stop is picked.
  ///
  /// [ripple] runs from 0 to 1 again and again and drives the ring.
  static Map<String, dynamic> geoJson(
    BusStop? stop, {
    Duration sinceSelected = popDuration,
    double ripple = 0,
  }) {
    if (stop == null) return _empty;
    final eased = 1 - math.pow(1 - ripple.clamp(0.0, 1.0), 2).toDouble();
    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {
            'id': stop.id,
            'scale': restingScale * popScale(sinceSelected),
            'rippleRadius': 26 + 28 * eased,
            'rippleOpacity': 0.38 * (1 - eased),
          },
          'geometry': {
            'type': 'Point',
            'coordinates': stop.position.toGeoJson(),
          },
        },
      ],
    };
  }

  /// Adds the image, the source and the layers. Call after every style
  /// load. [icon] comes from [paintStopBadge]; [color] is the ripple's.
  Future<void> attach(
    MapLibreMapController map, {
    required Uint8List icon,
    required String color,
  }) async {
    await map.addImage(iconName, icon);
    await map.addGeoJsonSource(source, _empty);
    await map.addCircleLayer(
      source,
      rippleLayer,
      CircleLayerProperties(
        circleRadius: const ['get', 'rippleRadius'],
        circleColor: color,
        circleOpacity: const ['get', 'rippleOpacity'],
      ),
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      source,
      iconLayer,
      const SymbolLayerProperties(
        iconImage: iconName,
        iconSize: [
          '/',
          ['get', 'scale'],
          mapImageScale,
        ],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
  }

  /// Replaces what is drawn.
  Future<void> update(
    MapLibreMapController map,
    Map<String, dynamic> geoJson,
  ) => map.setGeoJsonSource(source, geoJson);
}
