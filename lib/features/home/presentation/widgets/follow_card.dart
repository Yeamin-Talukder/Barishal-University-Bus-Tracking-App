import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/eta_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../data/models/bus.dart';
import '../../../../data/repositories/bus_location_repository.dart';
import '../../../../data/repositories/transport_network_repository.dart';
import '../../../buses/presentation/arrival_text.dart';
import '../../../buses/presentation/bus_card.dart';
import '../../../buses/presentation/bus_status.dart';
import '../../../map/application/map_selection.dart';
import '../../../map/application/map_view_state.dart';

/// The small card shown over the map while it follows a bus.
///
/// The map is moving by itself, so the card says which bus it is on, where
/// that bus is going next and when, and how fresh its position is. It also
/// holds the controls for following: turn with the bus or stay north-up,
/// re-centre after the passenger has moved the map, and stop.
class FollowCard extends ConsumerWidget {
  const FollowCard({required this.tracked, super.key});

  final TrackedBus tracked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = busStatusNow(ref, tracked);
    final paused = ref.watch(followPausedProvider);
    final headingUp = ref.watch(followHeadingUpProvider);
    final network = ref.watch(transportNetworkProvider).value;
    final route = tracked.bus.routeId == null
        ? null
        : network?.routeById(tracked.bus.routeId!);
    final next = network == null || route == null
        ? null
        : ref
              .watch(etaServiceProvider)
              .estimateNextStop(
                route: route,
                stops: network.stopsOf(route),
                location: tracked.location,
                now: ref.watch(clockProvider)(),
              );
    final nextStop = next?.nextStop;
    final estimate = next?.estimate;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                10,
                AppSpacing.xs,
                10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BusBadge(color: status.color(context), size: 38),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Following Bus ${tracked.bus.number}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            BusStatusPill(tracked: tracked),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (nextStop != null && estimate != null)
                          Text(
                            'Next: ${nextStop.name} · ${arrivalText(estimate)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          Text(
                            status == BusTrackingStatus.live
                                ? 'Next stop not known yet'
                                : 'Shown where it was last seen',
                            style: muted,
                          ),
                        Text(lastSeenText(ref, tracked), style: muted),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: headingUp
                        ? 'Keep the map north-up'
                        : 'Turn the map with the bus',
                    visualDensity: VisualDensity.compact,
                    isSelected: headingUp,
                    onPressed: ref
                        .read(followHeadingUpProvider.notifier)
                        .toggle,
                    icon: const Icon(Icons.explore_outlined),
                    selectedIcon: const Icon(Icons.navigation_rounded),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(mapSelectionProvider.notifier)
                        .setFollowingBus(false),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ),
            // After the passenger has moved the map away from the bus.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: !paused
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: ref
                              .read(followPausedProvider.notifier)
                              .resume,
                          icon: const Icon(Icons.center_focus_strong_rounded),
                          label: const Text('Re-centre'),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
