import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/coordinate_parser.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../data/models/bus.dart';
import '../../../../data/models/bus_route.dart';
import '../../../../data/models/bus_stop.dart';
import '../../../../shared/widgets/info_tile.dart';
import '../../../../shared/widgets/route_card.dart';
import '../../../../shared/widgets/route_color.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../../../shared/widgets/stop_badge.dart';
import '../../../buses/presentation/arrival_text.dart';
import '../../../buses/presentation/bus_card.dart';
import '../../application/stop_arrivals.dart';

export '../../application/stop_arrivals.dart' show ApproachingBus;

/// The selected route, shown in the home sheet: its ends, whether it is
/// running, and its stops in travel order.
class RouteDetails extends StatelessWidget {
  const RouteDetails({
    required this.route,
    required this.stops,
    required this.onStopSelected,
    required this.onClose,
    this.reversed = false,
    this.onSwapDirection,
    super.key,
  });

  final BusRoute route;

  /// The route's stops, in travel order from its start to its end.
  final List<BusStop> stops;
  final ValueChanged<BusStop> onStopSelected;
  final VoidCallback onClose;

  /// Whether the route is being shown from its end back to its start. The
  /// stops are listed, and the arrows on the map point, that way.
  final bool reversed;

  /// Shows the route the other way round. Without it there is no switch.
  final VoidCallback? onSwapDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>()!;
    final ends = [
      route.startName,
      route.endName,
    ].where((name) => name.isNotEmpty).join(' to ');
    final ordered = reversed ? stops.reversed.toList() : stops;
    final from = reversed ? route.endName : route.startName;
    final to = reversed ? route.startName : route.endName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.sm,
          ),
          child: Row(
            children: [
              RouteIcon(colorHex: route.colorHex, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ends.isNotEmpty)
                      Text(
                        ends,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              StatusPill(
                label: route.isActive ? 'Running' : 'Not running',
                color: route.isActive ? semantic.success : semantic.muted,
              ),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (onSwapDirection != null && from.isNotEmpty && to.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: SoftCard(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Direction shown',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '$from → $to',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Show the other direction',
                    onPressed: onSwapDirection,
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                ],
              ),
            ),
          ),
        SectionTitle(stops.isEmpty ? 'Stops' : 'Stops (${stops.length})'),
        if (stops.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'No stops have been added for this route yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (index, stop) in ordered.indexed)
            _StopStep(
              stop: stop,
              color: routeColor(route.colorHex),
              isFirst: index == 0,
              isLast: index == ordered.length - 1,
              onTap: () => onStopSelected(stop),
            ),
      ],
    );
  }
}

