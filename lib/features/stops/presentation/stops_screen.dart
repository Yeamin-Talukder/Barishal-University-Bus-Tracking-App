import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/bus_route.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/models/transport_network.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../shared/widgets/route_color.dart';
import '../../../shared/widgets/transport_list_view.dart';
import '../../map/application/map_selection.dart';
import 'widgets/stop_card.dart';

/// The stops that match [query] (in their name or description) and, when
/// [routeId] is given, that the route calls at.
List<BusStop> filterStops(
  TransportNetwork network, {
  String query = '',
  String? routeId,
}) {
  final words = query.trim().toLowerCase();
  final route = routeId == null ? null : network.routeById(routeId);
  return [
    for (final stop in network.stops)
      if ((route == null || route.stopIds.contains(stop.id)) &&
          (words.isEmpty ||
              stop.name.toLowerCase().contains(words) ||
              (stop.description?.toLowerCase().contains(words) ?? false)))
        stop,
  ];
}

/// Lists the bus stops, with a search box and a filter by route pinned at
/// the top. Tapping a stop opens it on the map.
///
/// Only stops from the stop data are listed; the app never invents stops.
class StopsScreen extends ConsumerStatefulWidget {
  const StopsScreen({super.key});

  @override
  ConsumerState<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends ConsumerState<StopsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _routeId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final network = ref.watch(transportNetworkProvider).value;
    final hasStops = network != null && network.stops.isNotEmpty;
    // A route that was removed while it was chosen no longer filters.
    final routeId = network?.routeById(_routeId ?? '') == null
        ? null
        : _routeId;
    final isFiltering = _query.trim().isNotEmpty || routeId != null;
    final shown = hasStops
        ? filterStops(network, query: _query, routeId: routeId).length
        : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Stops')),
      body: Column(
        children: [
          // Nothing to search until there are stops.
          if (hasStops)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search stops',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                      filled: true,
                      fillColor: scheme.surfaceContainerHigh,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (network.routes.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All stops',
                            selected: routeId == null,
                            onTap: () => setState(() => _routeId = null),
                          ),
                          for (final route in network.routes)
                            _FilterChip(
                              label: route.name,
                              semanticLabel: 'Stops on ${route.name}',
                              route: route,
                              selected: routeId == route.id,
                              onTap: () => setState(
                                () => _routeId = routeId == route.id
                                    ? null
                                    : route.id,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    switch (shown) {
                      0 => 'No stops',
                      1 => isFiltering ? '1 stop found' : '1 stop',
                      _ => isFiltering ? '$shown stops found' : '$shown stops',
                    },
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TransportListView<BusStop>(
              itemsOf: (network) =>
                  filterStops(network, query: _query, routeId: routeId),
              emptyIcon: isFiltering && hasStops
                  ? Icons.search_off_rounded
                  : Icons.location_on_rounded,
              emptyTitle: isFiltering && hasStops
                  ? 'No stop matches'
                  : 'No stops yet',
              emptyMessage: isFiltering && hasStops
                  ? 'Try another name, or choose "All stops".'
                  : 'Bus stops will be listed here once their locations have '
                        'been verified.',
              itemBuilder: (context, network, stop) => StopCard(
                key: ValueKey(stop.id),
                stop: stop,
                routes: network.routesServing(stop.id),
                onTap: () {
                  ref.read(mapSelectionProvider.notifier).selectStop(stop.id);
                  context.go(AppRoutes.home);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chip that narrows the list to one route's stops, or to all of them.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    this.route,
  });

  final String label;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  /// The route this chip filters by; null for "All stops".
  final BusRoute? route;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final route = this.route;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        label: semanticLabel,
        child: ChoiceChip(
          showCheckmark: false,
          avatar: route == null
              ? Icon(
                  Icons.apps_rounded,
                  size: 18,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                )
              : Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: routeColor(route.colorHex),
                    shape: BoxShape.circle,
                  ),
                ),
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      ),
    );
  }
}
