import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/geo_math.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/repositories/transport_network_repository.dart';

/// Where the passenger was when the device last gave a position.
class UserPosition {
  const UserPosition(this.position, this.at);

  final GeoPoint position;
  final DateTime at;
}

/// The passenger's own position, once they have asked for it (with the
/// "My location" button or from the nearest-stop card). Null until then.
/// It is kept on the device only and never sent anywhere.
class UserPositionController extends Notifier<UserPosition?> {
  @override
  UserPosition? build() => null;

  void set(GeoPoint position, DateTime at) =>
      state = UserPosition(position, at);

  void clear() => state = null;
}

final userPositionProvider =
    NotifierProvider<UserPositionController, UserPosition?>(
      UserPositionController.new,
    );

/// The stop closest to the passenger.
class NearestStop {
  const NearestStop({required this.stop, required this.distanceMeters});

  final BusStop stop;

  /// Straight-line distance from the passenger to the stop.
  final double distanceMeters;

  /// Roughly how long the walk is. The app has no footpaths to measure
  /// along, so this is the straight-line distance made a third longer for
  /// streets that do not run straight, at an easy walking pace.
  Duration get walkingTime => walkingTimeFor(distanceMeters);
}

/// Streets rarely run straight to where one is going.
const double walkDetourFactor = 1.3;

/// An easy walking pace: about 4.7 km/h.
const double walkingMetersPerSecond = 1.3;

/// Beyond this a stop is too far to call "near" or to suggest walking to.
const double nearestStopWithinMeters = 3000;

Duration walkingTimeFor(double straightLineMeters) => Duration(
  seconds: (straightLineMeters * walkDetourFactor / walkingMetersPerSecond)
      .round(),
);

/// The stop of [stops] nearest to [from] in a straight line, or null when
/// there are no stops.
NearestStop? nearestStopTo(GeoPoint from, List<BusStop> stops) {
  NearestStop? nearest;
  for (final stop in stops) {
    final distance = haversineDistanceMeters(
      from.latitude,
      from.longitude,
      stop.position.latitude,
      stop.position.longitude,
    );
    if (nearest == null || distance < nearest.distanceMeters) {
      nearest = NearestStop(stop: stop, distanceMeters: distance);
    }
  }
  return nearest;
}

/// What to tell a passenger who wants to catch a bus at a stop.
enum LeaveAdvice {
  /// There is time to spare before setting off.
  wait,

  /// Set off now to be there when the bus is.
  leaveNow,

  /// The walk is longer than the bus will take.
  tooLate,
}

/// When to set off to catch a bus that arrives in [busIn], for a walk of
/// [walk]. A minute is kept in hand, since both numbers are estimates.
({LeaveAdvice advice, Duration leaveIn}) leaveAdvice({
  required Duration walk,
  required Duration busIn,
}) {
  final spare = busIn - walk;
  if (spare < const Duration(seconds: -45)) {
    return (advice: LeaveAdvice.tooLate, leaveIn: Duration.zero);
  }
  if (spare <= const Duration(minutes: 1, seconds: 30)) {
    return (advice: LeaveAdvice.leaveNow, leaveIn: Duration.zero);
  }
  return (
    advice: LeaveAdvice.wait,
    leaveIn: spare - const Duration(minutes: 1),
  );
}

/// The advice as a sentence.
String leaveAdviceText(
  ({LeaveAdvice advice, Duration leaveIn}) advice,
) => switch (advice.advice) {
  LeaveAdvice.tooLate => 'The walk is longer than that. Try the next bus.',
  LeaveAdvice.leaveNow => 'Leave now to catch it.',
  LeaveAdvice.wait =>
    'Leave in about ${(advice.leaveIn.inSeconds / 60).round().clamp(1, 999)} min.',
};

/// A straight-line distance for display: "350 m" or "1.4 km".
String distanceText(double meters) {
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    return '${rounded < 10 ? 10 : rounded} m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// The stop nearest to the passenger, when their position is known and a
/// stop is within [nearestStopWithinMeters]. Null otherwise.
final nearestStopProvider = Provider<NearestStop?>((ref) {
  final user = ref.watch(userPositionProvider);
  final network = ref.watch(transportNetworkProvider).value;
  if (user == null || network == null) return null;
  final nearest = nearestStopTo(user.position, network.stops);
  if (nearest == null || nearest.distanceMeters > nearestStopWithinMeters) {
    return null;
  }
  return nearest;
});
