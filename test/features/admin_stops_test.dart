import 'dart:convert';

import 'package:bu_bus_tracker/core/router/app_router.dart';
import 'package:bu_bus_tracker/core/router/app_routes.dart';
import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/data/datasources/transport_geojson_parser.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/data/repositories/stop_repository.dart';
import 'package:bu_bus_tracker/data/repositories/transport_network_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:bu_bus_tracker/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _ready = FirebaseStatus(FirebaseAvailability.ready);

const _gate = BusStop(
  id: 'gate',
  name: 'Main Gate',
  description: 'Beside the bank',
  position: GeoPoint(22.6600, 90.3630),
);
const _club = BusStop(
  id: 'club',
  name: 'Barishal Club',
  position: GeoPoint(22.7000, 90.3700),
);
const _suggestedNuria = BusStop(
  id: 'review-nuria-school',
  name: 'Nuria School',
  description: 'Matched to "Nuria Ideal School". Position not confirmed.',
  position: GeoPoint(22.69026, 90.3594),
);
const _suggestedGate = BusStop(
  id: 'review-main-gate',
  name: 'main gate',
  description: 'Position not confirmed.',
  position: GeoPoint(22.66, 90.36),
);

class _EmptyBundle extends CachingAssetBundle {
  static const _empty = '{"type":"FeatureCollection","features":[]}';

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode(_empty));
}

/// Pumps the app signed in with [role], and returns what the test needs.
Future<(ProviderContainer, FakeStopRepository)> _pumpAs(
  WidgetTester tester,
  UserRole role, {
  List<BusStop> stops = const [],
  List<BusStop> suggestions = const [],
  bool isActive = true,
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
        isActive: isActive,
      ),
    );
  auth.signInAs(account);
  final repository = FakeStopRepository(stops);
  final container = await pumpApp(
    tester,
    firebaseStatus: _ready,
    authRepository: auth,
    userProfileRepository: profiles,
    stopRepository: repository,
    suggestedStops: suggestions,
  );
  return (container, repository);
}

