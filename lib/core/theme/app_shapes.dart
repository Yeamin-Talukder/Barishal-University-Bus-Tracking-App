import 'package:flutter/material.dart';

/// Corner radii. Generous, in the Material 3 Expressive manner: small
/// things are softly rounded, cards and sheets clearly so, and controls
/// that are pressed are fully round.
abstract final class AppRadius {
  /// Tags, pills inside rows, small tiles.
  static const double sm = 10;

  /// Icon tiles, text fields inside forms, menus.
  static const double md = 14;

  /// Cards.
  static const double lg = 20;

  /// Sheets, dialogs, large banners.
  static const double xl = 28;
}

/// The shapes the component themes are built from.
abstract final class AppShapes {
  /// Buttons, chips, search fields: fully round ends.
  static const OutlinedBorder pill = StadiumBorder();

  static final RoundedRectangleBorder card = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.lg),
  );

  static final RoundedRectangleBorder menu = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
  );

  static final RoundedRectangleBorder dialog = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.xl),
  );

  /// A sheet that rises from the bottom edge.
  static const RoundedRectangleBorder sheet = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
  );

  /// The floating action button: a rounded square, not a circle.
  static final RoundedRectangleBorder floatingAction = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
  );
}

/// How long things take to move, and how they ease.
abstract final class AppMotion {
  /// A state changing in place: a colour, an icon, a selection.
  static const Duration quick = Duration(milliseconds: 200);

  /// Something arriving or leaving: a card, a sheet's content.
  static const Duration standard = Duration(milliseconds: 320);

  /// Material's emphasized easing: quick to start, gentle to settle.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}
