import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../announcements/presentation/announcement_list.dart';

import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/services/eta_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../data/models/bus.dart';
import '../../../../data/models/bus_route.dart';
import '../../../../data/models/transport_network.dart';
import '../../../../data/repositories/bus_location_repository.dart';
import '../../../../data/repositories/transport_network_repository.dart';
import '../../../../shared/widgets/route_card.dart';
import '../../../buses/presentation/arrival_text.dart';
import '../../../alerts/presentation/arrival_alert_views.dart';
import '../../../buses/presentation/bus_card.dart';
import '../../../buses/presentation/bus_details_view.dart';
import '../../../map/application/map_selection.dart';
import '../../../map/application/map_view_state.dart';
import '../../../prediction/presentation/predicted_buses_section.dart';
import '../../application/stop_arrivals.dart';
import 'nearest_stop_card.dart';
import 'selection_details.dart';

/// The draggable sheet over the map.
///
/// With nothing selected it summarises the buses and lists the routes. When
/// the passenger picks a route, stop or bus, it shows that instead and opens
/// far enough to read it.
///
/// On a wide screen ([asPanel]) the same content is a panel at the side of
/// the map instead: it does not slide, it is simply there.
class HomeSheet extends ConsumerStatefulWidget {
  const HomeSheet({this.asPanel = false, super.key});

  /// Whether to be a fixed panel beside the map rather than a sheet that
  /// slides up over it.
  final bool asPanel;

  /// Fractions of the available height the sheet rests at.
  static const double collapsedSize = 0.17;
  static const double halfSize = 0.46;
  static const double expandedSize = 0.9;

  @override
  ConsumerState<HomeSheet> createState() => _HomeSheetState();
}

class _HomeSheetState extends ConsumerState<HomeSheet> {
  final DraggableScrollableController _sheet = DraggableScrollableController();
  final ScrollController _panelScroll = ScrollController();

  @override
  void dispose() {
    _sheet.dispose();
    _panelScroll.dispose();
    super.dispose();
  }

  /// Opens the sheet to its middle position if it is lower than that.
  void _reveal() {
    if (!_sheet.isAttached || _sheet.size >= HomeSheet.halfSize) return;
    _sheet.animateTo(
      HomeSheet.halfSize,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    ref.listen(mapSelectionProvider, (previous, next) {
      if (next.isEmpty || next == previous) return;
      if (!widget.asPanel) return _reveal();
      // What was picked is shown from its top.
      if (_panelScroll.hasClients) _panelScroll.jumpTo(0);
    });

    if (widget.asPanel) {
      return Material(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: PointerInterceptor(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            child: _SheetContent(
              scrollController: _panelScroll,
              showHandle: false,
            ),
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: HomeSheet.collapsedSize,
      minChildSize: HomeSheet.collapsedSize,
      maxChildSize: HomeSheet.expandedSize,
      snap: true,
      snapSizes: const [HomeSheet.halfSize],
      builder: (context, scrollController) {
        // A Material, so the list rows inside can draw their ink ripples.
        return Material(
          color: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 16,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: PointerInterceptor(
            // Let a mouse or trackpad drag the sheet too, not only touch.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: _SheetContent(scrollController: scrollController),
            ),
          ),
        );
      },
    );
  }
}

class _SheetContent extends ConsumerWidget {
  const _SheetContent({required this.scrollController, this.showHandle = true});

  final ScrollController scrollController;

  /// Whether to draw the bar that says the sheet can be dragged.
  final bool showHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(transportNetworkProvider).value;
    final buses = ref.watch(trackedBusesProvider).value ?? const [];
    final selection = ref.watch(mapSelectionProvider);
    final select = ref.read(mapSelectionProvider.notifier);

    final route = selection.routeId == null
        ? null
        : network?.routeById(selection.routeId!);
    final stop = selection.stopId == null
        ? null
        : network?.stopById(selection.stopId!);
    final bus = selection.busId == null
        ? null
        : buses
              .where((tracked) => tracked.bus.id == selection.busId)
              .firstOrNull;

    final Widget body;
    if (network != null && route != null) {
      body = RouteDetails(
        key: ValueKey('route-${route.id}'),
        route: route,
        stops: network.stopsOf(route),
        onStopSelected: (stop) => select.selectStop(stop.id),
        onClose: select.clear,
        // The arrows on the map point the way the stops are listed.
        reversed: ref.watch(routeShownReversedProvider),
        onSwapDirection: ref.read(routeShownReversedProvider.notifier).toggle,
      );
    } else if (network != null && stop != null) {
      final routesHere = network.routesServing(stop.id);
      final busesHere = [
        for (final tracked in buses)
          if (routesHere.any((route) => route.id == tracked.bus.routeId))
            tracked,
      ];
      body = StopDetails(
        key: ValueKey('stop-${stop.id}'),
        stop: stop,
        routes: routesHere,
        onRouteSelected: (route) => select.selectRoute(route.id),
        onClose: select.clear,
        hasTrackedBuses: busesHere.isNotEmpty,
        approaching: ref.watch(stopArrivalsProvider(stop.id)),
        arrivalActionBuilder: (arrival) => ArrivalAlertButton(
          busId: arrival.bus.bus.id,
          busNumber: arrival.bus.bus.number,
          stopId: stop.id,
          stopName: stop.name,
        ),
        predictedArrivals: PredictedArrivalsSection(stopId: stop.id),
        onBusSelected: (tracked) => select.selectBus(tracked.bus.id),
      );
    } else if (bus != null) {
      final busRoute = bus.bus.routeId == null
          ? null
          : network?.routeById(bus.bus.routeId!);
      // Where the bus is heading and when it should get there.
      final next = network == null || busRoute == null
          ? null
          : ref
                .watch(etaServiceProvider)
                .estimateNextStop(
                  route: busRoute,
                  stops: network.stopsOf(busRoute),
                  location: bus.location,
                  now: ref.watch(clockProvider)(),
                );
      body = BusDetailsView(
        key: ValueKey('bus-${bus.bus.id}'),
        tracked: bus,
        route: busRoute,
        nextStopName: next?.nextStop?.name,
        estimatedArrival: next == null ? null : arrivalText(next.estimate),
        isFollowing: selection.isFollowingBus,
        onFollowChanged: select.setFollowingBus,
        onClose: select.clear,
      );
    } else {
      body = _Overview(key: const ValueKey('overview'), buses: buses);
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        if (showHandle)
          const _DragHandle()
        else
          const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          // Keep the new content at the top while the old one fades out.
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            children: [...previousChildren, ?currentChild],
          ),
          child: body,
        ),
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// What the sheet shows when nothing is selected.
class _Overview extends ConsumerWidget {
  const _Overview({required this.buses, super.key});

  final List<TrackedBus> buses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(transportNetworkProvider);
    final select = ref.read(mapSelectionProvider.notifier);
    final config = ref.watch(trackingConfigurationProvider);
    final now = ref.watch(clockProvider)();
    final liveCount = buses
        .where(
          (tracked) =>
              config.statusOf(tracked.location?.updatedAt, now) ==
              BusTrackingStatus.live,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AnnouncementList(),
        _TrackingSummary(busCount: buses.length, liveCount: liveCount),
        const NearestStopCard(),
        if (buses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final tracked in buses)
            BusCard(
              tracked: tracked,
              routeName: tracked.bus.routeId == null
                  ? null
                  : network.value?.routeById(tracked.bus.routeId!)?.name,
              onTap: () => select.selectBus(tracked.bus.id),
            ),
        ],
        PredictedBusesSection(onRouteSelected: select.selectRoute),
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle('Routes'),
        network.when(
          // A change to the stops reloads this; keep showing it meanwhile.
          skipLoadingOnReload: true,
          loading: () => const _RouteListSkeleton(),
          error: (error, stackTrace) => const _SheetMessage(
            'The route list could not be read from this device.',
          ),
          data: (network) => _RouteList(
            network: network,
            onRouteSelected: (route) => select.selectRoute(route.id),
          ),
        ),
      ],
    );
  }
}

