import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/constants/university_map_configuration.dart';
import '../../../data/models/geo_point.dart';
import '../../map/application/map_providers.dart';
import '../../map/application/offline_map_service.dart';
import '../../map/application/university_map_configuration_provider.dart';

/// Builds the map used to choose a stop's position: it opens on `initial`,
/// reports the centre of the map each time the map stops moving, and moves
/// to whatever position `moveTo` is given.
typedef StopPickerMapBuilder = Widget Function(
  BuildContext context,
  GeoPoint initial,
  ValueChanged<GeoPoint> onMoved,
  ValueListenable<GeoPoint?> moveTo,
);

/// Widget tests override this to avoid creating a native map view.
final stopPickerMapBuilderProvider = Provider<StopPickerMapBuilder>(
  (ref) =>
      (context, initial, onMoved, moveTo) =>
          StopPickerMap(initial: initial, onMoved: onMoved, moveTo: moveTo),
);

/// A map whose centre is the position being chosen. The pin is drawn over
/// the centre by the screen using it; the admin moves the map under the pin.
class StopPickerMap extends ConsumerStatefulWidget {
  const StopPickerMap({
    required this.initial,
    required this.onMoved,
    required this.moveTo,
    super.key,
  });

  final GeoPoint initial;
  final ValueChanged<GeoPoint> onMoved;

  /// Set to a position to move the map there, for example after the admin
  /// pastes coordinates.
  final ValueListenable<GeoPoint?> moveTo;

  /// Close enough to tell one side of a junction from the other.
  static const double zoom = 16.5;

  @override
  ConsumerState<StopPickerMap> createState() => _StopPickerMapState();
}

class _StopPickerMapState extends ConsumerState<StopPickerMap> {
  MapLibreMapController? _map;

  /// The style the map was created with. MapLibre is never rebuilt.
  String? _style;

  @override
  void initState() {
    super.initState();
    widget.moveTo.addListener(_moveToRequested);
  }

  @override
  void dispose() {
    widget.moveTo.removeListener(_moveToRequested);
    super.dispose();
  }

  void _moveToRequested() {
    final target = widget.moveTo.value;
    final map = _map;
    if (target == null || map == null) return;
    unawaited(
      map.animateCamera(
        CameraUpdate.newLatLng(LatLng(target.latitude, target.longitude)),
      ),
    );
  }

  void _reportCentre() {
    final target = _map?.cameraPosition?.target;
    if (target == null || !mounted) return;
    widget.onMoved(GeoPoint(target.latitude, target.longitude));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isReady = ref.watch(
      offlineMapServiceProvider.select((state) => state.isReady),
    );
    final mapStyle = Theme.of(context).brightness == Brightness.dark
        ? UniversityMapStyle.dark
        : UniversityMapStyle.light;
    final style = ref.watch(mapStyleJsonProvider(mapStyle));
    _style ??= style.value;

    final styleJson = _style;
    if (!isReady || styleJson == null) {
      return ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Center(
          child: !isReady || style.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'The map is not installed on this device. Install it '
                    'from the Profile tab to place a stop.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    final config = ref.watch(universityMapConfigurationProvider);
    final bounds = config.coverageBounds;
    return MapLibreMap(
      styleString: styleJson,
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.initial.latitude, widget.initial.longitude),
        zoom: StopPickerMap.zoom,
      ),
      minMaxZoomPreference: MinMaxZoomPreference(
        config.minZoom,
        config.maxZoom,
      ),
      cameraTargetBounds: CameraTargetBounds(
        LatLngBounds(
          southwest: LatLng(bounds.south, bounds.west),
          northeast: LatLng(bounds.north, bounds.east),
        ),
      ),
      // Needed for the centre to be readable when the map stops.
      trackCameraPosition: true,
      // A tilted or turned map would make the pin's position ambiguous.
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      attributionEnabled: false,
      compassEnabled: false,
      onMapCreated: (map) => _map = map,
      onCameraIdle: _reportCentre,
    );
  }
}
