import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../data/models/transport_network.dart';
import '../../../../data/repositories/bus_location_repository.dart';
import '../../../../data/repositories/transport_network_repository.dart';
import '../../../../shared/widgets/info_tile.dart';
import '../../../../shared/widgets/route_color.dart';
import '../../../schedule/data/bus_schedule_repository.dart';
import '../../application/route_departures.dart';

/// Which bus to get on: the next departures from the timetable, each with
/// the names of the buses that run it.
///
/// Passengers know the buses by name, and several stand side by side at
/// the university. The timetable says which of them goes on which route at
/// which time, so that is put first, in the largest text.
///
/// For a route it lists the next departures going one way; for a stop, the
/// next departure of every route and direction that picks up there. It
/// takes no space when the timetable has nothing to say.
class TimetableBuses extends ConsumerStatefulWidget {
  /// The next departures on a route, going the way it is being shown.
  const TimetableBuses.forRoute({
    required String this.routeId,
    required this.reversed,
    super.key,
  }) : stopId = null;

  /// The next departures that pick up at a stop.
  const TimetableBuses.forStop({required String this.stopId, super.key})
    : routeId = null,
      reversed = false;

  final String? routeId;
  final bool reversed;
  final String? stopId;

  @override
  ConsumerState<TimetableBuses> createState() => _TimetableBusesState();
}

class _TimetableBusesState extends ConsumerState<TimetableBuses> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // "In 5 min" must not go stale while the screen stays open.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(busScheduleProvider).value;
    final network = ref.watch(transportNetworkProvider).value;
    if (schedule == null || network == null) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();

    final routeId = widget.routeId;
    final stop = widget.stopId == null
        ? null
        : network.stopById(widget.stopId!);
    final route = routeId == null ? null : network.routeById(routeId);
    final departures = route != null
        ? upcomingDepartures(
            schedule: schedule,
            route: route,
            now: now,
            reversed: widget.reversed,
          )
        : stop != null
        ? upcomingDeparturesAt(
            schedule: schedule,
            network: network,
            stop: stop,
            now: now,
          )
        : const <RouteDeparture>[];
    if (departures.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          stop != null ? 'Which bus to take here' : 'Which bus goes this way',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (index, departure) in departures.indexed) ...[
                  if (index > 0)
                    const Divider(
                      height: 1,
                      indent: AppSpacing.md,
                      endIndent: AppSpacing.md,
                    ),
                  _DepartureRow(
                    departure: departure,
                    now: now,
                    isNext: index == 0,
                    // On a route's own page the route need not be said.
                    colorHex: stop == null
                        ? null
                        : network.routeById(departure.routeId)?.colorHex,
                    // Whether the bus sets off from the stop being shown.
                    leavesFromHere: stop == null
                        ? null
                        : _originId(network, departure) == stop.id,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            'From the timetable, not a live position. '
            'Look for the bus with this name.',
            style: muted,
          ),
        ),
      ],
    );
  }

  /// The id of the stop a departure sets off from.
  static String? _originId(TransportNetwork network, RouteDeparture departure) {
    final route = network.routeById(departure.routeId);
    if (route == null) return null;
    final stops = network.stopsOf(route);
    if (stops.isEmpty) return null;
    return (departure.reversed ? stops.last : stops.first).id;
  }
}

/// One departure: when it leaves, and the buses that run it.
class _DepartureRow extends StatelessWidget {
  const _DepartureRow({
    required this.departure,
    required this.now,
    required this.isNext,
    required this.colorHex,
    required this.leavesFromHere,
  });

  final RouteDeparture departure;
  final DateTime now;
  final bool isNext;

  /// The route's colour, when the row has to say which route it is.
  final String? colorHex;

  /// For a stop: whether the bus sets off from it. Null on a route's page.
  final bool? leavesFromHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final time = formatClockTime(departure.at.hour * 60 + departure.at.minute);
    final accent = isNext ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      container: true,
      label:
          '${departure.buses}. ${departure.routeName} to ${departure.toName}. '
          'Leaves ${departure.fromName} at $time, '
          '${departsInText(departure.at, now)}.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 92,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isNext ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    Text(
                      'Leaves',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      time,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isNext ? scheme.primary : scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      departsInText(departure.at, now),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name is what the passenger looks for on the bus.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.directions_bus_rounded,
                          size: 18,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            departure.buses,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (colorHex != null)
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: routeColor(colorHex!),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${departure.routeName} → ${departure.toName}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'To ${departure.toName}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      leavesFromHere == true
                          ? 'Sets off from this stop'
                          : leavesFromHere == false
                          ? 'Sets off from ${departure.fromName}, '
                                'then comes this way'
                          : 'From ${departure.fromName}',
                      style: muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
