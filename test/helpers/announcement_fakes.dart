import 'dart:async';

import 'package:bu_bus_tracker/data/repositories/announcement_repository.dart';

/// An in-memory stand-in for the `announcements` collection.
class FakeAnnouncementRepository implements AnnouncementRepository {
  FakeAnnouncementRepository([List<Announcement> initial = const []]) {
    for (final announcement in initial) {
      announcements[announcement.id] = announcement;
    }
  }

  final Map<String, Announcement> announcements = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  /// The time given to a newly posted announcement.
  DateTime postedAt = DateTime(2026, 11, 11, 9);

  /// When set, every change is refused with this.
  AnnouncementWriteFailure? failWith;

  List<Announcement> get _sorted =>
      sortAnnouncements(announcements.values.toList());

  @override
  Stream<List<Announcement>> watchAnnouncements() async* {
    yield _sorted;
    yield* _changes.stream.map((_) => _sorted);
  }

  @override
  Future<void> saveAnnouncement(Announcement announcement) async {
    final failure = failWith;
    if (failure != null) throw failure;
    final id = announcement.id.isEmpty ? 'note-${_nextId++}' : announcement.id;
    announcements[id] = Announcement(
      id: id,
      title: announcement.title,
      message: announcement.message,
      isActive: announcement.isActive,
      createdAt: announcement.createdAt ?? postedAt,
    );
    _changes.add(null);
  }

  @override
  Future<void> deleteAnnouncement(String id) async {
    final failure = failWith;
    if (failure != null) throw failure;
    announcements.remove(id);
    _changes.add(null);
  }
}
