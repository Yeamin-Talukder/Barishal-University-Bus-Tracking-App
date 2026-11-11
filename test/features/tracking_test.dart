import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/core/services/location_service.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/repositories/bus_location_repository.dart';
import 'package:bu_bus_tracker/data/repositories/bus_repository.dart';
import 'package:bu_bus_tracker/data/repositories/live_tracking_repository.dart';
import 'package:bu_bus_tracker/data/repositories/tracking_mirror.dart';
import 'package:bu_bus_tracker/features/admin/data/people_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:bu_bus_tracker/features/driver/application/driver_location_source.dart';
import 'package:bu_bus_tracker/features/driver/application/trip_controller.dart';
import 'package:bu_bus_tracker/features/map/application/bus_map_layer.dart';
import 'package:bu_bus_tracker/features/map/application/stop_map_layer.dart';
import 'package:bu_bus_tracker/features/profile/presentation/profile_screen.dart';

import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const _ready = FirebaseStatus(FirebaseAvailability.ready);

const _chitra = Bus(
  id: 'chitra',
  number: 'BU-01',
  name: 'Chitra',
  routeId: '01',
  driverUid: 'driver-1',
  isActive: true,
);
const _lota = Bus(id: 'lota', number: 'BU-02', name: 'Lota', isActive: true);
const _parked = Bus(
  id: 'parked',
  number: 'BU-03',
  name: 'Payra',
  driverUid: 'driver-2',
  isActive: false,
);

