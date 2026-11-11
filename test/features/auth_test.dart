import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/features/auth/application/session.dart';
import 'package:bu_bus_tracker/features/auth/data/auth_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _ready = FirebaseStatus(FirebaseAvailability.ready);
const _googleButton = 'Sign in with Google';

Future<void> _tapGoogle(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, _googleButton);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('UserProfile', () {
    test('reads a stored profile', () {
      final profile = UserProfile.fromMap('u1', {
        'name': 'Rahim',
        'email': 'rahim@example.com',
        'studentId': 'CSE-7',
        'role': 'driver',
        'isActive': true,
      });

      expect(profile.name, 'Rahim');
      expect(profile.role, UserRole.driver);
      expect(profile.studentId, 'CSE-7');
      expect(profile.isActive, isTrue);
    });

    test('an unknown or missing role is the least privileged one', () {
      expect(UserRole.parse('owner'), UserRole.student);
      expect(UserRole.parse(null), UserRole.student);
      expect(UserProfile.fromMap('u', const {}).role, UserRole.student);
    });

    test('is active only when the server says exactly true', () {
      expect(UserProfile.fromMap('u', const {}).isActive, isFalse);
      expect(
        UserProfile.fromMap('u', const {'isActive': 'true'}).isActive,
        isFalse,
      );
    });
  });

  group('AuthFailure', () {
    test('explains the failures a person can act on', () {
      expect(
        AuthFailure.fromCode('user-disabled').message,
        'This account has been disabled.',
      );
      expect(
        AuthFailure.fromCode('network-request-failed').message,
        contains('No connection'),
      );
      expect(
        AuthFailure.fromCode('operation-not-allowed').message,
        'Google sign-in is not switched on for this app.',
      );
    });

    test('unknown codes get a plain message, not the code', () {
      final failure = AuthFailure.fromCode('internal-error-xyz');

      expect(failure.message, 'Something went wrong. Try again.');
      expect(failure.message, isNot(contains('xyz')));
    });
  });

  group('SessionController', () {
    late FakeAuthRepository auth;
    late FakeUserProfileRepository profiles;
    late SessionController session;

    setUp(() {
      auth = FakeAuthRepository();
      profiles = FakeUserProfileRepository();
      session = SessionController(auth, profiles);
    });

    test(
      'a first Google sign-in creates a profile with no special access',
      () async {
        auth.googleAccount = auth.addAccount(
          email: 'karim@example.com',
          name: ' Karim ',
        );

        await session.signInWithGoogle();

        final profile = profiles.profiles[auth.current!.uid]!;
        expect(profile.name, 'Karim');
        expect(profile.email, 'karim@example.com');
        expect(profile.role, UserRole.student);
        expect(profile.isActive, isTrue);
      },
    );

    test('uses the email when Google gives no name', () async {
      auth.googleAccount = auth.addAccount(email: 'karim@example.com');

      await session.signInWithGoogle();

      expect(profiles.profiles[auth.current!.uid]?.name, 'karim');
    });

    test('a later sign-in leaves the profile, and its role, alone', () async {
      final account = auth.addAccount(email: 'driver@example.com', name: 'X');
      auth.googleAccount = account;
      profiles.put(
        UserProfile(
          uid: account.uid,
          name: 'A Driver',
          email: account.email,
          role: UserRole.driver,
          isActive: true,
        ),
      );

      await session.signInWithGoogle();

      expect(profiles.createCalls, 0);
      expect(profiles.profiles[account.uid]?.role, UserRole.driver);
      expect(profiles.profiles[account.uid]?.name, 'A Driver');
    });

    test('closing the Google window signs nobody in', () async {
      auth
        ..googleAccount = auth.addAccount(email: 'karim@example.com')
        ..cancel = true;

      await expectLater(
        session.signInWithGoogle(),
        throwsA(isA<SignInCancelled>()),
      );
      expect(auth.current, isNull);
      expect(profiles.profiles, isEmpty);
    });

    test('says so when the profile cannot be saved', () async {
      auth.googleAccount = auth.addAccount(email: 'karim@example.com');
      profiles.failWrites = true;

      await expectLater(
        session.signInWithGoogle(),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.code,
            'code',
            'profile-not-saved',
          ),
        ),
      );
    });
  });

  group('Profile tab, drivers and staff', () {
    testWidgets('says sign-in is unavailable without the backend', (
      tester,
    ) async {
      await pumpApp(tester);
      await openAccountSection(tester);

      expect(find.text('Sign-in is not available'), findsOneWidget);
      expect(find.text(_googleButton), findsNothing);
    });

    testWidgets('offers Google sign-in and nothing else', (tester) async {
      await pumpApp(tester, firebaseStatus: _ready);
      await openAccountSection(tester);

      expect(find.text('Drivers and staff'), findsOneWidget);
      expect(find.text('You do not need an account'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, _googleButton), findsOneWidget);
      // No email, password or registration anywhere.
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Create account'), findsNothing);
      expect(find.textContaining('password'), findsNothing);
    });

    testWidgets('signs in with Google and shows the new account', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      auth.googleAccount = auth.addAccount(
        email: 'nusrat@example.com',
        name: 'Nusrat Jahan',
      );
      final profiles = FakeUserProfileRepository();
      await pumpApp(
        tester,
        firebaseStatus: _ready,
        authRepository: auth,
        userProfileRepository: profiles,
      );
      await openAccountSection(tester);

      await _tapGoogle(tester);

      expect(auth.current?.email, 'nusrat@example.com');
      expect(profiles.profiles[auth.current!.uid]?.role, UserRole.student);
      expect(find.text('Nusrat Jahan'), findsOneWidget);
      expect(find.text('nusrat@example.com'), findsOneWidget);
      expect(find.text('Passenger'), findsOneWidget);
      expect(find.textContaining('no driver or admin access'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('shows the new profile even if the first listener missed it', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      auth.googleAccount = auth.addAccount(
        email: 'nusrat@example.com',
        name: 'Nusrat Jahan',
      );
      final profiles = FakeUserProfileRepository()..dropLiveUpdates = true;
      await pumpApp(
        tester,
        firebaseStatus: _ready,
        authRepository: auth,
        userProfileRepository: profiles,
      );
      await openAccountSection(tester);

      await _tapGoogle(tester);

      expect(find.text('Passenger'), findsOneWidget);
      expect(find.text('Profile not set up'), findsNothing);
    });

    testWidgets('a driver signing in again is still a driver', (tester) async {
      final auth = FakeAuthRepository();
      final account = auth.addAccount(
        email: 'driver@example.com',
        name: 'Abdul',
      );
      auth.googleAccount = account;
      final profiles = FakeUserProfileRepository()
        ..put(
          UserProfile(
            uid: account.uid,
            name: 'Abdul Driver',
            email: account.email,
            role: UserRole.driver,
            isActive: true,
          ),
        );
      await pumpApp(
        tester,
        firebaseStatus: _ready,
        authRepository: auth,
        userProfileRepository: profiles,
      );
      await openAccountSection(tester);

      await _tapGoogle(tester);

      expect(find.text('Abdul Driver'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.textContaining('no driver or admin access'), findsNothing);
    });

    testWidgets(
      'closing the Google window changes nothing and shows no error',
      (tester) async {
        final auth = FakeAuthRepository()..cancel = true;
        await pumpApp(tester, firebaseStatus: _ready, authRepository: auth);
        await openAccountSection(tester);

        await _tapGoogle(tester);

        expect(auth.signInAttempts, 1);
        expect(auth.current, isNull);
        expect(
          find.widgetWithText(FilledButton, _googleButton),
          findsOneWidget,
        );
        expect(find.textContaining('went wrong'), findsNothing);
      },
    );

    testWidgets('a failed sign-in is explained in plain words', (tester) async {
      final auth = FakeAuthRepository()
        ..failWith = AuthFailure.fromCode('network-request-failed');
      await pumpApp(tester, firebaseStatus: _ready, authRepository: auth);
      await openAccountSection(tester);

      await _tapGoogle(tester);

      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.textContaining('network-request-failed'), findsNothing);
      expect(find.widgetWithText(FilledButton, _googleButton), findsOneWidget);
    });

    testWidgets('shows the signed-in person, their role, and signs out', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      final account = auth.addAccount(email: 'driver@example.com');
      final profiles = FakeUserProfileRepository()
        ..put(
          UserProfile(
            uid: account.uid,
            name: 'Abdul Driver',
            email: account.email,
            role: UserRole.driver,
            isActive: true,
          ),
        );
      auth.signInAs(account);
      await pumpApp(
        tester,
        firebaseStatus: _ready,
        authRepository: auth,
        userProfileRepository: profiles,
      );
      await openAccountSection(tester);

      expect(find.text('Abdul Driver'), findsOneWidget);
      expect(find.text('driver@example.com'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);

      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('You do not need an account'), findsOneWidget);
      expect(auth.current, isNull);
    });

    testWidgets('marks a deactivated account', (tester) async {
      final auth = FakeAuthRepository();
      final account = auth.addAccount(email: 'x@example.com');
      final profiles = FakeUserProfileRepository()
        ..put(
          UserProfile(
            uid: account.uid,
            name: 'Former Driver',
            email: account.email,
            role: UserRole.student,
            isActive: false,
          ),
        );
      auth.signInAs(account);
      await pumpApp(
        tester,
        firebaseStatus: _ready,
        authRepository: auth,
        userProfileRepository: profiles,
      );
      await openAccountSection(tester);

      expect(find.text('Deactivated'), findsOneWidget);
    });
  });
}