class _TrackingSummary extends StatelessWidget {
  const _TrackingSummary({required this.busCount, required this.liveCount});

  final int busCount;
  final int liveCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>()!;
    final color = liveCount > 0 ? semantic.success : semantic.muted;

    final title = switch (liveCount) {
      0 => 'No live buses',
      1 => '1 bus live',
      _ => '$liveCount buses live',
    };
    final subtitle = busCount == 0
        ? 'Live tracking is not available yet.'
        : liveCount == busCount
        ? 'Positions are up to date.'
        : '${busCount - liveCount} of $busCount not reporting right now.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          BusBadge(color: color, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (liveCount > 0) _LiveDot(color: color),
        ],
      ),
    );
  }
}

/// A dot with a soft halo: something is live right now.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RouteList extends StatelessWidget {
  const _RouteList({required this.network, required this.onRouteSelected});

  final TransportNetwork network;
  final ValueChanged<BusRoute> onRouteSelected;

  @override
  Widget build(BuildContext context) {
    if (network.routes.isEmpty) {
      return const _SheetMessage(
        'No routes have been added yet. They will appear here and on the '
        'map once the university transport office has confirmed them.',
      );
    }

    return Column(
      children: [
        for (final route in network.routes)
          _RouteRow(route: route, onTap: () => onRouteSelected(route)),
        if (network.problems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _SheetMessage(
              '${network.problems.length} entries in the route data were '
              'skipped because they are invalid.',
            ),
          ),
      ],
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.route, required this.onTap});

  final BusRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ends = [
      route.startName,
      route.endName,
    ].where((name) => name.isNotEmpty).join(' to ');
    final stopCount = route.stopIds.length;
    final details = [
      if (ends.isNotEmpty) ends,
      if (stopCount > 0) '$stopCount stops',
      if (!route.isActive) 'Not running',
    ].join(' · ');

    return RouteCard(route: route, details: details, onTap: onTap);
  }
}

class _RouteListSkeleton extends StatelessWidget {
  const _RouteListSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              height: 44,
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
        ],
      ),
    );
  }
}
