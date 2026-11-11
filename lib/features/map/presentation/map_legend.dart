import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/stop_badge.dart';
import '../../buses/presentation/bus_card.dart';
import '../../prediction/presentation/predicted_buses_section.dart';

/// Opens the key to the map: what each marker and line means.
Future<void> showMapLegend(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const MapLegend(),
  );
}

/// The key to the map. It uses the same badges the map and the lists use,
/// so what it explains is what is seen.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;

    Widget line(Color color, {required bool bold}) => SizedBox(
      width: 40,
      child: Center(
        child: Container(
          width: 36,
          height: bold ? 7 : 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            boxShadow: bold
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );

    final rows = <(Widget, String, String)>[
      (
        BusBadge(color: semantic.success, size: 40),
        'Live bus',
        'Its position arrived in the last few seconds. The small pointer '
            'shows which way it is going.',
      ),
      (
        BusBadge(color: semantic.warning, size: 40),
        'Delayed',
        'Its last position is up to a minute old.',
      ),
      (
        BusBadge(color: semantic.offline, size: 40),
        'Offline',
        'It has stopped reporting. The marker is where it was last seen, '
            'not where it is now.',
      ),
      (
        const PredictedBadge(size: 40),
        'Predicted',
        'Not a real position: worked out from the timetable or from where '
            'the bus was last seen. Its label starts with "~".',
      ),
      (
        const StopBadge(size: 40),
        'Bus stop',
        'Tap one to see its routes and the buses on their way.',
      ),
      (
        line(scheme.primary, bold: false),
        'Routes',
        'Each route has its own colour. Where routes share a road they are '
            'drawn side by side.',
      ),
      (
        line(scheme.primary, bold: true),
        'Selected route',
        'Drawn bold with a glow; the others fade back.',
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Map key',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (symbol, title, meaning) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 44, child: Center(child: symbol)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meaning,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
