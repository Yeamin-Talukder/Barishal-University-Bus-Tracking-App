import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/user_profile.dart';

/// A sign-in problem, with a message that can be shown to the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;

  /// The underlying error code, for logs and tests.
  final String? code;

  /// Turns a Firebase error code into plain words. Technical detail never
  /// reaches the screen.
  factory AuthFailure.fromCode(String code) {
    final message = switch (code) {
      'user-disabled' => 'This account has been disabled.',
      'account-exists-with-different-credential' =>
        'This email is already used with a different way of signing in.',
      'too-many-requests' =>
        'Too many attempts. Wait a few minutes and try again.',
      'network-request-failed' =>
        'No connection. Check your internet and try again.',
      'operation-not-allowed' =>
        'Google sign-in is not switched on for this app.',
      'popup-blocked' =>
        'The browser blocked the Google sign-in window. Allow pop-ups and '
            'try again.',
      'not-configured' =>
        'Google sign-in is not set up correctly for this app.',
      _ => 'Something went wrong. Try again.',
    };
    return AuthFailure(message, code: code);
  }

  @override
  String toString() => 'AuthFailure($code): $message';
}

/// The person closed the Google sign-in window without choosing an account.
/// Not an error: nothing needs to be shown.
class SignInCancelled implements Exception {
  const SignInCancelled();
}

/// Signs people in and out. Google is the only way to sign in.
abstract interface class AuthRepository {
  /// Emits the signed-in account, or null when nobody is signed in.
  Stream<AuthAccount?> watchAccount();

  /// Asks the person to choose a Google account and signs them in with it.
  /// Throws [SignInCancelled] if they back out, [AuthFailure] otherwise.
  Future<AuthAccount> signInWithGoogle();

  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;
  Future<void>? _googleReady;

  static AuthAccount _account(User user) => AuthAccount(
    uid: user.uid,
    email: user.email ?? '',
    displayName: user.displayName,
    isEmailVerified: user.emailVerified,
  );

  @override
  Stream<AuthAccount?> watchAccount() =>
      _auth.userChanges().map((user) => user == null ? null : _account(user));

  @override
  Future<AuthAccount> signInWithGoogle() async {
    try {
      final credential = kIsWeb
          // The browser has its own Google sign-in window.
          ? await _auth.signInWithPopup(GoogleAuthProvider())
          : await _auth.signInWithCredential(await _googleCredential());
      return _account(credential.user!);
    } on GoogleSignInException catch (error) {
      debugPrint('Google sign-in failed: ${error.code}');
      throw switch (error.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted => const SignInCancelled(),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          AuthFailure.fromCode('not-configured'),
        _ => AuthFailure.fromCode('unknown'),
      };
    } on FirebaseAuthException catch (error) {
      debugPrint('Sign-in refused: ${error.code}');
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request' ||
          error.code == 'web-context-cancelled') {
        throw const SignInCancelled();
      }
      throw AuthFailure.fromCode(error.code);
    }
  }

  /// Shows the device's Google account chooser and returns what Firebase
  /// needs to sign that account in.
  Future<OAuthCredential> _googleCredential() async {
    final google = GoogleSignIn.instance;
    await (_googleReady ??= google.initialize());
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw AuthFailure.fromCode('not-configured');
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (kIsWeb) return;
    // Forget the Google account too, so the next sign-in asks which one.
    try {
      final google = GoogleSignIn.instance;
      await (_googleReady ??= google.initialize());
      await google.signOut();
    } catch (error) {
      debugPrint('Could not sign out of Google: $error');
    }
  }
}

/// Used when the app is running without Firebase: nobody is signed in and
/// nobody can sign in.
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  @override
  Stream<AuthAccount?> watchAccount() => Stream.value(null);

  @override
  Future<AuthAccount> signInWithGoogle() => throw const AuthFailure(
    'Sign-in is not available in this build.',
    code: 'unavailable',
  );

  @override
  Future<void> signOut() async {}
}
