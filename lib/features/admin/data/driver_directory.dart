import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_bootstrap.dart';
import '../../auth/application/session.dart';
import '../../auth/domain/user_profile.dart';

/// The people who can be given a bus to drive: active accounts whose role
/// is driver.
///
/// Only an admin can read other people's profiles; the security rules
/// refuse this list to anyone else.
abstract interface class DriverDirectory {
  Stream<List<UserProfile>> watchDrivers();
}

class FirestoreDriverDirectory implements DriverDirectory {
  FirestoreDriverDirectory(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<UserProfile>> watchDrivers() => _firestore
      .collection('users')
      .where('role', isEqualTo: UserRole.driver.name)
      .snapshots()
      .map((snapshot) {
        final drivers = [
          for (final document in snapshot.docs)
            UserProfile.fromMap(document.id, document.data()),
        ].where((driver) => driver.isActive).toList();
        drivers.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return drivers;
      });
}

class UnavailableDriverDirectory implements DriverDirectory {
  const UnavailableDriverDirectory();

  @override
  Stream<List<UserProfile>> watchDrivers() => Stream.value(const []);
}

final driverDirectoryProvider = Provider<DriverDirectory>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableDriverDirectory();
  }
  return FirestoreDriverDirectory(FirebaseFirestore.instance);
});

/// The drivers, for an admin. Empty for everyone else, without asking the
/// database for something it would refuse.
final driversProvider = StreamProvider<List<UserProfile>>((ref) {
  if (!ref.watch(isAdminProvider)) return Stream.value(const []);
  return ref.watch(driverDirectoryProvider).watchDrivers();
});
