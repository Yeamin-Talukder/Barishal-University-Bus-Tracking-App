import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../data/models/bus_route.dart';
import '../../../../shared/widgets/info_tile.dart';
import '../../../../shared/widgets/route_card.dart' show RouteIcon;
import '../../../../shared/widgets/route_color.dart';
import '../../../../shared/widgets/status_pill.dart';

/// A route in the Routes list: its colour, its ends, whether it is running
/// and how many of its buses are live. Tapping it shows the route on the
/// map.
class RouteCard extends StatelessWidget {
  const RouteCard({
    required this.route,
    required this.liveBusCount,
    required this.onTap,
    super.key,
  });

  final BusRoute route;

  /// Buses on this route reporting a live position right now.
  final int liveBusCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final color = routeColor(route.colorHex);
    final hasLiveBus = liveBusCount > 0;

    final ends = [
      route.startName,
      route.endName,
    ].where((name) => name.isNotEmpty).join(' to ');
    final stopCount = route.stopIds.length;
    final facts = [
      stopCount == 1 ? '1 stop' : '$stopCount stops',
      switch (liveBusCount) {
        0 => 'No live buses',
        1 => '1 bus live',
        _ => '$liveBusCount buses live',
      },
    ].join(' · ');

    return Appear(
      child: SoftCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The route's colour, as on the map.
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      RouteIcon(colorHex: route.colorHex, size: 48),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    route.name,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                StatusPill(
                                  label: route.isActive
                                      ? 'Running'
                                      : 'Not running',
                                  color: route.isActive
                                      ? semantic.success
                                      : semantic.muted,
                                ),
                              ],
                            ),
                            if (ends.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(ends, style: theme.textTheme.bodyMedium),
                            ],
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Icon(
                                  hasLiveBus
                                      ? Icons.directions_bus_rounded
                                      : Icons.directions_bus_outlined,
                                  size: 15,
                                  color: hasLiveBus
                                      ? semantic.success
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    facts,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: hasLiveBus
                                          ? scheme.onSurface
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
