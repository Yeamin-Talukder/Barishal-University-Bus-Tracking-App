import 'dart:math' show cos, max, min, pow, sin;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/constants/university_map_configuration.dart';
import '../../../core/utils/geo_math.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/models/geo_point.dart';
import 'university_map_configuration_provider.dart';

/// Moves the map camera on behalf of the UI.
///
/// The map widget attaches MapLibre's controller here when the map is
/// created, so buttons and lists can move the camera without holding a
/// reference to the map themselves.
class MapCameraController {
  MapCameraController(this._configuration);

  static const Duration _moveDuration = Duration(milliseconds: 700);
  static const double _userLocationZoom = 16;
  static const double _stopZoom = 16;
  static const double _busZoom = 15.5;

  /// While a bus is followed the camera is closer, leans forward, and
  /// turns to face the way the bus is going, as a navigation app does.
  static const double followZoom = 16.6;
  static const double followTilt = 45;

  /// The closest and furthest the passenger may zoom while following.
  static const double _followZoomNearest = 18;
  static const double _followZoomFurthest = 13.5;

  /// Space kept clear at the sides of something fitted on screen.
  static const double _sidePadding = 48;

  /// How much of the map the app's own widgets cover, in logical pixels: the
  /// labels at the top and the open sheet at the bottom. The home screen
  /// keeps this up to date. Selected things are centred in what is left, so
  /// they are not hidden behind the sheet.
  double coveredTop = 0;
  double coveredBottom = 0;

  /// How much a side panel covers at the left, on a wide screen.
  double coveredLeft = 0;

  /// Height of the map on screen, in logical pixels. Needed to keep a
  /// followed bus a little below the middle.
  double viewHeight = 0;

  /// While following with the map turned to the bus's heading, the bus is
  /// drawn this far below the middle of the uncovered part of the map (as
  /// a part of its height), so more of the road ahead is in view.
  static const double followLookAhead = 0.16;

  double _lookAheadPixels(bool headingUp) {
    if (!headingUp) return 0;
    final uncovered = viewHeight - coveredTop - coveredBottom;
    return uncovered <= 0 ? 0 : uncovered * followLookAhead;
  }

  final UniversityMapConfiguration _configuration;
  MapLibreMapController? _map;

  bool get isAttached => _map != null;

  /// The underlying MapLibre controller, for on-device tests that need to
  /// inspect what the map has drawn. App code moves the camera through the
  /// methods below instead.
  @visibleForTesting
  MapLibreMapController? get map => _map;

  void attach(MapLibreMapController map) => _map = map;

  void detach(MapLibreMapController map) {
    if (identical(_map, map)) _map = null;
  }

  /// Returns the camera to the university at the default zoom, facing north.
  Future<void> showUniversity() {
    return _moveTo(
      GeoPoint(_configuration.centerLatitude, _configuration.centerLongitude),
      zoom: _configuration.initialZoom,
    );
  }

  /// Centres the camera on the passenger's own position.
  Future<void> showUserLocation(GeoPoint position) {
    return _moveTo(position, zoom: _userLocationZoom);
  }

  /// Shows a bus stop close up, in the middle of the uncovered part of the
  /// map.
  Future<void> showStop(BusStop stop) {
    return _moveTo(_centreFor(stop.position, zoom: _stopZoom), zoom: _stopZoom);
  }

  /// Shows a bus close up, in the middle of the uncovered part of the map.
  /// While a bus is being followed this is called for each new position.
  Future<void> showBus(GeoPoint position) {
    return _moveTo(_centreFor(position, zoom: _busZoom), zoom: _busZoom);
  }

  /// The way the camera is facing, clockwise from north.
  double get bearing => _map?.cameraPosition?.bearing ?? 0;

