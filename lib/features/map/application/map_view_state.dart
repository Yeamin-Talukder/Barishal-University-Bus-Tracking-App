import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/preferences_service.dart';
import 'map_selection.dart';

/// Whether following a bus is on hold because the passenger moved the map
/// themselves. The bus stays picked and "followed"; the camera just stops
/// chasing it until they ask it to re-centre.
class FollowPaused extends Notifier<bool> {
  @override
  bool build() {
    // A new bus, or following switched on or off, starts afresh.
    ref.listen(mapSelectionProvider, (previous, next) {
      if (previous?.busId != next.busId ||
          previous?.isFollowingBus != next.isFollowingBus) {
        state = false;
      }
    });
    return false;
  }

  void pause() => state = true;

  void resume() => state = false;
}

final followPausedProvider = NotifierProvider<FollowPaused, bool>(
  FollowPaused.new,
);

/// While following a bus: whether the map turns to face the way the bus is
/// going (as car navigation does) or stays north-up. Remembered on the
/// device.
class FollowHeadingUp extends Notifier<bool> {
  static const String _key = 'map.followHeadingUp';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? true;

  void set(bool headingUp) {
    state = headingUp;
    ref.read(sharedPreferencesProvider).setBool(_key, headingUp);
  }

  void toggle() => set(!state);
}

final followHeadingUpProvider = NotifierProvider<FollowHeadingUp, bool>(
  FollowHeadingUp.new,
);

/// Which way the picked route is being shown: false from its start to its
/// end, true the other way. A newly picked route starts at false.
class RouteShownReversed extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(mapSelectionProvider.select((selection) => selection.routeId), (
      previous,
      next,
    ) {
      if (previous != next) state = false;
    });
    return false;
  }

  void toggle() => state = !state;

  void set(bool reversed) => state = reversed;
}

final routeShownReversedProvider = NotifierProvider<RouteShownReversed, bool>(
  RouteShownReversed.new,
);
