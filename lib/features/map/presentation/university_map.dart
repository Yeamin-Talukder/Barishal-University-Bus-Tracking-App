import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/constants/university_map_configuration.dart';
import '../../../core/services/eta_service.dart';
import '../../../core/utils/geo_math.dart';
import '../../../core/utils/route_geometry.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/models/transport_network.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../home/application/nearest_stop.dart';
import '../application/bus_grouping.dart';
import '../application/bus_map_layer.dart';
import '../application/bus_motion.dart';
import '../application/map_view_state.dart';
import '../application/route_flow_layer.dart';
import '../../prediction/application/prediction_providers.dart';
import '../application/predicted_bus_layer.dart';
import '../application/stop_map_layer.dart';
import '../application/map_camera_controller.dart';
import '../application/map_providers.dart';
import '../application/map_selection.dart';
import '../application/offline_map_service.dart';
import '../application/transport_map_layers.dart';
import '../application/university_map_configuration_provider.dart';
import 'bus_group_sheet.dart';
import 'offline_map_placeholder.dart';

/// Builds the map shown on the home tab. Widget tests override this to avoid
/// creating a native map view.
final universityMapBuilderProvider = Provider<WidgetBuilder>(
  (ref) =>
      (context) => const UniversityMap(),
);

/// The interactive vector map, centred on the university.
///
/// It owns everything that touches MapLibre: choosing the style for the
/// current theme, restricting the camera to the covered area and keeping the
/// route and stop layers attached across style changes. The rest of the app
/// talks to it through [mapCameraControllerProvider].
class UniversityMap extends ConsumerStatefulWidget {
  const UniversityMap({super.key});

  @override
  ConsumerState<UniversityMap> createState() => _UniversityMapState();
}

