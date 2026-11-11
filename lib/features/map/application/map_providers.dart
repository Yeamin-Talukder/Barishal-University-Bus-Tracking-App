import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/university_map_configuration.dart';
import '../data/map_package.dart';
import 'map_style_service.dart';
import 'offline_map_service.dart';

final mapStyleServiceProvider = Provider<MapStyleService>(
  (ref) => MapStyleService(bundle: rootBundle),
);

/// Location of the installed map data. Fails while the map is not installed.
///
/// Not retried automatically: it is recomputed when the map becomes ready.
final mapResourcesProvider = FutureProvider<MapResources>((ref) {
  final isReady = ref.watch(
    offlineMapServiceProvider.select((state) => state.isReady),
  );
  if (!isReady) throw StateError('The offline map is not installed.');
  return ref.watch(mapTileRepositoryProvider).resources();
}, retry: (retryCount, error) => null);

/// The ready-to-use style JSON for each map theme.
final mapStyleJsonProvider = FutureProvider.family<String, UniversityMapStyle>((
  ref,
  style,
) async {
  final resources = await ref.watch(mapResourcesProvider.future);
  return ref.watch(mapStyleServiceProvider).loadStyle(style, resources);
});
