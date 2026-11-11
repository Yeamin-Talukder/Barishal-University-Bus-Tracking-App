import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../shared/widgets/info_tile.dart';
import '../../../shared/widgets/route_color.dart';
import '../../../shared/widgets/stop_badge.dart';
import 'bus_card.dart';
import 'bus_journey.dart';
import 'bus_status.dart';

/// Everything known about one bus, with the control to follow it on the map.
///
/// Each fact has a card of its own: where the bus is heading and when it
/// should get there, how fast it is going and which way, its route, when it
/// last reported and where.
///
/// Values that cannot be trusted are shown as unavailable rather than
/// guessed: speed and direction need a good, moving GPS fix, and the next
/// stop and arrival estimate come from the ETA service, which says why when
/// it has none.
class BusDetailsView extends ConsumerWidget {
  const BusDetailsView({
    required this.tracked,
    required this.route,
    required this.isFollowing,
    required this.onFollowChanged,
    required this.onClose,
    this.nextStopName,
    this.estimatedArrival,
    super.key,
  });

  final TrackedBus tracked;

  /// The route the bus is assigned to, if it is known.
  final BusRoute? route;

  final bool isFollowing;
  final ValueChanged<bool> onFollowChanged;
  final VoidCallback onClose;

  /// The next stop on the route, when it can be worked out.
  final String? nextStopName;

  /// The arrival estimate for the next stop, or the reason there is none.
  final String? estimatedArrival;

  static const String _unavailable = 'Not available';

  /// The speed that fills the speed bar. A bus in town rarely goes faster.
  static const double _fullBarMetersPerSecond = 60 / 3.6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bus = tracked.bus;
    final location = tracked.location;
    final status = busStatusNow(ref, tracked);
    final statusColor = status.color(context);
    final journey = busJourneyNow(ref, tracked);
    final config = ref.watch(trackingConfigurationProvider);

    // Speed and heading from an old or poor fix would mislead.
    final motionIsReliable =
        location != null &&
        status == BusTrackingStatus.live &&
        config.hasReliableMotion(location);
    final speed = motionIsReliable ? location.speedMetersPerSecond : null;
    final heading = motionIsReliable ? location.headingDegrees : null;

    Widget pair(Widget left, Widget right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: right),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The badge the bus has on the map, in its status colour.
              BusBadge(color: statusColor, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Bus ${bus.number}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        BusStatusPill(tracked: tracked),
                      ],
                    ),
                    Text(
                      bus.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (journey != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.near_me_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              journey,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (status != BusTrackingStatus.live && location != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: SoftCard(
                color: statusColor.withValues(alpha: 0.1),
                borderColor: statusColor.withValues(alpha: 0.35),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: statusColor, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'This is the last position the bus reported, not '
                        'where it is now.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Appear(
            child: _NextStopCard(
              stopName: nextStopName,
              arrival: estimatedArrival,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Appear(
            delay: const Duration(milliseconds: 60),
            child: pair(
              InfoTile(
                icon: const Icon(Icons.speed_rounded),
                label: 'Speed',
                value: speed == null ? _unavailable : formatSpeed(speed),
                isKnown: speed != null,
                footer: _SpeedBar(
                  fraction: speed == null
                      ? 0
                      : (speed / _fullBarMetersPerSecond).clamp(0.0, 1.0),
                ),
              ),
              InfoTile(
                // The arrow points the way the bus is heading, north up.
                icon: heading == null
                    ? const Icon(Icons.explore_rounded)
                    : AnimatedRotation(
                        turns: heading / 360,
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        child: const Icon(Icons.navigation_rounded),
                      ),
                label: 'Direction',
                value: heading == null
                    ? _unavailable
                    : 'Heading ${formatHeading(heading)}',
                isKnown: heading != null,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Appear(
            delay: const Duration(milliseconds: 120),
            child: pair(
              InfoTile(
                icon: const Icon(Icons.route_rounded),
                label: 'Route',
                value: route?.name ?? 'No route assigned',
                color: route == null ? null : routeColor(route!.colorHex),
                isKnown: route != null,
              ),
              InfoTile(
                icon: const Icon(Icons.update_rounded),
                label: 'Last update',
                value: lastSeenText(ref, tracked),
                color: statusColor,
                isKnown: location != null,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Appear(
            delay: const Duration(milliseconds: 180),
            child: InfoTile(
              icon: const Icon(Icons.my_location_rounded),
              label: 'Location',
              value: location == null
                  ? _unavailable
                  : formatCoordinates(
                      location.position.latitude,
                      location.position.longitude,
                    ),
              isKnown: location != null,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: isFollowing
                ? OutlinedButton.icon(
                    onPressed: () => onFollowChanged(false),
                    icon: const Icon(Icons.gps_off_rounded),
                    label: const Text('Stop following'),
                  )
                : FilledButton.icon(
                    // There is nothing to follow without a position.
                    onPressed: location == null
                        ? null
                        : () => onFollowChanged(true),
                    icon: const Icon(Icons.gps_fixed_rounded),
                    label: const Text('Follow this bus'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Where the bus is heading and when it should get there: the two things a
/// passenger looks for first.
class _NextStopCard extends StatelessWidget {
  const _NextStopCard({required this.stopName, required this.arrival});

  final String? stopName;
  final String? arrival;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final isKnown = stopName != null;

    return SoftCard(
      color: scheme.primary.withValues(alpha: isKnown ? 0.09 : 0.04),
      borderColor: scheme.primary.withValues(alpha: isKnown ? 0.3 : 0.12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StopBadge(highlighted: isKnown),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next stop', style: muted),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previousChildren, ?currentChild],
                      ),
                      child: Text(
                        stopName ?? BusDetailsView._unavailable,
                        key: ValueKey(stopName),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isKnown
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: scheme.primary.withValues(alpha: 0.18)),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Arrival at next stop', style: muted),
                    const SizedBox(height: 2),
                    Text(
                      arrival ?? BusDetailsView._unavailable,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A bar that fills with the bus's reported speed, and moves smoothly when
/// the speed changes. Empty when the speed is not known.
class _SpeedBar extends StatelessWidget {
  const _SpeedBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fraction),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 5,
          backgroundColor: scheme.outlineVariant.withValues(alpha: 0.5),
          color: scheme.primary,
        ),
      ),
    );
  }
}
