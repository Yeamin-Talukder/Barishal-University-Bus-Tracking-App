import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/firebase_bootstrap.dart';
import 'core/services/preferences_service.dart';
import 'features/auth/application/session.dart';

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
