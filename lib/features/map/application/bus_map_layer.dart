import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/geo_point.dart';
import 'stop_map_layer.dart' show mapImageScale;

/// Colours for the bus markers, as CSS hex strings.
class BusMarkerColors {
  const BusMarkerColors({
    required this.live,
    required this.delayed,
    required this.offline,
    required this.outline,
    required this.selection,
    required this.label,
    required this.labelHalo,
  });

  final String live;
  final String delayed;
  final String offline;
  final String outline;
  final String selection;
  final String label;
  final String labelHalo;

  String of(BusTrackingStatus status) => switch (status) {
    BusTrackingStatus.live => live,
    BusTrackingStatus.delayed => delayed,
    BusTrackingStatus.offline => offline,
  };
}

/// The colour to draw on top of a badge of colour [body] so it can be read.
Color busBadgeInk(Color body) => body.computeLuminance() > 0.45
    ? AppColors.darkBackground
    : const Color(0xFFFFFFFF);

Future<Uint8List> _png(ui.PictureRecorder recorder) async {
  const size = BusMapLayer.iconPixels;
  final image = await recorder.endRecording().toImage(
    (size * mapImageScale).toInt(),
    (size * mapImageScale).toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Paints the bus badge: a round pin in the status colour with a white rim,
/// a soft shadow and a white bus pictogram. It always stays upright.
Future<Uint8List> paintBusBadge({required Color body}) async {
  const size = BusMapLayer.iconPixels;
  const centre = ui.Offset(size / 2, size / 2);
  const radius = BusMapLayer.badgeRadiusPixels;
  const white = Color(0xFFFFFFFF);
  // The pictogram: white, or dark when the status colour itself is light
  // (as it is in the dark theme).
  final ink = busBadgeInk(body);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(mapImageScale);

  // Shadow, a little below the pin.
  canvas
    ..drawCircle(
      centre.translate(0, 3),
      radius + 3,
      ui.Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    )
    ..drawCircle(centre, radius + 5, ui.Paint()..color = white)
    ..drawCircle(centre, radius, ui.Paint()..color = body);

  // The bus, seen from the front.
  final busBody = ui.RRect.fromRectAndCorners(
    ui.Rect.fromCenter(center: centre.translate(0, -1), width: 30, height: 32),
    topLeft: const ui.Radius.circular(8),
    topRight: const ui.Radius.circular(8),
    bottomLeft: const ui.Radius.circular(5),
    bottomRight: const ui.Radius.circular(5),
  );
  final paintWhite = ui.Paint()..color = ink;
  final paintBody = ui.Paint()..color = body;
  canvas
    ..drawRRect(busBody, paintWhite)
    // Windscreen.
    ..drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: centre.translate(0, -6),
          width: 22,
          height: 11,
        ),
        const ui.Radius.circular(3),
      ),
      paintBody,
    )
    // Headlights.
    ..drawCircle(centre.translate(-8, 8), 2.6, paintBody)
    ..drawCircle(centre.translate(8, 8), 2.6, paintBody)
    // Wheels.
    ..drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: centre.translate(-9, 17),
          width: 7,
          height: 6,
        ),
        const ui.Radius.circular(2),
      ),
      paintWhite,
    )
    ..drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: centre.translate(9, 17),
          width: 7,
          height: 6,
        ),
        const ui.Radius.circular(2),
      ),
      paintWhite,
    );
  return _png(recorder);
}

