import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_selection.dart';

/// How the map treats the passenger's own position, as map apps do.
///
/// The position itself comes from the phone's location sensors (satellites,
/// and the networks around it). Which way the passenger is facing comes
/// from its compass, steadied by its motion sensors: that is drawn as an
/// arrow on the dot, and in [compass] mode it turns the whole map.
enum MyLocationMode {
  /// The map stays where the passenger puts it. Their dot is still drawn,
  /// once their position has been found.
  free,

  /// The map keeps the passenger in the middle as they move, north-up.
  following,

  /// As [following], and the map turns with the phone, so that what is in
  /// front of the passenger is at the top of the screen.
  compass,
}

/// What the next tap on the location button does, as in other map apps:
/// the first tap follows the passenger, the next turns the map with the
/// phone, the one after goes back to north-up.
///
/// Without [hasCompassMode] (the web map cannot turn with the device)
/// there is only following.
MyLocationMode nextMyLocationMode(
  MyLocationMode current, {
  required bool hasCompassMode,
}) => switch (current) {
  MyLocationMode.free => MyLocationMode.following,
  MyLocationMode.following =>
    hasCompassMode ? MyLocationMode.compass : MyLocationMode.following,
  MyLocationMode.compass => MyLocationMode.following,
};

class MyLocationModeController extends Notifier<MyLocationMode> {
  @override
  MyLocationMode build() {
    // The camera cannot follow a bus and the passenger at once: following
    // a bus lets go of the passenger.
    ref.listen(mapSelectionProvider, (previous, next) {
      if (next.isFollowingBus && state != MyLocationMode.free) {
        state = MyLocationMode.free;
      }
    });
    return MyLocationMode.free;
  }

  void set(MyLocationMode mode) => state = mode;
}

/// How the map is following the passenger right now. It falls back to
/// [MyLocationMode.free] when they move the map themselves, or when the
/// map is sent to look at something else.
final myLocationModeProvider =
    NotifierProvider<MyLocationModeController, MyLocationMode>(
      MyLocationModeController.new,
    );

/// Whether the map can draw which way the passenger is facing and turn
/// with the phone. The phone apps can; the web map has no access to a
/// compass through the map it uses.
final compassModeAvailableProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS),
);