class _UniversityMapState extends ConsumerState<UniversityMap>
    with SingleTickerProviderStateMixin {
  final TransportMapLayers _transportLayers = TransportMapLayers();
  final BusMapLayer _busLayer = BusMapLayer();

  /// Smooths each bus's reported positions into steady movement.
  final BusMotionTracker _busMotion = BusMotionTracker();

  /// Each route's line as drawn, by route id, for putting buses on it.
  final Map<String, RouteGeometry?> _tracks = {};
  late final Ticker _busTicker = createTicker(_onTick);
  Duration _lastBusFrame = Duration.zero;
  bool _drawingBuses = false;
  static const Duration _busFrameGap = Duration(milliseconds: 66);
  static const Duration _followFrameGap = Duration(milliseconds: 33);

  /// Following a bus: the way the map is turned, eased towards the bus's
  /// heading; when the turn into following is over; and whether a camera
  /// move is still on its way to the map.
  double? _followBearing;
  DateTime _followSettlesAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _movingFollowCamera = false;
  bool _wasFollowing = false;
  static const int _pulsePeriodMs = 2200;
  bool _busLayerAttached = false;

  /// Where buses probably are, when there is no live position for them.
  final PredictedBusLayer _predictedLayer = PredictedBusLayer();
  bool _predictedAttached = false;

  /// Which way the picked route runs, and how far a picked bus has come.
  final RouteFlowLayer _flowLayer = RouteFlowLayer();
  bool _flowAttached = false;
  bool _drawingFlow = false;
  DateTime _flowDrawnAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _flowGap = Duration(milliseconds: 700);

  /// The groups of overlapping buses as last drawn, to skip redrawing
  /// them when nothing changed.
  String _groupsDrawn = '';

  /// The picked stop's animated badge.
  final StopFocusLayer _stopFocus = StopFocusLayer();
  bool _stopFocusAttached = false;
  bool _drawingStopFocus = false;
  String? _focusedStopId;
  DateTime _stopFocusedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Held in a field because `ref` must not be used while disposing.
  late final MapCameraController _camera;

  MapLibreMapController? _map;

  /// The style the map was created with. It never changes afterwards, so
  /// MapLibre is not rebuilt; later styles are applied with `setStyle`.
  String? _initialStyle;
  String? _appliedStyle;
  bool _layersAttached = false;

  /// Whether the tab holding the map is the one being shown.
  bool _isOnScreen = true;

  /// A selection made while the map was hidden, still to be framed.
  MapSelection? _selectionAwaitingCamera;

  @override
  void initState() {
    super.initState();
    _camera = ref.read(mapCameraControllerProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab container switches tickers off for tabs that are not showing.
    _isOnScreen = TickerMode.valuesOf(context).enabled;
    final waiting = _selectionAwaitingCamera;
    if (_isOnScreen && waiting != null) {
      _selectionAwaitingCamera = null;
      // Give the map a moment to be laid out at its real size first.
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (mounted) unawaited(_showOnCamera(waiting));
      });
    }
  }

  @override
  void dispose() {
    final map = _map;
    if (map != null) _camera.detach(map);
    _busTicker.dispose();
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController map) {
    _map = map;
    _camera.attach(map);
  }

  void _forgetMap() {
    final map = _map;
    if (map != null) _camera.detach(map);
    _map = null;
    _initialStyle = null;
    _appliedStyle = null;
    _layersAttached = false;
    _busLayerAttached = false;
    _stopFocusAttached = false;
    _predictedAttached = false;
    _flowAttached = false;
    _groupsDrawn = '';
  }

  /// Runs after the first style and after every `setStyle`.
  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || !mounted) return;
    _layersAttached = false;

    _stopFocusAttached = false;

    final network =
        ref.read(transportNetworkProvider).value ?? TransportNetwork.empty;
    final scheme = Theme.of(context).colorScheme;
    final layerColors = _layerColors();
    try {
      // A stop: a strong badge that stands out from the map, with the sign
      // in the map's own background colour.
      final stopIcon = await paintStopBadge(
        body: scheme.onSurface,
        rim: scheme.surface,
        ink: scheme.surface,
      );
      if (!mounted) return;
      // The ring round the nearest stop comes back with the layers.
      await _transportLayers.showNearestStop(
        null,
        ref.read(nearestStopProvider)?.stop.id,
        attached: false,
      );
      await _transportLayers.attach(
        map,
        network,
        ref.read(mapSelectionProvider),
        layerColors,
        stopIcon: stopIcon,
        busRouteId: _pickedBusRouteId(),
      );
      _layersAttached = true;
    } catch (error) {
      // The base map still works without the transport layers.
      debugPrint('Could not add route and stop layers: $error');
    }

    _flowAttached = false;
    try {
      if (!mounted) return;
      final arrow = await paintRouteArrow(
        ink: AppColors.darkBackground,
        rim: const Color(0xCCFFFFFF),
      );
      if (!mounted) return;
      await _flowLayer.attach(
        map,
        arrow: arrow,
        casingColor: layerColors.routeCasing,
        labelColor: layerColors.label,
        labelHaloColor: layerColors.labelHalo,
        timeColor: layerColors.label,
      );
      _flowAttached = true;
      unawaited(_drawFlow(force: true));
    } catch (error) {
      debugPrint('Could not add the route arrows: $error');
    }

    try {
      // The picked stop, in the app's main colour.
      final selectedIcon = await paintStopBadge(
        body: scheme.primary,
        rim: scheme.surface,
        ink: scheme.onPrimary,
      );
      if (!mounted) return;
      await _stopFocus.attach(
        map,
        icon: selectedIcon,
        color: layerColors.selection,
      );
      _stopFocusAttached = true;
      _syncStopFocus(ref.read(mapSelectionProvider));
    } catch (error) {
      debugPrint('Could not add the picked stop\'s marker: $error');
    }

    // Predicted buses go under the live ones.
    _predictedAttached = false;
    try {
      if (!mounted) return;
      final icon = await paintPredictedBadge(
        color: Theme.of(context).extension<AppSemanticColors>()!.info,
        paper: scheme.surface,
      );
      if (!mounted) return;
      await _predictedLayer.attach(
        map,
        icon: icon,
        labelColor: layerColors.label,
        haloColor: layerColors.labelHalo,
      );
      _predictedAttached = true;
      unawaited(_drawPredicted());
    } catch (error) {
      debugPrint('Could not add the predicted buses: $error');
    }

    _busLayerAttached = false;
    try {
      if (!mounted) return;
      final semantic = Theme.of(context).extension<AppSemanticColors>()!;
      final bodies = {
        BusTrackingStatus.live: semantic.success,
        BusTrackingStatus.delayed: semantic.warning,
        BusTrackingStatus.offline: semantic.offline,
      };
      final badges = <BusTrackingStatus, Uint8List>{};
      final pointers = <BusTrackingStatus, Uint8List>{};
      for (final MapEntry(key: status, value: body) in bodies.entries) {
        badges[status] = await paintBusBadge(body: body);
        pointers[status] = await paintBusPointer(body: body);
      }
      if (!mounted) return;
      await _busLayer.attach(
        map,
        _busColors(),
        badges: badges,
        pointers: pointers,
      );
      _busLayerAttached = true;
      _groupsDrawn = '';
      _onBusesChanged();
    } catch (error) {
      debugPrint('Could not add the bus markers: $error');
    }
  }

  /// The direction to show for a bus: only for a live, moving bus with a
  /// good fix. Anything else would be a guess.
  double? _headingOf(TrackedBus bus) {
    final location = bus.location;
    final config = ref.read(trackingConfigurationProvider);
    if (location == null ||
        config.statusOf(location.updatedAt, ref.read(clockProvider)()) !=
            BusTrackingStatus.live ||
        !config.hasReliableMotion(location)) {
      return null;
    }
    return location.headingDegrees;
  }

  /// Redraws the bus markers where they are right now: gliding towards
  /// their latest reported positions, with the live ring at its current
  /// phase.
  Future<void> _drawBuses() async {
    final map = _map;
    if (map == null || !_busLayerAttached || !mounted || _drawingBuses) return;
    _drawingBuses = true;
    final config = ref.read(trackingConfigurationProvider);
    final now = ref.read(clockProvider)();
    final wallClock = DateTime.now();
    final buses = ref.read(trackedBusesProvider).value ?? const <TrackedBus>[];
    final zoom = map.cameraPosition?.zoom;
    final network = ref.read(transportNetworkProvider).value;
    final selectedBusId = ref.read(mapSelectionProvider).busId;
    BusTrackingStatus statusOf(TrackedBus bus) =>
        config.statusOf(bus.location?.updatedAt, now);
    // Where each marker goes, worked out once: the groups need it too.
    final positions = {
      for (final bus in buses)
        if (bus.location != null)
          bus.bus.id: _drawnPosition(bus, wallClock, zoom),
    };
    // Buses that would lie on top of each other become one marker with a
    // count. The picked bus always keeps its own.
    final groups = zoom == null
        ? const <BusGroup>[]
        : groupOverlappingBuses(
            [
              for (final MapEntry(key: id, value: position)
                  in positions.entries)
                (id: id, position: position),
            ],
            zoom: zoom,
            keepApartId: selectedBusId,
          );
    final grouped = {for (final group in groups) ...group.busIds};
    final colors = _busColors();
    try {
      await _busLayer.update(
        map,
        BusMapLayer.geoJson(
          buses,
          statusOf: statusOf,
          headingOf: (bus) =>
              _busMotion.poseOf(bus.bus.id, wallClock)?.headingDegrees,
          positionOf: (bus) => positions[bus.bus.id]!,
          routeColorOf: (bus) => bus.bus.routeId == null
              ? null
              : network?.routeById(bus.bus.routeId!)?.colorHex,
          ageOf: (bus) => bus.location == null
              ? null
              : now.difference(bus.location!.updatedAt),
          hiddenIds: grouped,
          colors: colors,
          selectedBusId: selectedBusId,
          pulse:
              (wallClock.millisecondsSinceEpoch % _pulsePeriodMs) /
              _pulsePeriodMs,
        ),
      );
      // A group is coloured by the freshest of its buses.
      final groupMarkers = [
        for (final group in groups)
          (
            group: group,
            status: buses
                .where((bus) => group.busIds.contains(bus.bus.id))
                .map(statusOf)
                .reduce((a, b) => a.index <= b.index ? a : b),
          ),
      ];
      final signature = [
        for (final (:group, :status) in groupMarkers)
          '${group.busIds.join('|')}:${status.name}:'
              '${group.position.latitude.toStringAsFixed(5)},'
              '${group.position.longitude.toStringAsFixed(5)}',
      ].join(';');
      if (signature != _groupsDrawn) {
        _groupsDrawn = signature;
        await _busLayer.updateGroups(
          map,
          BusMapLayer.groupsGeoJson(groupMarkers, colors: colors),
        );
      }
    } catch (error) {
      debugPrint('Could not update the bus markers: $error');
    } finally {
      _drawingBuses = false;
    }
  }

  /// Starts the animation clock if it is not running.
  void _ensureTicking() {
    if (_busTicker.isActive) return;
    _lastBusFrame = Duration.zero;
    unawaited(_busTicker.start());
  }

  /// Follows the selection: a newly picked stop gets the animated badge,
  /// and it is taken away when the stop is let go.
  void _syncStopFocus(MapSelection selection) {
    final stopId = selection.stopId;
    if (stopId != _focusedStopId) {
      _focusedStopId = stopId;
      _stopFocusedAt = DateTime.now();
    }
    if (stopId != null && _stopFocusAttached) _ensureTicking();
    unawaited(_drawStopFocus());
  }

  /// Redraws the picked stop's badge at its current size, with the ripple
  /// at its current phase.
  Future<void> _drawStopFocus() async {
    final map = _map;
    if (map == null || !_stopFocusAttached || !mounted || _drawingStopFocus) {
      return;
    }
    _drawingStopFocus = true;
    final stopId = _focusedStopId;
    final stop = stopId == null
        ? null
        : ref.read(transportNetworkProvider).value?.stopById(stopId);
    final now = DateTime.now();
    try {
      await _stopFocus.update(
        map,
        StopFocusLayer.geoJson(
          stop,
          sinceSelected: now.difference(_stopFocusedAt),
          ripple:
              (now.difference(_stopFocusedAt).inMilliseconds %
                  StopFocusLayer.ripplePeriodMs) /
              StopFocusLayer.ripplePeriodMs,
        ),
      );
    } catch (error) {
      debugPrint('Could not update the picked stop\'s marker: $error');
    } finally {
      _drawingStopFocus = false;
    }
  }

  /// Redraws the predicted buses, each set to the side with its route's
  /// line as the live ones are.
  Future<void> _drawPredicted() async {
    final map = _map;
    if (map == null || !_predictedAttached || !mounted) return;
    final buses = ref.read(predictedBusesProvider);
    final network = ref.read(transportNetworkProvider).value;
    final zoom = map.cameraPosition?.zoom;
    final selectedRoute = _focusRouteId();
    try {
      await _predictedLayer.update(
        map,
        PredictedBusLayer.geoJson(
          buses,
          positionOf: (bus) {
            final index =
                network?.routes.indexWhere((r) => r.id == bus.routeId) ?? -1;
            if (zoom == null || index < 0 || selectedRoute == bus.routeId) {
              return bus.position;
            }
            return TransportMapLayers.inLane(
              bus.position,
              lineBearingDegrees: bus.lineBearingDegrees,
              lane: TransportGeoJson.laneOf(index, network!.routes.length),
              zoom: zoom,
            );
          },
        ),
      );
    } catch (error) {
      debugPrint('Could not update the predicted buses: $error');
    }
  }

  /// The route of the bus the passenger picked, if it has a line. While a
  /// bus is picked its route is brought forward like a picked route.
  String? _pickedBusRouteId() {
    final busId = ref.read(mapSelectionProvider).busId;
    if (busId == null) return null;
    final buses = ref.read(trackedBusesProvider).value ?? const <TrackedBus>[];
    final tracked = buses.where((bus) => bus.bus.id == busId).firstOrNull;
    if (tracked == null || tracked.location == null) return null;
    return _trackOf(tracked) == null ? null : tracked.bus.routeId;
  }

  /// The route drawn on the middle of the road: the picked one, or the
  /// picked bus's.
  String? _focusRouteId() =>
      ref.read(mapSelectionProvider).routeId ?? _pickedBusRouteId();

  /// What to draw about travel along the route in focus, and the minutes
  /// to show at the stops ahead of a picked bus.
  (RouteFlow?, List<StopTime>) _currentFlow() {
    final network = ref.read(transportNetworkProvider).value;
    final selection = ref.read(mapSelectionProvider);
    if (network == null) return (null, const []);

    final route = selection.routeId == null
        ? null
        : network.routeById(selection.routeId!);
    if (route != null) {
      final line = TransportGeoJson.withoutStubs(route.path);
      if (line.length < 2) return (null, const []);
      // Arrows along the line the route layers draw, the way it is shown.
      return (
        RouteFlow(
          color: route.colorHex,
          name: route.name,
          ahead: ref.read(routeShownReversedProvider)
              ? line.reversed.toList()
              : line,
        ),
        const [],
      );
    }

    final busId = selection.busId;
    final buses = ref.read(trackedBusesProvider).value ?? const <TrackedBus>[];
    final tracked = buses.where((bus) => bus.bus.id == busId).firstOrNull;
    final busRoute = tracked?.bus.routeId == null
        ? null
        : network.routeById(tracked!.bus.routeId!);
    final track = tracked == null ? null : _trackOf(tracked);
    final location = tracked?.location;
    if (tracked == null ||
        busRoute == null ||
        track == null ||
        location == null) {
      return (null, const []);
    }

    final stops = network.stopsOf(busRoute);
    final eta = ref.read(etaServiceProvider);
    final now = ref.read(clockProvider)();
    final isLive =
        ref
            .read(trackingConfigurationProvider)
            .statusOf(location.updatedAt, now) ==
        BusTrackingStatus.live;
    final direction = !isLive
        ? null
        : eta
              .progress(route: busRoute, stops: stops, location: location)
              .direction;
    if (direction == null) {
      // Which way it is going is not known: the whole line, no arrows and
      // nothing marked as covered.
      return (
        RouteFlow(
          color: busRoute.colorHex,
          name: busRoute.name,
          ahead: track.path,
          drawLines: true,
          arrows: false,
        ),
        const [],
      );
    }

    final drawn =
        _busMotion.poseOf(tracked.bus.id, DateTime.now())?.position ??
        location.position;
    final times = <StopTime>[
      for (final stop in stops)
        if (eta.estimateArrival(
              route: busRoute,
              stops: stops,
              stop: stop,
              location: location,
              now: now,
            )
            case ArrivalEstimated(:final travelTime))
          (
            position: stop.position,
            text: RouteFlowGeoJson.timeText(travelTime),
          ),
    ];
    return (
      RouteFlow.forBus(
        track: track,
        alongMeters: track.project(drawn).distanceAlongMeters,
        forwards: direction == TravelDirection.forward,
        color: busRoute.colorHex,
        name: busRoute.name,
      ),
      times,
    );
  }

  /// Redraws the arrows, the covered part of a picked bus's route and the
  /// minutes at its stops. Not more than about once a second unless
  /// [force]d: the line is long and changes slowly.
  Future<void> _drawFlow({bool force = false}) async {
    final map = _map;
    if (map == null || !_flowAttached || !mounted || _drawingFlow) return;
    final now = DateTime.now();
    if (!force && now.difference(_flowDrawnAt) < _flowGap) return;
    _drawingFlow = true;
    _flowDrawnAt = now;
    try {
      final (flow, times) = _currentFlow();
      await _flowLayer.update(map, flow);
      await _flowLayer.updateTimes(map, times);
    } catch (error) {
      debugPrint('Could not update the route arrows: $error');
    } finally {
      _drawingFlow = false;
    }
  }

  /// The line of the route [bus] is on, as it is drawn on the map (without
  /// the stubs the drawing leaves out). Null if the route has no line.
  RouteGeometry? _trackOf(TrackedBus bus) {
    final routeId = bus.bus.routeId;
    if (routeId == null) return null;
    if (_tracks.containsKey(routeId)) return _tracks[routeId];
    final route = ref.read(transportNetworkProvider).value?.routeById(routeId);
    final drawn = route == null
        ? const <GeoPoint>[]
        : TransportGeoJson.withoutStubs(route.path);
    return _tracks[routeId] = drawn.length < 2 ? null : RouteGeometry(drawn);
  }

  /// Where the marker of [bus] is drawn at [now].
  ///
  /// A bus on its route is put on the route's line. With several routes
  /// showing, each line is set to one side in its own lane, and the bus is
  /// set to the side with it, so it is seen on its own line and not on the
  /// neighbour's.
  GeoPoint _drawnPosition(TrackedBus bus, DateTime now, double? zoom) {
    final pose = _busMotion.poseOf(bus.bus.id, now);
    if (pose == null) return bus.location!.position;
    final bearing = pose.trackBearingDegrees;
    final network = ref.read(transportNetworkProvider).value;
    final routeId = bus.bus.routeId;
    if (bearing == null || zoom == null || network == null || routeId == null) {
      return pose.position;
    }
    // The route in focus is drawn on the middle of the road.
    if (_focusRouteId() == routeId) return pose.position;
    final index = network.routes.indexWhere((route) => route.id == routeId);
    if (index < 0) return pose.position;
    return TransportMapLayers.inLane(
      pose.position,
      lineBearingDegrees: bearing,
      lane: TransportGeoJson.laneOf(index, network.routes.length),
      zoom: zoom,
    );
  }

  /// Runs while there is something to animate: a marker gliding, a live
  /// bus whose ring is pulsing, or a picked stop. Redraws about fifteen
  /// times a second.
  void _onTick(Duration elapsed) {
    // A followed bus is redrawn twice as often: the camera travels with
    // it, and a camera that steps is far easier to see than a marker.
    final isFollowing = _isFollowing;
    final gap = isFollowing ? _followFrameGap : _busFrameGap;
    if (elapsed - _lastBusFrame < gap) return;
    _lastBusFrame = elapsed;
    final config = ref.read(trackingConfigurationProvider);
    final now = ref.read(clockProvider)();
    final buses = ref.read(trackedBusesProvider).value ?? const <TrackedBus>[];
    final anyLive = buses.any(
      (bus) =>
          bus.location != null &&
          config.statusOf(bus.location!.updatedAt, now) ==
              BusTrackingStatus.live,
    );
    final stopPicked = _focusedStopId != null && _stopFocusAttached;
    // A picked bus is marked by a ring that moves, live or not.
    final busPicked = ref.read(mapSelectionProvider).busId != null;
    if (!anyLive &&
        !_busMotion.isMoving(DateTime.now()) &&
        !stopPicked &&
        !busPicked) {
      _busTicker.stop();
      _lastBusFrame = Duration.zero;
    }
    unawaited(_drawBuses());
    if (stopPicked) unawaited(_drawStopFocus());
    // The covered part of a picked bus's route grows as it moves.
    if (ref.read(mapSelectionProvider).busId != null) unawaited(_drawFlow());
    if (isFollowing) _followCamera();
  }

  /// Whether a bus is being followed on a map that is showing.
  bool get _isFollowing =>
      _isOnScreen && ref.read(mapSelectionProvider).isFollowingBus;

  /// Keeps the camera on the followed bus, where its marker is drawn right
  /// now, and turns the map to face the way it is going.
  void _followCamera() {
    final busId = ref.read(mapSelectionProvider).busId;
    if (busId == null || _movingFollowCamera) return;
    // The passenger moved the map themselves: leave it where they put it
    // until they ask to re-centre.
    if (ref.read(followPausedProvider)) return;
    // Let the turn into following finish before taking over.
    if (DateTime.now().isBefore(_followSettlesAt)) return;
    final pose = _busMotion.poseOf(busId, DateTime.now());
    if (pose == null) return;
    final headingUp = ref.read(followHeadingUpProvider);
    // North-up: the map turns back to north and stays there.
    final heading = headingUp ? pose.headingDegrees : 0.0;
    // With no direction to trust, the map keeps facing the way it was.
    _followBearing = heading == null
        ? (_followBearing ?? _camera.bearing)
        : MapCameraController.turnTowards(
            _followBearing ?? _camera.bearing,
            heading,
            0.12,
          );
    _movingFollowCamera = true;
    _camera
        .trackBus(pose.position, _followBearing!, headingUp: headingUp)
        .catchError(
          (Object error) => debugPrint('Could not follow the bus: $error'),
        )
        .whenComplete(() => _movingFollowCamera = false);
  }

  /// Starts or stops following as the selection says: turning to face the
  /// bus when it starts, and back to north-up when it stops.
  Future<void> _syncFollowing(MapSelection selection) async {
    final following = selection.isFollowingBus && selection.busId != null;
    if (following == _wasFollowing) return;
    _wasFollowing = following;
    if (!_isOnScreen) return;
    if (following) {
      final pose = _busMotion.poseOf(selection.busId!, DateTime.now());
      final position = pose?.position ?? _positionOfBus(selection.busId);
      if (position == null) return;
      final headingUp = ref.read(followHeadingUpProvider);
      _followBearing = headingUp
          ? (pose?.headingDegrees ?? _camera.bearing)
          : 0;
      _followSettlesAt = DateTime.now().add(const Duration(milliseconds: 750));
      _ensureTicking();
      await _camera.enterFollow(
        position,
        headingDegrees: pose?.headingDegrees,
        headingUp: headingUp,
      );
    } else {
      _followBearing = null;
      await _camera.leaveFollow();
    }
  }

  /// Brings the camera back to the followed bus: after the passenger
  /// moved the map away and asked to re-centre, or after they switched
  /// between turning with the bus and north-up. Their zoom is kept.
  Future<void> _recentreOnFollowedBus() async {
    final selection = ref.read(mapSelectionProvider);
    final busId = selection.busId;
    if (!_isFollowing || busId == null) return;
    final pose = _busMotion.poseOf(busId, DateTime.now());
    final position = pose?.position ?? _positionOfBus(busId);
    if (position == null) return;
    final headingUp = ref.read(followHeadingUpProvider);
    _followBearing = headingUp ? (pose?.headingDegrees ?? _camera.bearing) : 0;
    _followSettlesAt = DateTime.now().add(const Duration(milliseconds: 750));
    _ensureTicking();
    await _camera.enterFollow(
      position,
      headingDegrees: pose?.headingDegrees,
      headingUp: headingUp,
      keepZoom: true,
    );
  }

  /// The passenger moved the map with their fingers. While a bus is being
  /// followed that puts following on hold, so the map does not snap back
  /// under their hand.
  void _onCameraMoveStarted(CameraMoveReason reason) {
    if (reason == CameraMoveReason.gesture) _pauseFollowing();
  }

  /// Puts following on hold, if a bus is being followed.
  void _pauseFollowing() {
    if (!_isFollowing) return;
    if (!ref.read(followPausedProvider)) {
      ref.read(followPausedProvider.notifier).pause();
    }
  }

  /// Where a finger or the mouse went down on the map, until it lifts.
  Offset? _pointerDownAt;

  /// A drag across the map while a bus is followed puts following on hold.
  ///
  /// The map reports a move made by hand itself, but not on the web while
  /// the camera is being moved many times a second to keep up with a bus:
  /// each of those moves cancels the drag before the map counts it as one.
  /// So the drag is watched for here as well. A tap stays a tap.
  void _onPointerMove(PointerMoveEvent event) {
    final from = _pointerDownAt;
    if (from == null || (event.position - from).distance < _dragSlop) return;
    _pointerDownAt = null;
    _pauseFollowing();
  }

  /// How far a pointer must travel before it is a drag and not a tap.
  static const double _dragSlop = 12;

  /// The reported position of the bus with [busId], if it has one.
  GeoPoint? _positionOfBus(String? busId) {
    if (busId == null) return null;
    final buses = ref.read(trackedBusesProvider).value ?? const <TrackedBus>[];
    return buses
        .where((tracked) => tracked.bus.id == busId)
        .firstOrNull
        ?.location
        ?.position;
  }

  /// New positions arrived: start each marker gliding to its new place,
  /// and keep a followed bus in view.
  Future<void> _onBusesChanged() async {
    if (!mounted) return;
    final buses = ref.read(trackedBusesProvider).value ?? const <TrackedBus>[];
    _busMotion.update(
      buses,
      DateTime.now(),
      headingOf: _headingOf,
      trackOf: _trackOf,
    );
    if (_busLayerAttached) _ensureTicking();
    await _drawBuses();
    unawaited(_drawFlow());
    // A followed bus is kept in view by the animation clock, frame by
    // frame, so there is nothing more to do here.
    if (_isFollowing) _ensureTicking();
  }

  Future<void> _onNetworkChanged(TransportNetwork network) async {
    // The lines may have changed: work them out afresh when next needed.
    _tracks.clear();
    final map = _map;
    if (map == null || !_layersAttached) return;
    try {
      await _transportLayers.update(map, network);
    } catch (error) {
      debugPrint('Could not update route and stop layers: $error');
    }
    unawaited(_drawFlow(force: true));
  }

  /// Highlights the selection on the map and brings it into view.
  Future<void> _onSelectionChanged(MapSelection selection) async {
    final map = _map;
    final network = ref.read(transportNetworkProvider).value;
    if (map == null || network == null) return;

    if (_layersAttached) {
      try {
        await _transportLayers.applySelection(
          map,
          network,
          selection,
          busRouteId: _pickedBusRouteId(),
        );
      } catch (error) {
        debugPrint('Could not show the selection on the map: $error');
      }
    }
    unawaited(_drawFlow(force: true));
    _syncStopFocus(selection);
    // Moves the ring to the selected bus.
    await _drawBuses();

    if (_isOnScreen) {
      final wasFollowing = _wasFollowing;
      await _syncFollowing(selection);
      // Following moves the camera itself; so does leaving it.
      if (!selection.isFollowingBus && !wasFollowing) {
        await _showOnCamera(selection);
      }
    } else {
      // The map is on a hidden tab. A hidden map cannot frame anything
      // correctly, so the camera moves when it is shown again.
      _selectionAwaitingCamera = selection;
    }
  }

  /// Moves the camera to the selected route or stop.
  Future<void> _showOnCamera(MapSelection selection) async {
    final network = ref.read(transportNetworkProvider).value;
    if (network == null) return;
    final route = selection.routeId == null
        ? null
        : network.routeById(selection.routeId!);
    final stop = selection.stopId == null
        ? null
        : network.stopById(selection.stopId!);
    if (route != null) {
      await _camera.showRoute(route);
    } else if (stop != null) {
      await _camera.showStop(stop);
    } else {
      final bus = _positionOfBus(selection.busId);
      if (bus != null) await _camera.showBus(bus);
    }
  }

  /// A tap on the map selects the stop or route under the finger.
  /// Whether the list of a group's buses is open, and when it last closed.
  ///
  /// On the web the map is an HTML element under the app's own drawing, so
  /// the tap that picks a bus from the list, or closes it, also reaches
  /// the map. Left alone it would land on the group's marker again and
  /// open the list a second time. Taps are therefore ignored while the
  /// list is open and for a moment after it closes.
  bool _pickingFromGroup = false;
  DateTime? _groupListClosedAt;
  static const Duration _groupListEcho = Duration(milliseconds: 400);

  Future<void> _onMapTapped(Point<double> point, LatLng coordinates) async {
    final map = _map;
    if (map == null || !_layersAttached || _pickingFromGroup) return;
    final closedAt = _groupListClosedAt;
    if (closedAt != null &&
        DateTime.now().difference(closedAt) < _groupListEcho) {
      return;
    }
    try {
      // A finger is not a pin: a bus or a stop is picked when the tap lands
      // near it, and the nearest one wins.
      final around = _tapArea(point);
      if (_busLayerAttached) {
        // Several buses under one marker: ask which one.
        final groupId = nearestTappedId(
          await map.queryRenderedFeaturesInRect(
            around,
            BusMapLayer.tappableGroupLayers,
            null,
          ),
          coordinates.latitude,
          coordinates.longitude,
        );
        final groupBusIds = groupId == null
            ? null
            : BusMapLayer.busIdsOfGroup(groupId);
        if (groupBusIds != null && mounted) {
          // The same tap, reported a second time while the first was
          // being looked up.
          if (_pickingFromGroup) return;
          _pickingFromGroup = true;
          final String? picked;
          try {
            picked = await showBusGroupSheet(context, groupBusIds);
          } finally {
            _pickingFromGroup = false;
            _groupListClosedAt = DateTime.now();
          }
          if (picked != null && mounted) {
            ref.read(mapSelectionProvider.notifier).selectBus(picked);
          }
          return;
        }
        if (!mounted) return;
        final busId = nearestTappedId(
          await map.queryRenderedFeaturesInRect(
            around,
            BusMapLayer.tappableLayers,
            null,
          ),
          coordinates.latitude,
          coordinates.longitude,
        );
        if (busId != null) {
          ref.read(mapSelectionProvider.notifier).selectBus(busId);
          return;
        }
      }
      if (!mounted) return;
      final stopId = nearestTappedId(
        await map.queryRenderedFeaturesInRect(
          around,
          TransportMapLayers.tappableStopLayers,
          null,
        ),
        coordinates.latitude,
        coordinates.longitude,
      );
      // A predicted bus opens its route: there is no bus to open.
      if (stopId == null && _predictedAttached && mounted) {
        final predictedId = nearestTappedId(
          await map.queryRenderedFeaturesInRect(
            around,
            PredictedBusLayer.tappableLayers,
            null,
          ),
          coordinates.latitude,
          coordinates.longitude,
        );
        final predicted = ref
            .read(predictedBusesProvider)
            .where((bus) => bus.id == predictedId)
            .firstOrNull;
        if (predicted != null) {
          ref
              .read(mapSelectionProvider.notifier)
              .selectRoute(predicted.routeId);
          return;
        }
      }
      if (stopId != null) {
        ref.read(mapSelectionProvider.notifier).selectStop(stopId);
        return;
      }
      final routeId = _featureId(
        await map.queryRenderedFeatures(
          point,
          TransportMapLayers.tappableRouteLayers,
          null,
        ),
      );
      if (routeId != null && mounted) {
        ref.read(mapSelectionProvider.notifier).selectRoute(routeId);
      }
    } catch (error) {
      debugPrint('Could not read what was tapped on the map: $error');
    }
  }

  /// The square around a tap in which a bus or stop still counts as hit:
  /// about a fingertip. Android reports taps in screen pixels, the other
  /// platforms in logical ones.
  Rect _tapArea(Point<double> point) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final reach =
        18.0 * (isAndroid ? MediaQuery.devicePixelRatioOf(context) : 1);
    return Rect.fromCenter(
      center: Offset(point.x, point.y),
      width: reach * 2,
      height: reach * 2,
    );
  }

  /// The `id` property of the first feature MapLibre returned, if any.
  static String? _featureId(List<dynamic> features) {
    for (final feature in features) {
      if (feature is Map && feature['properties'] is Map) {
        final id = (feature['properties'] as Map)['id'];
        if (id is String) return id;
      }
    }
    return null;
  }

  void _applyStyle(String style) {
    if (style == _appliedStyle) return;
    _appliedStyle = style;
    final map = _map;
    if (map != null) unawaited(map.setStyle(style));
  }

  TransportLayerColors _layerColors() {
    final scheme = Theme.of(context).colorScheme;
    return TransportLayerColors(
      routeCasing: _hex(scheme.surface),
      stopFill: _hex(scheme.surface),
      stopStroke: _hex(scheme.onSurface),
      selection: _hex(scheme.primary),
      label: _hex(scheme.onSurface),
      labelHalo: _hex(scheme.surface),
      nearest: _hex(Theme.of(context).extension<AppSemanticColors>()!.info),
    );
  }

  BusMarkerColors _busColors() {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return BusMarkerColors(
      live: _hex(semantic.success),
      delayed: _hex(semantic.warning),
      offline: _hex(semantic.offline),
      outline: _hex(scheme.surface),
      selection: _hex(scheme.primary),
      label: _hex(scheme.onSurface),
      labelHalo: _hex(scheme.surface),
    );
  }

  static String _hex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final offlineMap = ref.watch(offlineMapServiceProvider);
    if (!offlineMap.isReady) {
      // The map data is missing or being prepared. Drop the old map so a
      // fresh one is created when the data is back.
      _forgetMap();
      return OfflineMapPlaceholder(state: offlineMap);
    }

    final config = ref.watch(universityMapConfigurationProvider);
    final mapStyle = Theme.of(context).brightness == Brightness.dark
        ? UniversityMapStyle.dark
        : UniversityMapStyle.light;
    final style = ref.watch(mapStyleJsonProvider(mapStyle));

    ref.listen(transportNetworkProvider, (previous, next) {
      final network = next.value;
      if (network != null) unawaited(_onNetworkChanged(network));
    });
    ref.listen(trackedBusesProvider, (previous, next) {
      unawaited(_onBusesChanged());
    });
    ref.listen(mapSelectionProvider, (previous, next) {
      unawaited(_onSelectionChanged(next));
      // Which line is on the middle of the road has changed.
      unawaited(_drawPredicted());
    });
    ref.listen(predictedBusesProvider, (previous, next) {
      unawaited(_drawPredicted());
    });
    ref.listen(nearestStopProvider, (previous, next) {
      unawaited(
        _transportLayers
            .showNearestStop(_map, next?.stop.id, attached: _layersAttached)
            .catchError(
              (Object error) =>
                  debugPrint('Could not mark the nearest stop: $error'),
            ),
      );
    });
    // The arrows turn round with the direction being shown.
    ref.listen(routeShownReversedProvider, (previous, next) {
      unawaited(_drawFlow(force: true));
    });
    // Re-centre was asked for, or the way the map faces was switched.
    ref.listen(followPausedProvider, (previous, next) {
      if (previous == true && !next) unawaited(_recentreOnFollowedBus());
    });
    ref.listen(followHeadingUpProvider, (previous, next) {
      if (previous != next) unawaited(_recentreOnFollowedBus());
    });

    final styleJson = style.value;
    if (styleJson != null) {
      _initialStyle ??= styleJson;
      if (_appliedStyle == null) {
        _appliedStyle = styleJson;
      } else if (styleJson != _appliedStyle) {
        // Theme changed: swap the style once this frame is done.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyStyle(styleJson);
        });
      }
    }

    final initialStyle = _initialStyle;
    if (initialStyle == null) {
      if (style.hasError) {
        return _MapUnavailable(
          onRetry: () => ref.invalidate(mapResourcesProvider),
        );
      }
      return const _MapLoading();
    }

    final bounds = config.coverageBounds;
    return Listener(
      onPointerDown: (event) => _pointerDownAt = event.position,
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _pointerDownAt = null,
      onPointerCancel: (_) => _pointerDownAt = null,
      // Zooming with the mouse wheel is moving the map by hand too.
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) _pauseFollowing();
      },
      child: MapLibreMap(
        styleString: initialStyle,
        initialCameraPosition: CameraPosition(
          target: LatLng(config.centerLatitude, config.centerLongitude),
          zoom: config.initialZoom,
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
        myLocationEnabled: ref.watch(userLocationVisibleProvider),
        // Attribution is shown by the app's own label so it stays visible
        // above the bottom sheet.
        attributionEnabled: false,
        // The zoom is needed to keep each bus on its own route line.
        trackCameraPosition: true,
        // The compass sits below the route chips, which float across the top
        // of the map. The web map cannot move its compass, so it has none.
        compassEnabled: !kIsWeb,
        compassViewPosition: CompassViewPosition.topRight,
        compassViewMargins: Point(16, MediaQuery.paddingOf(context).top + 76),
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleLoaded,
        onMapClick: _onMapTapped,
        onCameraMoveStarted: _onCameraMoveStarted,
      ),
    );
  }
}

/// The `id` of the point feature nearest to a tap at [latitude],
/// [longitude], among the [features] MapLibre found around it; null when
/// there is none.
@visibleForTesting
String? nearestTappedId(
  List<dynamic> features,
  double latitude,
  double longitude,
) {
  String? nearest;
  var nearestDistance = double.infinity;
  for (final feature in features) {
    if (feature is! Map) continue;
    final properties = feature['properties'];
    final geometry = feature['geometry'];
    if (properties is! Map || properties['id'] is! String) continue;
    final id = properties['id'] as String;
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      // No position to compare: keep it only if nothing better turns up.
      nearest ??= id;
      continue;
    }
    final distance = haversineDistanceMeters(
      latitude,
      longitude,
      (coordinates[1] as num).toDouble(),
      (coordinates[0] as num).toDouble(),
    );
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = id;
    }
  }
  return nearest;
}

class _MapLoading extends StatelessWidget {
  const _MapLoading();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: EmptyState(
        icon: Icons.map_rounded,
        title: 'The map could not be opened',
        message:
            'The map data on this device could not be prepared. Check that '
            'the device has free storage, then try again.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
    );
  }
}
