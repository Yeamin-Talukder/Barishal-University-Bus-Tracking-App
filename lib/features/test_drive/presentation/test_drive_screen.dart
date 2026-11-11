import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/repositories/route_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../shared/widgets/info_tile.dart';
import '../../../shared/widgets/route_card.dart';
import '../../buses/presentation/bus_card.dart';
import '../application/test_drive.dart';

/// "From A to B" for a bus on [route], whichever way it sets off.
String testJourneyText(BusRoute route, {required bool towardsStart}) {
  final start = route.startName.isEmpty ? 'the start' : route.startName;
  final end = route.endName.isEmpty ? 'the end' : route.endName;
  return towardsStart ? '$end → $start' : '$start → $end';
}

/// Lets anyone try the app with pretend buses that exist only on this
/// phone: add buses, choose their route, direction, speed and start, and
/// set them going.
class TestDriveScreen extends ConsumerWidget {
  const TestDriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final test = ref.watch(testDriveProvider);
    final controller = ref.read(testDriveProvider.notifier);
    final network = ref.watch(transportNetworkProvider).value;
    final routes = [
      for (final route in network?.routes ?? const <BusRoute>[])
        if (route.path.length >= 2) route,
    ];
    final isFull = test.buses.length >= TestDriveController.mostBuses;
    final routesAreLoading =
        network == null || ref.watch(officialRoutesProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Test the system')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          SoftCard(
            color: scheme.primary.withValues(alpha: 0.08),
            borderColor: scheme.primary.withValues(alpha: 0.25),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.science_rounded, color: scheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pretend buses, on this phone only',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'These buses are made up by the app so you can see '
                        'how it works. Nothing is sent to the server and '
                        'nobody else sees them. Each one is named TEST, and '
                        'they all disappear when you stop the test.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (routes.isEmpty)
            SoftCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                // The routes come from the server a moment after the app
                // opens; do not say there are none before they are in.
                routesAreLoading
                    ? 'Loading the routes…'
                    : 'There is no route on the map to drive along yet. Test '
                          'buses follow the real routes, so one must be drawn '
                          'first.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 52,
              child: test.isRunning
                  ? FilledButton.tonalIcon(
                      onPressed: controller.stop,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop the test'),
                    )
                  : FilledButton.icon(
                      onPressed: test.buses.isEmpty ? null : controller.start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start the test'),
                    ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: Alignment.topCenter,
              child: test.isRunning
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => context.go(AppRoutes.home),
                          icon: const Icon(Icons.map_rounded),
                          label: const Text('Watch on the map'),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: Text(
                    test.buses.isEmpty
                        ? 'Test buses'
                        : 'Test buses (${test.buses.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (test.isRunning)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: semantic.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Running',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: semantic.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (test.buses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'No test buses yet. Add one, or add a ready-made set.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final bus in test.buses)
                Padding(
                  key: ValueKey(bus.id),
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Appear(
                    child: _TestBusCard(
                      bus: bus,
                      route: network?.routeById(bus.routeId),
                      onRemove: () => controller.removeBus(bus.id),
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isFull
                        ? null
                        : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (context) => _AddBusSheet(routes: routes),
                          ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a bus'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isFull
                        ? null
                        : () => controller.addSampleBuses(routes),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Add a set'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isFull
                  ? 'That is the most test buses that can run at once '
                        '(${TestDriveController.mostBuses}).'
                  : '"Add a set" puts one bus each way on up to three '
                        'routes, at different speeds, starting a few seconds '
                        'apart. A bus that reaches the end of its route '
                        'waits a moment and drives back.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TestBusCard extends StatelessWidget {
  const _TestBusCard({
    required this.bus,
    required this.route,
    required this.onRemove,
  });

  final TestBus bus;

  /// Null if the route has been removed since the bus was added.
  final BusRoute? route;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final delay = bus.startDelay.inSeconds;

    return SoftCard(
      child: Row(
        children: [
          BusBadge(color: semantic.success),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      bus.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (route != null)
                      Flexible(child: RoutePill(route: route!)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  route == null
                      ? 'Its route is no longer on the map'
                      : testJourneyText(route!, towardsStart: bus.towardsStart),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${bus.speedKmh.round()} km/h',
                    delay == 0 ? 'starts at once' : 'starts after $delay s',
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove ${bus.label}',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

/// The form for one more test bus.
class _AddBusSheet extends ConsumerStatefulWidget {
  const _AddBusSheet({required this.routes});

  /// The routes a bus can drive along. Never empty.
  final List<BusRoute> routes;

  @override
  ConsumerState<_AddBusSheet> createState() => _AddBusSheetState();
}

class _AddBusSheetState extends ConsumerState<_AddBusSheet> {
  late BusRoute _route = widget.routes.first;
  bool _towardsStart = false;
  double _speedKmh = 40;
  double _delaySeconds = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add a test bus',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Route', style: label),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final route in widget.routes)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(
                      Icons.route_rounded,
                      size: 18,
                      color: _route.id == route.id
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    label: Text(route.name),
                    selected: _route.id == route.id,
                    onSelected: (_) => setState(() => _route = route),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Which way it sets off', style: label),
            const SizedBox(height: AppSpacing.xs),
            RadioGroup<bool>(
              groupValue: _towardsStart,
              onChanged: (value) =>
                  setState(() => _towardsStart = value ?? false),
              child: Column(
                children: [
                  for (final towardsStart in [false, true])
                    RadioListTile<bool>(
                      value: towardsStart,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        testJourneyText(_route, towardsStart: towardsStart),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: Text('Speed', style: label)),
                Text(
                  '${_speedKmh.round()} km/h',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            Slider(
              value: _speedKmh,
              min: 10,
              max: 60,
              divisions: 10,
              label: '${_speedKmh.round()} km/h',
              onChanged: (value) => setState(() => _speedKmh = value),
            ),
            Row(
              children: [
                Expanded(child: Text('Starts after', style: label)),
                Text(
                  _delaySeconds == 0
                      ? 'At once'
                      : '${_delaySeconds.round()} seconds',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            Slider(
              value: _delaySeconds,
              max: 60,
              divisions: 12,
              label: '${_delaySeconds.round()} s',
              onChanged: (value) => setState(() => _delaySeconds = value),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  ref
                      .read(testDriveProvider.notifier)
                      .addBus(
                        routeId: _route.id,
                        towardsStart: _towardsStart,
                        speedKmh: _speedKmh,
                        startDelay: Duration(seconds: _delaySeconds.round()),
                      );
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add this bus'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
