import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/models/bus_route.dart';
import 'route_color.dart';

/// A route as a card: its colour down the side, as on the map, its name and
/// a line of detail.
class RouteCard extends StatelessWidget {
  const RouteCard({
    required this.route,
    required this.onTap,
    this.details,
    super.key,
  });

  final BusRoute route;
  final VoidCallback onTap;

  /// A line under the name, when there is something to say.
  final String? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = routeColor(route.colorHex);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        RouteIcon(colorHex: route.colorHex),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                route.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (details != null && details!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  details!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The route symbol on a tile tinted with the route's colour.
class RouteIcon extends StatelessWidget {
  const RouteIcon({required this.colorHex, this.size = 40, super.key});

  final String colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = routeColor(colorHex);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(Icons.route_rounded, color: color, size: size * 0.55),
    );
  }
}

/// A route's name on a pill tinted with its colour.
class RoutePill extends StatelessWidget {
  const RoutePill({required this.route, super.key});

  final BusRoute route;

  @override
  Widget build(BuildContext context) {
    final color = routeColor(route.colorHex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              route.name,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
