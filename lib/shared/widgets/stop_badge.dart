import 'package:flutter/material.dart';

import '../../features/map/application/stop_map_layer.dart';

/// The bus-stop badge used in lists and headers: the same sign a stop has
/// on the map. It pops into place when it first appears.
class StopBadge extends StatelessWidget {
  const StopBadge({this.size = 44, this.highlighted = false, super.key});

  final double size;

  /// Drawn in the app's main colour, as the picked stop is on the map.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = highlighted ? scheme.primary : scheme.secondaryContainer;
    final ink = highlighted ? scheme.onPrimary : scheme.onSecondaryContainer;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: body,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: body.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: CustomPaint(
          painter: _StopSignPainter(ink: ink, cutout: body),
        ),
      ),
    );
  }
}

class _StopSignPainter extends CustomPainter {
  const _StopSignPainter({required this.ink, required this.cutout});

  final Color ink;
  final Color cutout;

  @override
  void paint(Canvas canvas, Size size) {
    // The sign is designed for a badge 60 units across.
    drawStopSign(
      canvas,
      size.center(Offset.zero),
      size.shortestSide / 60,
      ink: ink,
      cutout: cutout,
    );
  }

  @override
  bool shouldRepaint(_StopSignPainter old) =>
      old.ink != ink || old.cutout != cutout;
}
