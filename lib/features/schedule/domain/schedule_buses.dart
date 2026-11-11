import '../../../data/models/bus.dart';
import 'bus_schedule.dart';

/// The buses the schedule names, as buses that can be added to the bus list.
///
/// The schedule writes the vehicles of a departure as text, for example
/// "Chitra, BRTC-04,06" or "Lota/Kirtankhola/Payra". This reads the
/// individual buses out of that text. Nothing is invented:
///
///  - A bus's number is its label in the schedule in English, and its name
///    is the same label in Bangla (or the English one where there is none).
///  - A bus gets a route only when the schedule names it on exactly one
///    route number. A bus used on several routes gets none.
///  - Every bus is in service, because the schedule lists it.
List<Bus> busesNamedInSchedule(BusSchedule schedule) {
  final found = <String, _NamedBus>{};

  for (final timetable in schedule.timetables) {
    for (final point in timetable.departures) {
      for (final trip in point.trips) {
        final english = _split(trip.vehicles.en, bangla: false);
        final bangla = _split(trip.vehicles.bn, bangla: true);
        // Where only one language is written, use it for both.
        final labels = english.isNotEmpty ? english : bangla;
        final paired = bangla.length == labels.length;
        for (final (index, label) in labels.indexed) {
          final entry = found.putIfAbsent(
            label.toLowerCase(),
            () => _NamedBus(label, paired ? bangla[index] : label),
          );
          entry.routes.add(timetable.routeNumber);
        }
      }
    }
  }

  final buses = [
    for (final entry in found.values)
      Bus(
        id: '',
        number: entry.label,
        name: entry.banglaLabel,
        routeId: entry.routes.length == 1 ? entry.routes.single : null,
        isActive: true,
      ),
  ];
  buses.sort(
    (a, b) => a.number.toLowerCase().compareTo(b.number.toLowerCase()),
  );
  return buses;
}

class _NamedBus {
  _NamedBus(this.label, this.banglaLabel);

  final String label;
  final String banglaLabel;
  final Set<String> routes = {};
}

/// Splits "Chitra, BRTC-04,06" into Chitra, BRTC-04 and BRTC-06.
List<String> _split(String text, {required bool bangla}) {
  final digit = bangla ? '[০-৯0-9]' : r'\d';
  var cleaned = text.trim();
  if (cleaned.isEmpty) return const [];

  // "2 buses (A/B/C)" and its Bangla form: keep what is in the brackets.
  cleaned = cleaned
      .replaceFirst(
        RegExp(
          bangla ? '^$digit+\\s*টি\\s*বাস\\s*' : '^$digit+\\s*buses?\\s*',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[()]'), ' ');

  final labels = <String>[];
  String? prefix;
  final separators = RegExp(bangla ? r'[,/]|\s+ও\s+' : r'[,/]|\s+and\s+');
  for (final raw in cleaned.split(separators)) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    if (prefix != null && RegExp('^$digit+\$').hasMatch(part)) {
      // "BRTC-04,05": the second number shares the first one's prefix.
      labels.add('$prefix$part');
      continue;
    }
    labels.add(part);
    final numbered = RegExp('^(.*?-)$digit+\$').firstMatch(part);
    prefix = numbered?.group(1);
  }
  return labels;
}
