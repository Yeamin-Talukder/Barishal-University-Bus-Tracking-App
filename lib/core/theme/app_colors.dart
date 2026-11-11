import 'package:flutter/material.dart';

/// The app's colour palette: Teal Mint.
///
/// Chosen by the owner on 11 November 2026 to replace Dark Crimson, which
/// used too much red. Neutral slate surfaces carry the screens; the mint
/// accent marks only what matters (the main button, the selected tab and
/// chip, key figures). Offline buses are grey, not red, so one colour never
/// means "selected", "a route" and "lost signal" at once.
///
/// Widgets read colours from the [ColorScheme] or from [AppSemanticColors];
/// these raw values are only for building the themes. A screen that needs a
/// colour that is not here should not invent one.
abstract final class AppColors {
  // Brand.
  /// Fills on dark surfaces: buttons, the selected chip, badges.
  static const Color mint = Color(0xFF5FD4BC);

  /// The primary on light surfaces, dark enough for text and icons on white.
  static const Color mintDeep = Color(0xFF0A7563);

  /// Text and icons in the brand colour on dark surfaces.
  static const Color mintSoft = Color(0xFF7FE0CB);
  static const Color secondary = Color(0xFF8FB8B0);
  static const Color tertiary = Color(0xFFE6A23C);

  // Dark surfaces, from the page behind everything up to raised surfaces.
  static const Color darkBackground = Color(0xFF0F1318);
  static const Color darkBackgroundSecondary = Color(0xFF141920);
  static const Color darkCard = Color(0xFF1A2028);
  static const Color darkElevated = Color(0xFF232A34);

  /// The tonal fill behind a selected tab, chip or navigation item.
  static const Color darkHighlight = Color(0xFF173A35);
  static const Color darkBorder = Color(0xFF2E3640);

  // Dark text.
  static const Color darkText = Color(0xFFEEF2F6);
  static const Color darkTextSecondary = Color(0xFFAEB8C2);
  static const Color darkTextMuted = Color(0xFF8592A0);
  static const Color darkTextDisabled = Color(0xFF5F6B78);

  // Status, on dark surfaces. Live is a yellow-green so it is not taken for
  // the mint accent; offline is a cool grey, told apart by its icon.
  static const Color live = Color(0xFF46D369);
  static const Color warning = Color(0xFFF5B544);
  static const Color offline = Color(0xFF8A97A8);
  static const Color info = Color(0xFF72A9E8);

  /// Real errors (a failed save, a form problem). Never a bus status.
  static const Color error = Color(0xFFF28B82);

  // Light theme: cool white surfaces with the deep mint.
  static const Color lightBackground = Color(0xFFF2F5F7);
  static const Color lightBackgroundSecondary = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF8FAFB);
  static const Color lightElevated = Color(0xFFEAEFF3);
  static const Color lightHighlight = Color(0xFFD4F0E9);
  static const Color lightBorder = Color(0xFFDCE3E9);
  static const Color lightText = Color(0xFF16202A);
  static const Color lightTextSecondary = Color(0xFF4A5663);
  static const Color lightTextMuted = Color(0xFF6B7682);
  static const Color lightTextDisabled = Color(0xFFA9B2BC);

  // Status, darkened to stay readable on white.
  static const Color liveOnLight = Color(0xFF12893F);
  static const Color warningOnLight = Color(0xFF9E6500);
  static const Color offlineOnLight = Color(0xFF66727F);
  static const Color infoOnLight = Color(0xFF2C6CB3);
  static const Color errorOnLight = Color(0xFFC5372F);

  /// Colours handed out to bus routes that come without one, in order. Easy
  /// to tell apart, also for colour-blind riders, and never the accent or a
  /// status colour, so a route line is not read as "selected" or "live".
  static const List<Color> routePalette = [
    Color(0xFFF2994A), // orange
    Color(0xFF6FA8FF), // blue
    Color(0xFFB79CFF), // purple
    Color(0xFFFF8FA3), // pink
    Color(0xFFE6C24C), // gold
    Color(0xFF4FC3F7), // sky
  ];
}

/// Status colours that Material's [ColorScheme] has no slot for.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.offline,
    required this.info,
    required this.muted,
  });

  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.liveOnLight,
    warning: AppColors.warningOnLight,
    offline: AppColors.offlineOnLight,
    info: AppColors.infoOnLight,
    muted: AppColors.lightTextMuted,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: AppColors.live,
    warning: AppColors.warning,
    offline: AppColors.offline,
    info: AppColors.info,
    muted: AppColors.darkTextMuted,
  );

  /// Live data, healthy state.
  final Color success;

  /// Delayed data, needs attention.
  final Color warning;

  /// A bus that has gone quiet, or something that failed.
  final Color offline;

  /// Neutral information.
  final Color info;

  /// Not in use, not known, not running: nothing is wrong, nothing is live.
  final Color muted;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? offline,
    Color? info,
    Color? muted,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      offline: offline ?? this.offline,
      info: info ?? this.info,
      muted: muted ?? this.muted,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      info: Color.lerp(info, other.info, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}
