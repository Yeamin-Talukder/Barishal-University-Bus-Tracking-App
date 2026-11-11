import 'dart:io';

import 'package:bu_bus_tracker/core/router/app_router.dart';
import 'package:bu_bus_tracker/core/router/app_routes.dart';
import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/repositories/bus_location_repository.dart';
import 'package:bu_bus_tracker/data/repositories/bus_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:bu_bus_tracker/features/schedule/data/bus_schedule_parser.dart';
import 'package:bu_bus_tracker/features/schedule/domain/bus_schedule.dart';
import 'package:bu_bus_tracker/features/schedule/domain/schedule_buses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _ready = FirebaseStatus(FirebaseAvailability.ready);

const _chitra = Bus(
  id: 'chitra',
  number: 'BU-01',
  name: 'Chitra',
  registrationNumber: 'BARISHAL-11-0001',
  routeId: '91',
  driverUid: 'driver-abdul',
  isActive: true,
);
const _lota = Bus(id: 'lota', number: 'BU-02', name: 'Lota', isActive: false);

const _abdul = UserProfile(
  uid: 'driver-abdul',
  name: 'Abdul Karim',
  email: 'abdul@example.com',
  role: UserRole.driver,
  isActive: true,
);
const _rahim = UserProfile(
  uid: 'driver-rahim',
  name: 'Rahim Uddin',
  email: 'rahim@example.com',
  role: UserRole.driver,
  isActive: true,
);

