/// Build-time switches, set with `--dart-define`.
abstract final class AppEnvironment {
  /// Loads the clearly labelled sample route and stops in `assets/demo/`
  /// instead of the verified data in `assets/data/`.
  ///
  /// Off by default. Turn on for development with
  /// `--dart-define=DEMO_DATA=true`. The app shows a "Demo data" label
  /// whenever this is on.
  static const bool useDemoData = bool.fromEnvironment('DEMO_DATA');

  /// Loads the official stops with positions that still await confirmation
  /// (`assets/review/`), so that someone who knows the city can check them
  /// on the map. Takes precedence over [useDemoData].
  ///
  /// Off by default. Turn on with `--dart-define=REVIEW_STOPS=true`. The app
  /// shows an "Unconfirmed stop positions" label whenever this is on.
  static const bool useUnconfirmedStops = bool.fromEnvironment('REVIEW_STOPS');

  /// Uses the local Firebase emulators instead of the real project, so
  /// development and tests never create accounts or data in production.
  ///
  /// Turn on with `--dart-define=FIREBASE_EMULATORS=true`.
  static const bool useFirebaseEmulators = bool.fromEnvironment(
    'FIREBASE_EMULATORS',
  );

  /// Where the emulators run. Use `10.0.2.2` on an Android emulator.
  static const String firebaseEmulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: 'localhost',
  );
}
