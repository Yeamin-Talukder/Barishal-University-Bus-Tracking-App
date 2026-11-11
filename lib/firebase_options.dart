// Placeholder. The project's real Firebase configuration is not published.
//
// Run `flutterfire configure` to replace this file with your own Firebase
// project's settings (see README.md and FIREBASE_SETUP.md). Until then the
// app starts without a backend: the offline map and the built-in schedule
// work, and the Profile tab says the tracking service is not set up.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured for this build. '
      'Run `flutterfire configure` to connect a Firebase project.',
    );
  }
}
