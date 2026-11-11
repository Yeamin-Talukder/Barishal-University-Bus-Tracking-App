import 'package:bu_bus_tracker/core/router/app_router.dart';
import 'package:bu_bus_tracker/core/router/app_routes.dart';
import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/core/utils/formatting.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:bu_bus_tracker/features/schedule/data/bus_schedule_parser.dart';
import 'package:bu_bus_tracker/features/schedule/data/bus_schedule_repository.dart';
import 'package:bu_bus_tracker/features/schedule/domain/bus_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _ready = FirebaseStatus(FirebaseAvailability.ready);

const _university = LocalizedText(bn: 'বিশ্ববিদ্যালয়', en: 'University');
const _club = LocalizedText(bn: 'বরিশাল ক্লাব', en: 'Barishal Club');

/// Student route 01 as it would be saved in the database.
const _route01 = RouteTimetable(
  id: 'student-01',
  groupId: 'student',
  routeNumber: '01',
  stops: [
    _club,
    LocalizedText(en: 'Toll Ghar'),
    _university,
  ],
  departures: [
    DeparturePoint(
      from: _university,
      trips: [
        ScheduledTrip(
          minutes: 8 * 60 + 30,
          vehicles: LocalizedText(bn: 'চিত্রা', en: 'Chitra'),
        ),
      ],
    ),
  ],
);

const _teacher04 = RouteTimetable(
  id: 'teacher-04',
  groupId: 'teacher',
  routeNumber: '04',
  stops: [],
  departures: [
    DeparturePoint(
      from: _university,
      trips: [
        ScheduledTrip(
          minutes: 14 * 60,
          vehicles: LocalizedText(en: 'Micro-04'),
        ),
      ],
    ),
  ],
);

Future<(ProviderContainer, FakeTimetableRepository)> _pumpAs(
  WidgetTester tester,
  UserRole role, {
  List<RouteTimetable> saved = const [],
}) async {
  final auth = FakeAuthRepository();
  final account = auth.addAccount(email: 'a@example.com');
  final profiles = FakeUserProfileRepository()
    ..put(
      UserProfile(
        uid: account.uid,
        name: 'Office',
        email: account.email,
        role: role,
        isActive: true,
      ),
    );
  auth.signInAs(account);
  final repository = FakeTimetableRepository(saved);
  final container = await pumpApp(
    tester,
    firebaseStatus: _ready,
    authRepository: auth,
    userProfileRepository: profiles,
    timetableRepository: repository,
  );
  return (container, repository);
}

Future<void> _open(WidgetTester tester, ProviderContainer container) async {
  container.read(appRouterProvider).push(AppRoutes.adminSchedule);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String text) =>
    tester.enterText(find.widgetWithText(TextField, label), text);

Future<void> _save(WidgetTester tester) =>
    _tap(tester, find.widgetWithText(FilledButton, 'Save route'));

