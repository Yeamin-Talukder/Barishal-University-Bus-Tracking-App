import 'dart:convert';

import '../models/bus_route.dart';
import '../models/bus_stop.dart';
import '../models/geo_point.dart';

/// Items read from a GeoJSON file, with a note for each entry that was
/// skipped.
class ParsedFeatures<T> {
  const ParsedFeatures(this.items, this.problems);

  final List<T> items;
  final List<String> problems;
}

/// Reads routes and stops from the GeoJSON import format described in
/// `docs/TRANSPORT_DATA_FORMAT.md`.
///
/// Invalid entries are skipped and reported rather than guessed at: a route
/// or stop with bad coordinates must never reach the map.
class TransportGeoJsonParser {
  const TransportGeoJsonParser({required this.fallbackRouteColors});

  /// Colours handed out, in order, to routes that do not specify one.
  final List<String> fallbackRouteColors;

  static final RegExp _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

  ParsedFeatures<BusStop> parseStops(String source) {
    final stops = <BusStop>[];
    final problems = <String>[];
    final seenIds = <String>{};

    for (final (index, feature) in _features(source, problems).indexed) {
      final label = 'Stop ${index + 1}';
      final properties = _properties(feature);
      final id = _text(properties['id']);
      final name = _text(properties['name']);
      final geometry = feature['geometry'];

      if (id == null || name == null) {
        problems.add('$label: "id" and "name" are required.');
        continue;
      }
      if (!seenIds.add(id)) {
        problems.add('$label: duplicate id "$id".');
        continue;
      }
      if (geometry is! Map || geometry['type'] != 'Point') {
        problems.add('$label ($id): geometry must be a Point.');
        continue;
      }
      final position = _point(geometry['coordinates']);
      if (position == null) {
        problems.add('$label ($id): invalid coordinates.');
        continue;
      }

      stops.add(
        BusStop(
          id: id,
          name: name,
          position: position,
          description: _text(properties['description']),
        ),
      );
    }
    return ParsedFeatures(stops, problems);
  }

  ParsedFeatures<BusRoute> parseRoutes(String source) {
    final routes = <BusRoute>[];
    final problems = <String>[];
    final seenIds = <String>{};

    for (final (index, feature) in _features(source, problems).indexed) {
      final label = 'Route ${index + 1}';
      final properties = _properties(feature);
      final id = _text(properties['id']);
      final name = _text(properties['name']);
      final geometry = feature['geometry'];

      if (id == null || name == null) {
        problems.add('$label: "id" and "name" are required.');
        continue;
      }
      if (!seenIds.add(id)) {
        problems.add('$label: duplicate id "$id".');
        continue;
      }
      if (geometry is! Map || geometry['type'] != 'LineString') {
        problems.add('$label ($id): geometry must be a LineString.');
        continue;
      }
      final coordinates = geometry['coordinates'];
      final path = coordinates is List
          ? coordinates.map(_point).toList()
          : const <GeoPoint?>[];
      if (path.length < 2 || path.contains(null)) {
        problems.add(
          '$label ($id): needs at least two points, all with valid '
          'coordinates.',
        );
        continue;
      }

      final color = _text(properties['color']);
      if (color != null && !_hexColor.hasMatch(color)) {
        problems.add('$label ($id): colour "$color" is not #RRGGBB; ignored.');
      }
      final stopIds = properties['stops'];

      routes.add(
        BusRoute(
          id: id,
          name: name,
          colorHex: color != null && _hexColor.hasMatch(color)
              ? color.toUpperCase()
              : fallbackRouteColors[routes.length % fallbackRouteColors.length],
          startName: _text(properties['start']) ?? '',
          endName: _text(properties['end']) ?? '',
          path: path.cast<GeoPoint>(),
          stopIds: stopIds is List
              ? stopIds.map(_text).whereType<String>().toList()
              : const [],
          isActive: properties['active'] != false,
        ),
      );
    }
    return ParsedFeatures(routes, problems);
  }

  List<Map<String, dynamic>> _features(String source, List<String> problems) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      problems.add('The file is not valid JSON: ${error.message}');
      return const [];
    }
    if (decoded is! Map ||
        decoded['type'] != 'FeatureCollection' ||
        decoded['features'] is! List) {
      problems.add('The file must be a GeoJSON FeatureCollection.');
      return const [];
    }
    return [
      for (final feature in decoded['features'] as List)
        if (feature is Map<String, dynamic>) feature,
    ];
  }

  Map<String, dynamic> _properties(Map<String, dynamic> feature) {
    final properties = feature['properties'];
    return properties is Map<String, dynamic> ? properties : const {};
  }

  String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Reads a GeoJSON position (`[longitude, latitude]`).
  GeoPoint? _point(Object? value) {
    if (value is! List || value.length < 2) return null;
    final longitude = value[0];
    final latitude = value[1];
    if (longitude is! num || latitude is! num) return null;
    final point = GeoPoint(latitude.toDouble(), longitude.toDouble());
    return point.isValid ? point : null;
  }
}
