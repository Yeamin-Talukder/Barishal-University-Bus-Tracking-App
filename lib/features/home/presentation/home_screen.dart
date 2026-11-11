import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/layout.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../shared/widgets/demo_data_notice.dart';
import '../../alerts/application/arrival_alert.dart';
import '../../alerts/presentation/arrival_alert_views.dart';
import '../../map/application/map_camera_controller.dart';
import '../../map/application/map_selection.dart';
import '../../map/application/offline_map_service.dart';
import '../../map/presentation/map_attribution.dart';
import '../../map/presentation/map_controls.dart';
import '../../map/presentation/map_legend.dart';
import '../../map/presentation/university_map.dart';
import '../../test_drive/application/test_drive.dart';
import '../../prediction/application/prediction_providers.dart';
import 'widgets/follow_card.dart';
import 'widgets/home_sheet.dart';
import 'widgets/route_chips.dart';

/// The map-first home tab: a full-screen map with floating controls and a
/// draggable sheet. On a wide screen the sheet is a panel at the side
/// instead, and the map has the rest.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// The side panel's width on a wide screen, and the gap around it.
  static const double panelWidth = 380;
  static const double panelGap = AppSpacing.md;

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
    // The bus the map is following, if there is one.
    final selection = ref.watch(mapSelectionProvider);
    final buses = ref.watch(trackedBusesProvider).value ?? const <TrackedBus>[];
    final followedBus = !selection.isFollowingBus
        ? null
        : buses
              .where((tracked) => tracked.bus.id == selection.busId)
              .firstOrNull;
    // Pretend buses are on the map: say so for as long as they are.
    final isTesting = ref.watch(
      testDriveProvider.select((test) => test.isRunning),
    );
    final hasAlert = ref.watch(
      arrivalAlertProvider.select((state) => state.alert != null),
    );
    final config = ref.watch(trackingConfigurationProvider);
    final now = ref.watch(clockProvider)();
    final liveCount = buses
        .where(
          (tracked) =>
              config.statusOf(tracked.location?.updatedAt, now) ==
              BusTrackingStatus.live,
        )
        .length;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = isWideLayout(constraints.biggest);
          // The panel never takes more than a little under half the width.
          final panel = math.min(panelWidth, constraints.maxWidth * 0.44);
          final besidePanel = wide ? panel + panelGap * 2 : 0.0;

          // Controls sit just above the collapsed sheet, or at the bottom
          // when there is no sheet.
          final aboveSheet = wide
              ? AppSpacing.lg
              : constraints.maxHeight * HomeSheet.collapsedSize + AppSpacing.md;

          // Tell the camera what the app's own widgets cover, so it frames
          // things beside them. This only stores numbers; nothing is
          // rebuilt.
          ref.read(mapCameraControllerProvider)
            ..coveredTop =
                MediaQuery.paddingOf(context).top + RouteChips.height + 28
            ..coveredBottom = wide
                ? 0
                : constraints.maxHeight * HomeSheet.halfSize
            ..coveredLeft = besidePanel
            ..viewHeight = constraints.maxHeight;

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
                left: besidePanel,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  left: !wide,
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
                            child: FollowCard(tracked: followedBus),
                          ),
                        ),
                      if (hasAlert)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: PointerInterceptor(
                            child: const ArrivalAlertLabel(),
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
                  left: besidePanel + (wide ? 0 : AppSpacing.md),
                  bottom: aboveSheet,
                  child: PointerInterceptor(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LiveKeyChip(liveCount: liveCount),
                        const SizedBox(height: 6),
                        const MapAttribution(),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: AppSpacing.lg,
                  bottom: aboveSheet,
                  child: PointerInterceptor(child: const MapControls()),
                ),
              ],
              if (wide)
                Positioned(
                  left: panelGap,
                  top: panelGap,
                  bottom: panelGap,
                  width: panel,
                  child: const SafeArea(
                    right: false,
                    child: HomeSheet(asPanel: true),
                  ),
                )
              else
                const Positioned.fill(child: HomeSheet()),
            ],
          );
        },
      ),
    );
  }
}

/// A small chip on the map saying how many buses are live. Tapping it
/// opens the key to the map: what green, amber, grey and dashed markers
/// mean.
class LiveKeyChip extends StatelessWidget {
  const LiveKeyChip({required this.liveCount, super.key});

  final int liveCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final color = liveCount > 0 ? semantic.success : semantic.offline;

    return Material(
      color: scheme.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: StadiumBorder(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showMapLegend(context),
        child: Tooltip(
          message: 'What the markers mean',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  liveCount == 0 ? 'No live bus' : '$liveCount live',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
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