/// Paints the direction pointer: a small wedge that sits just outside the
/// badge, pointing up. The map turns it to the bus's heading, so it circles
/// the badge like a compass needle.
Future<Uint8List> paintBusPointer({required Color body}) async {
  const size = BusMapLayer.iconPixels;
  const centre = size / 2;
  const white = Color(0xFFFFFFFF);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(mapImageScale);

  // Tip at the top, base tucked under the badge's rim.
  const tipY = centre - BusMapLayer.badgeRadiusPixels - 21;
  const baseY = centre - BusMapLayer.badgeRadiusPixels + 2;
  final wedge = ui.Path()
    ..moveTo(centre, tipY)
    ..lineTo(centre + 15, baseY)
    ..quadraticBezierTo(centre, baseY - 7, centre - 15, baseY)
    ..close();
  canvas
    ..drawPath(
      wedge,
      ui.Paint()
        ..color = const Color(0x44000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    )
    ..drawPath(
      wedge,
      ui.Paint()
        ..color = white
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = ui.StrokeJoin.round,
    )
    ..drawPath(wedge, ui.Paint()..color = body);
  return _png(recorder);
}

/// The buses drawn on the map: one marker per bus that has reported a
/// position.
///
/// A marker is a round badge in the colour of the bus's status. A live bus
/// has a soft ring pulsing around it. When the direction of travel can be
/// trusted, a pointer on the badge's rim shows it; otherwise there is no
/// pointer, because one would claim a direction the app does not have. A
/// bus with no position gets no marker at all.
class BusMapLayer {
  static const String source = 'bu-buses';
  static const String pulseLayer = 'bu-bus-pulse';
  static const String selectedLayer = 'bu-bus-selected';
  static const String pointerLayer = 'bu-bus-pointer';
  static const String badgeLayer = 'bu-bus-badge';
  static const String labelLayer = 'bu-bus-label';

  /// Side of the square images at their design size; they are drawn on
  /// the map at half of it. The pictures themselves are [mapImageScale]
  /// times larger, so they stay sharp on a dense screen.
  static const double iconPixels = 128;
  static const double badgeRadiusPixels = 30;

  /// How large the markers are drawn, as a fraction of their design size:
  /// the badge is about 52 pixels across, easy to see and to tap.
  static const double markerScale = 0.74;

  /// Layers a tap is tested against.
  static const List<String> tappableLayers = [badgeLayer, labelLayer];

  static String badgeName(BusTrackingStatus status) =>
      'bu-bus-badge-${status.name}';
  static String pointerName(BusTrackingStatus status) =>
      'bu-bus-pointer-${status.name}';

  /// The markers as GeoJSON.
  ///
  /// [statusOf] says how fresh each position is. [headingOf] gives the
  /// direction of travel when it can be trusted. [positionOf] lets the
  /// caller draw a bus part-way between two reported positions while it
  /// glides. [pulse] runs from 0 to 1 again and again and drives the ring
  /// around live buses.
  static Map<String, dynamic> geoJson(
    List<TrackedBus> buses, {
    required BusTrackingStatus Function(TrackedBus bus) statusOf,
    required double? Function(TrackedBus bus) headingOf,
    required BusMarkerColors colors,
    GeoPoint Function(TrackedBus bus)? positionOf,
    String? selectedBusId,
    double pulse = 0,
  }) {
    // The ring grows and fades; easing out makes it breathe, not blink.
    final eased = 1 - math.pow(1 - pulse.clamp(0.0, 1.0), 2).toDouble();
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final tracked in buses)
          if (tracked.location != null)
            {
              'type': 'Feature',
              'properties': {
                'id': tracked.bus.id,
                'number': tracked.bus.number,
                'color': colors.of(statusOf(tracked)),
                'badge': badgeName(statusOf(tracked)),
                'pointer': pointerName(statusOf(tracked)),
                'selected': tracked.bus.id == selectedBusId,
                'heading': ?headingOf(tracked),
                if (statusOf(tracked) == BusTrackingStatus.live) ...{
                  'pulseRadius': 30 + 28 * eased,
                  'pulseOpacity': 0.32 * (1 - eased),
                },
              },
              'geometry': {
                'type': 'Point',
                'coordinates':
                    (positionOf?.call(tracked) ?? tracked.location!.position)
                        .toGeoJson(),
              },
            },
      ],
    };
  }

  static const Map<String, dynamic> _empty = {
    'type': 'FeatureCollection',
    'features': <Object>[],
  };

  /// Adds the images, the source and the layers. Call after every style
  /// load. [badges] and [pointers] come from [paintBusBadge] and
  /// [paintBusPointer].
  Future<void> attach(
    MapLibreMapController map,
    BusMarkerColors colors, {
    required Map<BusTrackingStatus, Uint8List> badges,
    required Map<BusTrackingStatus, Uint8List> pointers,
  }) async {
    for (final MapEntry(key: status, value: bytes) in badges.entries) {
      await map.addImage(badgeName(status), bytes);
    }
    for (final MapEntry(key: status, value: bytes) in pointers.entries) {
      await map.addImage(pointerName(status), bytes);
    }
    await map.addGeoJsonSource(source, _empty);

    // The breathing ring around a live bus.
    await map.addCircleLayer(
      source,
      pulseLayer,
      const CircleLayerProperties(
        circleRadius: ['get', 'pulseRadius'],
        circleColor: ['get', 'color'],
        circleOpacity: ['get', 'pulseOpacity'],
        circlePitchAlignment: 'map',
      ),
      filter: const ['has', 'pulseRadius'],
      enableInteraction: false,
    );
    // A steady ring around the bus the passenger picked.
    await map.addCircleLayer(
      source,
      selectedLayer,
      CircleLayerProperties(
        circleRadius: 40,
        circleColor: colors.selection,
        circleOpacity: 0.16,
        circleStrokeColor: colors.selection,
        circleStrokeWidth: 2.5,
      ),
      filter: const [
        '==',
        ['get', 'selected'],
        true,
      ],
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      source,
      pointerLayer,
      const SymbolLayerProperties(
        iconImage: ['get', 'pointer'],
        iconSize: markerScale / mapImageScale,
        iconRotate: ['get', 'heading'],
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      filter: const ['has', 'heading'],
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      source,
      badgeLayer,
      const SymbolLayerProperties(
        iconImage: ['get', 'badge'],
        iconSize: markerScale / mapImageScale,
        iconRotationAlignment: 'viewport',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      source,
      labelLayer,
      SymbolLayerProperties(
        textField: const ['get', 'number'],
        textFont: const ['NotoSans-Medium'],
        textSize: 13.5,
        textAnchor: 'top',
        // Below the badge and clear of the pointer when it points down.
        textOffset: const [
          'literal',
          [0, 3.05],
        ],
        textColor: colors.label,
        textHaloColor: colors.labelHalo,
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
