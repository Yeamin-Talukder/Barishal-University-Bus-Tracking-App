import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_environment.dart';
import '../../../core/services/firebase_bootstrap.dart';
import '../data/auth_repository.dart';
import '../data/user_profile_repository.dart';
import '../domain/user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableAuthRepository();
  }
  return FirebaseAuthRepository(FirebaseAuth.instance);
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableUserProfileRepository();
  }
  return FirestoreUserProfileRepository(FirebaseFirestore.instance);
});

/// The signed-in account, or null.
final accountProvider = StreamProvider<AuthAccount?>(
  (ref) => ref.watch(authRepositoryProvider).watchAccount(),
);

/// The signed-in person's profile, or null when signed out or not yet
/// created.
///
/// It follows the account's uid only, so it is not restarted when other
/// account details (such as the display name) change.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(
    accountProvider.select((account) => account.value?.uid),
  );
  if (uid == null) return Stream.value(null);
  return ref.watch(userProfileRepositoryProvider).watchProfile(uid);
});

/// Whether the signed-in person is an active admin.
///
/// This only decides what the app shows. The database's security rules make
/// the same check on every change, and they are what is trusted.
final isAdminProvider = Provider<bool>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  return profile != null && profile.isActive && profile.role == UserRole.admin;
});

/// Sign-in and sign-out as the screens use them.
final sessionControllerProvider = Provider<SessionController>(
  (ref) => SessionController(
    ref.watch(authRepositoryProvider),
    ref.watch(userProfileRepositoryProvider),
  ),
);

class SessionController {
  SessionController(this._auth, this._profiles);

  final AuthRepository _auth;
  final UserProfileRepository _profiles;

  static const AuthFailure _profileFailure = AuthFailure(
    'You are signed in, but your profile could not be saved. Check your '
    'connection; it will be tried again the next time you sign in.',
    code: 'profile-not-saved',
  );

  /// Signs in with a Google account. The first time, this also creates
  /// the person's profile, with no special access.
  ///
  /// Throws [SignInCancelled] if they back out, [AuthFailure] otherwise.
  Future<void> signInWithGoogle() async {
    final account = await _auth.signInWithGoogle();
    await _ensureProfile(account, name: account.displayName);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> _ensureProfile(AuthAccount account, {String? name}) async {
    try {
      final existing = await _profiles.watchProfile(account.uid).first;
      if (existing != null) return;
      final profileName = name == null || name.trim().isEmpty
          ? account.email.split('@').first
          : name;
      await _profiles.createProfile(
        account: account,
        // The security rules accept at most 80 characters.
        name: profileName.trim().length > 80
            ? profileName.trim().substring(0, 80)
            : profileName,
      );
    } catch (error) {
      debugPrint('Could not save the profile: $error');
      throw _profileFailure;
    }
  }
}

/// Points the Firebase SDKs at the local emulators, for development and
/// end-to-end checks that must not touch the real project.
///
/// Enabled with `--dart-define=FIREBASE_EMULATORS=true`.
Future<void> connectToFirebaseEmulatorsIfRequested() async {
  if (!AppEnvironment.useFirebaseEmulators) return;
  const host = AppEnvironment.firebaseEmulatorHost;
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseDatabase.instance.useDatabaseEmulator(host, 9000);
  debugPrint('Using the Firebase emulators at $host.');
}
