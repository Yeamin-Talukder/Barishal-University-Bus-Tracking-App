import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../data/models/bus_route.dart';
import '../../../../data/models/bus_stop.dart';
import '../../../../shared/widgets/info_tile.dart';
import '../../../../shared/widgets/route_card.dart';
import '../../../../shared/widgets/stop_badge.dart';

/// A stop in the Stops list: its badge and name, what is said about the
/// place, the routes that call there and where it is. Tapping it shows the
/// stop on the map.
class StopCard extends StatelessWidget {
  const StopCard({
    required this.stop,
    required this.routes,
    required this.onTap,
    super.key,
  });

  final BusStop stop;

  /// The routes that call at this stop.
  final List<BusRoute> routes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final description = stop.description;

    return Appear(
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const StopBadge(size: 48),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // The whole card opens the stop on the map; this says so.
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.map_rounded,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (routes.isEmpty)
              Text('No route calls here yet', style: muted)
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [for (final route in routes) RoutePill(route: route)],
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(
                  Icons.my_location_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    formatCoordinates(
                      stop.position.latitude,
                      stop.position.longitude,
                    ),
                    style: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
