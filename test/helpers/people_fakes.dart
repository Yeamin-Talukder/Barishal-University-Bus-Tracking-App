import 'dart:async';

import 'package:bu_bus_tracker/features/admin/data/people_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';

/// An in-memory stand-in for an admin's view of the `users` collection.
class FakePeopleRepository implements PeopleRepository {
  FakePeopleRepository([List<UserProfile> initial = const []]) {
    for (final person in initial) {
      people[person.uid] = person;
    }
  }

  final Map<String, UserProfile> people = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// When set, every change is refused with this, as the security rules
  /// would refuse someone who is not an admin.
  PeopleWriteFailure? failWith;

  List<UserProfile> get _sorted =>
      people.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Stream<List<UserProfile>> watchPeople() async* {
    yield _sorted;
    yield* _changes.stream.map((_) => _sorted);
  }

  @override
  Future<void> setAccess(
    String uid, {
    required UserRole role,
    required bool isActive,
  }) async {
    final failure = failWith;
    if (failure != null) throw failure;
    final person = people[uid]!;
    people[uid] = UserProfile(
      uid: uid,
      name: person.name,
      email: person.email,
      studentId: person.studentId,
      role: role,
      isActive: isActive,
    );
    _changes.add(null);
  }
}
