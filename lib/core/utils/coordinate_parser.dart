import '../../data/models/geo_point.dart';

/// Reads a position out of text copied from a map app, most usefully Google
/// Maps. Returns null when the text holds no usable position; it never
/// guesses.
///
/// Understood:
///  - a decimal pair, latitude first: `22.690260, 90.359400`
///  - the same with degree signs and hemisphere letters:
///    `22.69026° N, 90.35940° E`
///  - degrees, minutes and seconds: `22°41'24.9"N 90°21'33.8"E`
///  - a full Google Maps link holding the position (`!3d..!4d..`,
///    `?q=..,..` or `@..,..`)
///
/// A short link such as `maps.app.goo.gl/...` holds no position in its text
/// and cannot be read.
GeoPoint? parseCoordinates(String input) {
  final text = _decoded(input).trim();
  if (text.isEmpty) return null;

  return _fromLink(text) ?? _fromDms(text) ?? _fromDecimalPair(text);
}

/// Undoes percent-encoding, as in a link's `%2C` for a comma. Text that is
/// not validly encoded is used as it is.
String _decoded(String input) {
  if (!input.contains('%')) return input;
  try {
    return Uri.decodeComponent(input);
  } on ArgumentError {
    return input;
  } on FormatException {
    return input;
  }
}

/// A position as text that Google Maps accepts in its search box, and that
/// [parseCoordinates] reads back: `22.690260, 90.359400`.
String coordinatesToText(GeoPoint point) =>
    '${point.latitude.toStringAsFixed(6)}, '
    '${point.longitude.toStringAsFixed(6)}';

const String _number = r'-?\d{1,3}(?:\.\d+)?';

GeoPoint? _point(double latitude, double longitude) {
  final point = GeoPoint(latitude, longitude);
  return point.isValid ? point : null;
}

GeoPoint? _fromLink(String text) {
  if (!text.contains('://') && !text.contains('maps')) return null;
  final patterns = [
    // The pin of the place itself. Preferred over the map's centre.
    RegExp('!3d($_number)!4d($_number)'),
    RegExp(
      '[?&](?:q|query|ll|destination|daddr)=(?:loc:)?($_number),\\s*($_number)',
    ),
    // The centre of the map when the link was copied.
    RegExp('@($_number),($_number)'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      return _point(double.parse(match[1]!), double.parse(match[2]!));
    }
  }
  return null;
}

GeoPoint? _fromDms(String text) {
  const part =
      r'''(\d{1,3})\s*°\s*(\d{1,2})\s*['′’]\s*(\d{1,2}(?:\.\d+)?)\s*(?:"|″|”|'')\s*([NSEWnsew])''';
  final match = RegExp('$part[\\s,]*$part').firstMatch(text);
  if (match == null) return null;

  double value(int offset) {
    final degrees = double.parse(match[offset]!);
    final minutes = double.parse(match[offset + 1]!);
    final seconds = double.parse(match[offset + 2]!);
    if (minutes >= 60 || seconds >= 60) return double.nan;
    final letter = match[offset + 3]!.toUpperCase();
    final sign = letter == 'S' || letter == 'W' ? -1 : 1;
    return sign * (degrees + minutes / 60 + seconds / 3600);
  }

  final first = match[4]!.toUpperCase();
  final second = match[8]!.toUpperCase();
  final firstIsLatitude = first == 'N' || first == 'S';
  final secondIsLatitude = second == 'N' || second == 'S';
  if (firstIsLatitude == secondIsLatitude) return null;
  return firstIsLatitude
      ? _point(value(1), value(5))
      : _point(value(5), value(1));
}

GeoPoint? _fromDecimalPair(String text) {
  final match = RegExp(
    '^[\\s(\\[]*($_number)\\s*°?\\s*([NSns])?\\s*[,;\\s]\\s*'
    '($_number)\\s*°?\\s*([EWew])?[\\s)\\]]*\$',
  ).firstMatch(text);
  if (match == null) return null;

  var latitude = double.parse(match[1]!);
  var longitude = double.parse(match[3]!);
  if (match[2]?.toUpperCase() == 'S') latitude = -latitude.abs();
  if (match[4]?.toUpperCase() == 'W') longitude = -longitude.abs();
  return _point(latitude, longitude);
}
