import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/location_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../home/application/nearest_stop.dart';
import '../application/map_camera_controller.dart';
import '../application/map_selection.dart';
import '../application/university_map_configuration_provider.dart';
import 'map_legend.dart';

/// The floating map buttons: the key to the map, every route at once, the
/// university, and the passenger's own position.
class MapControls extends ConsumerStatefulWidget {
  const MapControls({super.key});

  @override
  ConsumerState<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends ConsumerState<MapControls> {
  bool _locating = false;

  Future<void> _showUniversity() {
    return ref.read(mapCameraControllerProvider).showUniversity();
  }

  /// Zooms out to every route at once, and lets go of whatever is picked
  /// so that nothing is left dimmed.
  Future<void> _showAllRoutes() {
    ref.read(mapSelectionProvider.notifier).clear();
    final routes = ref.read(transportNetworkProvider).value?.routes ?? const [];
    return ref.read(mapCameraControllerProvider).showRoutes(routes);
  }

  Future<void> _showMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);

    final service = ref.read(locationServiceProvider);
    final result = await service.currentLocation();
    if (!mounted) return;
    setState(() => _locating = false);

    switch (result) {
      case LocationFound(:final position):
        ref.read(userLocationVisibleProvider.notifier).show();
        final config = ref.read(universityMapConfigurationProvider);
        if (!config.isWithinCoverage(position.latitude, position.longitude)) {
          _showMessage('You are outside the area this map covers.');
          return;
        }
        // The nearest-stop card uses the same position.
        ref
            .read(userPositionProvider.notifier)
            .set(position, ref.read(clockProvider)());
        await ref.read(mapCameraControllerProvider).showUserLocation(position);
      case LocationUnavailable(:final problem, :final canFixInSettings):
        _showMessage(
          result.message,
          action: canFixInSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: () => service.openSettingsFor(problem),
                )
              : null,
        );
    }
  }

  void _showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = Container(
      width: 28,
      height: 1,
      color: scheme.outlineVariant.withValues(alpha: 0.7),
    );

    // One rounded block holding the buttons, as map apps do.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MapButton(
              tooltip: 'Map key',
              icon: Icons.help_outline_rounded,
              onPressed: () => showMapLegend(context),
            ),
            divider,
            _MapButton(
              tooltip: 'All routes',
              icon: Icons.zoom_out_map_rounded,
              onPressed: _showAllRoutes,
            ),
            divider,
            _MapButton(
              tooltip: 'University',
              icon: Icons.school_rounded,
              onPressed: _showUniversity,
            ),
            divider,
            _MapButton(
              tooltip: 'My location',
              icon: Icons.my_location_rounded,
              busy: _locating,
              onPressed: _showMyLocation,
            ),
          ],
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: tooltip,
      onPressed: busy ? null : onPressed,
      constraints: const BoxConstraints.tightFor(width: 50, height: 50),
      style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: busy
            ? SizedBox.square(
                key: const ValueKey('busy'),
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: scheme.primary,
                ),
              )
            : Icon(icon, key: ValueKey(icon), color: scheme.primary),
      ),
    );
  }
}
