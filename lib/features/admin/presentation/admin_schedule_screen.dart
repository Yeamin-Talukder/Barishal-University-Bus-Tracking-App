import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../../schedule/domain/bus_schedule.dart';
import 'timetable_editor_screen.dart';

/// Where an admin changes the bus schedule: one timetable per route and
/// passenger group.
///
/// The screen is only a convenience: the database refuses these changes
/// from anyone who is not an admin, whatever is shown here.
class AdminScheduleScreen extends ConsumerStatefulWidget {
  const AdminScheduleScreen({super.key});

  @override
  ConsumerState<AdminScheduleScreen> createState() =>
      _AdminScheduleScreenState();
}

class _AdminScheduleScreenState extends ConsumerState<AdminScheduleScreen> {
  String _groupId = BusSchedule.standardGroups.first.id;
  bool _importing = false;

  /// Copies the schedule built into the app into the database, so it can be
  /// edited from then on.
  Future<void> _import(BusSchedule bundled) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      await ref.read(timetableRepositoryProvider).saveAll(bundled.timetables);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${bundled.timetables.length} timetables copied. You can edit '
            'them now.',
          ),
        ),
      );
    } on ScheduleWriteFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final official = ref.watch(officialTimetablesProvider);
    final saved = sortTimetables(official.value ?? const <RouteTimetable>[]);
    final hasSchedule = saved.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage schedule')),
      floatingActionButton: isAdmin && hasSchedule
          ? FloatingActionButton.extended(
              onPressed: () => context.push(
                AppRoutes.adminTimetableEditor,
                extra: TimetableDraft.create(_groupId),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add route'),
            )
          : null,
      body: !isAdmin
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Admins only',
              message:
                  'Only a transport office admin can change the schedule. '
                  'Sign in with an admin account.',
            )
          : official.isLoading && !official.hasValue
          ? const Center(child: CircularProgressIndicator())
          : official.hasError && !official.hasValue
          ? const EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'The schedule could not be loaded',
              message: 'Check the connection and open this again.',
            )
          : hasSchedule
          ? _routes(context, saved)
          : _startEditing(context),
    );
  }

  /// Shown while the database has no timetables: passengers still see the
  /// copy built into the app.
  Widget _startEditing(BuildContext context) {
    final theme = Theme.of(context);
    final bundled = ref.watch(bundledScheduleProvider).value;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SectionCard(
          title: 'Schedule',
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Passengers see the schedule built into the app',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'To change it, copy it into the database first. After '
                    'that, every change you make here reaches all phones '
                    'within seconds, and the built-in copy is no longer '
                    'shown.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _importing || bundled == null || bundled.isEmpty
                        ? null
                        : () => _import(bundled),
                    icon: _importing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Icon(Icons.edit_calendar_rounded),
                    label: Text(
                      bundled == null
                          ? 'Start editing the schedule'
                          : 'Start editing the schedule '
                                '(${bundled.timetables.length} timetables)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _importing
                        ? null
                        : () => context.push(
                            AppRoutes.adminTimetableEditor,
                            extra: TimetableDraft.create(_groupId),
                          ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Start from an empty schedule'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _routes(BuildContext context, List<RouteTimetable> saved) {
    final inGroup = [
      for (final timetable in saved)
        if (timetable.groupId == _groupId) timetable,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        // Room for the Add route button.
        96,
      ),
      children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final group in BusSchedule.standardGroups)
              ButtonSegment(value: group.id, label: Text(group.name)),
          ],
          selected: {_groupId},
          onSelectionChanged: (selection) =>
              setState(() => _groupId = selection.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Routes (${inGroup.length})',
          children: [
            if (inGroup.isEmpty)
              const ListTile(
                leading: Icon(Icons.event_busy_rounded),
                title: Text('No routes for this group'),
                subtitle: Text('Add one with the button below.'),
              )
            else
              for (final timetable in inGroup)
                ListTile(
                  leading: const Icon(Icons.route_rounded),
                  title: Text('Route ${timetable.routeNumber}'),
                  subtitle: Text(
                    [
                      '${timetable.tripCount} departures',
                      '${timetable.stops.length} stops',
                      [
                        for (final point in timetable.departures)
                          point.from.primary,
                      ].join(' and '),
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(
                    AppRoutes.adminTimetableEditor,
                    extra: TimetableDraft.edit(timetable),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
