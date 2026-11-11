import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Colour scheme of the light theme: cool white surfaces and the deep mint.
///
/// The deep mint is the primary here, because it is the one that reads well
/// as text and icons on white. Like the dark scheme, every role
/// is set by hand and nothing follows the phone's wallpaper.
const ColorScheme lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: AppColors.mintDeep,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: AppColors.lightHighlight,
  onPrimaryContainer: AppColors.lightText,
  secondary: Color(0xFF4E6B66),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: AppColors.lightHighlight,
  onSecondaryContainer: AppColors.lightText,
  tertiary: Color(0xFF8F5E0B),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFF8E6C6),
  onTertiaryContainer: AppColors.lightText,
  error: AppColors.errorOnLight,
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFBE3E1),
  onErrorContainer: AppColors.errorOnLight,
  surface: AppColors.lightBackgroundSecondary,
  onSurface: AppColors.lightText,
  onSurfaceVariant: AppColors.lightTextSecondary,
  surfaceDim: AppColors.lightElevated,
  surfaceBright: AppColors.lightBackgroundSecondary,
  surfaceContainerLowest: AppColors.lightBackground,
  surfaceContainerLow: AppColors.lightCard,
  surfaceContainer: AppColors.lightCard,
  surfaceContainerHigh: AppColors.lightElevated,
  surfaceContainerHighest: AppColors.lightElevated,
  outline: AppColors.lightTextDisabled,
  outlineVariant: AppColors.lightBorder,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: AppColors.lightText,
  onInverseSurface: AppColors.lightBackground,
  inversePrimary: AppColors.mintSoft,
  surfaceTint: Color(0x00000000),
);

const Color lightScaffoldBackground = AppColors.lightBackground;
const AppSemanticColors lightSemanticColors = AppSemanticColors.light;
