import 'package:bu_bus_tracker/core/router/app_router.dart';
import 'package:bu_bus_tracker/core/router/app_routes.dart';
import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/data/repositories/announcement_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _ready = FirebaseStatus(FirebaseAvailability.ready);

final _holiday = Announcement(
  id: 'holiday',
  title: 'No buses on Friday',
  message: 'The university is closed for the holiday.',
  isActive: true,
  createdAt: DateTime(2026, 11, 10),
);
final _old = Announcement(
  id: 'old',
  title: 'Old notice',
  message: 'This one was taken down.',
  isActive: false,
  createdAt: DateTime(2026, 11, 1),
);

Future<(ProviderContainer, FakeAnnouncementRepository)> _pumpAs(
  WidgetTester tester,
  UserRole? role, {
  List<Announcement> saved = const [],
}) async {
  final auth = FakeAuthRepository();
  final profiles = FakeUserProfileRepository();
  if (role != null) {
    final account = auth.addAccount(email: 'a@example.com');
    profiles.put(
      UserProfile(
        uid: account.uid,
        name: 'Office',
        email: account.email,
        role: role,
        isActive: true,
      ),
    );
    auth.signInAs(account);
  }
  final repository = FakeAnnouncementRepository(saved);
  final container = await pumpApp(
    tester,
    firebaseStatus: _ready,
    authRepository: auth,
    userProfileRepository: profiles,
    announcementRepository: repository,
  );
  return (container, repository);
}

Future<void> _openAdmin(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(appRouterProvider).push(AppRoutes.adminAnnouncements);
  await tester.pumpAndSettle();
}

void main() {
  group('Announcement documents', () {
    test('a stored announcement is read', () {
      final announcement = announcementFromMap('a', {
        'title': ' Notice ',
        'message': 'Route change.',
        'isActive': true,
        'createdAt': DateTime(2026, 11, 10),
      })!;

      expect(announcement.title, 'Notice');
      expect(announcement.message, 'Route change.');
      expect(announcement.isActive, isTrue);
      expect(announcement.createdAt, DateTime(2026, 11, 10));
    });

    test('showing must be explicit, and a damaged one is skipped', () {
      expect(
        announcementFromMap('a', {'title': 'T', 'message': 'M'})!.isActive,
        isFalse,
      );
      expect(announcementFromMap('a', {'title': 'T'}), isNull);
      expect(announcementFromMap('a', {'title': ' ', 'message': 'M'}), isNull);
    });

    test('newest first, with a just-posted one at the top', () {
      const fresh = Announcement(
        id: 'new',
        title: 'New',
        message: 'm',
        isActive: true,
      );

      expect(
        [
          for (final a in sortAnnouncements([_old, fresh, _holiday])) a.id,
        ],
        ['new', 'holiday', 'old'],
      );
    });
  });

  group('Home screen', () {
    testWidgets('shows what the transport office has posted, to anyone', (
      tester,
    ) async {
      await _pumpAs(tester, null, saved: [_holiday, _old]);

      expect(find.text('No buses on Friday'), findsOneWidget);
      expect(
        find.text('The university is closed for the holiday.'),
        findsOneWidget,
      );
      expect(find.text('Transport office, 10 November 2026'), findsOneWidget);
      // A hidden announcement is not shown.
      expect(find.text('Old notice'), findsNothing);
    });

    testWidgets('shows nothing when there are no announcements', (
      tester,
    ) async {
      await _pumpAs(tester, null);

      expect(find.byIcon(Icons.campaign_rounded), findsNothing);
    });
  });

  group('Announcements admin', () {
    testWidgets('refuses anyone who is not an admin', (tester) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.driver,
        saved: [_old],
      );
      await _openAdmin(tester, container);

      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Old notice'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('lists every announcement, shown or hidden', (tester) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: [_holiday, _old],
      );
      await _openAdmin(tester, container);

      expect(find.text('Announcements (2)'), findsOneWidget);
      expect(find.textContaining('Showing to passengers'), findsOneWidget);
      expect(find.textContaining('Hidden'), findsOneWidget);
    });

    testWidgets('posts a new announcement that passengers then see', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(tester, UserRole.admin);
      await _openAdmin(tester, container);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // A title and a message are required.
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a title.'), findsOneWidget);
      expect(find.text('Enter the message.'), findsOneWidget);
      expect(repository.announcements, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Route 02 delayed',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Message'),
        'The 9:15 bus leaves at 9:45 today.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();

      final posted = repository.announcements.values.single;
      expect(posted.title, 'Route 02 delayed');
      expect(posted.isActive, isTrue);
      expect(
        find.text('Announcement is showing to passengers.'),
        findsOneWidget,
      );

      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(find.text('The 9:15 bus leaves at 9:45 today.'), findsOneWidget);
    });

    testWidgets('hides an announcement without deleting it', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: [_holiday],
      );
      await _openAdmin(tester, container);

      await tester.tap(find.text('No buses on Friday'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show to passengers'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = repository.announcements['holiday']!;
      expect(saved.isActive, isFalse);
      // The day it was first posted is kept.
      expect(saved.createdAt, DateTime(2026, 11, 10));
      expect(
        find.text('Announcement saved, hidden from passengers.'),
        findsOneWidget,
      );
    });

    testWidgets('deletes only after a second, explicit tap', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: [_holiday],
      );
      await _openAdmin(tester, container);

      await tester.tap(find.text('No buses on Friday'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repository.announcements, hasLength(1));
      expect(find.textContaining('Delete it for good?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Yes, delete'));
      await tester.pumpAndSettle();

      expect(repository.announcements, isEmpty);
      expect(find.text('Announcement deleted.'), findsOneWidget);
    });

    testWidgets('says so when the server refuses a change', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: [_holiday],
      );
      repository.failWith = const AnnouncementWriteFailure(
        'Only a transport office admin can change announcements.',
      );
      await _openAdmin(tester, container);

      await tester.tap(find.text('No buses on Friday'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Only a transport office admin can change announcements.'),
        findsOneWidget,
      );
    });
  });
}
