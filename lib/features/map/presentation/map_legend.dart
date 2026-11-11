import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../shared/widgets/route_color.dart';
import '../../../shared/widgets/stop_badge.dart';
import '../../buses/presentation/bus_card.dart';
import '../../prediction/presentation/predicted_buses_section.dart';
import '../application/transport_map_layers.dart';

/// Opens the key to the map: what each marker and line means.
Future<void> showMapLegend(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const MapLegend(),
  );
}

/// A short piece of a route's line as the map draws it: its colour, with
/// its pattern (plain, dashes or dots) down the middle.
class RoutePatternSwatch extends StatelessWidget {
  const RoutePatternSwatch({
    required this.color,
    required this.pattern,
    this.width = 40,
    super.key,
  });

  final Color color;

  /// 0 plain, 1 dashes, 2 dots: see [TransportGeoJson.patternOf].
  final int pattern;
  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, 12),
      painter: _RoutePatternPainter(
        color: color,
        ink: Theme.of(context).colorScheme.surface,
        pattern: pattern,
      ),
    );
  }
}

class _RoutePatternPainter extends CustomPainter {
  const _RoutePatternPainter({
    required this.color,
    required this.ink,
    required this.pattern,
  });

  final Color color;
  final Color ink;
  final int pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
      Offset(4, y),
      Offset(size.width - 4, y),
      Paint()
        ..color = color
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    final mark = Paint()
      ..color = ink
      ..strokeWidth = pattern == 2 ? 3.4 : 2.6
      ..strokeCap = pattern == 2 ? StrokeCap.round : StrokeCap.butt;
    if (pattern == 1) {
      for (var x = 6.0; x < size.width - 10; x += 12) {
        canvas.drawLine(Offset(x, y), Offset(x + 6, y), mark);
      }
    } else if (pattern == 2) {
      for (var x = 8.0; x < size.width - 6; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 0.1, y), mark);
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePatternPainter old) =>
      old.color != color || old.ink != ink || old.pattern != pattern;
}

/// The key to the map. It uses the same badges the map and the lists use,
/// so what it explains is what is seen.
class MapLegend extends ConsumerWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final routes =
        ref.watch(transportNetworkProvider).value?.routes ?? const [];

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
        'Its position arrived in the last few seconds. A soft ring pulses '
            'round it, and the small pointer shows which way it is going. '
            'The thin outer ring is the colour of its route.',
      ),
      (
        BusBadge(color: semantic.warning, size: 40),
        'Delayed',
        'Its last position is up to a minute old. It is drawn a little '
            'faded and says how long ago it was seen.',
      ),
      (
        Opacity(
          opacity: 0.6,
          child: BusBadge(color: semantic.offline, size: 40),
        ),
        'Offline',
        'It has stopped reporting. The marker is grey, faded and does not '
            'move: it is where the bus was last seen, not where it is now.',
      ),
      (
        const PredictedBadge(size: 40),
        'Predicted',
        'Not a real position: worked out from the timetable or from where '
            'the bus was last seen. Its label starts with "~".',
      ),
      (
        Badge(
          label: const Text('3'),
          backgroundColor: scheme.onSurface,
          textColor: scheme.surface,
          child: BusBadge(color: semantic.success, size: 36),
        ),
        'Several buses',
        'Buses too close together to show apart share one marker with a '
            'count. Tap it for the list, or zoom in to separate them.',
      ),
      (
        const StopBadge(size: 40),
        'Bus stop',
        'Tap one to see its routes and the buses on their way. A blue '
            'ring marks the stop nearest to you.',
      ),
      (
        line(scheme.primary, bold: false),
        'Routes',
        'Each route has its own colour and its own pattern: plain, dashes '
            'or dots. Where routes share a road they are drawn side by '
            'side.',
      ),
      (
        line(scheme.primary, bold: true),
        'Selected route',
        'Drawn bold with a glow; the others fade back. Arrows show the '
            'direction being shown. For a picked bus, the part it has '
            'covered is faded and each stop ahead shows the minutes to go.',
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
            if (routes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'The routes on this map',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final (index, route) in routes.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Center(
                          child: RoutePatternSwatch(
                            color: routeColor(route.colorHex),
                            pattern: TransportGeoJson.patternOf(index),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          route.name,
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
