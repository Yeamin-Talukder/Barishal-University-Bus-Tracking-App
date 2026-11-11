import 'package:bu_bus_tracker/core/services/preferences_service.dart';
import 'package:bu_bus_tracker/core/theme/theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _containerWith(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('is dark when nothing is stored', () async {
    final container = await _containerWith({});

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('follows the system theme once that is chosen', () async {
    final container = await _containerWith({
      ThemeModeController.storageKey: 'system',
    });

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('restores the stored theme', () async {
    final container = await _containerWith({
      ThemeModeController.storageKey: 'dark',
    });

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('falls back to dark for an unknown stored value', () async {
    final container = await _containerWith({
      ThemeModeController.storageKey: 'sepia',
    });

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('changing the theme updates state and persists it', () async {
    final container = await _containerWith({});

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getString(ThemeModeController.storageKey),
      'light',
    );
  });
}
