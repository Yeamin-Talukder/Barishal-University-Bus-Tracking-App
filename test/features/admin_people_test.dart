import 'package:bu_bus_tracker/core/router/app_router.dart';
import 'package:bu_bus_tracker/core/router/app_routes.dart';
import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/features/admin/data/people_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _ready = FirebaseStatus(FirebaseAvailability.ready);

const _nusrat = UserProfile(
  uid: 'u-nusrat',
  name: 'Nusrat Jahan',
  email: 'nusrat@example.com',
  role: UserRole.student,
  isActive: true,
);
const _abdul = UserProfile(
  uid: 'u-abdul',
  name: 'Abdul Karim',
  email: 'abdul@example.com',
  role: UserRole.driver,
  isActive: true,
);
const _old = UserProfile(
  uid: 'u-old',
  name: 'Old Account',
  email: 'old@example.com',
  role: UserRole.student,
  isActive: false,
);

const _abdulsBus = Bus(
  id: 'chitra',
  number: 'BU-01',
  name: 'Chitra',
  routeId: '01',
  driverUid: 'u-abdul',
  isActive: true,
);

typedef _Setup = ({
  ProviderContainer container,
  FakePeopleRepository people,
  FakeBusRepository buses,
});

Future<_Setup> _pumpAs(
  WidgetTester tester,
  UserRole role, {
  List<UserProfile> others = const [_nusrat, _abdul, _old],
  List<Bus> buses = const [],
}) async {
  final auth = FakeAuthRepository();
  final account = auth.addAccount(email: 'office@example.com');
  final me = UserProfile(
    uid: account.uid,
    name: 'Office Admin',
    email: account.email,
    role: role,
    isActive: true,
  );
  final profiles = FakeUserProfileRepository()..put(me);
  auth.signInAs(account);
  final people = FakePeopleRepository([me, ...others]);
  final busRepository = FakeBusRepository(buses);
  final container = await pumpApp(
    tester,
    firebaseStatus: _ready,
    authRepository: auth,
    userProfileRepository: profiles,
    peopleRepository: people,
    busRepository: busRepository,
  );
  return (container: container, people: people, buses: busRepository);
}

Future<void> _open(WidgetTester tester, ProviderContainer container) async {
  container.read(appRouterProvider).push(AppRoutes.adminPeople);
  await tester.pumpAndSettle();
}

