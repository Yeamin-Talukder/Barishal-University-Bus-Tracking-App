import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../data/models/bus.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../shared/widgets/transport_list_view.dart';
import '../../map/application/map_selection.dart';
import '../../schedule/presentation/schedule_view.dart';
import 'widgets/route_card.dart';

/// The Routes tab: the official schedule, and the routes drawn on the map.
///
/// Only routes from the route data are listed under "On the map"; the app
/// never invents a route's path. Tapping one opens it on the map.
class RoutesScreen extends ConsumerWidget {
  const RoutesScreen({super.key});

  static const String scheduleTab = 'Schedule';
  static const String mapTab = 'On the map';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buses = ref.watch(trackedBusesProvider).value ?? const [];
    final config = ref.watch(trackingConfigurationProvider);
    final now = ref.watch(clockProvider)();

    int liveBusesOn(BusRoute route) => buses
        .where(
          (tracked) =>
              tracked.bus.routeId == route.id &&
              config.statusOf(tracked.location?.updatedAt, now) ==
                  BusTrackingStatus.live,
        )
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Routes'),
          bottom: const TabBar(
            tabs: [
              Tab(text: RoutesScreen.scheduleTab),
              Tab(text: RoutesScreen.mapTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const ScheduleView(),
            TransportListView<BusRoute>(
              itemsOf: (network) => network.routes,
              emptyIcon: Icons.route_rounded,
              emptyTitle: 'No routes on the map yet',
              emptyMessage:
                  'The official routes will be drawn on the map once the '
                  'positions of their stops have been confirmed. Their '
                  'timetable is under Schedule.',
              itemBuilder: (context, network, route) => RouteCard(
                route: route,
                liveBusCount: liveBusesOn(route),
                onTap: () {
                  ref.read(mapSelectionProvider.notifier).selectRoute(route.id);
                  context.go(AppRoutes.home);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
