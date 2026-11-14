import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/firebase_bootstrap.dart';
import 'core/services/preferences_service.dart';
import 'features/auth/application/session.dart';
import 'features/home_widget/presentation/widget_config_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final firebaseStatus = await initializeFirebase();
  if (firebaseStatus.isReady) {
    await connectToFirebaseEmulatorsIfRequested();
  } else {
    debugPrint('Firebase unavailable: ${firebaseStatus.detail}');
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        firebaseStatusProvider.overrideWithValue(firebaseStatus),
      ],
      child: const BuBusTrackerApp(),
    ),
  );
}

/// The home-screen widget's settings screen, started by
/// `WidgetConfigActivity.kt` on its own: no Firebase, no map, so it opens
/// quickly from the home screen.
@pragma('vm:entry-point')
Future<void> widgetConfigMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const WidgetConfigApp(),
    ),
  );
}