Future<(ProviderContainer, FakeBusRepository)> _pumpAs(
  WidgetTester tester,
  UserRole role, {
  List<Bus> buses = const [],
  List<UserProfile> drivers = const [_abdul, _rahim],
  BusSchedule? schedule,
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
  final repository = FakeBusRepository(buses);
  final container = await pumpApp(
    tester,
    firebaseStatus: _ready,
    authRepository: auth,
    userProfileRepository: profiles,
    busRepository: repository,
    drivers: drivers,
    schedule: schedule,
  );
  return (container, repository);
}

Future<void> _open(WidgetTester tester, ProviderContainer container) async {
  container.read(appRouterProvider).push(AppRoutes.adminBuses);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // A focused text field scrolls itself back into view, which would move
  // the thing being tapped. Leave the field first, as a person's tap does.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String text) =>
    tester.enterText(find.widgetWithText(TextFormField, label), text);

/// Opens a dropdown and picks the entry with [text].
Future<void> _choose(WidgetTester tester, Key dropdown, String text) async {
  await _tap(tester, find.byKey(dropdown));
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// The schedule file that ships with the app.
BusSchedule _official() => const BusScheduleParser().parse(
  File('assets/data/schedule.json').readAsStringSync(),
);

void main() {
  group('Buses named in the schedule', () {
    test('are every bus the official schedule names, once each', () {
      final buses = busesNamedInSchedule(_official());

      expect(
        [for (final bus in buses) bus.number],
        [
          'Agunmukha',
          'Andharmanik',
          'Boikali',
          'BRTC-04',
          'BRTC-05',
          'BRTC-06',
          'BRTC-07',
          'BRTC-08',
          'BRTC-09',
          'BRTC-10',
          'BRTC-11',
          'BRTC-12',
          'BRTC-13',
          'BRTC-14',
          'Chitra',
          'Ilisha',
          'Jayanti',
          'Kirtankhola',
          'Lota',
          'Micro-02',
          'Micro-03',
          'Micro-04',
          'Micro-05',
          'Noyabhangani',
          'Payra',
          'Sandhya',
          'Sugandha',
        ],
      );
      expect(buses, hasLength(27));
      expect(buses.every((bus) => bus.isActive), isTrue);
      expect(buses.every((bus) => bus.id.isEmpty), isTrue);
    });

    test('keep the Bangla name the schedule gives them', () {
      final byNumber = {
        for (final bus in busesNamedInSchedule(_official())) bus.number: bus,
      };

      expect(byNumber['Chitra']!.name, 'চিত্রা');
      expect(byNumber['BRTC-05']!.name, 'বিআরটিসি-০৫');
      // Written "BRTC-12,13,14" in the schedule.
      expect(byNumber['BRTC-14']!.name, 'বিআরটিসি-১৪');
      expect(byNumber['Micro-03']!.name, 'মাইক্রো-০৩');
    });

    test('get a route only when the schedule uses them on one route', () {
      final byNumber = {
        for (final bus in busesNamedInSchedule(_official())) bus.number: bus,
      };

      expect(byNumber['BRTC-05']!.routeId, '01');
      expect(byNumber['BRTC-09']!.routeId, '03');
      expect(byNumber['Sandhya']!.routeId, '02');
      expect(byNumber['Micro-03']!.routeId, '07');
      // On student route 01, staff route 08 and more.
      expect(byNumber['Boikali']!.routeId, isNull);
      // On teacher routes 04 and 05.
      expect(byNumber['Micro-04']!.routeId, isNull);
    });

    test('reads the ways the schedule writes several buses', () {
      BusSchedule one(String en, String bn) => BusSchedule(
        source: '',
        recordedOn: null,
        notes: const [],
        groups: BusSchedule.standardGroups,
        timetables: [
          RouteTimetable(
            groupId: 'student',
            routeNumber: '01',
            stops: const [],
            departures: [
              DeparturePoint(
                from: const LocalizedText(en: 'A'),
                trips: [
                  ScheduledTrip(
                    minutes: 0,
                    vehicles: LocalizedText(en: en, bn: bn),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      List<String> numbers(String en, [String bn = '']) => [
        for (final bus in busesNamedInSchedule(one(en, bn))) bus.number,
      ];

      expect(numbers('Chitra, BRTC-04,06'), ['BRTC-04', 'BRTC-06', 'Chitra']);
      expect(numbers('Chitra and Boikali'), ['Boikali', 'Chitra']);
      expect(numbers('2 buses (Lota/Payra)'), ['Lota', 'Payra']);
      expect(numbers('Lota/Kirtankhola/Payra'), [
        'Kirtankhola',
        'Lota',
        'Payra',
      ]);
      // Only Bangla written: it is used as the label.
      expect(numbers('', 'চিত্রা ও বৈকালি'), ['চিত্রা', 'বৈকালি']);
      expect(numbers('', ''), isEmpty);
    });
  });

  group('Bus documents', () {
    test('a bus is stored with only the fields the rules allow', () {
      expect(busToMap(_chitra), {
        'busNumber': 'BU-01',
        'name': 'Chitra',
        'isActive': true,
        'registrationNumber': 'BARISHAL-11-0001',
        'routeId': '91',
        'driverUid': 'driver-abdul',
      });
      expect(busToMap(_lota), {
        'busNumber': 'BU-02',
        'name': 'Lota',
        'isActive': false,
      });
    });

    test('a stored bus is read back', () {
      final bus = busFromMap('chitra', busToMap(_chitra))!;

      expect(bus.number, 'BU-01');
      expect(bus.name, 'Chitra');
      expect(bus.routeId, '91');
      expect(bus.driverUid, 'driver-abdul');
      expect(bus.isActive, isTrue);
    });

    test(
      'a damaged document is skipped, and "in service" must be explicit',
      () {
        expect(busFromMap('x', {'name': 'No number'}), isNull);
        expect(busFromMap('x', {'busNumber': ' ', 'name': 'Blank'}), isNull);
        expect(
          busFromMap('x', {'busNumber': 'B', 'name': 'N'})!.isActive,
          isFalse,
        );
        expect(
          busFromMap('x', {
            'busNumber': 'B',
            'name': 'N',
            'isActive': 'yes',
          })!.isActive,
          isFalse,
        );
      },
    );
  });

  group('Passengers', () {
    test(
      'see the buses in service, with no position, and not the others',
      () async {
        final repository = FakeBusRepository(const [_chitra, _lota]);
        final container = ProviderContainer(
          overrides: [busRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        container.listen(trackedBusesProvider, (previous, next) {});
        // Wait for the list itself, not for a fixed moment.
        final tracked = await container.read(reportedBusesProvider.future);
        expect([for (final item in tracked) item.bus.number], ['BU-01']);
        // The app never invents a position.
        expect(tracked.single.location, isNull);
      },
    );
  });

  group('Manage buses', () {
    testWidgets('refuses anyone who is not an admin', (tester) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.driver,
        buses: const [_chitra],
      );
      await _open(tester, container);

      expect(find.text('Admins only'), findsOneWidget);
      expect(find.textContaining('Chitra'), findsNothing);

      container.read(appRouterProvider).push(AppRoutes.adminBusEditor);
      await tester.pumpAndSettle();
      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Bus number'), findsNothing);
    });

    testWidgets('lists each bus with its route, driver and state', (
      tester,
    ) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.admin,
        buses: const [_chitra, _lota],
      );
      await _open(tester, container);

      expect(find.text('Buses (2)'), findsOneWidget);
      expect(find.text('BU-01 · Chitra'), findsOneWidget);
      expect(find.text('Route 91 · Driver: Abdul Karim'), findsOneWidget);
      expect(find.text('BU-02 · Lota'), findsOneWidget);
      expect(
        find.text('No route · No driver · Not in service'),
        findsOneWidget,
      );
    });

    testWidgets('adds a bus with a route and a driver', (tester) async {
      final (container, repository) = await _pumpAs(tester, UserRole.admin);
      await _open(tester, container);
      expect(find.text('No buses yet'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // The number and the name are required.
      await _tap(tester, find.widgetWithText(FilledButton, 'Add bus'));
      expect(find.text('Enter the bus number.'), findsOneWidget);
      expect(find.text('Enter the name of the bus.'), findsOneWidget);
      expect(repository.buses, isEmpty);

      await _type(tester, 'Bus number', 'BRTC-05');
      await _type(tester, 'Name', 'Boikali');
      await _choose(tester, const Key('bus-route'), 'Route 91');
      await _choose(
        tester,
        const Key('bus-driver'),
        'Rahim Uddin (rahim@example.com)',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Add bus'));

      final saved = repository.buses.values.single;
      expect(saved.number, 'BRTC-05');
      expect(saved.name, 'Boikali');
      expect(saved.routeId, '91');
      expect(saved.driverUid, 'driver-rahim');
      expect(saved.isActive, isTrue);
      expect(saved.registrationNumber, isNull);

      expect(find.text('Buses (1)'), findsOneWidget);
      expect(find.text('Route 91 · Driver: Rahim Uddin'), findsOneWidget);
    });

    testWidgets('changes a bus, takes it out of service, keeps its id', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        buses: const [_chitra],
      );
      await _open(tester, container);
      await tester.tap(find.text('BU-01 · Chitra'));
      await tester.pumpAndSettle();
      expect(find.text('Edit bus BU-01'), findsOneWidget);

      await _type(tester, 'Name', 'Chitra 2');
      await _choose(tester, const Key('bus-route'), 'No route');
      await _choose(tester, const Key('bus-driver'), 'No driver');
      await _tap(tester, find.text('In service'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Save changes'));

      expect(repository.buses.keys, ['chitra']);
      final saved = repository.buses['chitra']!;
      expect(saved.name, 'Chitra 2');
      expect(saved.routeId, isNull);
      expect(saved.driverUid, isNull);
      expect(saved.isActive, isFalse);
      expect(saved.registrationNumber, 'BARISHAL-11-0001');
    });

    testWidgets('refuses a number or a driver another bus already has', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        buses: const [_chitra, _lota],
      );
      await _open(tester, container);
      await tester.tap(find.text('BU-02 · Lota'));
      await tester.pumpAndSettle();

      await _type(tester, 'Bus number', 'bu-01');
      await _tap(tester, find.widgetWithText(FilledButton, 'Save changes'));
      expect(
        find.text('Another bus already has the number bu-01.'),
        findsOneWidget,
      );

      await _type(tester, 'Bus number', 'BU-02');
      await _choose(
        tester,
        const Key('bus-driver'),
        'Abdul Karim (abdul@example.com)',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Save changes'));
      expect(
        find.textContaining('That driver already has bus BU-01'),
        findsOneWidget,
      );
      expect(repository.buses['lota']!.driverUid, isNull);
    });

    testWidgets('offers the buses the schedule names, and adds them all', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        schedule: _official(),
      );
      await _open(tester, container);

      expect(find.text('Named in the schedule (27)'), findsOneWidget);
      await _tap(tester, find.widgetWithText(FilledButton, 'Add all 27 buses'));

      expect(repository.buses, hasLength(27));
      expect(find.text('27 buses added.'), findsOneWidget);
      expect(find.text('Buses (27)'), findsOneWidget);
      // Nothing left to offer.
      expect(find.textContaining('Named in the schedule'), findsNothing);
      final chitra = repository.buses.values.firstWhere(
        (bus) => bus.number == 'Chitra',
      );
      expect(chitra.name, 'চিত্রা');
      expect(chitra.isActive, isTrue);
    });

    testWidgets('does not offer a bus that is already in the list', (
      tester,
    ) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.admin,
        schedule: _official(),
        buses: const [
          Bus(id: 'x', number: 'chitra', name: 'Chitra', isActive: true),
        ],
      );
      await _open(tester, container);

      expect(find.text('Named in the schedule (26)'), findsOneWidget);
    });

    testWidgets('opens one schedule bus to check it before adding', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        schedule: _official(),
      );
      await _open(tester, container);

      await _tap(tester, find.text('BRTC-05 · বিআরটিসি-০৫'));
      expect(find.text('Add bus'), findsWidgets);
      expect(find.widgetWithText(TextFormField, 'বিআরটিসি-০৫'), findsOneWidget);
      // Nothing to delete yet.
      expect(find.byTooltip('Delete this bus'), findsNothing);

      await _tap(tester, find.widgetWithText(FilledButton, 'Add bus'));

      final saved = repository.buses.values.single;
      expect(saved.number, 'BRTC-05');
      expect(saved.name, 'বিআরটিসি-০৫');
      expect(saved.routeId, '01');
      expect(find.text('Named in the schedule (26)'), findsOneWidget);
    });

    testWidgets('says when there are no drivers to choose from', (
      tester,
    ) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.admin,
        drivers: const [],
      );
      await _open(tester, container);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('There are no drivers yet'), findsOneWidget);
    });

    testWidgets('deletes a bus only after asking', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        buses: const [_chitra, _lota],
      );
      await _open(tester, container);
      await tester.tap(find.text('BU-02 · Lota'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete this bus'));
      await tester.pumpAndSettle();
      expect(find.text('Delete bus BU-02?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.buses.keys, containsAll(['chitra', 'lota']));

      await tester.tap(find.byTooltip('Delete this bus'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.buses.keys, ['chitra']);
      expect(find.text('Bus BU-02 deleted.'), findsOneWidget);
      expect(find.text('Buses (1)'), findsOneWidget);
    });

    testWidgets('says so when the server refuses a change', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        buses: const [_chitra],
      );
      repository.failWith = const BusWriteFailure(
        'Only a transport office admin can change the buses.',
      );
      await _open(tester, container);
      await tester.tap(find.text('BU-01 · Chitra'));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(FilledButton, 'Save changes'));

      expect(
        find.text('Only a transport office admin can change the buses.'),
        findsOneWidget,
      );
      expect(find.text('Edit bus BU-01'), findsOneWidget);
    });
  });
}
