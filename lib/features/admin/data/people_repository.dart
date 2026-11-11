import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_bootstrap.dart';
import '../../../data/repositories/live_tracking_repository.dart';
import '../../auth/application/session.dart';
import '../../auth/domain/user_profile.dart';

/// A change to someone's access that could not be made, with a message that
/// can be shown to the admin as it is.
class PeopleWriteFailure implements Exception {
  const PeopleWriteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everyone who has signed in, and what they are allowed to do.
///
/// Only an admin can read other people's profiles or change a role: the
/// database's security rules refuse everyone else, whatever the app shows.
abstract interface class PeopleRepository {
  /// Every profile, sorted by name, and again whenever one changes.
  Stream<List<UserProfile>> watchPeople();

  /// Changes what a person may do, and whether their account is active.
  /// Throws [PeopleWriteFailure].
  Future<void> setAccess(
    String uid, {
    required UserRole role,
    required bool isActive,
  });
}

class FirestorePeopleRepository implements PeopleRepository {
  FirestorePeopleRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const Duration _serverWait = Duration(seconds: 12);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Stream<List<UserProfile>> watchPeople() => _users.snapshots().map((snapshot) {
    final people = [
      for (final document in snapshot.docs)
        UserProfile.fromMap(document.id, document.data()),
    ];
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return people;
  });

  @override
  Future<void> setAccess(
    String uid, {
    required UserRole role,
    required bool isActive,
  }) async {
    try {
      await _users
          .doc(uid)
          .update({'role': role.name, 'isActive': isActive})
          .timeout(_serverWait);
    } on TimeoutException {
      throw const PeopleWriteFailure(
        'No answer from the server. The change is kept on this device and '
        'will be sent when the connection is back.',
      );
    } on FirebaseException catch (error) {
      debugPrint('Access change refused: ${error.code}');
      throw PeopleWriteFailure(switch (error.code) {
        'permission-denied' =>
          'Only a transport office admin can change what people may do.',
        'not-found' => 'That account no longer exists.',
        'unavailable' => 'No connection. Check the internet and try again.',
        _ => 'The change could not be saved. Try again.',
      });
    }
  }
}

/// A people list that also tells the tracking database who is an admin,
/// because that database cannot see the Firestore profiles.
class MirroringPeopleRepository implements PeopleRepository {
  const MirroringPeopleRepository(this._inner, this._access);

  final PeopleRepository _inner;
  final TrackingAccess _access;

  @override
  Stream<List<UserProfile>> watchPeople() => _inner.watchPeople();

  @override
  Future<void> setAccess(
    String uid, {
    required UserRole role,
    required bool isActive,
  }) async {
    await _inner.setAccess(uid, role: role, isActive: isActive);
    try {
      await _access.setAdmin(uid, isAdmin: role == UserRole.admin && isActive);
    } on TrackingFailure catch (failure) {
      throw PeopleWriteFailure(failure.message);
    }
  }
}

/// Used when the app is not connected to the tracking service.
class UnavailablePeopleRepository implements PeopleRepository {
  const UnavailablePeopleRepository();

  @override
  Stream<List<UserProfile>> watchPeople() => Stream.value(const []);

  @override
  Future<void> setAccess(
    String uid, {
    required UserRole role,
    required bool isActive,
  }) => throw const PeopleWriteFailure(
    'This build is not connected to the tracking service.',
  );
}

final peopleRepositoryProvider = Provider<PeopleRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailablePeopleRepository();
  }
  return MirroringPeopleRepository(
    FirestorePeopleRepository(FirebaseFirestore.instance),
    ref.watch(trackingAccessProvider),
  );
});

/// Everyone who has signed in, for an admin. Empty for everyone else,
/// without asking the database for something it would refuse.
final peopleProvider = StreamProvider<List<UserProfile>>((ref) {
  if (!ref.watch(isAdminProvider)) return Stream.value(const []);
  return ref.watch(peopleRepositoryProvider).watchPeople();
});
