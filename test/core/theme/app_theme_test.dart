import 'package:bu_bus_tracker/core/theme/app_colors.dart';
import 'package:bu_bus_tracker/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrast ratio between two colours, as WCAG defines it (1 to 21).
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('The Teal Mint theme', () {
    final scheme = AppTheme.dark.colorScheme;
    final semantic = AppTheme.dark.extension<AppSemanticColors>()!;

    test('uses the palette as specified', () {
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, const Color(0xFF5FD4BC));
      expect(scheme.primaryContainer, const Color(0xFF173A35));
      expect(scheme.secondary, const Color(0xFF8FB8B0));
      expect(scheme.tertiary, const Color(0xFFE6A23C));

      expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF0F1318));
      expect(scheme.surface, const Color(0xFF141920));
      expect(scheme.surfaceContainerLow, const Color(0xFF1A2028));
      expect(scheme.surfaceContainerHigh, const Color(0xFF232A34));
      expect(scheme.secondaryContainer, const Color(0xFF173A35));
      expect(scheme.outlineVariant, const Color(0xFF2E3640));

      expect(scheme.onSurface, const Color(0xFFEEF2F6));
      expect(scheme.onSurfaceVariant, const Color(0xFFAEB8C2));

      expect(semantic.success, const Color(0xFF46D369));
      expect(semantic.warning, const Color(0xFFF5B544));
      expect(semantic.offline, const Color(0xFF8A97A8));
      expect(semantic.info, const Color(0xFF72A9E8));
    });

    test('layers get lighter as they come forward', () {
      final layers = [
        AppTheme.dark.scaffoldBackgroundColor,
        scheme.surface,
        scheme.surfaceContainerLow,
        scheme.surfaceContainerHigh,
      ];
      for (var i = 1; i < layers.length; i++) {
        expect(
          layers[i].computeLuminance(),
          greaterThan(layers[i - 1].computeLuminance()),
        );
      }
    });

    test('nothing follows the wallpaper or a surface tint', () {
      expect(scheme.surfaceTint.a, 0);
      expect(AppTheme.dark.useMaterial3, isTrue);
    });
  });

  group('Both themes', () {
    for (final (name, theme) in [
      ('dark', AppTheme.dark),
      ('light', AppTheme.light),
    ]) {
      final scheme = theme.colorScheme;
      final semantic = theme.extension<AppSemanticColors>()!;

      test('$name: text can be read on every surface', () {
        for (final surface in [
          theme.scaffoldBackgroundColor,
          scheme.surface,
          scheme.surfaceContainerLow,
          scheme.surfaceContainerHigh,
        ]) {
          expect(_contrast(scheme.onSurface, surface), greaterThan(7));
          expect(_contrast(scheme.onSurfaceVariant, surface), greaterThan(4.5));
          // The brand colour used for text and icons.
          expect(_contrast(theme.accent, surface), greaterThan(4.5));
        }
      });

      test('$name: labels can be read on filled buttons and chips', () {
        expect(_contrast(scheme.onPrimary, scheme.primary), greaterThan(3.9));
        expect(
          _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
          greaterThan(7),
        );
      });

      test('$name: status colours stand out from the cards they sit on', () {
        for (final status in [
          semantic.success,
          semantic.warning,
          semantic.offline,
          semantic.info,
        ]) {
          expect(_contrast(status, scheme.surfaceContainerLow), greaterThan(3));
        }
      });

      test("$name: controls share the app's rounded shapes", () {
        expect(
          theme.filledButtonTheme.style!.shape!.resolve({}),
          isA<StadiumBorder>(),
        );
        expect(theme.chipTheme.shape, isA<StadiumBorder>());
        expect(theme.bottomSheetTheme.shape, isA<RoundedRectangleBorder>());
        expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
      });
    }

    test('the light theme is cool white with the deep mint', () {
      final scheme = AppTheme.light.colorScheme;
      expect(scheme.brightness, Brightness.light);
      expect(scheme.primary, AppColors.mintDeep);
      expect(AppTheme.light.scaffoldBackgroundColor, AppColors.lightBackground);
    });
  });
}
