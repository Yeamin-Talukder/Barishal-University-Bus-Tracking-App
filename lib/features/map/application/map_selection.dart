import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the passenger has picked to look at on the map. At most one of a
/// route, a stop or a bus is selected at a time.
@immutable
class MapSelection {
  const MapSelection({
    this.routeId,
    this.stopId,
    this.busId,
    this.isFollowingBus = false,
  });

  static const MapSelection none = MapSelection();

  final String? routeId;
  final String? stopId;
  final String? busId;

  /// Whether the camera should keep the selected bus in view.
  final bool isFollowingBus;

  bool get isEmpty => routeId == null && stopId == null && busId == null;

  @override
  bool operator ==(Object other) =>
      other is MapSelection &&
      other.routeId == routeId &&
      other.stopId == stopId &&
      other.busId == busId &&
      other.isFollowingBus == isFollowingBus;

  @override
  int get hashCode => Object.hash(routeId, stopId, busId, isFollowingBus);
}

final mapSelectionProvider =
    NotifierProvider<MapSelectionController, MapSelection>(
      MapSelectionController.new,
    );

class MapSelectionController extends Notifier<MapSelection> {
  @override
  MapSelection build() => MapSelection.none;

  void selectRoute(String routeId) => state = MapSelection(routeId: routeId);

  void selectStop(String stopId) => state = MapSelection(stopId: stopId);

  void selectBus(String busId) => state = MapSelection(busId: busId);

  /// Starts or stops the camera following the selected bus.
  void setFollowingBus(bool following) {
    final busId = state.busId;
    if (busId == null) return;
    state = MapSelection(busId: busId, isFollowingBus: following);
  }

  void clear() => state = MapSelection.none;
}
