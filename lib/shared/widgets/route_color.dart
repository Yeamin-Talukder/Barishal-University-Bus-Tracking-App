import 'package:flutter/material.dart';

/// Turns a route's `#RRGGBB` colour into a [Color].
Color routeColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// The coloured bar that identifies a route in lists.
class RouteColorBar extends StatelessWidget {
  const RouteColorBar({required this.colorHex, this.height = 40, super.key});

  final String colorHex;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: height,
      decoration: BoxDecoration(
        color: routeColor(colorHex),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