/// One stop on the route's timeline: a dot joined to its neighbours.
class _StopStep extends StatelessWidget {
  const _StopStep({
    required this.stop,
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final BusStop stop;
  final Color color;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTerminal = isFirst || isLast;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.lg),
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: 3,
                      color: isFirst ? Colors.transparent : color,
                    ),
                  ),
                  Container(
                    width: isTerminal ? 14 : 10,
                    height: isTerminal ? 14 : 10,
                    decoration: BoxDecoration(
                      color: isTerminal ? color : theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 3,
                      color: isLast ? Colors.transparent : color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                stop.name,
                style: isTerminal
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

/// How far a bus still has to drive, for example "450 m away" or
/// "2.3 km away".
String distanceAwayText(double meters) {
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    return '${rounded < 10 ? 10 : rounded} m away';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

/// One bus on its way to the stop: which bus, where it is going, when it
/// should arrive and how far it still has to drive.
class _ArrivalCard extends StatelessWidget {
  const _ArrivalCard({
    required this.arrival,
    required this.isNext,
    required this.onTap,
    this.action,
  });

  final ApproachingBus arrival;
  final bool isNext;
  final VoidCallback? onTap;

  /// Something to do about this bus, such as setting an alert.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final journey = arrival.journey;

    return SoftCard(
      onTap: onTap,
      color: isNext ? scheme.primary.withValues(alpha: 0.07) : null,
      borderColor: isNext ? scheme.primary.withValues(alpha: 0.3) : null,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                // Only live buses get an estimate.
                BusBadge(color: semantic.success),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Bus ${arrival.bus.bus.number}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNext) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xl,
                                ),
                              ),
                              child: Text(
                                'Next',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(arrival.routeName, style: muted),
                    ],
                  ),
                ),
                ?action,
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: (isNext ? scheme.primary : scheme.outlineVariant).withValues(
              alpha: isNext ? 0.18 : 0.6,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 17, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    arrivalText(arrival.estimate),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.straighten_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  distanceAwayText(arrival.estimate.distanceMeters),
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The selected stop, shown in the home sheet: where it is and which routes
/// call there.
class StopDetails extends StatelessWidget {
  const StopDetails({
    required this.stop,
    required this.routes,
    required this.onRouteSelected,
    required this.onClose,
    this.approaching = const [],
    this.hasTrackedBuses = false,
    this.onBusSelected,
    this.predictedArrivals,
    this.arrivalActionBuilder,
    super.key,
  });

  /// Builds something to do about a bus on its way here, such as a bell
  /// for setting an alert.
  final Widget Function(ApproachingBus arrival)? arrivalActionBuilder;

  final BusStop stop;

  /// The routes that call at this stop.
  final List<BusRoute> routes;
  final ValueChanged<BusRoute> onRouteSelected;
  final VoidCallback onClose;

  /// Buses on their way to this stop with an arrival estimate, soonest
  /// first.
  final List<ApproachingBus> approaching;

  /// Whether any bus on these routes is being tracked at all. With none,
  /// the arrivals section is left out rather than shown empty.
  final bool hasTrackedBuses;
  final ValueChanged<TrackedBus>? onBusSelected;

  /// Times from the timetable and from buses last seen, shown under the
  /// live ones. It takes no space when it has nothing to show.
  final Widget? predictedArrivals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final scheme = theme.colorScheme;
    final description = stop.description;
    final coordinates = formatCoordinates(
      stop.position.latitude,
      stop.position.longitude,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // The same badge the picked stop has on the map.
              const StopBadge(size: 52, highlighted: true),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      routes.isEmpty
                          ? 'Bus stop'
                          : routes.length == 1
                          ? 'Bus stop · 1 route'
                          : 'Bus stop · ${routes.length} routes',
                      style: muted,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(description, style: theme.textTheme.bodyMedium),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Appear(
            child: InfoTile(
              icon: const Icon(Icons.my_location_rounded),
              label: 'Location',
              value: coordinates,
              trailing: IconButton(
                tooltip: 'Copy coordinates',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  // In the form Google Maps takes: "22.659970, 90.363380".
                  await Clipboard.setData(
                    ClipboardData(text: coordinatesToText(stop.position)),
                  );
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('Coordinates copied')),
                    );
                },
              ),
            ),
          ),
        ),
        if (hasTrackedBuses) ...[
          const SectionTitle('Buses on the way'),
          if (approaching.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'No bus can be estimated for this stop right now.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final (index, arrival) in approaching.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Appear(
                  delay: Duration(milliseconds: 60 * index),
                  child: _ArrivalCard(
                    arrival: arrival,
                    // The soonest bus stands out.
                    isNext: index == 0,
                    action: arrivalActionBuilder?.call(arrival),
                    onTap: onBusSelected == null
                        ? null
                        : () => onBusSelected!(arrival.bus),
                  ),
                ),
              ),
        ],
        ?predictedArrivals,
        const SectionTitle('Routes at this stop'),
        if (routes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'No route calls at this stop yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final route in routes)
            RouteCard(
              route: route,
              details: route.isActive ? null : 'Not running',
              onTap: () => onRouteSelected(route),
            ),
      ],
    );
  }
}
