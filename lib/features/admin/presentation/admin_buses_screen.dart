import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_repository.dart';
import '../../../data/repositories/live_tracking_repository.dart';
import '../../../data/repositories/tracking_mirror.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../../schedule/domain/bus_schedule.dart';
import '../../schedule/domain/schedule_buses.dart';
import '../data/driver_directory.dart';

/// What the bus editor starts from. Null [bus] adds a new one.
@immutable
class BusDraft {
  const BusDraft(this.bus);

  final Bus bus;
}

/// The route numbers a bus can be assigned to: those in the schedule.
final scheduleRouteNumbersProvider = Provider<List<String>>((ref) {
  final schedule = ref.watch(busScheduleProvider).value;
  final numbers = {
    for (final timetable in schedule?.timetables ?? const <RouteTimetable>[])
      timetable.routeNumber,
  }.toList()..sort();
  return numbers;
});

/// Where an admin adds, changes and removes buses.
///
/// The screen is only a convenience: the database refuses these changes
/// from anyone who is not an admin, whatever is shown here.
class AdminBusesScreen extends ConsumerWidget {
  const AdminBusesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage buses')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.adminBusEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add bus'),
            )
          : null,
      body: isAdmin
          ? const _BusList()
          : const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Admins only',
              message:
                  'Only a transport office admin can change the buses. Sign '
                  'in with an admin account.',
            ),
    );
  }
}

class _BusList extends ConsumerWidget {
  const _BusList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final buses = ref.watch(registeredBusesProvider);
    final saved = buses.value ?? const <Bus>[];
    final driverNames = {
      for (final driver in ref.watch(driversProvider).value ?? const [])
        driver.uid: driver.name,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        // Room for the Add bus button.
        96,
      ),
      children: [
        SectionCard(
          title: 'Buses (${saved.length})',
          children: [
            if (buses.isLoading && !buses.hasValue)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (buses.hasError && !buses.hasValue)
              const ListTile(
                leading: Icon(Icons.cloud_off_rounded),
                title: Text('The buses could not be loaded'),
                subtitle: Text('Check the connection and open this again.'),
              )
            else if (saved.isEmpty)
              const ListTile(
                leading: Icon(Icons.directions_bus_rounded),
                title: Text('No buses yet'),
                subtitle: Text('Add one with the button below.'),
              )
            else
              for (final bus in saved)
                ListTile(
                  leading: Icon(
                    Icons.directions_bus_rounded,
                    color: bus.isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  title: Text('${bus.number} · ${bus.name}'),
                  subtitle: Text(
                    [
                      bus.routeId == null ? 'No route' : 'Route ${bus.routeId}',
                      bus.driverUid == null
                          ? 'No driver'
                          : 'Driver: '
                                '${driverNames[bus.driverUid] ?? 'not in the driver list'}',
                      if (!bus.isActive) 'Not in service',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(
                    AppRoutes.adminBusEditor,
                    extra: BusDraft(bus),
                  ),
                ),
          ],
        ),
        _ScheduleBuses(saved: saved),
        const _DriverSync(),
      ],
    );
  }
}

/// The buses the schedule names that are not in the bus list yet, offered
/// to the admin to add: all at once, or one at a time after a look.
class _ScheduleBuses extends ConsumerStatefulWidget {
  const _ScheduleBuses({required this.saved});

  final List<Bus> saved;

  @override
  ConsumerState<_ScheduleBuses> createState() => _ScheduleBusesState();
}

class _ScheduleBusesState extends ConsumerState<_ScheduleBuses> {
  bool _busy = false;

  Future<void> _addAll(List<Bus> buses) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(busRepositoryProvider).addAll(buses);
      messenger.showSnackBar(
        SnackBar(content: Text('${buses.length} buses added.')),
      );
    } on BusWriteFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schedule = ref.watch(busScheduleProvider).value;
    if (schedule == null) return const SizedBox.shrink();

    final savedNumbers = {
      for (final bus in widget.saved) bus.number.toLowerCase(),
    };
    final missing = [
      for (final bus in busesNamedInSchedule(schedule))
        if (!savedNumbers.contains(bus.number.toLowerCase())) bus,
    ];
    if (missing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: SectionCard(
        title: 'Named in the schedule (${missing.length})',
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The schedule names these buses, and they are not in the '
                  'list above yet. A bus gets a route only when the '
                  'schedule uses it on a single route. Add them all, or '
                  'open one to check it first.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _addAll(missing),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(Icons.playlist_add_rounded),
                  label: Text('Add all ${missing.length} buses'),
                ),
              ],
            ),
          ),
          for (final bus in missing)
            ListTile(
              dense: true,
              leading: const Icon(Icons.directions_bus_rounded),
              title: Text(
                bus.name == bus.number
                    ? bus.number
                    : '${bus.number} · ${bus.name}',
              ),
              subtitle: Text(
                bus.routeId == null
                    ? 'On more than one route in the schedule'
                    : 'Route ${bus.routeId}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () =>
                  context.push(AppRoutes.adminBusEditor, extra: BusDraft(bus)),
            ),
        ],
      ),
    );
  }
}

/// Keeps the tracking database's note of who drives each bus in line with
/// the bus list, whenever this screen is open. The tracking database decides
/// who may start a trip but cannot see the bus list, so a missed update
/// heals itself here.
class _DriverSync extends ConsumerStatefulWidget {
  const _DriverSync();

  @override
  ConsumerState<_DriverSync> createState() => _DriverSyncState();
}

class _DriverSyncState extends ConsumerState<_DriverSync> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(registeredBusesProvider, (previous, next) {
      final buses = next.value;
      if (buses == null) return;
      ref
          .read(trackingAccessProvider)
          .setBusDrivers({
            for (final bus in buses) bus.id: trackingDriverOf(bus),
          })
          .catchError(
            (Object error) => debugPrint('Driver sync skipped: $error'),
          );
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
