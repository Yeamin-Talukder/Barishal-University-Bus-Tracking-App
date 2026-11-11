import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../shared/widgets/demo_data_notice.dart';
import '../../map/application/map_camera_controller.dart';
import '../../map/application/map_selection.dart';
import '../../map/application/offline_map_service.dart';
import '../../map/presentation/map_attribution.dart';
import '../../map/presentation/map_controls.dart';
import '../../map/presentation/university_map.dart';
import '../../test_drive/application/test_drive.dart';
import '../../prediction/application/prediction_providers.dart';
import 'widgets/home_sheet.dart';
import 'widgets/route_chips.dart';

/// The map-first home tab: a full-screen map with floating controls and a
/// draggable sheet.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the app learning from live buses, and saving what it learns,
    // for as long as the map page exists.
    ref.listen(predictionLearnerProvider, (previous, next) {});
    final buildMap = ref.watch(universityMapBuilderProvider);
    final network = ref.watch(transportNetworkProvider).value;
    final needsNotice = network?.needsNotice ?? false;
    // The map buttons and credit only make sense while a map is showing.
    final isMapReady = ref.watch(
      offlineMapServiceProvider.select((state) => state.isReady),
    );
    // Unknown counts as connected, so the label never flashes at startup.
    final isOffline = ref.watch(hasConnectionProvider).value == false;
    // The bus the map is following, by its number, if there is one.
    final selection = ref.watch(mapSelectionProvider);
    final followedBus = !selection.isFollowingBus
        ? null
        : (ref.watch(trackedBusesProvider).value ?? const [])
              .where((tracked) => tracked.bus.id == selection.busId)
              .map((tracked) => tracked.bus.number)
              .firstOrNull;
    // Pretend buses are on the map: say so for as long as they are.
    final isTesting = ref.watch(
      testDriveProvider.select((test) => test.isRunning),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Controls sit just above the collapsed sheet.
          final aboveSheet =
              constraints.maxHeight * HomeSheet.collapsedSize + AppSpacing.md;

          // Tell the camera what the sheet (when open to show a selection)
          // and the labels at the top cover, so it frames things beside
          // them. This only stores two numbers; nothing is rebuilt.
          ref.read(mapCameraControllerProvider)
            ..coveredTop =
                MediaQuery.paddingOf(context).top + RouteChips.height + 28
            ..coveredBottom = constraints.maxHeight * HomeSheet.halfSize;

          // On web the map is an HTML element under the Flutter canvas, and
          // would otherwise also react to taps and drags on the widgets drawn
          // over it. PointerInterceptor does nothing on Android and iOS.
          return Stack(
            children: [
              Positioned.fill(child: buildMap(context)),
              // Each label intercepts taps only over itself, so the map
              // beside it stays usable.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMapReady)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: PointerInterceptor(child: const RouteChips()),
                        ),
                      if (needsNotice)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            0,
                          ),
                          child: PointerInterceptor(
                            child: DemoDataNotice(origin: network!.origin),
                          ),
                        ),
                      if (followedBus != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: PointerInterceptor(
                            child: _FollowingLabel(
                              busNumber: followedBus,
                              onStop: () => ref
                                  .read(mapSelectionProvider.notifier)
                                  .setFollowingBus(false),
                            ),
                          ),
                        ),
                      if (isTesting)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: PointerInterceptor(
                            child: _TestModeLabel(
                              onStop: ref.read(testDriveProvider.notifier).stop,
                            ),
                          ),
                        ),
                      if (isOffline)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: PointerInterceptor(
                            child: const _OfflineLabel(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (isMapReady) ...[
                Positioned(
                  left: AppSpacing.md,
                  bottom: aboveSheet,
                  child: PointerInterceptor(child: const MapAttribution()),
                ),
                Positioned(
                  right: AppSpacing.lg,
                  bottom: aboveSheet,
                  child: PointerInterceptor(child: const MapControls()),
                ),
              ],
              const Positioned.fill(child: HomeSheet()),
            ],
          );
        },
      ),
    );
  }
}

/// Shown while the map follows a bus: it is turning and moving by itself,
/// so it says why, and offers the way out.
class _FollowingLabel extends StatelessWidget {
  const _FollowingLabel({required this.busNumber, required this.onStop});

  final String busNumber;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.navigation_rounded, size: 18, color: scheme.onPrimary),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Following Bus $busNumber',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onPrimary,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

/// Shown while a test is running, so the pretend buses on the map are
/// never taken for real ones. It also stops the test.
class _TestModeLabel extends StatelessWidget {
  const _TestModeLabel({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.science_rounded,
            size: 18,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Test mode: TEST buses are pretend',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onTertiaryContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

/// Shown while the device has no network connection. It makes the difference
/// clear: the map is still available, live bus positions are not.
class _OfflineLabel extends StatelessWidget {
  const _OfflineLabel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.extension<AppSemanticColors>()!.muted;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 18, color: muted),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'No connection. The map still works offline.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
