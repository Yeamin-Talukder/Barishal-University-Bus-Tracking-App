import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/geo_point.dart';
import 'bus_grouping.dart';
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
///
/// A thin ring in the colour of the bus's route goes round the badge, so a
/// bus is seen to belong to its line. A bus that is not live is faded and
/// says how long ago it was seen. Buses that would lie on top of each
/// other are drawn as one marker with a count ([groupsGeoJson]).
class BusMapLayer {
  static const String source = 'bu-buses';
  static const String pulseLayer = 'bu-bus-pulse';
  static const String selectedLayer = 'bu-bus-selected';
  static const String pointerLayer = 'bu-bus-pointer';
  static const String routeRingLayer = 'bu-bus-route-ring';
  static const String badgeLayer = 'bu-bus-badge';
  static const String labelLayer = 'bu-bus-label';
  static const String seenLayer = 'bu-bus-seen';

  static const String groupSource = 'bu-bus-groups';
  static const String groupBackLayer = 'bu-bus-group-back';
  static const String groupBadgeLayer = 'bu-bus-group-badge';
  static const String groupBubbleLayer = 'bu-bus-group-bubble';
  static const String groupCountLayer = 'bu-bus-group-count';
  static const String groupLabelLayer = 'bu-bus-group-label';

  /// How strongly a marker is drawn for each status: a position that is
  /// not fresh recedes, so the eye goes to the buses that are moving.
  static double opacityOf(BusTrackingStatus status) => switch (status) {
    BusTrackingStatus.live => 1,
    BusTrackingStatus.delayed => 0.8,
    BusTrackingStatus.offline => 0.55,
  };

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

  /// Layers a tap on a group of buses is tested against.
  static const List<String> tappableGroupLayers = [
    groupBadgeLayer,
    groupLabelLayer,
  ];

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
  /// around live buses. [routeColorOf] gives the colour of the bus's route
  /// for the ring round its badge. [ageOf] is how old the position is; a
  /// bus that is not live shows it. Buses in [hiddenIds] are left out:
  /// they are drawn as part of a group instead.
  static Map<String, dynamic> geoJson(
    List<TrackedBus> buses, {
    required BusTrackingStatus Function(TrackedBus bus) statusOf,
    required double? Function(TrackedBus bus) headingOf,
    required BusMarkerColors colors,
    GeoPoint Function(TrackedBus bus)? positionOf,
    String? Function(TrackedBus bus)? routeColorOf,
    Duration? Function(TrackedBus bus)? ageOf,
    Set<String> hiddenIds = const {},
    String? selectedBusId,
    double pulse = 0,
  }) {
    // The ring grows and fades; easing out makes it breathe, not blink.
    final eased = 1 - math.pow(1 - pulse.clamp(0.0, 1.0), 2).toDouble();
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final tracked in buses)
          if (tracked.location != null && !hiddenIds.contains(tracked.bus.id))
            {
              'type': 'Feature',
              'properties': {
                'id': tracked.bus.id,
                'number': tracked.bus.number,
                'color': colors.of(statusOf(tracked)),
                'badge': badgeName(statusOf(tracked)),
                'pointer': pointerName(statusOf(tracked)),
                'selected': tracked.bus.id == selectedBusId,
                'opacity': opacityOf(statusOf(tracked)),
                'routeColor': ?routeColorOf?.call(tracked),
                if (statusOf(tracked) != BusTrackingStatus.live &&
                    ageOf?.call(tracked) != null)
                  'seen': 'seen ${seenAgoShort(ageOf!(tracked)!)}',
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

  /// The group markers as GeoJSON: one for each set of buses that would
  /// otherwise cover each other. A group takes the colour of the freshest
  /// status among its buses.
  static Map<String, dynamic> groupsGeoJson(
    List<({BusGroup group, BusTrackingStatus status})> groups, {
    required BusMarkerColors colors,
  }) {
    return {
      'type': 'FeatureCollection',
      'features': [
        for (final (:group, :status) in groups)
          {
            'type': 'Feature',
            'properties': {
              'id': groupId(group.busIds),
              'count': '${group.busIds.length}',
              'label': '${group.busIds.length} buses',
              'color': colors.of(status),
              'badge': badgeName(status),
            },
            'geometry': {
              'type': 'Point',
              'coordinates': group.position.toGeoJson(),
            },
          },
      ],
    };
  }

  /// A group's id on the map: its buses' ids, joined.
  static String groupId(List<String> busIds) => 'group:${busIds.join('|')}';

  /// The ids of the buses in the group with [id], or null if [id] is not a
  /// group's.
  static List<String>? busIdsOfGroup(String id) =>
      id.startsWith('group:') ? id.substring(6).split('|') : null;

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
    // A ring in the colour of the bus's route, showing just outside the
    // badge's white rim.
    await map.addCircleLayer(
      source,
      routeRingLayer,
      const CircleLayerProperties(
        circleRadius: (badgeRadiusPixels + 5) * markerScale + 3.5,
        circleColor: ['get', 'routeColor'],
        circleOpacity: ['get', 'opacity'],
      ),
      filter: const ['has', 'routeColor'],
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      source,
      badgeLayer,
      const SymbolLayerProperties(
        iconImage: ['get', 'badge'],
        iconSize: markerScale / mapImageScale,
        iconRotationAlignment: 'viewport',
        iconOpacity: ['get', 'opacity'],
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
    // How long ago a bus that is not live was seen, under its number.
    await map.addSymbolLayer(
      source,
      seenLayer,
      SymbolLayerProperties(
        textField: const ['get', 'seen'],
        textFont: const ['NotoSans-Medium'],
        textSize: 11.5,
        textAnchor: 'top',
        textOffset: const [
          'literal',
          [0, 5.0],
        ],
        textColor: colors.label,
        textOpacity: 0.85,
        textHaloColor: colors.labelHalo,
        textHaloWidth: 2,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      filter: const ['has', 'seen'],
      enableInteraction: false,
    );

    // Buses that would cover each other: one badge with a second one
    // peeking out behind it, and how many there are.
    await map.addGeoJsonSource(groupSource, _empty);
    await map.addCircleLayer(
      groupSource,
      groupBackLayer,
      CircleLayerProperties(
        circleRadius: badgeRadiusPixels * markerScale,
        circleColor: const ['get', 'color'],
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 3.5,
        circleTranslate: const [7, -6],
      ),
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      groupSource,
      groupBadgeLayer,
      const SymbolLayerProperties(
        iconImage: ['get', 'badge'],
        iconSize: markerScale / mapImageScale,
        iconRotationAlignment: 'viewport',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    await map.addCircleLayer(
      groupSource,
      groupBubbleLayer,
      CircleLayerProperties(
        circleRadius: 11.5,
        circleColor: colors.label,
        circleStrokeColor: colors.outline,
        circleStrokeWidth: 2,
        circleTranslate: const [21, -21],
      ),
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      groupSource,
      groupCountLayer,
      SymbolLayerProperties(
        textField: const ['get', 'count'],
        textFont: const ['NotoSans-Medium'],
        textSize: 13,
        textColor: colors.labelHalo,
        textTranslate: const [21, -21],
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      groupSource,
      groupLabelLayer,
      SymbolLayerProperties(
        textField: const ['get', 'label'],
        textFont: const ['NotoSans-Medium'],
        textSize: 13.5,
        textAnchor: 'top',
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

  /// Replaces the group markers.
  Future<void> updateGroups(
    MapLibreMapController map,
    Map<String, dynamic> geoJson,
  ) => map.setGeoJsonSource(groupSource, geoJson);
}
