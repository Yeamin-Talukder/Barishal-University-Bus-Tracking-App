import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/repositories/bus_repository.dart';
import '../../../data/repositories/live_tracking_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/application/session.dart';
import '../../auth/domain/user_profile.dart';
import '../application/trip_controller.dart';

/// Whether the signed-in person is an active driver.
final isDriverProvider = Provider<bool>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  return profile != null && profile.isActive && profile.role == UserRole.driver;
});

/// The bus in service that is assigned to the signed-in driver, if any.
final myBusProvider = Provider<Bus?>((ref) {
  final uid = ref.watch(accountProvider).value?.uid;
  if (uid == null || !ref.watch(isDriverProvider)) return null;
  final buses = ref.watch(registeredBusesProvider).value ?? const <Bus>[];
  return buses.where((bus) => bus.isActive && bus.driverUid == uid).firstOrNull;
});

/// The route the driver picked for the next trip. Until they pick, the
/// bus's own route is used.
final tripRouteProvider =
    NotifierProvider<TripRouteChoice, ({bool isSet, String? routeId})>(
      TripRouteChoice.new,
    );

class TripRouteChoice extends Notifier<({bool isSet, String? routeId})> {
  @override
  ({bool isSet, String? routeId}) build() => (isSet: false, routeId: null);

  void choose(String? routeId) => state = (isSet: true, routeId: routeId);
}

/// The Profile section a driver uses to start and end a trip. While a trip
/// is running, this phone shares the bus's position.
///
/// Shown only to drivers. The database decides whether a trip may start:
/// only the driver an admin assigned to the bus is accepted.
class DriverSection extends ConsumerWidget {
  const DriverSection({super.key});

  static const String title = 'Your bus';

  static String _time(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour:${two(time.minute)}:${two(time.second)} '
        '${time.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isDriverProvider)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final semantic = theme.extension<AppSemanticColors>()!;
    final uid = ref.watch(accountProvider).value!.uid;
    final bus = ref.watch(myBusProvider);
    final trip = ref.watch(tripControllerProvider);
    final controller = ref.read(tripControllerProvider.notifier);

    if (bus == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: const SectionCard(
          title: title,
          children: [
            ListTile(
              leading: Icon(Icons.directions_bus_rounded),
              title: Text('No bus is assigned to you'),
              subtitle: Text(
                'The transport office assigns a bus to each driver. Ask them '
                'to assign yours.',
              ),
            ),
          ],
        ),
      );
    }

    // A trip left open on this bus, for example because the app was closed.
    final openTrip = ref.watch(activeTripProvider(bus.id)).value;
    final hasOpenTrip =
        trip.phase == TripPhase.idle &&
        openTrip != null &&
        openTrip.driverUid == uid;
    // The routes drawn on the map, which arrival estimates can follow.
    final routes =
        ref.watch(transportNetworkProvider).value?.routes ?? const <BusRoute>[];
    final choice = ref.watch(tripRouteProvider);
    final chosenRoute = choice.isSet
        ? choice.routeId
        : (routes.any((route) => route.id == bus.routeId) ? bus.routeId : null);
    final problem = trip.problem;
    final lastSentAt = trip.lastSentAt;
    final accuracy = trip.lastAccuracyMeters;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: SectionCard(
        title: title,
        children: [
          ListTile(
            leading: const Icon(Icons.directions_bus_rounded),
            title: Text('${bus.number} · ${bus.name}'),
            subtitle: Text(
              bus.routeId == null ? 'No route set' : 'Route ${bus.routeId}',
            ),
            trailing: trip.isSharing
                ? StatusPill(label: 'Sharing', color: semantic.success)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (trip.isSharing) ...[
                  Text(
                    lastSentAt == null
                        ? 'Waiting for the phone\'s first position.'
                        : 'Last position sent at ${_time(lastSentAt)}'
                              '${accuracy == null ? '' : ', accurate to about ${accuracy.round()} m'}'
                              '. ${trip.sentCount} sent this trip.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'You can switch to other apps or turn the screen off. A '
                    'notification stays up while the position is shared.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ] else if (hasOpenTrip)
                  Text(
                    'A trip is open on this bus, but this phone is not '
                    'sharing its position. Passengers see the bus as it was '
                    'last reported.',
                    style: theme.textTheme.bodyMedium,
                  )
                else if (trip.phase == TripPhase.idle)
                  Text(
                    'Start a trip when the bus sets off. Passengers then see '
                    'where it is until you end the trip.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                if (problem != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    problem,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (trip.phase == TripPhase.idle &&
                    !hasOpenTrip &&
                    routes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String?>(
                    key: const Key('trip-route'),
                    initialValue: chosenRoute,
                    decoration: const InputDecoration(
                      labelText: 'Route for this trip',
                      helperText:
                          'Passengers get arrival times for the route you '
                          'choose.',
                      helperMaxLines: 2,
                    ),
                    items: [
                      const DropdownMenuItem(child: Text('No route')),
                      for (final route in routes)
                        DropdownMenuItem(
                          value: route.id,
                          child: Text(route.name),
                        ),
                    ],
                    onChanged: (value) =>
                        ref.read(tripRouteProvider.notifier).choose(value),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                switch (trip.phase) {
                  TripPhase.starting || TripPhase.ending => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  TripPhase.sharing => OutlinedButton.icon(
                    onPressed: () => controller.end(bus.id),
                    icon: const Icon(Icons.stop_circle_rounded),
                    label: const Text('End trip'),
                  ),
                  TripPhase.idle when hasOpenTrip => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: () => controller.resume(openTrip),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Resume sharing'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => controller.end(bus.id),
                        icon: const Icon(Icons.stop_circle_rounded),
                        label: const Text('End trip'),
                      ),
                    ],
                  ),
                  TripPhase.idle => FilledButton.icon(
                    onPressed: () {
                      final route = chosenRoute;
                      controller.start(
                        route == bus.routeId
                            ? bus
                            : Bus(
                                id: bus.id,
                                number: bus.number,
                                name: bus.name,
                                registrationNumber: bus.registrationNumber,
                                routeId: route,
                                driverUid: bus.driverUid,
                                isActive: bus.isActive,
                              ),
                        uid,
                      );
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start trip'),
                  ),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}
