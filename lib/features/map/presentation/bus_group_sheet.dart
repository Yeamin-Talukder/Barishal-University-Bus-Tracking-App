import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../buses/presentation/bus_card.dart';

/// Lists the buses that share one marker on the map and lets the passenger
/// pick one. Returns the id of the bus picked, or null if none was.
Future<String?> showBusGroupSheet(BuildContext context, List<String> busIds) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // On web the map is an HTML element under the Flutter canvas: without
    // this it would also react to taps and drags on the list.
    builder: (context) =>
        PointerInterceptor(child: BusGroupList(busIds: busIds)),
  );
}

/// The buses in one group on the map.
class BusGroupList extends ConsumerWidget {
  const BusGroupList({required this.busIds, super.key});

  final List<String> busIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final network = ref.watch(transportNetworkProvider).value;
    final buses = [
      for (final tracked in ref.watch(trackedBusesProvider).value ?? const [])
        if (busIds.contains(tracked.bus.id)) tracked,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                '${buses.length} buses here',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                2,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'They are too close together to show apart. Pick one, or '
                'zoom in to separate them.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final tracked in buses)
              BusCard(
                tracked: tracked,
                routeName: tracked.bus.routeId == null
                    ? null
                    : network?.routeById(tracked.bus.routeId!)?.name,
                onTap: () => Navigator.of(context).pop(tracked.bus.id),
              ),
          ],
        ),
      ),
    );
  }
}