const _trip = ActiveTrip(
  busId: 'chitra',
  tripId: 'trip-9',
  driverUid: 'driver-1',
);
const _campus = PositionFix(
  position: GeoPoint(22.659967, 90.363381),
  headingDegrees: 90,
  speedMetersPerSecond: 8.5,
  accuracyMeters: 6,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  group('Stored positions and trips', () {
    test('a position is stored with what the phone measured', () {
      expect(positionToMap(_trip, _campus), {
        'tripId': 'trip-9',
        'driverUid': 'driver-1',
        'latitude': 22.659967,
        'longitude': 90.363381,
        'heading': 90,
        'speed': 8.5,
        'accuracy': 6,
      });
    });

    test('readings the server would refuse are left out, not sent', () {
      final map = positionToMap(
        _trip,
        const PositionFix(
          position: GeoPoint(22.66, 90.36),
          headingDegrees: 400,
          speedMetersPerSecond: -1,
          accuracyMeters: 9000,
        ),
      );

      expect(map.keys, ['tripId', 'driverUid', 'latitude', 'longitude']);
    });

    test('a stored position is read back with the server\'s time', () {
      final location = busLocationFromMap({
        'tripId': 'trip-9',
        'driverUid': 'driver-1',
        'latitude': 22.66,
        'longitude': 90.36,
        'heading': 45,
        'speed': 7,
        'updatedAt': 1794300000000,
      })!;

      expect(location.position, const GeoPoint(22.66, 90.36));
      expect(location.headingDegrees, 45);
      expect(location.speedMetersPerSecond, 7);
      expect(location.accuracyMeters, isNull);
      expect(location.tripId, 'trip-9');
      expect(
        location.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1794300000000),
      );
    });

    test('a damaged position is ignored, never guessed at', () {
      expect(busLocationFromMap(null), isNull);
      expect(busLocationFromMap('here'), isNull);
      expect(busLocationFromMap({'latitude': 22.6, 'longitude': 90.3}), isNull);
      expect(
        busLocationFromMap({
          'latitude': '22.6',
          'longitude': 90.3,
          'updatedAt': 1,
        }),
        isNull,
      );
      expect(
        busLocationFromMap({
          'latitude': 122.6,
          'longitude': 90.3,
          'updatedAt': 1,
        }),
        isNull,
      );
    });

    test('only an active, well-formed trip counts as a trip', () {
      expect(
        activeTripFromMap('chitra', {
          'tripId': 't',
          'driverUid': 'd',
          'status': 'active',
          'routeId': '01',
          'startedAt': 5000,
        })!.routeId,
        '01',
      );
      expect(activeTripFromMap('chitra', null), isNull);
      expect(
        activeTripFromMap('chitra', {
          'tripId': 't',
          'driverUid': 'd',
          'status': 'ended',
        }),
        isNull,
      );
      expect(
        activeTripFromMap('chitra', {'driverUid': 'd', 'status': 'active'}),
        isNull,
      );
    });
  });

  group('What passengers see', () {
    test('each bus in service with the position it last reported', () async {
      final tracking = FakeTracking(now: () => DateTime(2026, 11, 11, 8, 30));
      tracking.busDrivers['chitra'] = 'driver-1';
      final repository = LiveBusLocationRepository(
        FakeBusRepository(const [_chitra, _lota, _parked]),
        tracking,
        refreshEvery: const Duration(hours: 1),
      );
      final seen = <List<TrackedBus>>[];
      final subscription = repository.watchBuses().listen(seen.add);
      addTearDown(subscription.cancel);
      await _settle();

      // Before any trip: the buses in service, with no position.
      expect([for (final bus in seen.last) bus.bus.number], ['BU-01', 'BU-02']);
      expect(seen.last.every((bus) => bus.location == null), isTrue);

      final trip = await tracking.startTrip(
        bus: _chitra,
        driverUid: 'driver-1',
      );
      await tracking.publishPosition(trip, _campus);
      await _settle();

      final chitra = seen.last.firstWhere((bus) => bus.bus.id == 'chitra');
      expect(chitra.location!.position, _campus.position);
      expect(chitra.location!.updatedAt, DateTime(2026, 11, 11, 8, 30));
      // A bus that is not on a trip still has no position.
      expect(
        seen.last.firstWhere((bus) => bus.bus.id == 'lota').location,
        isNull,
      );

      await tracking.endTrip('chitra');
      await _settle();
      expect(seen.last.every((bus) => bus.location == null), isTrue);
    });

    test(
      'the list is sent again as time passes, so a quiet bus is seen to age',
      () async {
        final repository = LiveBusLocationRepository(
          FakeBusRepository(const [_chitra]),
          FakeTracking(),
          refreshEvery: const Duration(milliseconds: 20),
        );
        var count = 0;
        final subscription = repository.watchBuses().listen((_) => count++);
        addTearDown(subscription.cancel);

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(count, greaterThan(2));
      },
    );
  });

  group('Copying admin changes to the tracking database', () {
    test('saving a bus records who drives it', () async {
      final tracking = FakeTracking();
      final buses = MirroringBusRepository(FakeBusRepository(), tracking);

      final id = await buses.saveBus(
        const Bus(
          id: '',
          number: 'BU-09',
          name: 'New',
          driverUid: 'driver-1',
          isActive: true,
        ),
      );

      expect(tracking.busDrivers, {id: 'driver-1'});
    });

    test(
      'a bus out of service, or without a driver, has no driver recorded',
      () async {
        final tracking = FakeTracking()..busDrivers['parked'] = 'driver-2';
        final buses = MirroringBusRepository(
          FakeBusRepository(const [_parked]),
          tracking,
        );

        await buses.saveBus(_parked);
        expect(tracking.busDrivers, isEmpty);

        await buses.saveBus(_lota);
        expect(tracking.busDrivers, isEmpty);
      },
    );

    test('changing a bus\'s driver ends the trip in progress on it', () async {
      final tracking = FakeTracking()..busDrivers['chitra'] = 'driver-1';
      final trip = await tracking.startTrip(
        bus: _chitra,
        driverUid: 'driver-1',
      );
      await tracking.publishPosition(trip, _campus);
      final buses = MirroringBusRepository(
        FakeBusRepository(const [_chitra]),
        tracking,
      );

      await buses.saveBus(
        const Bus(
          id: 'chitra',
          number: 'BU-01',
          name: 'Chitra',
          driverUid: 'driver-2',
          isActive: true,
        ),
      );

      expect(tracking.busDrivers, {'chitra': 'driver-2'});
      expect(tracking.trips, isEmpty);
      expect(tracking.locations, isEmpty);
    });

    test(
      'saving a bus without changing its driver leaves its trip alone',
      () async {
        final tracking = FakeTracking()..busDrivers['chitra'] = 'driver-1';
        await tracking.startTrip(bus: _chitra, driverUid: 'driver-1');
        final buses = MirroringBusRepository(
          FakeBusRepository(const [_chitra]),
          tracking,
        );

        await buses.saveBus(_chitra);

        expect(tracking.trips.keys, ['chitra']);
      },
    );

    test('deleting a bus removes its driver and its trip', () async {
      final tracking = FakeTracking()..busDrivers['chitra'] = 'driver-1';
      await tracking.startTrip(bus: _chitra, driverUid: 'driver-1');
      final inner = FakeBusRepository(const [_chitra]);
      final buses = MirroringBusRepository(inner, tracking);

      await buses.deleteBus('chitra');

      expect(inner.buses, isEmpty);
      expect(tracking.busDrivers, isEmpty);
      expect(tracking.trips, isEmpty);
    });

    test('says so when the copy is refused', () async {
      final tracking = FakeTracking()
        ..refuseAccessChanges = const TrackingFailure(
          'not set up for tracking',
        );
      final buses = MirroringBusRepository(FakeBusRepository(), tracking);

      await expectLater(
        buses.saveBus(_chitra),
        throwsA(
          isA<BusWriteFailure>().having(
            (failure) => failure.message,
            'message',
            'not set up for tracking',
          ),
        ),
      );
    });

    test('making someone an admin, or not, is recorded', () async {
      final tracking = FakeTracking();
      const person = UserProfile(
        uid: 'u1',
        name: 'N',
        email: 'n@example.com',
        role: UserRole.student,
        isActive: true,
      );
      final people = MirroringPeopleRepository(
        FakePeopleRepository(const [person]),
        tracking,
      );

      await people.setAccess('u1', role: UserRole.admin, isActive: true);
      expect(tracking.admins, {'u1'});

      // A deactivated admin is no longer an admin for tracking either.
      await people.setAccess('u1', role: UserRole.admin, isActive: false);
      expect(tracking.admins, isEmpty);

      await people.setAccess('u1', role: UserRole.driver, isActive: true);
      expect(tracking.admins, isEmpty);
    });
  });

  group('TripController', () {
    late FakeTracking tracking;
    late FakeDriverLocationSource gps;
    late ProviderContainer container;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 11, 11, 8, 30);
      tracking = FakeTracking(now: () => now)
        ..busDrivers['chitra'] = 'driver-1';
      gps = FakeDriverLocationSource();
      container = ProviderContainer(
        overrides: [
          liveTrackingRepositoryProvider.overrideWithValue(tracking),
          driverLocationSourceProvider.overrideWithValue(gps),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
    });

    TripController controller() =>
        container.read(tripControllerProvider.notifier);
    TripState state() => container.read(tripControllerProvider);

    test('starting a trip opens it and begins listening to the GPS', () async {
      await controller().start(_chitra, 'driver-1');

      expect(state().phase, TripPhase.sharing);
      expect(tracking.trips['chitra']!.driverUid, 'driver-1');
      expect(gps.isListening, isTrue);
      expect(state().lastSentAt, isNull);
    });

    test(
      'each position is published, but not more often than allowed',
      () async {
        await controller().start(_chitra, 'driver-1');

        gps.emit(_campus);
        await _settle();
        expect(tracking.published, hasLength(1));
        expect(state().sentCount, 1);
        expect(state().lastSentAt, now);
        expect(state().lastAccuracyMeters, 6);

        // One second later: too soon.
        now = now.add(const Duration(seconds: 1));
        gps.emit(_campus);
        await _settle();
        expect(tracking.published, hasLength(1));

        now = now.add(const Duration(seconds: 4));
        gps.emit(_campus);
        await _settle();
        expect(tracking.published, hasLength(2));
        expect(state().sentCount, 2);
      },
    );

    test(
      'ending the trip stops the GPS and removes the bus\'s position',
      () async {
        await controller().start(_chitra, 'driver-1');
        gps.emit(_campus);
        await _settle();

        await controller().end('chitra');

        expect(state().phase, TripPhase.idle);
        expect(state().problem, isNull);
        expect(gps.isListening, isFalse);
        expect(tracking.trips, isEmpty);
        expect(tracking.locations, isEmpty);

        // A late position from the phone is not sent.
        gps.emit(_campus);
        await _settle();
        expect(tracking.published, hasLength(1));
      },
    );

    test('does not start without location, and says why', () async {
      gps.problem = LocationProblem.permissionDenied;

      await controller().start(_chitra, 'driver-1');

      expect(state().phase, TripPhase.idle);
      expect(state().problem, contains('Location permission is needed'));
      expect(tracking.trips, isEmpty);
      expect(gps.started, 0);
    });

    test('a driver cannot start a trip on a bus that is not theirs', () async {
      await controller().start(_chitra, 'driver-2');

      expect(state().phase, TripPhase.idle);
      expect(state().problem, contains('not assigned to you'));
      expect(tracking.trips, isEmpty);
      expect(gps.started, 0);
    });

    test('a refused position is reported, and sharing carries on', () async {
      await controller().start(_chitra, 'driver-1');
      tracking.refusePositions = const TrackingFailure(
        'The position was refused.',
      );

      gps.emit(_campus);
      await _settle();

      expect(state().phase, TripPhase.sharing);
      expect(state().problem, 'The position was refused.');
      expect(state().sentCount, 0);

      tracking.refusePositions = null;
      now = now.add(const Duration(seconds: 5));
      gps.emit(_campus);
      await _settle();
      expect(state().problem, isNull);
      expect(state().sentCount, 1);
    });

    test('says so when the phone stops giving its position', () async {
      await controller().start(_chitra, 'driver-1');

      gps.fail();
      await _settle();

      expect(state().phase, TripPhase.sharing);
      expect(state().problem, contains('stopped giving its position'));
    });

    test('a trip left open can be resumed', () async {
      final open = await tracking.startTrip(
        bus: _chitra,
        driverUid: 'driver-1',
      );

      await controller().resume(open);
      gps.emit(_campus);
      await _settle();

      expect(state().phase, TripPhase.sharing);
      expect(tracking.published, hasLength(1));
      expect(tracking.locations['chitra']!.tripId, open.tripId);
    });

    test(
      'if the trip cannot be closed, the phone still stops sharing',
      () async {
        await controller().start(_chitra, 'driver-1');
        tracking.refuseEnd = const TrackingFailure(
          'No answer from the server.',
        );

        await controller().end('chitra');

        expect(state().phase, TripPhase.idle);
        expect(gps.isListening, isFalse);
        expect(state().problem, contains('could not be closed'));
      },
    );
  });

  group('Profile tab, driver', () {
    Future<(FakeTracking, FakeDriverLocationSource)> pumpAs(
      WidgetTester tester,
      UserRole role, {
      List<Bus> buses = const [],
      bool openTrip = false,
    }) async {
      final auth = FakeAuthRepository();
      final account = auth.addAccount(email: 'd@example.com');
      final profiles = FakeUserProfileRepository()
        ..put(
          UserProfile(
            uid: account.uid,
            name: 'Abdul',
            email: account.email,
            role: role,
            isActive: true,
          ),
        );
      auth.signInAs(account);
      final mine = [
        for (final bus in buses)
          Bus(
            id: bus.id,
            number: bus.number,
            name: bus.name,
            routeId: bus.routeId,
            driverUid: account.uid,
            isActive: bus.isActive,
          ),
      ];
      final tracking = FakeTracking(now: () => DateTime(2026, 11, 11, 8, 30));
      for (final bus in mine) {
        tracking.busDrivers[bus.id] = account.uid;
      }
      if (openTrip) {
        await tracking.startTrip(bus: mine.first, driverUid: account.uid);
      }
      final gps = FakeDriverLocationSource();
      await pumpApp(
        tester,
        firebaseStatus: _ready,
        authRepository: auth,
        userProfileRepository: profiles,
        busRepository: FakeBusRepository(mine),
        tracking: tracking,
        driverLocationSource: gps,
        now: DateTime(2026, 11, 11, 8, 30, 15),
      );
      await openTab(tester, 'Profile');
      await tester.drag(
        find
            .descendant(
              of: find.byType(ProfileScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      return (tracking, gps);
    }

    Future<void> press(WidgetTester tester, String label) async {
      final button = find.text(label);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('is not shown to passengers or admins', (tester) async {
      await pumpAs(tester, UserRole.student, buses: const [_chitra]);
      expect(find.text('Your bus'), findsNothing);
      expect(find.text('Start trip'), findsNothing);
    });

    testWidgets('an admin does not get driver controls', (tester) async {
      await pumpAs(tester, UserRole.admin, buses: const [_chitra]);
      expect(find.text('Start trip'), findsNothing);
    });

    testWidgets('tells a driver with no bus to ask for one', (tester) async {
      await pumpAs(tester, UserRole.driver);

      expect(find.text('No bus is assigned to you'), findsOneWidget);
      expect(find.text('Start trip'), findsNothing);
    });

    testWidgets('a bus out of service cannot be driven', (tester) async {
      await pumpAs(tester, UserRole.driver, buses: const [_parked]);

      expect(find.text('No bus is assigned to you'), findsOneWidget);
    });

    testWidgets('starts a trip, shares positions, and ends it', (tester) async {
      final (tracking, gps) = await pumpAs(
        tester,
        UserRole.driver,
        buses: const [_chitra],
      );
      expect(find.text('BU-01 · Chitra'), findsOneWidget);
      expect(find.text('Route 01'), findsOneWidget);

      await press(tester, 'Start trip');

      expect(tracking.trips.keys, ['chitra']);
      expect(find.text('Sharing'), findsOneWidget);
      expect(
        find.text('Waiting for the phone\'s first position.'),
        findsOneWidget,
      );

      gps.emit(_campus);
      await tester.pumpAndSettle();

      expect(tracking.published, hasLength(1));
      expect(
        find.textContaining('Last position sent at 8:30:15 AM'),
        findsOneWidget,
      );
      expect(find.textContaining('accurate to about 6 m'), findsOneWidget);

      await press(tester, 'End trip');

      expect(tracking.trips, isEmpty);
      expect(gps.isListening, isFalse);
      expect(find.text('Start trip'), findsOneWidget);
      expect(find.text('Sharing'), findsNothing);
    });

    testWidgets('explains when location cannot be used', (tester) async {
      final (tracking, gps) = await pumpAs(
        tester,
        UserRole.driver,
        buses: const [_chitra],
      );
      gps.problem = LocationProblem.serviceDisabled;

      await press(tester, 'Start trip');

      expect(
        find.textContaining('Location is turned off on this phone'),
        findsOneWidget,
      );
      expect(tracking.trips, isEmpty);
      expect(find.text('Start trip'), findsOneWidget);
    });

    testWidgets('offers to resume or end a trip left open', (tester) async {
      final (tracking, gps) = await pumpAs(
        tester,
        UserRole.driver,
        buses: const [_chitra],
        openTrip: true,
      );

      expect(
        find.textContaining('this phone is not sharing its position'),
        findsOneWidget,
      );
      expect(find.text('Start trip'), findsNothing);

      await press(tester, 'Resume sharing');
      expect(find.text('Sharing'), findsOneWidget);
      expect(gps.isListening, isTrue);

      await press(tester, 'End trip');
      expect(tracking.trips, isEmpty);
    });
  });

  group('Bus markers', () {
    const colors = BusMarkerColors(
      live: '#00aa00',
      delayed: '#ffaa00',
      offline: '#888888',
      outline: '#ffffff',
      selection: '#0000ff',
      label: '#000000',
      labelHalo: '#ffffff',
    );
    final here = BusLocation(
      position: const GeoPoint(22.66, 90.36),
      updatedAt: DateTime(2026, 11, 11, 8, 30),
    );

    test('only a bus that reported a position gets a marker', () {
      final geoJson = BusMapLayer.geoJson(
        [
          TrackedBus(bus: _chitra, location: here),
          const TrackedBus(bus: _lota),
        ],
        statusOf: (_) => BusTrackingStatus.live,
        headingOf: (_) => null,
        colors: colors,
      );

      final features = geoJson['features'] as List;
      expect(features, hasLength(1));
      final feature = features.single as Map;
      expect(feature['properties'], {
        'id': 'chitra',
        'number': 'BU-01',
        'color': '#00aa00',
        'badge': 'bu-bus-badge-live',
        'pointer': 'bu-bus-pointer-live',
        'selected': false,
        // A live bus has a ring; at the start of a pulse it is small and
        // at its strongest.
        'pulseRadius': 30.0,
        'pulseOpacity': 0.32,
      });
      // GeoJSON order: longitude first.
      expect((feature['geometry'] as Map)['coordinates'], [90.36, 22.66]);
    });

    test('the marker\'s colour says how fresh the position is', () {
      String colorFor(BusTrackingStatus status) {
        final geoJson = BusMapLayer.geoJson(
          [TrackedBus(bus: _chitra, location: here)],
          statusOf: (_) => status,
          headingOf: (_) => null,
          colors: colors,
        );
        return ((geoJson['features'] as List).single
                as Map)['properties']['color']
            as String;
      }

      expect(colorFor(BusTrackingStatus.live), '#00aa00');
      expect(colorFor(BusTrackingStatus.delayed), '#ffaa00');
      expect(colorFor(BusTrackingStatus.offline), '#888888');
    });

    test('a direction is drawn only when one is given', () {
      Map<dynamic, dynamic> properties(double? heading) =>
          ((BusMapLayer.geoJson(
                            [TrackedBus(bus: _chitra, location: here)],
                            statusOf: (_) => BusTrackingStatus.delayed,
                            headingOf: (_) => heading,
                            colors: colors,
                          )['features']
                          as List)
                      .single
                  as Map)['properties']
              as Map;

      expect(properties(135)['heading'], 135);
      expect(properties(135)['badge'], 'bu-bus-badge-delayed');
      expect(properties(135)['pointer'], 'bu-bus-pointer-delayed');
      // No heading: no key at all, so the map draws the badge alone.
      expect(properties(null).containsKey('heading'), isFalse);
    });

    test('only a live bus has the pulsing ring', () {
      Map<dynamic, dynamic> properties(
        BusTrackingStatus status,
        double pulse,
      ) =>
          ((BusMapLayer.geoJson(
                            [TrackedBus(bus: _chitra, location: here)],
                            statusOf: (_) => status,
                            headingOf: (_) => null,
                            colors: colors,
                            pulse: pulse,
                          )['features']
                          as List)
                      .single
                  as Map)['properties']
              as Map;

      for (final status in [
        BusTrackingStatus.delayed,
        BusTrackingStatus.offline,
      ]) {
        expect(properties(status, 0.5).containsKey('pulseRadius'), isFalse);
      }
      // The ring grows and fades away over one pulse.
      final early = properties(BusTrackingStatus.live, 0.1);
      final late = properties(BusTrackingStatus.live, 0.9);
      expect(late['pulseRadius'], greaterThan(early['pulseRadius'] as double));
      expect(late['pulseOpacity'], lessThan(early['pulseOpacity'] as double));
      expect(properties(BusTrackingStatus.live, 1)['pulseOpacity'], 0);
    });

    test('a gliding bus is drawn where the caller says it is', () {
      final geoJson = BusMapLayer.geoJson(
        [TrackedBus(bus: _chitra, location: here)],
        statusOf: (_) => BusTrackingStatus.live,
        headingOf: (_) => null,
        positionOf: (_) => const GeoPoint(22.661, 90.361),
        colors: colors,
      );

      expect(
        (((geoJson['features'] as List).single as Map)['geometry']
            as Map)['coordinates'],
        [90.361, 22.661],
      );
    });

    testWidgets('the badge and the pointer are real pictures of one size', (
      tester,
    ) async {
      const green = Color(0xFF1E8E5A);
      for (final paint in [
        () => paintBusBadge(body: green),
        () => paintBusPointer(body: green),
      ]) {
        final bytes = await tester.runAsync(paint);

        // PNG signature.
        expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
        final image = await tester.runAsync(() async {
          final codec = await instantiateImageCodec(bytes);
          return (await codec.getNextFrame()).image;
        });
        // The same size, so the pointer turns around the badge's centre;
        // and several times the design size, so they stay sharp.
        expect(image!.width, BusMapLayer.iconPixels * mapImageScale);
        expect(image.height, BusMapLayer.iconPixels * mapImageScale);
      }
    });

    test('the pictogram can be read on a dark and on a light badge', () {
      expect(busBadgeInk(const Color(0xFF1E8E5A)), const Color(0xFFFFFFFF));
      // The dark theme's status colours are light: draw in dark on them.
      expect(busBadgeInk(const Color(0xFF7FE0B0)), const Color(0xFF0F1318));
    });

    test('the selected bus is marked', () {
      final geoJson = BusMapLayer.geoJson(
        [TrackedBus(bus: _chitra, location: here)],
        statusOf: (_) => BusTrackingStatus.live,
        headingOf: (_) => null,
        colors: colors,
        selectedBusId: 'chitra',
      );

      expect(
        ((geoJson['features'] as List).single as Map)['properties']['selected'],
        isTrue,
      );
    });
  });
}
