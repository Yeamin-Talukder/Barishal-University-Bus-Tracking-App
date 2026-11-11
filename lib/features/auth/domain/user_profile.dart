import 'package:flutter/foundation.dart';

/// What a signed-in person is allowed to do. The role is stored on the
/// server and can only be changed by an admin; the app merely displays and
/// obeys it.
///
/// Passengers need no account at all. [student] is the stored name of the
/// role every new account starts with: it grants nothing beyond what the
/// public already has, and is shown as "Passenger".
enum UserRole {
  student,
  driver,
  admin;

  /// Reads a stored role. Anything unrecognised is treated as a student,
  /// the least privileged role.
  static UserRole parse(Object? value) => UserRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => UserRole.student,
  );

  String get label => switch (this) {
    UserRole.student => 'Passenger',
    UserRole.driver => 'Driver',
    UserRole.admin => 'Admin',
  };
}

/// A signed-in account, as Firebase Authentication knows it.
@immutable
class AuthAccount {
  const AuthAccount({
    required this.uid,
    required this.email,
    this.displayName,
    this.isEmailVerified = false,
  });

  final String uid;
  final String email;
  final String? displayName;
  final bool isEmailVerified;
}

/// A person's profile (`users/{uid}` in Firestore).
@immutable
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.studentId,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final studentId = data['studentId'];
    return UserProfile(
      uid: uid,
      name: data['name'] is String ? data['name'] as String : '',
      email: data['email'] is String ? data['email'] as String : '',
      studentId: studentId is String && studentId.isNotEmpty ? studentId : null,
      role: UserRole.parse(data['role']),
      // A profile is only active when the server says so explicitly.
      isActive: data['isActive'] == true,
    );
  }

  final String uid;
  final String name;
  final String email;
  final String? studentId;
  final UserRole role;
  final bool isActive;
}