void main() {
  group('parseClockTime', () {
    test('reads the ways a time is typed', () {
      expect(parseClockTime('8:30 AM'), 8 * 60 + 30);
      expect(parseClockTime('8.30pm'), 20 * 60 + 30);
      expect(parseClockTime('12:00 AM'), 0);
      expect(parseClockTime('12:10 PM'), 12 * 60 + 10);
      expect(parseClockTime('9 am'), 9 * 60);
      expect(parseClockTime('16:05'), 16 * 60 + 5);
      expect(parseClockTime('1605'), 16 * 60 + 5);
      expect(parseClockTime(' 7:45 '), 7 * 60 + 45);
    });

    test('is the opposite of formatClockTime', () {
      for (final minutes in [0, 510, 720, 730, 965, 1439]) {
        expect(parseClockTime(formatClockTime(minutes)), minutes);
      }
    });

    test('returns nothing for text that is not a time', () {
      for (final input in ['', 'soon', '25:00', '8:75', '13 PM', '0 AM', '8']) {
        expect(parseClockTime(input), isNull, reason: input);
      }
    });
  });

  group('Timetable documents', () {
    const parser = BusScheduleParser();

    test('a timetable is stored and read back unchanged', () {
      final map = parser.timetableToMap(_route01);

      expect(map['group'], 'student');
      expect(map['route'], '01');
      expect(
        (map['departures'] as List).single['trips'].single['time'],
        '08:30',
      );

      final back = parser.timetableFromMap(map, id: 'student-01');
      expect(back.id, 'student-01');
      expect(back.routeNumber, '01');
      expect(back.stops, _route01.stops);
      expect(back.departures.single.from, _university);
      expect(back.departures.single.trips.single.minutes, 510);
      expect(back.departures.single.trips.single.vehicles.bn, 'চিত্রা');
    });

    test('text may be in English only or Bangla only, but not empty', () {
      const english = LocalizedText(en: 'Toll Ghar');
      const bangla = LocalizedText(bn: 'টোলঘর');

      expect(english.primary, 'Toll Ghar');
      expect(english.secondary, isNull);
      expect(bangla.primary, 'টোলঘর');
      expect(bangla.secondary, isNull);
      expect(_university.primary, 'University');
      expect(_university.secondary, 'বিশ্ববিদ্যালয়');

      final map = parser.timetableToMap(_route01);
      (map['stops'] as List)[1] = {'bn': '', 'en': ''};
      expect(() => parser.timetableFromMap(map), throwsFormatException);
    });

    test('a first save gets an id from its group and route', () {
      expect(
        timetableIdFor(
          const RouteTimetable(
            groupId: 'staff',
            routeNumber: ' 08 ',
            stops: [],
            departures: [],
          ),
        ),
        'staff-08',
      );
    });
  });

  group('busScheduleProvider', () {
    // What the schedule shows, once it shows [expected] or two seconds
    // have passed: a fixed short pause is not enough on a busy machine.
    Future<List<String>> shown(
      ProviderContainer container,
      List<String> expected,
    ) async {
      var names = <String>[];
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final schedule = container.read(busScheduleProvider).value;
        if (schedule == null) continue;
        names = [
          for (final timetable in schedule.timetables)
            '${timetable.groupId} ${timetable.routeNumber}',
        ];
        if (names.join('|') == expected.join('|')) break;
      }
      return names;
    }

    test('shows the built-in schedule until the database has one', () async {
      final repository = FakeTimetableRepository();
      final container = ProviderContainer(
        overrides: [
          bundledScheduleProvider.overrideWith((ref) => sampleSchedule),
          timetableRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      container.listen(busScheduleProvider, (previous, next) {});

      expect(await shown(container, const ['student 91']), ['student 91']);

      // Saved in the "wrong" order: passengers see groups, then routes.
      await repository.saveAll(const [_teacher04, _route01]);
      expect(await shown(container, const ['student 01', 'teacher 04']), [
        'student 01',
        'teacher 04',
      ]);

      await repository.deleteTimetable('teacher-04');
      expect(await shown(container, const ['student 01']), ['student 01']);

      // With nothing left in the database, the built-in copy is back.
      await repository.deleteTimetable('student-01');
      expect(await shown(container, const ['student 91']), ['student 91']);
    });
  });

  group('Manage schedule', () {
    testWidgets('refuses anyone who is not an admin', (tester) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.driver,
        saved: const [_route01],
      );
      await _open(tester, container);

      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Route 01'), findsNothing);

      container.read(appRouterProvider).push(AppRoutes.adminTimetableEditor);
      await tester.pumpAndSettle();
      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Save route'), findsNothing);
    });

    testWidgets('copies the built-in schedule into the database to start', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(tester, UserRole.admin);
      await _open(tester, container);

      expect(
        find.text('Passengers see the schedule built into the app'),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.widgetWithText(
          FilledButton,
          'Start editing the schedule (1 timetables)',
        ),
      );

      expect(repository.timetables.keys, ['student-91']);
      expect(find.text('Routes (1)'), findsOneWidget);
      expect(find.text('Route 91'), findsOneWidget);
    });

    testWidgets('lists the routes of each group', (tester) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01, _teacher04],
      );
      await _open(tester, container);

      expect(find.text('Route 01'), findsOneWidget);
      expect(find.text('Route 04'), findsNothing);
      expect(find.textContaining('1 departures · 3 stops'), findsOneWidget);

      await tester.tap(find.text('Teacher'));
      await tester.pumpAndSettle();
      expect(find.text('Route 04'), findsOneWidget);
      expect(find.text('Route 01'), findsNothing);

      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();
      expect(find.text('No routes for this group'), findsOneWidget);
    });

    testWidgets(
      'adds a departure, keeps times in order, and passengers see it',
      (tester) async {
        final (container, repository) = await _pumpAs(
          tester,
          UserRole.admin,
          saved: const [_route01],
        );
        await _open(tester, container);
        await tester.tap(find.text('Route 01'));
        await tester.pumpAndSettle();
        expect(find.text('Edit route 01'), findsOneWidget);

        // A time that is not a time is refused.
        await _tap(tester, find.byKey(const Key('add-trip-0')));
        await _type(tester, 'Time', 'morning');
        await _type(tester, 'Buses', 'Boikali');
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Enter a time'), findsOneWidget);

        // An earlier time than the existing 8:30 AM one.
        await _type(tester, 'Time', '7:45 am');
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pumpAndSettle();
        expect(find.text('7:45 AM'), findsOneWidget);

        await _save(tester);

        final trips =
            repository.timetables['student-01']!.departures.single.trips;
        expect([for (final trip in trips) trip.minutes], [465, 510]);
        expect(trips.first.vehicles.en, 'Boikali');
        expect(find.text('Route 01 saved.'), findsOneWidget);

        // The passengers' schedule now shows the database's version.
        container.read(appRouterProvider).go(AppRoutes.routes);
        await tester.pumpAndSettle();
        expect(find.text('7:45 AM'), findsOneWidget);
        expect(find.text('Boikali'), findsOneWidget);
      },
    );

    testWidgets('changes and removes a departure', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01],
      );
      await _open(tester, container);
      await tester.tap(find.text('Route 01'));
      await tester.pumpAndSettle();

      await _tap(tester, find.text('8:30 AM'));
      await _type(tester, 'Time', '9:15 AM');
      await _type(tester, 'Buses', 'BRTC-06');
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('9:15 AM'), findsOneWidget);
      expect(find.text('8:30 AM'), findsNothing);

      await _save(tester);
      final trip =
          repository.timetables['student-01']!.departures.single.trips.single;
      expect(trip.minutes, 9 * 60 + 15);
      expect(trip.vehicles.en, 'BRTC-06');
      // The Bangla text that was there is kept until the admin changes it.
      expect(trip.vehicles.bn, 'চিত্রা');
    });

    testWidgets('will not save a place with no departures', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01],
      );
      await _open(tester, container);
      await tester.tap(find.text('Route 01'));
      await tester.pumpAndSettle();

      await _tap(
        tester,
        find.byTooltip('Remove the 8:30 AM departure from University'),
      );
      await _save(tester);

      expect(
        find.textContaining('Add a departure time for University'),
        findsOneWidget,
      );
      expect(repository.timetables['student-01']!.tripCount, 1);
    });

    testWidgets('adds a new route with a place, a departure and stops', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01],
      );
      await _open(tester, container);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Add route'), findsWidgets);

      // Nothing entered yet.
      await _save(tester);
      expect(find.text('Enter the route number.'), findsOneWidget);

      // A number this group already uses.
      await _type(tester, 'Route number', '01');
      await _save(tester);
      expect(find.textContaining('already has a route 01'), findsOneWidget);

      await _type(tester, 'Route number', '02');
      await _save(tester);
      expect(find.text('Add at least one departure place.'), findsOneWidget);

      await _tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Add departure place'),
      );
      await _type(tester, 'Name in English', 'Notun Bazar');
      await _type(tester, 'Name in Bangla', 'নতুন বাজার');
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('From Notun Bazar'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('add-trip-0')));
      await _type(tester, 'Time', '16:40');
      await _type(tester, 'Buses in Bangla', 'সন্ধ্যা');
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('4:40 PM'), findsOneWidget);

      for (final stop in ['Notun Bazar', 'University']) {
        await _tap(tester, find.widgetWithText(TextButton, 'Add stop'));
        await _type(tester, 'Name in English', stop);
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pumpAndSettle();
      }

      await _save(tester);

      final saved = repository.timetables['student-02']!;
      expect(saved.groupId, 'student');
      expect(saved.routeNumber, '02');
      expect(saved.departures.single.from.bn, 'নতুন বাজার');
      expect(saved.departures.single.trips.single.minutes, 16 * 60 + 40);
      expect(saved.departures.single.trips.single.vehicles.bn, 'সন্ধ্যা');
      expect(
        [for (final stop in saved.stops) stop.en],
        ['Notun Bazar', 'University'],
      );
      expect(find.text('Routes (2)'), findsOneWidget);
    });

    testWidgets('reorders, renames and removes stops', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01],
      );
      await _open(tester, container);
      await tester.tap(find.text('Route 01'));
      await tester.pumpAndSettle();

      await _tap(tester, find.byTooltip('Move stop Barishal Club down'));
      await _tap(tester, find.byTooltip('Remove stop University'));
      await _tap(tester, find.text('Toll Ghar'));
      await _type(tester, 'Name in Bangla', 'টোলঘর');
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      await _save(tester);

      final stops = repository.timetables['student-01']!.stops;
      expect(
        [for (final stop in stops) stop.en],
        ['Toll Ghar', 'Barishal Club'],
      );
      expect(stops.first.bn, 'টোলঘর');
    });

    testWidgets('deletes a route only after asking', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01, _teacher04],
      );
      await _open(tester, container);
      await tester.tap(find.text('Route 01'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete this route'));
      await tester.pumpAndSettle();
      expect(find.text('Delete route 01?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.timetables.keys, contains('student-01'));

      await tester.tap(find.byTooltip('Delete this route'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.timetables.keys, ['teacher-04']);
      expect(find.text('Route 01 deleted.'), findsOneWidget);
    });

    testWidgets('asks before throwing away unsaved changes', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01],
      );
      await _open(tester, container);
      await tester.tap(find.text('Route 01'));
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Remove stop Toll Ghar'));

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit route 01'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Routes (1)'), findsOneWidget);
      expect(repository.timetables['student-01']!.stops, hasLength(3));
    });

    testWidgets('says so when the server refuses a change', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        saved: const [_route01],
      );
      repository.failWith = const ScheduleWriteFailure(
        'Only a transport office admin can change the schedule.',
      );
      await _open(tester, container);
      await tester.tap(find.text('Route 01'));
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Remove stop Toll Ghar'));
      await _save(tester);

      expect(
        find.text('Only a transport office admin can change the schedule.'),
        findsOneWidget,
      );
      expect(find.text('Edit route 01'), findsOneWidget);
    });
  });
}
