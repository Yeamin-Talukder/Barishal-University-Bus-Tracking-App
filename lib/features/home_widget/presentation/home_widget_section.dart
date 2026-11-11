import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../shared/widgets/route_color.dart';
import '../../../shared/widgets/section_card.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../../schedule/domain/bus_schedule.dart';
import '../application/home_widget_sync.dart';
import '../domain/widget_snapshot.dart';

/// Profile → "Home-screen widget": what the widget shows, a live preview of
/// it, and a button that puts it on the home screen.
class HomeWidgetSection extends ConsumerStatefulWidget {
  const HomeWidgetSection({super.key});

  @override
  ConsumerState<HomeWidgetSection> createState() => _HomeWidgetSectionState();
}

class _HomeWidgetSectionState extends ConsumerState<HomeWidgetSection> with WidgetsBindingObserver {
  int _placed = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _count();
    // The preview's countdown moves on each minute.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the home screen after adding the widget.
    if (state == AppLifecycleState.resumed) _count();
  }

  Future<void> _count() async {
    final n = await ref.read(homeWidgetBridgeProvider)?.count() ?? 0;
    if (mounted) setState(() => _placed = n);
  }

  Future<void> _pin() async {
    final ok = await ref.read(homeWidgetBridgeProvider)?.pin() ?? false;
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Long-press your home screen, tap Widgets, and find BU Bus Tracker.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(homeWidgetBridgeProvider) == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final choice = ref.watch(widgetChoiceProvider);
    final controller = ref.read(widgetChoiceProvider.notifier);
    final schedule = ref.watch(busScheduleProvider).value;
    final routes = ref.watch(transportNetworkProvider).value?.routes ?? const [];
    final routeNumbers = [
      for (final t in schedule?.timetablesFor(choice.groupId) ?? const <RouteTimetable>[]) t.routeNumber,
    ];
    final departures = schedule == null
        ? const <WidgetDeparture>[]
        : widgetDepartures(schedule, choice, routeColors: routeColorsOf(routes));

    return SectionCard(
      title: 'Home-screen widget',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'See your next bus on the home screen, with a live countdown, without opening the app.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              _WidgetPreview(title: widgetTitle(choice), subtitle: choice.direction.label, departures: departures),
              const SizedBox(height: AppSpacing.lg),
              _Label('Who for'),
              SegmentedButton<String>(
                segments: [
                  for (final g in BusSchedule.standardGroups)
                    ButtonSegment(value: g.id, label: Text(g.name), icon: Icon(_groupIcon(g.id))),
                ],
                selected: {choice.groupId},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    controller.set(choice.copyWith(groupId: s.first, route: WidgetChoice.allRoutes)),
              ),
              const SizedBox(height: AppSpacing.md),
              _Label('Route'),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('All routes'),
                    selected: choice.route == WidgetChoice.allRoutes,
                    onSelected: (_) => controller.set(choice.copyWith(route: WidgetChoice.allRoutes)),
                  ),
                  for (final r in routeNumbers)
                    ChoiceChip(
                      avatar: _Dot(color: _colorFor(r, routes, routeNumbers)),
                      label: Text('Route $r'),
                      selected: choice.route == r,
                      onSelected: (_) => controller.set(choice.copyWith(route: r)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Label('Direction'),
              SegmentedButton<WidgetDirection>(
                segments: const [
                  ButtonSegment(value: WidgetDirection.both, label: Text('Both'), icon: Icon(Icons.swap_horiz_rounded)),
                  ButtonSegment(value: WidgetDirection.toUniversity, label: Text('To campus'), icon: Icon(Icons.school_rounded)),
                  ButtonSegment(value: WidgetDirection.fromUniversity, label: Text('From campus'), icon: Icon(Icons.home_rounded)),
                ],
                selected: {choice.direction},
                showSelectedIcon: false,
                onSelectionChanged: (s) => controller.set(choice.copyWith(direction: s.first)),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _pin,
                  icon: Icon(_placed > 0 ? Icons.add_to_home_screen_rounded : Icons.widgets_rounded),
                  label: Text(_placed > 0 ? 'Add another to home screen' : 'Add to home screen'),
                ),
              ),
              AnimatedSwitcher(
                duration: AppMotion.quick,
                child: _placed > 0
                    ? Padding(
                        key: const ValueKey('placed'),
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 16, color: theme.accent),
                            const SizedBox(width: 6),
                            Text(
                              _placed == 1 ? 'On your home screen. Changes here update it.' : '$_placed on your home screen.',
                              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('none')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _groupIcon(String id) => switch (id) {
        'teacher' => Icons.co_present_rounded,
        'staff' => Icons.badge_rounded,
        _ => Icons.school_rounded,
      };

  static Color _colorFor(String route, List<dynamic> routes, List<String> numbers) {
    for (final r in routes) {
      if (r.id == route) return routeColor(r.colorHex as String);
    }
    const palette = ['#F2994A', '#6FA8FF', '#B79CFF', '#FF8FA3', '#E6C24C', '#4FC3F7'];
    return routeColor(palette[numbers.indexOf(route).clamp(0, 99) % palette.length]);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// A drawing of the medium widget with the real next departures, so the
/// choice can be seen before the widget is placed.
class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({required this.title, required this.subtitle, required this.departures});
  final String title;
  final String subtitle;
  final List<WidgetDeparture> departures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final today = departures.where((d) => d.minutes >= nowMinutes).toList();
    final tomorrow = today.isEmpty;
    final upcoming = tomorrow ? departures : today;

    String time(int m) => MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay(hour: m ~/ 60, minute: m % 60),
          alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
        );
    String left(int m) {
      if (tomorrow) return 'Tomorrow';
      final diff = m - nowMinutes;
      if (diff < 1) return 'Now';
      if (diff < 60) return 'in $diff min';
      return 'in ${diff ~/ 60} h ${diff % 60} min';
    }

    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.enter,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child),
      ),
      child: Container(
        key: ValueKey('$title$subtitle${upcoming.length}${upcoming.firstOrNull?.minutes}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus_rounded, size: 20, color: theme.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(subtitle, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.refresh_rounded, size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 10),
            if (upcoming.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text(
                  'No buses in the timetable for this choice.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    _RouteChip(route: upcoming.first.route, color: routeColor(upcoming.first.colorHex)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('To ${upcoming.first.to}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text('From ${upcoming.first.from} · ${upcoming.first.vehicles}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(time(upcoming.first.minutes),
                            style: theme.textTheme.titleLarge?.copyWith(color: theme.accent, fontWeight: FontWeight.w800)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(left(upcoming.first.minutes),
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.accent, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              for (final d in upcoming.skip(1).take(2))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  child: Row(
                    children: [
                      _Dot(color: routeColor(d.colorHex)),
                      const SizedBox(width: 6),
                      SizedBox(width: 26, child: Text(d.route, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800))),
                      Expanded(
                        child: Text('To ${d.to}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                      ),
                      Text(time(d.minutes),
                          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
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

class _RouteChip extends StatelessWidget {
  const _RouteChip({required this.route, required this.color});
  final String route;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: color),
          const SizedBox(width: 5),
          Text(route, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
