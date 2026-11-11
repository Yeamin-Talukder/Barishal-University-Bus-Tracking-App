const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A storage size for display, for example `14.6 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A position for display, for example `22.65997° N, 90.36338° E`.
String formatCoordinates(double latitude, double longitude) {
  final northSouth = latitude >= 0 ? 'N' : 'S';
  final eastWest = longitude >= 0 ? 'E' : 'W';
  return '${latitude.abs().toStringAsFixed(5)}° $northSouth, '
      '${longitude.abs().toStringAsFixed(5)}° $eastWest';
}

/// How long ago something happened, for example `12 seconds ago`.
String formatAge(Duration age) {
  if (age.inSeconds < 5) return 'just now';
  if (age.inSeconds < 60) return '${age.inSeconds} seconds ago';
  if (age.inMinutes < 60) {
    return age.inMinutes == 1 ? '1 minute ago' : '${age.inMinutes} minutes ago';
  }
  if (age.inHours < 24) {
    return age.inHours == 1 ? '1 hour ago' : '${age.inHours} hours ago';
  }
  return age.inDays == 1 ? '1 day ago' : '${age.inDays} days ago';
}

/// A compass direction for a heading in degrees clockwise from north, for
/// example `north-east`.
String formatHeading(double degrees) {
  const names = [
    'north',
    'north-east',
    'east',
    'south-east',
    'south',
    'south-west',
    'west',
    'north-west',
  ];
  final normalised = degrees % 360;
  return names[((normalised + 22.5) ~/ 45) % 8];
}

/// A speed for display in km/h, for example `28 km/h`.
String formatSpeed(double metersPerSecond) =>
    '${(metersPerSecond * 3.6).round()} km/h';

/// A time of day for display, from minutes after midnight, for example
/// `8:30 AM` or `12:10 PM`.
String formatClockTime(int minutesAfterMidnight) {
  final hour24 = (minutesAfterMidnight ~/ 60) % 24;
  final minute = minutesAfterMidnight % 60;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final half = hour24 < 12 ? 'AM' : 'PM';
  return '$hour12:${minute.toString().padLeft(2, '0')} $half';
}

/// Reads a time of day as typed: `8:30 AM`, `8.30pm`, `16:05` or `1605`.
/// Returns minutes after midnight, or null when the text is not a time.
int? parseClockTime(String input) {
  final match = RegExp(
    r'^\s*(\d{1,2})\s*[:.]?\s*(\d{2})?\s*([AaPp])\.?\s*[Mm]?\.?\s*$|'
    r'^\s*(\d{1,2})\s*[:.]\s*(\d{2})\s*$|'
    r'^\s*(\d{2})(\d{2})\s*$',
  ).firstMatch(input);
  if (match == null) return null;

  final int hour;
  final int minute;
  if (match[3] != null) {
    // Twelve-hour, with AM or PM.
    final hour12 = int.parse(match[1]!);
    minute = int.parse(match[2] ?? '0');
    if (hour12 < 1 || hour12 > 12) return null;
    final isPm = match[3]!.toLowerCase() == 'p';
    hour = hour12 % 12 + (isPm ? 12 : 0);
  } else {
    hour = int.parse(match[4] ?? match[6]!);
    minute = int.parse(match[5] ?? match[7]!);
    if (hour > 23) return null;
  }
  if (minute > 59) return null;
  return hour * 60 + minute;
}

/// A date for display, for example `10 November 2026`.
String formatDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
