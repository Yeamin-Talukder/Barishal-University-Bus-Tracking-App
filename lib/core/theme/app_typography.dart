import 'package:flutter/material.dart';

/// Type scale for the app: Material 3's, with firmer headings.
///
/// It uses each platform's system typeface (Roboto on Android, San Francisco
/// on iOS) so that text, including Bangla, renders without downloading
/// fonts. Google Sans is not used: it is not licensed for other apps.
abstract final class AppTypography {
  static TextTheme textTheme(ColorScheme scheme) {
    final typography = Typography.material2021(colorScheme: scheme);
    final colors = scheme.brightness == Brightness.dark
        ? typography.white
        : typography.black;
    // `black` and `white` carry only colour and typeface. Sizes and weights
    // come from the geometry theme, and component themes built from this
    // text theme need them resolved up front.
    final theme = typography.englishLike.merge(colors);

    return theme
        .copyWith(
          headlineMedium: theme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          headlineSmall: theme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          titleLarge: theme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: theme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          bodyLarge: theme.bodyLarge?.copyWith(height: 1.45),
          bodyMedium: theme.bodyMedium?.copyWith(height: 1.45),
          bodySmall: theme.bodySmall?.copyWith(height: 1.4),
          labelLarge: theme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          labelMedium: theme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}