  /// Turns to face a followed bus and leans the camera forward. Called
  /// once when following starts, and again to re-centre; [trackBus] then
  /// keeps up with the bus.
  ///
  /// With [headingUp] the map faces [headingDegrees] (or stays as it is
  /// turned when the heading is not known) and leans forward; without it
  /// the map is north-up and level. [keepZoom] keeps the passenger's own
  /// zoom, for re-centring.
  Future<void> enterFollow(
    GeoPoint position, {
    double? headingDegrees,
    bool headingUp = true,
    bool keepZoom = false,
  }) async {
    final facing = headingUp ? (headingDegrees ?? bearing) : 0.0;
    final zoom = keepZoom
        ? (_map?.cameraPosition?.zoom ?? followZoom).clamp(
            _followZoomFurthest,
            _followZoomNearest,
          )
        : followZoom;
    await _map?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _latLng(
            centreFor(
              position,
              zoom: zoom,
              bearingDegrees: facing,
              coveredTop: coveredTop,
              coveredBottom: coveredBottom,
              coveredLeft: coveredLeft,
              lookAheadPixels: _lookAheadPixels(headingUp),
            ),
          ),
          zoom: zoom,
          bearing: facing,
          tilt: headingUp ? followTilt : 0,
        ),
      ),
      duration: _moveDuration,
    );
  }

  /// Puts the camera on a followed bus at once, facing [bearingDegrees].
  /// Called many times a second while the bus moves, so the camera travels
  /// with the marker instead of catching up in steps. The passenger's own
  /// zoom is kept.
  Future<void> trackBus(
    GeoPoint position,
    double bearingDegrees, {
    bool headingUp = true,
  }) async {
    final map = _map;
    if (map == null) return;
    final zoom = (map.cameraPosition?.zoom ?? followZoom).clamp(
      _followZoomFurthest,
      _followZoomNearest,
    );
    await map.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _latLng(
            centreFor(
              position,
              zoom: zoom,
              bearingDegrees: bearingDegrees,
              coveredTop: coveredTop,
              coveredBottom: coveredBottom,
              coveredLeft: coveredLeft,
              lookAheadPixels: _lookAheadPixels(headingUp),
            ),
          ),
          zoom: zoom,
          bearing: bearingDegrees,
          tilt: headingUp ? followTilt : 0,
        ),
      ),
    );
  }

  /// Turns the map back to north-up and level, where it is.
  Future<void> leaveFollow() async {
    final map = _map;
    final camera = map?.cameraPosition;
    if (map == null || camera == null) return;
    await map.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: camera.target, zoom: camera.zoom),
      ),
      duration: _moveDuration,
    );
  }

  static LatLng _latLng(GeoPoint point) =>
      LatLng(point.latitude, point.longitude);

  GeoPoint _centreFor(GeoPoint point, {required double zoom}) => centreFor(
    point,
    zoom: zoom,
    bearingDegrees: 0,
    coveredTop: coveredTop,
    coveredBottom: coveredBottom,
    coveredLeft: coveredLeft,
  );

  /// The camera target that puts [point] in the middle of the uncovered
  /// part of the map rather than the middle of the whole map.
  ///
  /// With more covered at the bottom than the top, the camera has to look
  /// further "down the screen" than the point; which way that is on the
  /// ground depends on how the map is turned. A panel at the left
  /// ([coveredLeft]) moves the point to the right in the same way.
  /// [lookAheadPixels] puts the point that far below the middle instead of
  /// on it, so more of what lies ahead is seen.
  @visibleForTesting
  static GeoPoint centreFor(
    GeoPoint point, {
    required double zoom,
    required double bearingDegrees,
    required double coveredTop,
    required double coveredBottom,
    double coveredLeft = 0,
    double lookAheadPixels = 0,
  }) {
    // MapLibre zoom levels are for 512-pixel tiles.
    final metersPerPixel =
        earthCircumferenceMeters *
        cos(degreesToRadians(point.latitude)) /
        (512 * pow(2, zoom));
    // How far the camera looks down the screen from the point, and how
    // far to the left of it.
    final downMeters =
        ((coveredBottom - coveredTop) / 2 - lookAheadPixels) * metersPerPixel;
    final leftMeters = coveredLeft / 2 * metersPerPixel;
    // Up the screen is the way the camera faces; right is a quarter turn
    // clockwise from that.
    final facing = degreesToRadians(bearingDegrees);
    final north = -downMeters * cos(facing) + leftMeters * sin(facing);
    final east = -downMeters * sin(facing) - leftMeters * cos(facing);
    return GeoPoint(
      point.latitude + north / metersPerDegreeLatitude,
      point.longitude +
          east /
              (metersPerDegreeLatitude * cos(degreesToRadians(point.latitude))),
    );
  }

  /// [current] turned a part of the way towards [target], the short way
  /// round. Used every frame so the map turns smoothly with the bus instead
  /// of twitching with each small change of heading.
  static double turnTowards(double current, double target, double part) {
    final turn = ((target - current + 540) % 360) - 180;
    return (current + turn * part.clamp(0.0, 1.0) + 360) % 360;
  }

  /// Fits every route on screen, clear of the app's overlays.
  Future<void> showRoutes(List<BusRoute> routes) async {
    final points = [for (final route in routes) ...route.path];
    if (points.isEmpty) return showUniversity();
    final latitudes = points.map((point) => point.latitude);
    final longitudes = points.map((point) => point.longitude);
    await _map?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(latitudes.reduce(min), longitudes.reduce(min)),
          northeast: LatLng(latitudes.reduce(max), longitudes.reduce(max)),
        ),
        left: coveredLeft + _sidePadding,
        top: coveredTop + _sidePadding,
        right: _sidePadding,
        bottom: coveredBottom + _sidePadding,
      ),
      duration: _moveDuration,
    );
  }

  /// Fits a whole route on screen, clear of the app's overlays.
  Future<void> showRoute(BusRoute route) async {
    final latitudes = route.path.map((point) => point.latitude);
    final longitudes = route.path.map((point) => point.longitude);
    await _map?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(latitudes.reduce(min), longitudes.reduce(min)),
          northeast: LatLng(latitudes.reduce(max), longitudes.reduce(max)),
        ),
        left: coveredLeft + _sidePadding,
        top: coveredTop + _sidePadding,
        right: _sidePadding,
        bottom: coveredBottom + _sidePadding,
      ),
      duration: _moveDuration,
    );
  }

  Future<void> _moveTo(GeoPoint target, {required double zoom}) async {
    await _map?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(target.latitude, target.longitude),
          zoom: zoom,
        ),
      ),
      duration: _moveDuration,
    );
  }
}

final mapCameraControllerProvider = Provider<MapCameraController>((ref) {
  return MapCameraController(ref.watch(universityMapConfigurationProvider));
});

/// Whether the map draws the passenger's own position. Turned on only after
/// location permission has been granted.
final userLocationVisibleProvider =
    NotifierProvider<UserLocationVisibility, bool>(UserLocationVisibility.new);

class UserLocationVisibility extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
}
