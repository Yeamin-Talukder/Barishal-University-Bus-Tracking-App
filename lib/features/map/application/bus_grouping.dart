import 'dart:math' as math;

import '../../../core/utils/geo_math.dart';
import '../../../data/models/geo_point.dart';

/// Several buses whose markers would lie on top of each other, shown as
/// one marker with a count.
class BusGroup {
  const BusGroup({required this.busIds, required this.position});

  /// The buses in the group, in the order they were given.
  final List<String> busIds;

  /// The middle of the group.
  final GeoPoint position;
}

/// How far apart, on screen, two bus markers must be to be drawn apart.
/// The badge is about 52 pixels across with its name under it, so closer
/// than this the badges touch and one bus's name lies on another's badge.
const double busGroupWithinPixels = 44;

/// Ground distance of one screen pixel at [zoom] and [latitude]. The map's
/// tiles are 512 pixels across.
double metersPerPixelAt(double zoom, double latitude) =>
    78271.51696 * math.cos(degreesToRadians(latitude)) / math.pow(2, zoom);

/// Finds the buses whose markers would overlap at [zoom].
///
/// Buses within [withinPixels] of each other on screen become one group.
/// Zooming in moves them apart on screen, so a group splits by itself.
/// [keepApartId] is never grouped: the bus the passenger picked always has
/// its own marker. A bus alone is in no group.
List<BusGroup> groupOverlappingBuses(
  List<({String id, GeoPoint position})> markers, {
  required double zoom,
  double withinPixels = busGroupWithinPixels,
  String? keepApartId,
}) {
  final free = [
    for (final marker in markers)
      if (marker.id != keepApartId) marker,
  ];
  final groups = <BusGroup>[];
  final taken = <String>{};
  for (final seed in free) {
    if (taken.contains(seed.id)) continue;
    final reach = withinPixels * metersPerPixelAt(zoom, seed.position.latitude);
    final members = [
      for (final other in free)
        if (!taken.contains(other.id) &&
            haversineDistanceMeters(
                  seed.position.latitude,
                  seed.position.longitude,
                  other.position.latitude,
                  other.position.longitude,
                ) <=
                reach)
          other,
    ];
    if (members.length < 2) continue;
    taken.addAll(members.map((member) => member.id));
    groups.add(
      BusGroup(
        busIds: [for (final member in members) member.id],
        position: GeoPoint(
          members.map((m) => m.position.latitude).reduce((a, b) => a + b) /
              members.length,
          members.map((m) => m.position.longitude).reduce((a, b) => a + b) /
              members.length,
        ),
      ),
    );
  }
  return groups;
}

/// How long ago a bus was last heard from, short enough to sit beside its
/// marker: "25 s ago", "4 min ago", "2 h ago", "3 d ago".
String seenAgoShort(Duration age) {
  if (age.inSeconds < 60) {
    // In steps of five, so the text does not flicker every second.
    final seconds = math.max(5, (age.inSeconds ~/ 5) * 5);
    return '$seconds s ago';
  }
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return '${age.inHours} h ago';
  return '${age.inDays} d ago';
}