Future<void> _openManageStops(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(appRouterProvider).push(AppRoutes.adminStops);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('TransportNetwork.withOfficialStops', () {
    const bundled = TransportNetwork(
      routes: [],
      stops: [
        BusStop(id: 'gate', name: 'Old Gate', position: GeoPoint(22.6, 90.3)),
        BusStop(id: 'other', name: 'Other', position: GeoPoint(22.61, 90.31)),
      ],
      origin: TransportDataOrigin.verified,
    );

    test(
      'adds the official stops, replacing a bundled stop with the same id',
      () {
        final network = bundled.withOfficialStops(const [_gate, _club]);

        expect(network.stops.map((stop) => stop.name), [
          'Main Gate',
          'Barishal Club',
          'Other',
        ]);
        expect(network.origin, TransportDataOrigin.verified);
      },
    );

    test('changes nothing when there are no official stops', () {
      expect(bundled.withOfficialStops(null), same(bundled));
      expect(bundled.withOfficialStops(const []), same(bundled));
    });

    test('never mixes official stops into sample or unconfirmed data', () {
      for (final origin in [
        TransportDataOrigin.demo,
        TransportDataOrigin.unconfirmed,
      ]) {
        final labelled = TransportNetwork(
          routes: const [],
          stops: bundled.stops,
          origin: origin,
        );
        expect(labelled.withOfficialStops(const [_club]), same(labelled));
      }
    });
  });

  group('Stop documents', () {
    test('a stop is stored with only the fields the rules allow', () {
      expect(stopToMap(_gate), {
        'name': 'Main Gate',
        'latitude': 22.66,
        'longitude': 90.363,
        'description': 'Beside the bank',
      });
      expect(stopToMap(_club).containsKey('description'), isFalse);
      expect(
        stopToMap(
          const BusStop(
            id: 'x',
            name: '  Padded  ',
            description: '   ',
            position: GeoPoint(22.6, 90.3),
          ),
        ),
        {'name': 'Padded', 'latitude': 22.6, 'longitude': 90.3},
      );
    });

    test('a stored stop is read back', () {
      final stop = stopFromMap('gate', stopToMap(_gate))!;

      expect(stop.id, 'gate');
      expect(stop.name, 'Main Gate');
      expect(stop.description, 'Beside the bank');
      expect(stop.position, _gate.position);
    });

    test('a damaged document is skipped, never guessed at', () {
      expect(stopFromMap('a', {'latitude': 22.6, 'longitude': 90.3}), isNull);
      expect(
        stopFromMap('a', {'name': ' ', 'latitude': 22.6, 'longitude': 90.3}),
        isNull,
      );
      expect(
        stopFromMap('a', {'name': 'A', 'latitude': '22.6', 'longitude': 90.3}),
        isNull,
      );
      expect(
        stopFromMap('a', {'name': 'A', 'latitude': 122.6, 'longitude': 90.3}),
        isNull,
      );
    });
  });

  group('transportNetworkProvider', () {
    test('shows the stops the transport office saved', () async {
      final repository = FakeStopRepository(const [_gate]);
      final container = ProviderContainer(
        overrides: [
          transportRepositoryProvider.overrideWithValue(
            AssetTransportRepository(
              bundle: _EmptyBundle(),
              origin: TransportDataOrigin.verified,
              parser: const TransportGeoJsonParser(
                fallbackRouteColors: ['#111111'],
              ),
            ),
          ),
          stopRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final seen = <List<String>>[];
      // Waits for the list to show [names], for up to two seconds: a fixed
      // short pause is not enough when the machine is busy.
      Future<void> settled(List<String> names) async {
        for (var i = 0; i < 100; i++) {
          if (seen.isNotEmpty && seen.last.join('|') == names.join('|')) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      container.listen(transportNetworkProvider, (previous, next) {
        final network = next.value;
        if (network != null) {
          seen.add([for (final stop in network.stops) stop.name]);
        }
      }, fireImmediately: true);

      await settled(['Main Gate']);
      expect(seen.last, ['Main Gate']);

      await repository.saveStop(
        const BusStop(
          id: '',
          name: 'Library',
          position: GeoPoint(22.65, 90.36),
        ),
      );
      await settled(['Library', 'Main Gate']);
      expect(seen.last, ['Library', 'Main Gate']);

      await repository.deleteStop('gate');
      await settled(['Library']);
      expect(seen.last, ['Library']);
    });
  });

  group('Profile tab, administration', () {
    Future<void> scrollToEnd(WidgetTester tester) async {
      await openTab(tester, 'Profile');
      await tester.drag(
        find
            .descendant(
              of: find.byType(ProfileScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an admin is offered Manage stops', (tester) async {
      await _pumpAs(tester, UserRole.admin);
      await scrollToEnd(tester);

      expect(find.text('Manage stops'), findsOneWidget);

      // Bring the row itself into view, wherever it is on the page.
      await tester.ensureVisible(find.text('Manage stops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage stops'));
      await tester.pumpAndSettle();
      expect(find.text('Stops on the map (0)'), findsOneWidget);
    });

    testWidgets('a driver, a deactivated admin and a passenger are not', (
      tester,
    ) async {
      await _pumpAs(tester, UserRole.driver);
      await scrollToEnd(tester);
      expect(find.text('Manage stops'), findsNothing);
    });

    testWidgets('a deactivated admin is not', (tester) async {
      await _pumpAs(tester, UserRole.admin, isActive: false);
      await scrollToEnd(tester);
      expect(find.text('Manage stops'), findsNothing);
    });

    testWidgets('someone signed out is not', (tester) async {
      await pumpApp(tester, firebaseStatus: _ready);
      await scrollToEnd(tester);
      expect(find.text('Manage stops'), findsNothing);
    });
  });

  group('Manage stops', () {
    testWidgets('refuses anyone who is not an admin', (tester) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.driver,
        stops: const [_gate],
      );
      await _openManageStops(tester, container);

      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Main Gate'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);

      container.read(appRouterProvider).push(AppRoutes.adminStopEditor);
      await tester.pumpAndSettle();
      expect(find.text('Admins only'), findsOneWidget);
      expect(find.byKey(fakePickerKey), findsNothing);
    });

    testWidgets('lists the saved stops, and suggestions not yet saved', (
      tester,
    ) async {
      final (container, _) = await _pumpAs(
        tester,
        UserRole.admin,
        stops: const [_gate, _club],
        suggestions: const [_suggestedNuria, _suggestedGate],
      );
      await _openManageStops(tester, container);

      expect(find.text('Stops on the map (2)'), findsOneWidget);
      expect(find.text('Main Gate'), findsOneWidget);
      expect(find.textContaining('Beside the bank'), findsOneWidget);
      expect(find.text('Barishal Club'), findsOneWidget);

      // "main gate" is already saved, so only Nuria School is suggested.
      expect(find.text('Suggested positions (1)'), findsOneWidget);
      expect(find.text('Nuria School'), findsOneWidget);
      expect(find.text('main gate'), findsNothing);
      expect(find.textContaining('passengers do not see them'), findsOneWidget);
    });

    testWidgets('adds a stop where the map was moved to', (tester) async {
      final (container, repository) = await _pumpAs(tester, UserRole.admin);
      await _openManageStops(tester, container);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byKey(fakePickerKey), findsOneWidget);

      // A name is required.
      await _press(tester, 'Add stop');
      expect(find.text("Enter the stop's name."), findsOneWidget);
      expect(repository.stops, isEmpty);

      await tester.tap(find.byKey(fakePickerMoveKey));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stop name'),
        'Nuria School',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Note (optional)'),
        'নুরিয়া স্কুল',
      );
      await _press(tester, 'Add stop');

      final saved = repository.stops.values.single;
      expect(saved.name, 'Nuria School');
      expect(saved.description, 'নুরিয়া স্কুল');
      expect(saved.position, fakePickerMovedTo);

      // Back on the list, which now shows it.
      expect(find.text('Stops on the map (1)'), findsOneWidget);
      expect(find.text('Nuria School'), findsOneWidget);
    });

    testWidgets('renames and moves an existing stop, keeping its id', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        stops: const [_gate],
      );
      await _openManageStops(tester, container);

      await tester.tap(find.text('Main Gate'));
      await tester.pumpAndSettle();
      expect(find.text('Edit stop'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Main Gate'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stop name'),
        'University Gate',
      );
      await tester.tap(find.byKey(fakePickerMoveKey));
      await tester.pump();
      await _press(tester, 'Save changes');

      expect(repository.stops.keys, ['gate']);
      expect(repository.stops['gate']!.name, 'University Gate');
      expect(repository.stops['gate']!.position, fakePickerMovedTo);
      expect(repository.stops['gate']!.description, 'Beside the bank');
    });

    testWidgets('saves a suggestion as a new stop once the admin accepts it', (
      tester,
    ) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        suggestions: const [_suggestedNuria],
      );
      await _openManageStops(tester, container);

      await tester.tap(find.text('Nuria School'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is not confirmed'), findsOneWidget);
      // The note about how it was matched is not carried into the stop.
      expect(find.textContaining('Matched to'), findsNothing);

      await _press(tester, 'Add stop');

      final saved = repository.stops.values.single;
      expect(saved.id, isNot(startsWith('review-')));
      expect(saved.name, 'Nuria School');
      expect(saved.position, _suggestedNuria.position);
      expect(saved.description, isNull);

      expect(find.text('Stops on the map (1)'), findsOneWidget);
      expect(find.textContaining('Suggested positions'), findsNothing);
    });

    group('coordinates', () {
      /// Makes the clipboard hold [text], and records what the app copies.
      List<String> useClipboard(WidgetTester tester, String? text) {
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData') {
              return text == null ? null : {'text': text};
            }
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        return copied;
      }

      Future<void> openEditor(WidgetTester tester) async {
        final (container, _) = await _pumpAs(
          tester,
          UserRole.admin,
          stops: const [_gate],
        );
        await _openManageStops(tester, container);
        await tester.tap(find.text('Main Gate'));
        await tester.pumpAndSettle();
      }

      String shownPosition(WidgetTester tester) => tester
          .widget<Text>(find.byKey(const Key('stop-editor-position')))
          .data!;

      testWidgets(
        'copies the pin\'s coordinates in the form Google Maps reads',
        (tester) async {
          final copied = useClipboard(tester, null);
          await openEditor(tester);

          await tester.tap(find.byTooltip('Copy coordinates'));
          await tester.pumpAndSettle();

          expect(copied, ['22.660000, 90.363000']);
          expect(find.text('Copied 22.660000, 90.363000'), findsOneWidget);
        },
      );

      testWidgets('offers what was copied from Google Maps and moves the pin', (
        tester,
      ) async {
        useClipboard(tester, '22.701660, 90.363940');
        await openEditor(tester);

        await tester.tap(find.text('Paste coordinates'));
        await tester.pumpAndSettle();
        // The copied position is already filled in.
        expect(
          find.widgetWithText(TextField, '22.701660, 90.363940'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Move pin'));
        await tester.pumpAndSettle();

        expect(shownPosition(tester), contains('22.70166'));
        expect(shownPosition(tester), contains('90.36394'));
      });

      testWidgets('saves the pasted position', (tester) async {
        useClipboard(tester, null);
        final (container, repository) = await _pumpAs(
          tester,
          UserRole.admin,
          stops: const [_gate],
        );
        await _openManageStops(tester, container);
        await tester.tap(find.text('Main Gate'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Paste coordinates'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Coordinates'),
          'https://maps.google.com/?q=22.701660,90.363940',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Move pin'));
        await tester.pumpAndSettle();
        await _press(tester, 'Save changes');

        final saved = repository.stops['gate']!.position;
        expect(saved.latitude, closeTo(22.70166, 1e-6));
        expect(saved.longitude, closeTo(90.36394, 1e-6));
      });

      testWidgets('does not fill in copied text that is not a position', (
        tester,
      ) async {
        useClipboard(tester, 'see you at 5');
        await openEditor(tester);

        await tester.tap(find.text('Paste coordinates'));
        await tester.pumpAndSettle();

        expect(find.text('see you at 5'), findsNothing);
      });

      testWidgets('refuses text that is not coordinates, and keeps the pin', (
        tester,
      ) async {
        useClipboard(tester, null);
        await openEditor(tester);
        final before = shownPosition(tester);

        await tester.tap(find.text('Paste coordinates'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Coordinates'),
          'Nuria School',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Move pin'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('These are not coordinates'),
          findsOneWidget,
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Coordinates'),
          'https://maps.app.goo.gl/AbCdEf123456',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Move pin'));
        await tester.pumpAndSettle();
        expect(find.textContaining('short link'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(shownPosition(tester), before);
      });

      testWidgets('refuses a place outside the area the map covers', (
        tester,
      ) async {
        useClipboard(tester, null);
        await openEditor(tester);
        final before = shownPosition(tester);

        await tester.tap(find.text('Paste coordinates'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Coordinates'),
          '23.8103, 90.4125', // Dhaka
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Move pin'));
        await tester.pumpAndSettle();

        expect(find.textContaining('outside the area'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(shownPosition(tester), before);
      });
    });

    testWidgets('deletes a stop only after asking', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        stops: const [_gate, _club],
      );
      await _openManageStops(tester, container);

      await tester.tap(find.byTooltip('Delete Main Gate'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Main Gate?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.stops.keys, containsAll(['gate', 'club']));

      await tester.tap(find.byTooltip('Delete Main Gate'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.stops.keys, ['club']);
      expect(find.text('Stops on the map (1)'), findsOneWidget);
      expect(find.text('Main Gate deleted.'), findsOneWidget);
    });

    testWidgets('says so when the server refuses a change', (tester) async {
      final (container, repository) = await _pumpAs(
        tester,
        UserRole.admin,
        stops: const [_gate],
      );
      repository.failWith = const StopWriteFailure(
        'Only a transport office admin can change the stops.',
      );
      await _openManageStops(tester, container);

      await tester.tap(find.text('Main Gate'));
      await tester.pumpAndSettle();
      await _press(tester, 'Save changes');

      expect(
        find.text('Only a transport office admin can change the stops.'),
        findsOneWidget,
      );
      // Still on the editor, nothing lost.
      expect(find.text('Edit stop'), findsOneWidget);
    });
  });
}
