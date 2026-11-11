import 'package:cloud_firestore/cloud_firestore.dart' hide GeoPoint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_bootstrap.dart';
import '../models/bus_route.dart';
import '../models/geo_point.dart';

/// The routes the transport office keeps in the database: each a line on
/// the map and the stops along it, in order.
///
/// Anyone may read them. Only an admin may change them.
abstract interface class RouteRepository {
  /// The routes, sorted by id, and again whenever one changes.
  Stream<List<BusRoute>> watchRoutes();
}

/// Reads a route document. Returns null for one that cannot be drawn, so a
/// damaged document never puts a wrong line on the map.
BusRoute? routeFromMap(String id, Map<String, dynamic> data) {
  final name = data['name'];
  final color = data['color'];
  final path = data['path'];
  if (name is! String || name.trim().isEmpty) return null;
  if (color is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
    return null;
  }
  if (path is! List) return null;

  final points = <GeoPoint>[];
  for (final item in path) {
    if (item is! Map) return null;
    final latitude = item['latitude'];
    final longitude = item['longitude'];
    if (latitude is! num || longitude is! num) return null;
    final point = GeoPoint(latitude.toDouble(), longitude.toDouble());
    if (!point.isValid) return null;
    points.add(point);
  }
  if (points.length < 2) return null;

  final stopIds = data['stopIds'];
  final start = data['startLocation'];
  final end = data['endLocation'];
  return BusRoute(
    id: id,
    name: name.trim(),
    colorHex: color.toUpperCase(),
    startName: start is String ? start : '',
    endName: end is String ? end : '',
    path: points,
    stopIds: [
      if (stopIds is List)
        for (final stopId in stopIds)
          if (stopId is String) stopId,
    ],
    // A route is running only when the database says so explicitly.
    isActive: data['isActive'] == true,
  );
}

/// Routes in the `routes` collection of Cloud Firestore.
class FirestoreRouteRepository implements RouteRepository {
  FirestoreRouteRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<BusRoute>> watchRoutes() =>
      _firestore.collection('routes').snapshots().map((snapshot) {
        final routes = <BusRoute>[
          for (final document in snapshot.docs)
            ?routeFromMap(document.id, document.data()),
        ];
        routes.sort((a, b) => a.id.compareTo(b.id));
        return routes;
      });
}

/// Used when the app is not connected to the tracking service.
class UnavailableRouteRepository implements RouteRepository {
  const UnavailableRouteRepository();

  @override
  Stream<List<BusRoute>> watchRoutes() => Stream.value(const []);
}

final routeRepositoryProvider = Provider<RouteRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableRouteRepository();
  }
  return FirestoreRouteRepository(FirebaseFirestore.instance);
});

/// The routes kept by the transport office, live.
final officialRoutesProvider = StreamProvider<List<BusRoute>>(
  (ref) => ref.watch(routeRepositoryProvider).watchRoutes(),
);
