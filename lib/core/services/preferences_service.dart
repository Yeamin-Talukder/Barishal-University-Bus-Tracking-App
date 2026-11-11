import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device's key-value store, loaded once before the app starts.
///
/// `main` overrides this with the loaded instance; tests override it with a
/// mock-backed one.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw StateError(
    'sharedPreferencesProvider must be overridden with a loaded instance.',
  );
});
