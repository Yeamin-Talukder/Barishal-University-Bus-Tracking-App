import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/route_color.dart';
import '../domain/widget_snapshot.dart';

/// What one widget shows: who for, which route and which way, with a
/// preview of the widget drawn from the real timetable above the choices.
///
/// Used in Profile and on the widget's own settings screen (long-press
/// the widget, then Settings).
class WidgetChoiceEditor extends StatelessWidget {
  const WidgetChoiceEditor({
    required this.timetable,
    required this.choice,
    required this.onChanged,
    super.key,
  });

  final WidgetTimetable timetable;
  final WidgetChoice choice;
  final ValueChanged<WidgetChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final routes = timetable.routesFor(choice.groupId);
    final groups = timetable.groups.isEmpty
        ? const {'student': 'Student', 'teacher': 'Teacher', 'staff': 'Staff'}
        : timetable.groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WidgetPreview(
          title: timetable.titleFor(choice),
          subtitle: choice.direction.label,
          departures: timetable.departuresFor(choice),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Label('Who for'),
        SegmentedButton<String>(
          segments: [
            for (final g in groups.entries)
              ButtonSegment(
                value: g.key,
                label: Text(g.value),
                icon: Icon(_groupIcon(g.key)),
              ),
          ],
          selected: {choice.groupId},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onChanged(
            choice.copyWith(groupId: s.first, route: WidgetChoice.allRoutes),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Label('Route'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: const Text('All routes'),
              selected: choice.route == WidgetChoice.allRoutes,
              onSelected: (_) =>
                  onChanged(choice.copyWith(route: WidgetChoice.allRoutes)),
            ),
            for (final r in routes)
              ChoiceChip(
                avatar: _Dot(color: routeColor(timetable.colorOf(r))),
                label: Text('Route $r'),
                selected: choice.route == r,
                onSelected: (_) => onChanged(choice.copyWith(route: r)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const _Label('Direction'),
        SegmentedButton<WidgetDirection>(
          segments: const [
            ButtonSegment(
              value: WidgetDirection.both,
              label: Text('Both'),
              icon: Icon(Icons.swap_horiz_rounded),
            ),
            ButtonSegment(
              value: WidgetDirection.toUniversity,
              label: Text('To campus'),
              icon: Icon(Icons.school_rounded),
            ),
            ButtonSegment(
              value: WidgetDirection.fromUniversity,
              label: Text('From campus'),
              icon: Icon(Icons.home_rounded),
            ),
          ],
          selected: {choice.direction},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              onChanged(choice.copyWith(direction: s.first)),
        ),
      ],
    );
  }

  static IconData _groupIcon(String id) => switch (id) {
    'teacher' => Icons.co_present_rounded,
    'staff' => Icons.badge_rounded,
    _ => Icons.school_rounded,
  };
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 10});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A drawing of the medium widget with the real next departures, so a
/// choice can be seen before it is saved. It follows the widget: bus names
/// first, the last bus of the day called out, tomorrow's when today's are
/// over.
class WidgetPreview extends StatefulWidget {
  const WidgetPreview({
    required this.title,
    required this.subtitle,
    required this.departures,
    super.key,
  });
  final String title;
  final String subtitle;
  final List<WidgetDeparture> departures;

  @override
  State<WidgetPreview> createState() => _WidgetPreviewState();
}

class _WidgetPreviewState extends State<WidgetPreview> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The countdown moves on each minute.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final day = WidgetDay.of(widget.departures, nowMinutes);
    final upcoming = day.upcoming;
    final last = day.lastToday;

    String time(int m) => MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: m ~/ 60, minute: m % 60),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    String left(UpcomingDeparture u) {
      if (u.tomorrow) return 'Tomorrow';
      final diff = u.departure.minutes - nowMinutes;
      if (diff < 1) return 'Now';
      if (diff < 60) return 'in $diff min';
      return 'in ${diff ~/ 60} h ${diff % 60} min';
    }

    final subtitle = last != null && day.leftToday > 1
        ? '${widget.subtitle} · last bus ${time(last.minutes)}'
        : widget.subtitle;

    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.enter,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(a),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(
          '${widget.title}$subtitle${upcoming.length}'
          '${upcoming.firstOrNull?.departure.minutes}',
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_bus_rounded,
                  size: 20,
                  color: theme.accent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (upcoming.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  'No buses in the timetable for this choice.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              _NextCard(
                label: day.nextLabel,
                warn: day.leftToday <= 1,
                next: upcoming.first,
                time: time(upcoming.first.departure.minutes),
                left: left(upcoming.first),
              ),
              const SizedBox(height: 6),
              for (final u in upcoming.skip(1).take(2))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      _Dot(color: routeColor(u.departure.colorHex), size: 8),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 24,
                        child: Text(
                          u.departure.route,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          u.departure.headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '  → ${u.departure.to}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${u.tomorrow ? 'Tmrw ' : ''}'
                        '${time(u.departure.minutes)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.label,
    required this.warn,
    required this.next,
    required this.time,
    required this.left,
  });

  final String label;
  final bool warn;
  final UpcomingDeparture next;
  final String time;
  final String left;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = next.departure;
    final labelColor = warn
        ? theme.extension<AppSemanticColors>()!.warning
        : theme.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _RouteChip(route: d.route, color: routeColor(d.colorHex)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'To ${d.to} · from ${d.from}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    time,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      left,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteChip extends StatelessWidget {
  const _RouteChip({required this.route, required this.color});
  final String route;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: color),
          const SizedBox(width: 5),
          Text(
            route,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