/// Opens [name]'s access dialog.
Future<void> _openPerson(WidgetTester tester, String name) async {
  final tile = find.text(name);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _pressSave(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('Manage people', () {
    testWidgets('refuses anyone who is not an admin', (tester) async {
      final setup = await _pumpAs(tester, UserRole.driver);
      await _open(tester, setup.container);

      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Nusrat Jahan'), findsNothing);
      expect(find.text('nusrat@example.com'), findsNothing);
    });

    testWidgets('lists everyone with what they may do', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      await _open(tester, setup.container);

      expect(find.text('People (4)'), findsOneWidget);
      expect(find.text('Office Admin (you)'), findsOneWidget);
      expect(find.text('nusrat@example.com\nPassenger'), findsOneWidget);
      expect(find.text('abdul@example.com\nDriver'), findsOneWidget);
      expect(
        find.text('old@example.com\nPassenger · Deactivated'),
        findsOneWidget,
      );
    });

    testWidgets('finds a person by name or email', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      await _open(tester, setup.container);

      await tester.enterText(find.byType(TextField), 'ABDUL');
      await tester.pumpAndSettle();
      expect(find.text('People (1 of 4)'), findsOneWidget);
      expect(find.text('Abdul Karim'), findsOneWidget);
      expect(find.text('Nusrat Jahan'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nusrat@');
      await tester.pumpAndSettle();
      expect(find.text('Nusrat Jahan'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No match'), findsOneWidget);
    });

    testWidgets('makes someone a driver', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      await _open(tester, setup.container);

      await _openPerson(tester, 'Nusrat Jahan');
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();
      await _pressSave(tester);

      expect(setup.people.people['u-nusrat']!.role, UserRole.driver);
      expect(setup.people.people['u-nusrat']!.isActive, isTrue);
      expect(find.text('Nusrat Jahan is now: Driver.'), findsOneWidget);
      expect(find.text('nusrat@example.com\nDriver'), findsOneWidget);
    });

    testWidgets('asks before making someone an admin', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      await _open(tester, setup.container);

      await _openPerson(tester, 'Nusrat Jahan');
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      await _pressSave(tester);

      expect(find.text('Make Nusrat Jahan an admin?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(setup.people.people['u-nusrat']!.role, UserRole.student);

      await _openPerson(tester, 'Nusrat Jahan');
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      await _pressSave(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(setup.people.people['u-nusrat']!.role, UserRole.admin);
    });

    testWidgets('deactivates and reactivates an account', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      await _open(tester, setup.container);

      await _openPerson(tester, 'Nusrat Jahan');
      await tester.tap(find.text('Account active'));
      await tester.pumpAndSettle();
      await _pressSave(tester);

      expect(setup.people.people['u-nusrat']!.isActive, isFalse);
      expect(find.text('Nusrat Jahan is deactivated.'), findsOneWidget);

      await _openPerson(tester, 'Old Account');
      await tester.tap(find.text('Account active'));
      await tester.pumpAndSettle();
      await _pressSave(tester);

      expect(setup.people.people['u-old']!.isActive, isTrue);
    });

    testWidgets('takes a driver off their bus when they stop being a driver', (
      tester,
    ) async {
      final setup = await _pumpAs(
        tester,
        UserRole.admin,
        buses: const [_abdulsBus],
      );
      await _open(tester, setup.container);

      await _openPerson(tester, 'Abdul Karim');
      await tester.tap(find.text('Passenger'));
      await tester.pumpAndSettle();
      await _pressSave(tester);

      expect(find.textContaining('the driver of bus BU-01'), findsOneWidget);
      // Nothing has changed until the admin confirms.
      expect(setup.people.people['u-abdul']!.role, UserRole.driver);
      expect(setup.buses.buses['chitra']!.driverUid, 'u-abdul');

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(setup.people.people['u-abdul']!.role, UserRole.student);
      final bus = setup.buses.buses['chitra']!;
      expect(bus.driverUid, isNull);
      // The rest of the bus is untouched.
      expect(bus.number, 'BU-01');
      expect(bus.routeId, '01');
      expect(bus.isActive, isTrue);
    });

    testWidgets('a deactivated driver also loses their bus', (tester) async {
      final setup = await _pumpAs(
        tester,
        UserRole.admin,
        buses: const [_abdulsBus],
      );
      await _open(tester, setup.container);

      await _openPerson(tester, 'Abdul Karim');
      await tester.tap(find.text('Account active'));
      await tester.pumpAndSettle();
      await _pressSave(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(setup.people.people['u-abdul']!.isActive, isFalse);
      expect(setup.buses.buses['chitra']!.driverUid, isNull);
    });

    testWidgets('an admin cannot change their own access', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      await _open(tester, setup.container);

      await tester.tap(find.text('Office Admin (you)'));
      await tester.pumpAndSettle();

      expect(find.text('Account active'), findsNothing);
      expect(
        find.textContaining('cannot change your own access'),
        findsOneWidget,
      );
    });

    testWidgets('saving with nothing changed does nothing', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      setup.people.failWith = const PeopleWriteFailure('should not be called');
      await _open(tester, setup.container);

      await _openPerson(tester, 'Nusrat Jahan');
      await _pressSave(tester);

      expect(find.text('should not be called'), findsNothing);
    });

    testWidgets('says so when the server refuses a change', (tester) async {
      final setup = await _pumpAs(tester, UserRole.admin);
      setup.people.failWith = const PeopleWriteFailure(
        'Only a transport office admin can change what people may do.',
      );
      await _open(tester, setup.container);

      await _openPerson(tester, 'Nusrat Jahan');
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();
      await _pressSave(tester);

      expect(
        find.text(
          'Only a transport office admin can change what people may do.',
        ),
        findsOneWidget,
      );
      expect(setup.people.people['u-nusrat']!.role, UserRole.student);
    });
  });
}
