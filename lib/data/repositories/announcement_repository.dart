import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_bootstrap.dart';

/// A short notice from the transport office to everyone using the app.
@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.isActive,
    this.createdAt,
  });

  /// Empty for one that has not been saved yet.
  final String id;
  final String title;
  final String message;

  /// Whether passengers see it. A hidden one is kept for the admin.
  final bool isActive;

  /// When it was first posted.
  final DateTime? createdAt;
}

/// A change to the announcements that could not be made, with a message
/// that can be shown to the admin as it is.
class AnnouncementWriteFailure implements Exception {
  const AnnouncementWriteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The announcements kept in the database. Anyone may read them; only an
/// admin may change them, and the security rules enforce that.
abstract interface class AnnouncementRepository {
  /// Every announcement, newest first, and again whenever one changes.
  Stream<List<Announcement>> watchAnnouncements();

  /// Posts [announcement] when its id is empty, otherwise replaces the one
  /// with that id, keeping the time it was first posted.
  Future<void> saveAnnouncement(Announcement announcement);

  Future<void> deleteAnnouncement(String id);
}

/// Reads an announcement document, or null if it is not a usable one.
Announcement? announcementFromMap(String id, Map<String, dynamic> data) {
  final title = data['title'];
  final message = data['message'];
  if (title is! String || title.trim().isEmpty) return null;
  if (message is! String || message.trim().isEmpty) return null;
  final createdAt = data['createdAt'];
  return Announcement(
    id: id,
    title: title.trim(),
    message: message.trim(),
    // Shown only when the database says so explicitly.
    isActive: data['isActive'] == true,
    createdAt: createdAt is Timestamp
        ? createdAt.toDate()
        : createdAt is DateTime
        ? createdAt
        : null,
  );
}

class FirestoreAnnouncementRepository implements AnnouncementRepository {
  FirestoreAnnouncementRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const Duration _serverWait = Duration(seconds: 12);

  CollectionReference<Map<String, dynamic>> get _announcements =>
      _firestore.collection('announcements');

  @override
  Stream<List<Announcement>> watchAnnouncements() =>
      _announcements.snapshots().map((snapshot) {
        final all = <Announcement>[
          for (final document in snapshot.docs)
            ?announcementFromMap(document.id, document.data()),
        ];
        return sortAnnouncements(all);
      });

  @override
  Future<void> saveAnnouncement(Announcement announcement) {
    final document = announcement.id.isEmpty
        ? _announcements.doc()
        : _announcements.doc(announcement.id);
    final createdAt = announcement.createdAt;
    return _send(
      document.set({
        'title': announcement.title.trim(),
        'message': announcement.message.trim(),
        'isActive': announcement.isActive,
        'createdAt': createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(createdAt),
      }),
    );
  }

  @override
  Future<void> deleteAnnouncement(String id) =>
      _send(_announcements.doc(id).delete());

  Future<void> _send(Future<void> write) async {
    try {
      await write.timeout(_serverWait);
    } on TimeoutException {
      throw const AnnouncementWriteFailure(
        'No answer from the server. The change is kept on this device and '
        'will be sent when the connection is back.',
      );
    } on FirebaseException catch (error) {
      debugPrint('Announcement change refused: ${error.code}');
      throw AnnouncementWriteFailure(switch (error.code) {
        'permission-denied' =>
          'Only a transport office admin can change announcements.',
        'unavailable' => 'No connection. Check the internet and try again.',
        _ => 'The change could not be saved. Try again.',
      });
    }
  }
}

/// Newest first; ones with no time yet (just posted) at the top.
List<Announcement> sortAnnouncements(List<Announcement> all) =>
    [...all]..sort((a, b) {
      final first = a.createdAt;
      final second = b.createdAt;
      if (first == null || second == null) {
        return first == second ? 0 : (first == null ? -1 : 1);
      }
      return second.compareTo(first);
    });

/// Used when the app is not connected to the tracking service.
class UnavailableAnnouncementRepository implements AnnouncementRepository {
  const UnavailableAnnouncementRepository();

  static const AnnouncementWriteFailure _failure = AnnouncementWriteFailure(
    'This build is not connected to the tracking service.',
  );

  @override
  Stream<List<Announcement>> watchAnnouncements() => Stream.value(const []);

  @override
  Future<void> saveAnnouncement(Announcement announcement) => throw _failure;

  @override
  Future<void> deleteAnnouncement(String id) => throw _failure;
}

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  if (!ref.watch(firebaseStatusProvider).isReady) {
    return const UnavailableAnnouncementRepository();
  }
  return FirestoreAnnouncementRepository(FirebaseFirestore.instance);
});

/// Every announcement, shown or hidden, newest first.
final announcementsProvider = StreamProvider<List<Announcement>>(
  (ref) => ref.watch(announcementRepositoryProvider).watchAnnouncements(),
);

/// The announcements passengers see.
final activeAnnouncementsProvider = Provider<List<Announcement>>((ref) {
  final all = ref.watch(announcementsProvider).value ?? const <Announcement>[];
  return [
    for (final announcement in all)
      if (announcement.isActive) announcement,
  ];
});
