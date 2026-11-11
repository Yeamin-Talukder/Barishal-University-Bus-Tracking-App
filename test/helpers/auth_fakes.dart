import 'dart:async';

import 'package:bu_bus_tracker/features/auth/data/auth_repository.dart';
import 'package:bu_bus_tracker/features/auth/data/user_profile_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';

/// An in-memory stand-in for Firebase Authentication with Google sign-in.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthAccount? signedInAs}) : _current = signedInAs;

  final StreamController<AuthAccount?> _changes =
      StreamController<AuthAccount?>.broadcast();

  AuthAccount? _current;
  int _nextId = 1;

  /// The account the Google window "returns" when someone signs in.
  AuthAccount? googleAccount;

  /// When set, the next sign-in fails with this.
  AuthFailure? failWith;

  /// When true, the person closes the Google window without choosing.
  bool cancel = false;

  int signInAttempts = 0;

  AuthAccount? get current => _current;

  /// Makes an account, as Google would describe it.
  AuthAccount addAccount({required String email, String? name}) =>
      AuthAccount(uid: 'uid-${_nextId++}', email: email, displayName: name);

  /// Puts the app in the state of [account] being signed in already.
  void signInAs(AuthAccount account) => _set(account);

  void _set(AuthAccount? account) {
    _current = account;
    _changes.add(account);
  }

  @override
  Stream<AuthAccount?> watchAccount() async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<AuthAccount> signInWithGoogle() async {
    signInAttempts++;
    if (cancel) throw const SignInCancelled();
    final failure = failWith;
    if (failure != null) throw failure;
    final account = googleAccount;
    if (account == null) {
      throw StateError('Set googleAccount before signing in.');
    }
    _set(account);
    return account;
  }

  @override
  Future<void> signOut() async => _set(null);
}

/// An in-memory stand-in for the `users` collection.
class FakeUserProfileRepository implements UserProfileRepository {
  final Map<String, UserProfile> profiles = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// When true, saving a profile fails, as it would with no connection.
  bool failWrites = false;

  /// When true, listeners that are already running are not told about
  /// changes, as happens when a listener started before the account was
  /// ready on the server. A new listener still reads the current value.
  bool dropLiveUpdates = false;
  int createCalls = 0;

  void put(UserProfile profile) {
    profiles[profile.uid] = profile;
    if (!dropLiveUpdates) _changes.add(null);
  }

  @override
  Stream<UserProfile?> watchProfile(String uid) async* {
    yield profiles[uid];
    yield* _changes.stream.map((_) => profiles[uid]);
  }

  @override
  Future<void> createProfile({
    required AuthAccount account,
    required String name,
    String? studentId,
  }) async {
    createCalls++;
    if (failWrites) throw Exception('offline');
    final trimmedId = studentId?.trim();
    put(
      UserProfile(
        uid: account.uid,
        name: name.trim(),
        email: account.email,
        studentId: trimmedId == null || trimmedId.isEmpty ? null : trimmedId,
        // Mirrors the security rules: a client can only create a student.
        role: UserRole.student,
        isActive: true,
      ),
    );
  }

  @override
  Future<void> updateProfile({
    required String uid,
    required String name,
    String? studentId,
  }) async {
    if (failWrites) throw Exception('offline');
    final existing = profiles[uid]!;
    put(
      UserProfile(
        uid: uid,
        name: name.trim(),
        email: existing.email,
        studentId: studentId,
        role: existing.role,
        isActive: existing.isActive,
      ),
    );
  }
}
