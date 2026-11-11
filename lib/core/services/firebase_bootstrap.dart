import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';

/// Whether the Firebase backend can be used in this run of the app.
enum FirebaseAvailability {
  /// Firebase initialised; backend features can run.
  ready,

  /// The project has not been linked to a Firebase project yet
  /// (`flutterfire configure` has not been run).
  notConfigured,

  /// Firebase is configured but failed to start.
  failed,
}

@immutable
class FirebaseStatus {
  const FirebaseStatus(this.availability, {this.detail});

  final FirebaseAvailability availability;

  /// Technical detail for logs and diagnostics, never shown raw to users.
  final String? detail;

  bool get isReady => availability == FirebaseAvailability.ready;
}

/// Starts Firebase without letting a missing or broken configuration stop the
/// app: the offline map and locally stored data must work regardless.
///
/// [initialize] exists so tests can stand in for the real SDK call.
Future<FirebaseStatus> initializeFirebase({
  Future<void> Function()? initialize,
}) async {
  try {
    await (initialize ?? _initializeDefaultApp)();
    return const FirebaseStatus(FirebaseAvailability.ready);
  } on UnsupportedError catch (error) {
    // Thrown by the placeholder `firebase_options.dart`.
    return FirebaseStatus(
      FirebaseAvailability.notConfigured,
      detail: error.message,
    );
  } catch (error) {
    return FirebaseStatus(FirebaseAvailability.failed, detail: '$error');
  }
}

Future<void> _initializeDefaultApp() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Result of the startup Firebase initialisation. `main` overrides this with
/// the real result.
final firebaseStatusProvider = Provider<FirebaseStatus>((ref) {
  return const FirebaseStatus(FirebaseAvailability.notConfigured);
});
