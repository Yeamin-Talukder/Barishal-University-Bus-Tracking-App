import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatting.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/info_tile.dart';
import '../../../shared/widgets/skeleton_list.dart';
import '../data/bus_schedule_repository.dart';
import '../domain/bus_schedule.dart';

/// The university's official bus schedule: pick who you are and a route, and
/// see every departure with the vehicles named for it.
///
/// The two choices stay pinned at the top while the timetable scrolls
/// beneath them.
///
/// It shows the schedule as published. It says nothing about where a bus is
/// now, and does not claim a bus runs today.
class ScheduleView extends ConsumerStatefulWidget {
  const ScheduleView({super.key});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  String? _groupId;
  String? _routeNumber;

  /// Which of the route's departure places is shown: the schedule is read
  /// one direction at a time.
  int _departureIndex = 0;

  /// Half-turns of the switch button, so it spins the same way each time.
  int _switchTurns = 0;

  /// Scrolls the timetable under the pinned selectors.
  final ScrollController _scroll = ScrollController();

  /// Whether the timetable has been scrolled away from its top.
  bool _isScrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(busScheduleProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: schedule.when(
        // An admin's change reloads the schedule; keep showing it meanwhile.
        skipLoadingOnReload: true,
        loading: () => const SkeletonList(key: ValueKey('loading')),
        error: (error, stackTrace) => EmptyState(
          key: const ValueKey('error'),
          icon: Icons.error_outline_rounded,
          title: 'The schedule could not be loaded',
          message: 'The schedule stored on this device could not be read.',
          action: FilledButton.icon(
            onPressed: () => ref
              ..invalidate(busScheduleRepositoryProvider)
              ..invalidate(bundledScheduleProvider)
              ..invalidate(busScheduleProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (schedule) => schedule.isEmpty
            ? const EmptyState(
                key: ValueKey('empty'),
                icon: Icons.event_busy_rounded,
                title: 'No schedule yet',
                message:
                    'The bus schedule will be shown here once the university '
                    'transport office has published it.',
              )
            : _content(context, schedule),
      ),
    );
  }

  Widget _content(BuildContext context, BusSchedule schedule) {
    final theme = Theme.of(context);

    final group = schedule.groups.firstWhere(
      (group) => group.id == _groupId,
      orElse: () => schedule.groups.first,
    );
    final timetables = schedule.timetablesFor(group.id);
    final timetable = timetables.isEmpty
        ? null
        : timetables.firstWhere(
            (timetable) => timetable.routeNumber == _routeNumber,
            orElse: () => timetables.first,
          );

    final departures = timetable?.departures ?? const <DeparturePoint>[];
    final departure = departures.isEmpty
        ? null
        : departures[_departureIndex % departures.length];

    return Column(
      key: const ValueKey('schedule-page'),
      children: [
        // Who you are and which route: always in reach, however far down
        // the timetable has been scrolled.
        _PinnedSelectors(
          isLifted: _isScrolled,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final group in schedule.groups)
                    ButtonSegment(
                      value: group.id,
                      icon: Icon(_groupIcon(group), size: 18),
                      label: Text(group.name),
                    ),
                ],
                selected: {group.id},
                onSelectionChanged: (selection) => _choose(() {
                  _groupId = selection.first;
                  _routeNumber = null;
                  _departureIndex = 0;
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in timetables)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        showCheckmark: false,
                        avatar: Icon(
                          Icons.route_rounded,
                          size: 18,
                          color: item == timetable
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        label: Text('Route ${item.routeNumber}'),
                        selected: item == timetable,
                        onSelected: (_) => _choose(() {
                          _routeNumber = item.routeNumber;
                          _departureIndex = 0;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            if (timetable != null && departure != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _DirectionSwitch(
                from: departure.from.primary,
                to: scheduleDestination(timetable, departure),
                turns: _switchTurns,
                // With one departure place there is nothing to switch to.
                onSwitch: departures.length < 2
                    ? null
                    // The other direction of the same route: stay where
                    // the passenger has scrolled to.
                    : () => setState(() {
                        _departureIndex =
                            (_departureIndex + 1) % departures.length;
                        _switchTurns++;
                      }),
              ),
            ],
          ],
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.vertical) {
                final isScrolled = notification.metrics.pixels > 4;
                if (isScrolled != _isScrolled) {
                  setState(() => _isScrolled = isScrolled);
                }
              }
              return false;
            },
            child: ListView(
              key: const ValueKey('schedule'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                if (timetable == null)
                  Text(
                    'The schedule has no routes for this group.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  _Timetable(
                    // Not keyed by direction: switching direction changes
                    // what is inside it, without starting it afresh.
                    key: ValueKey(
                      '${timetable.groupId}-${timetable.routeNumber}',
                    ),
                    timetable: timetable,
                    group: group,
                    departure: departure,
                  ),
                const SizedBox(height: AppSpacing.xl),
                _Source(schedule: schedule),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Applies a choice of group or route and shows the new timetable from
  /// its top.
  void _choose(VoidCallback change) {
    setState(change);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  static IconData _groupIcon(PassengerGroup group) {
    final name = '${group.id} ${group.name}'.toLowerCase();
    if (name.contains('student')) return Icons.school_rounded;
    if (name.contains('teacher')) return Icons.co_present_rounded;
    if (name.contains('staff')) return Icons.badge_rounded;
    return Icons.groups_rounded;
  }
}

/// Where buses leaving [departure] are going: the other end of the route.
///
/// Null when the schedule does not say (the route lists no stops and has
/// more or fewer than two departure places).
String? scheduleDestination(
  RouteTimetable timetable,
  DeparturePoint departure,
) {
  bool same(String a, String b) {
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    return x == y || x.contains(y) || y.contains(x);
  }

  final from = departure.from.primary;
  final stops = timetable.stops;
  if (stops.length >= 2) {
    if (same(from, stops.first.primary)) return stops.last.primary;
    if (same(from, stops.last.primary)) return stops.first.primary;
  }
  if (timetable.departures.length == 2) {
    return timetable.departures
        .firstWhere((other) => !identical(other, departure))
        .from
        .primary;
  }
  return null;
}

/// Whether the route's stops are listed backwards for buses leaving
/// [departure]: true when they set off from the last listed stop.
bool scheduleRunsBackwards(RouteTimetable timetable, DeparturePoint departure) {
  final stops = timetable.stops;
  if (stops.length < 2) return false;
  return scheduleDestination(timetable, departure) == stops.first.primary;
}

/// Says which direction of the route is shown, and switches to the other
/// one: "University → Barishal Club" becomes "Barishal Club → University".
class _DirectionSwitch extends StatelessWidget {
  const _DirectionSwitch({
    required this.from,
    required this.to,
    required this.turns,
    required this.onSwitch,
  });

  final String from;

  /// Null when the schedule does not say where the buses go.
  final String? to;
  final int turns;

  /// Null when the route has only one departure place.
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = to == null ? 'From $from' : '$from  →  $to';

    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSwitch,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.near_me_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Direction',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previousChildren, ?currentChild],
                      ),
                      // The new words rise into place as the old ones fade.
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.5),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        text,
                        key: ValueKey(text),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (onSwitch != null)
                Tooltip(
                  message: 'Switch direction',
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedRotation(
                      turns: turns / 2,
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        color: scheme.onPrimary,
                      ),
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

/// The selectors that stay at the top of the schedule. A soft shadow
/// appears under them once the timetable has been scrolled.
class _PinnedSelectors extends StatelessWidget {
  const _PinnedSelectors({required this.isLifted, required this.children});

  final bool isLifted;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLifted ? 0.14 : 0),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _Timetable extends StatelessWidget {
  const _Timetable({
    required this.timetable,
    required this.group,
    required this.departure,
    super.key,
  });

  final RouteTimetable timetable;
  final PassengerGroup group;

  /// The departure place whose times are shown. Null when the route has
  /// none.
  final DeparturePoint? departure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final stopCount = timetable.stops.length;
    final departure = this.departure;
    final tripCount = departure?.trips.length ?? 0;
    // The stops in the order this direction meets them.
    final stops =
        departure != null && scheduleRunsBackwards(timetable, departure)
        ? timetable.stops.reversed.toList()
        : timetable.stops;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Appear(
          child: SoftCard(
            color: scheme.primary.withValues(alpha: 0.09),
            borderColor: scheme.primary.withValues(alpha: 0.28),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.route_rounded, color: scheme.onPrimary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${group.name} route ${timetable.routeNumber}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        children: [
                          _Fact(
                            icon: Icons.departure_board_rounded,
                            text: tripCount == 1
                                ? '1 departure'
                                : '$tripCount departures',
                          ),
                          _Fact(
                            icon: Icons.pin_drop_rounded,
                            text: stopCount == 1
                                ? '1 place'
                                : '$stopCount places',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Appear(
          delay: const Duration(milliseconds: 60),
          child: _DirectionSwap(
            direction: departure?.from.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final point in [?departure]) ...[
                  _CardWithHeading(
                    icon: Icons.departure_board_rounded,
                    title: [
                      'From ${point.from.primary}',
                      ?point.from.secondary,
                    ].join('  ·  '),
                    children: [
                      for (final (index, trip) in point.trips.indexed) ...[
                        if (index > 0)
                          const Divider(
                            height: 1,
                            indent: AppSpacing.lg,
                            endIndent: AppSpacing.lg,
                          ),
                        _TripRow(trip: trip),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _CardWithHeading(
                  icon: Icons.signpost_rounded,
                  title: 'Stops on route ${timetable.routeNumber}',
                  children: [
                    if (stopCount >= 2)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.sm,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${timetable.stops.first.primary}  ⇄  '
                                '${timetable.stops.last.primary}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'The bus runs between the first and last places, in '
                                'both directions, and picks up and drops off at each '
                                'place between them.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (timetable.stops.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'The official schedule does not list the stops of this '
                            'route.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      for (final (index, stop) in stops.indexed)
                        _StopTile(
                          number: index + 1,
                          stop: stop,
                          isFirst: index == 0,
                          isLast: index == stopCount - 1,
                        ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Changes from one direction's times and stops to the other's without a
/// jump: the old ones fade out as the new ones fade and slide in, and the
/// height eases to its new size.
class _DirectionSwap extends StatelessWidget {
  const _DirectionSwap({required this.direction, required this.child});

  /// Names the direction shown; a change of it starts the transition.
  final String? direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topCenter,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(direction), child: child),
      ),
    );
  }
}

/// A small icon with a few words beside it.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 5),
        // A count that changes (with the direction) fades to its new value.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            text,
            key: ValueKey(text),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// A card with an icon and a heading at its top.
class _CardWithHeading extends StatelessWidget {
  const _CardWithHeading({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: scheme.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// One place on a route, on a line that joins it to its neighbours. The two
/// ends of the route are filled in and labelled, because the bus starts at
/// one and finishes at the other.
class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.number,
    required this.stop,
    required this.isFirst,
    required this.isLast,
  });

  final int number;
  final LocalizedText stop;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = scheme.primary;
    final isTerminal = isFirst || isLast;
    final line = primary.withValues(alpha: 0.35);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 3,
                    color: isFirst ? Colors.transparent : line,
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isTerminal
                        ? primary
                        : primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isTerminal ? scheme.onPrimary : primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 3,
                    color: isLast ? Colors.transparent : line,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    stop.primary,
                    style: isTerminal
                        ? theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          )
                        : theme.textTheme.bodyMedium,
                  ),
                  if (stop.secondary != null)
                    Text(
                      stop.secondary!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isTerminal)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Text(
                  'Start / end',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const SizedBox(width: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip});

  final ScheduledTrip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 104,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: scheme.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    formatClockTime(trip.minutes),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(
              Icons.directions_bus_rounded,
              size: 17,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.vehicles.primary,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (trip.vehicles.secondary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      trip.vehicles.secondary!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the schedule came from, and what it does not say.
class _Source extends StatelessWidget {
  const _Source({required this.schedule});

  final BusSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordedOn = schedule.recordedOn;

    return Text(
      [
        'Official university bus schedule'
            '${recordedOn == null ? '' : ', as of ${formatDate(recordedOn)}'}.',
        'It does not say on which days it applies, so check before relying '
            'on a time.',
        'English names are transliterations of the Bangla originals.',
      ].join(' '),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
