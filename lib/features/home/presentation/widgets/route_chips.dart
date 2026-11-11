import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../data/repositories/transport_network_repository.dart';
import '../../../../shared/widgets/route_color.dart';
import '../../../map/application/map_selection.dart';

/// A row of chips floating over the top of the map: one for every route,
/// and one to see them all. Tapping a route's chip puts that route in focus
/// on the map and in the sheet.
class RouteChips extends ConsumerWidget {
  const RouteChips({super.key});

  /// Height of the row, for laying things out beneath it.
  static const double height = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes =
        ref.watch(transportNetworkProvider).value?.routes ?? const [];
    if (routes.isEmpty) return const SizedBox.shrink();

    final selectedId = ref.watch(
      mapSelectionProvider.select((selection) => selection.routeId),
    );
    final select = ref.read(mapSelectionProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Room for the chips' shadows.
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 2, AppSpacing.lg, 10),
        itemCount: routes.length + 1,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _RouteChip(
              label: 'All routes',
              semanticLabel: 'Show all routes',
              color: scheme.primary,
              icon: Icons.layers_rounded,
              selected: selectedId == null,
              onTap: select.clear,
            );
          }
          final route = routes[index - 1];
          return _RouteChip(
            label: route.name,
            semanticLabel: 'Show ${route.name} on the map',
            color: routeColor(route.colorHex),
            selected: route.id == selectedId,
            onTap: () => route.id == selectedId
                ? select.clear()
                : select.selectRoute(route.id),
          );
        },
      ),
    );
  }
}

class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.label,
    required this.semanticLabel,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String semanticLabel;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Shown instead of the colour dot.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Text on the route's own colour: white unless the colour is light.
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final foreground = selected ? onColor : scheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: RouteChips.height,
        decoration: BoxDecoration(
          color: selected ? color : scheme.surface,
          borderRadius: BorderRadius.circular(RouteChips.height / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.24 : 0.16),
              blurRadius: selected ? 10 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null)
                    Icon(icon, size: 18, color: selected ? onColor : color)
                  else
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: selected ? onColor : color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
