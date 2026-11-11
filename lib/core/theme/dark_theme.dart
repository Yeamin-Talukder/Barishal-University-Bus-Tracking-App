import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Colour scheme of the dark theme, the app's default.
///
/// Every role is set by hand from [AppColors]. Nothing is generated from a
/// seed and nothing follows the phone's wallpaper, so the app looks the
/// same on every Android phone and on iOS.
///
/// Depth comes from the surface roles, darkest at the back:
/// page (`surfaceContainerLowest`) → sheets and bars (`surface`) → cards
/// (`surfaceContainerLow`, `surfaceContainer`) → raised things
/// (`surfaceContainerHigh`, `surfaceContainerHighest`).
const ColorScheme darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: AppColors.mint,
  onPrimary: AppColors.darkBackground,
  primaryContainer: AppColors.darkHighlight,
  onPrimaryContainer: AppColors.darkText,
  secondary: AppColors.secondary,
  onSecondary: AppColors.darkBackground,
  // The tonal fill of a selected chip, tab or navigation item.
  secondaryContainer: AppColors.darkHighlight,
  onSecondaryContainer: AppColors.darkText,
  tertiary: AppColors.tertiary,
  onTertiary: AppColors.darkBackground,
  tertiaryContainer: Color(0xFF3A2F1E),
  onTertiaryContainer: AppColors.darkText,
  error: AppColors.error,
  onError: AppColors.darkBackground,
  errorContainer: Color(0xFF3A1F22),
  onErrorContainer: AppColors.error,
  surface: AppColors.darkBackgroundSecondary,
  onSurface: AppColors.darkText,
  onSurfaceVariant: AppColors.darkTextSecondary,
  surfaceDim: AppColors.darkBackground,
  surfaceBright: AppColors.darkElevated,
  surfaceContainerLowest: AppColors.darkBackground,
  surfaceContainerLow: AppColors.darkCard,
  surfaceContainer: AppColors.darkCard,
  surfaceContainerHigh: AppColors.darkElevated,
  surfaceContainerHighest: AppColors.darkElevated,
  outline: AppColors.darkTextDisabled,
  outlineVariant: AppColors.darkBorder,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: AppColors.darkText,
  onInverseSurface: AppColors.darkBackground,
  inversePrimary: AppColors.mintDeep,
  // Layers are told apart by their own colours, not by a tint.
  surfaceTint: Color(0x00000000),
);

const Color darkScaffoldBackground = AppColors.darkBackground;
const AppSemanticColors darkSemanticColors = AppSemanticColors.dark;
