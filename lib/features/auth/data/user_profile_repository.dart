import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/user_profile.dart';

/// Reads and writes the signed-in person's own profile.
///
/// The security rules decide what is allowed: a person can create their
/// profile once, as an active student, and afterwards change only their name
/// and student id. Roles are changed by an admin.
abstract interface class UserProfileRepository {
  /// Emits the profile, or null while it does not exist.
  Stream<UserProfile?> watchProfile(String uid);

  /// Creates the profile for a newly registered account.
  Future<void> createProfile({
    required AuthAccount account,
    required String name,
    String? studentId,
  });

  Future<void> updateProfile({
    required String uid,
    required String name,
    String? studentId,
  });
}

class FirestoreUserProfileRepository implements UserProfileRepository {
  FirestoreUserProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _document(String uid) =>
      _firestore.collection('users').doc(uid);

  @override
  Stream<UserProfile?> watchProfile(String uid) {
    return _document(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : UserProfile.fromMap(uid, data);
    });
  }

  @override
  Future<void> createProfile({
    required AuthAccount account,
    required String name,
    String? studentId,
  }) {
    final trimmedId = studentId?.trim();
    return _document(account.uid).set({
      'name': name.trim(),
      'email': account.email,
      if (trimmedId != null && trimmedId.isNotEmpty) 'studentId': trimmedId,
      // The rules reject any other role or state from a client.
      'role': UserRole.student.name,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateProfile({
    required String uid,
    required String name,
    String? studentId,
  }) {
    final trimmedId = studentId?.trim();
    return _document(uid).update({
      'name': name.trim(),
      'studentId': trimmedId == null || trimmedId.isEmpty
          ? FieldValue.delete()
          : trimmedId,
    });
  }
}

/// Used when the app is running without Firebase.
class UnavailableUserProfileRepository implements UserProfileRepository {
  const UnavailableUserProfileRepository();

  @override
  Stream<UserProfile?> watchProfile(String uid) => Stream.value(null);

  @override
  Future<void> createProfile({
    required AuthAccount account,
    required String name,
    String? studentId,
  }) async {}

  @override
  Future<void> updateProfile({
    required String uid,
    required String name,
    String? studentId,
  }) async {}
}
