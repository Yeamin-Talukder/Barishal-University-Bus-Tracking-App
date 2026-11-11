import 'package:bu_bus_tracker/core/services/eta_service.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/data/repositories/bus_location_repository.dart';
import 'package:bu_bus_tracker/data/repositories/transport_network_repository.dart';
import 'package:bu_bus_tracker/features/buses/presentation/bus_journey.dart';
import 'package:bu_bus_tracker/features/test_drive/application/test_drive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

// One kilometre due north, give or take a metre.
const _south = GeoPoint(22.7000, 90.3600);
const _north = GeoPoint(22.7090, 90.3600);
const _path = [_south, _north];

const _network = TransportNetwork(
  origin: TransportDataOrigin.verified,
  stops: [
    BusStop(id: 's', name: 'Club', position: _south),
    BusStop(id: 'n', name: 'University', position: _north),
  ],
  routes: [
    BusRoute(
      id: 'r1',
      name: 'Route 01',
      colorHex: '#D94A38',
      startName: 'Club',
      endName: 'University',
      path: _path,
      stopIds: ['s', 'n'],
      isActive: true,
    ),
  ],
);

void main() {
  group('A test bus on its path', () {
    TestBusPose at(int seconds) => poseOnPath(
      _path,
      speedMetersPerSecond: 10,
      sinceSetOff: Duration(seconds: seconds),
    )!;

    test('sets off from the first point, facing along the road', () {
      final pose = at(0);
      expect(pose.position, _south);
      expect(pose.headingDegrees, closeTo(0, 0.5));
      expect(pose.speedMetersPerSecond, 10);
    });

    test('is part-way along after part of the drive', () {
      // About 1,000 m at 10 m/s: half-way after 50 seconds.
      final pose = at(50);
      expect(pose.position.latitude, closeTo(22.7045, 0.0002));
      expect(pose.position.longitude, 90.36);
    });

    test('waits at the far end, then drives back', () {
      final waiting = at(105);
      expect(waiting.position.latitude, closeTo(_north.latitude, 1e-9));
      expect(waiting.speedMetersPerSecond, 0);

      // The drive takes about 100 s and the wait 20 s.
      final returning = at(150);
      expect(returning.position.latitude, lessThan(_north.latitude));
      expect(returning.position.latitude, greaterThan(_south.latitude));
      expect(returning.headingDegrees, closeTo(180, 0.5));
      expect(returning.speedMetersPerSecond, 10);
    });

    test('starts over once it is back, so a test can be left running', () {
      // One round: out 100 s, wait 20 s, back 100 s, wait 20 s.
      final again = at(290);
      expect(again.headingDegrees, closeTo(0, 0.5));
      expect(again.position.latitude, greaterThan(_south.latitude));
      expect(again.position.latitude, lessThan(22.7045));
    });

    test('never leaves its path', () {
      for (var seconds = 0; seconds < 600; seconds += 7) {
        final latitude = at(seconds).position.latitude;
        expect(latitude, inInclusiveRange(_south.latitude, _north.latitude));
      }
    });

    test('there is no bus without a path to drive or a speed', () {
      expect(
        poseOnPath(
          const [_south],
          speedMetersPerSecond: 10,
          sinceSetOff: Duration.zero,
        ),
        isNull,
      );
      expect(
        poseOnPath(_path, speedMetersPerSecond: 0, sinceSetOff: Duration.zero),
        isNull,
      );
    });
  });

  group('The test, on this device', () {
    late DateTime now;
    late ProviderContainer container;

    setUp(() {
      now = DateTime(2026, 11, 11, 9);
      container = ProviderContainer(
        overrides: [
          transportNetworkProvider.overrideWith((ref) async => _network),
          reportedBusesProvider.overrideWith(
            (ref) => Stream.value(const <TrackedBus>[]),
          ),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(() {
        container.read(testDriveProvider.notifier).stop();
        container.dispose();
      });
    });

    Future<TestDriveController> ready() async {
      await container.read(transportNetworkProvider.future);
      container.listen(trackedBusesProvider, (previous, next) {});
      return container.read(testDriveProvider.notifier);
    }

    List<TrackedBus> shown() =>
        container.read(trackedBusesProvider).value ?? const [];

    test('nothing is shown until the test is started', () async {
      final test = await ready();
      test.addBus(routeId: 'r1', towardsStart: false, speedKmh: 36);

      expect(container.read(testDriveProvider).buses, hasLength(1));
      expect(shown(), isEmpty);
    });

    test(
      'a started bus is on the map, named TEST and said to be a test',
      () async {
        final test = await ready();
        test
          ..addBus(routeId: 'r1', towardsStart: false, speedKmh: 36)
          ..start();

        final bus = shown().single;
        expect(bus.bus.number, 'TEST 1');
        expect(bus.bus.name, 'Test bus, only on this phone');
        expect(bus.bus.routeId, 'r1');
        expect(bus.location!.position, _south);
        expect(bus.location!.updatedAt, now);
        expect(bus.location!.speedMetersPerSecond, closeTo(10, 1e-9));
      },
    );

    test('a bus set to go the other way starts from the far end', () async {
      final test = await ready();
      test
        ..addBus(routeId: 'r1', towardsStart: true, speedKmh: 36)
        ..start();

      final location = shown().single.location!;
      expect(location.position.latitude, closeTo(_north.latitude, 1e-9));
      expect(location.headingDegrees, closeTo(180, 0.5));
    });

    test('a bus with a delay sets off only when its time comes', () async {
      final test = await ready();
      test
        ..addBus(routeId: 'r1', towardsStart: false, speedKmh: 36)
        ..addBus(
          routeId: 'r1',
          towardsStart: true,
          speedKmh: 18,
          startDelay: const Duration(seconds: 10),
        )
        ..start();
      expect(shown().map((bus) => bus.bus.number), ['TEST 1']);

      now = now.add(const Duration(seconds: 12));
      // What the two-second timer does.
      test
        ..removeBus('nothing')
        ..addBus(routeId: 'missing-route', towardsStart: false, speedKmh: 20);

      expect(shown().map((bus) => bus.bus.number), ['TEST 1', 'TEST 2']);
      // The first has driven 12 s at 10 m/s: about 120 m north.
      expect(
        shown().first.location!.position.latitude,
        closeTo(22.70108, 0.0001),
      );
    });

    test('stopping takes every test bus away again', () async {
      final test = await ready();
      test
        ..addBus(routeId: 'r1', towardsStart: false, speedKmh: 36)
        ..start();
      expect(shown(), hasLength(1));

      test.stop();

      expect(shown(), isEmpty);
      expect(container.read(testDriveProvider).isRunning, isFalse);
      // The buses stay listed, ready to be started again.
      expect(container.read(testDriveProvider).buses, hasLength(1));
    });

    test('a ready-made set has one bus each way on every route', () async {
      final test = await ready();
      test.addSampleBuses(_network.routes);

      final buses = container.read(testDriveProvider).buses;
      expect(buses.map((bus) => bus.towardsStart), [true, false]);
      expect(buses.map((bus) => bus.speedKmh).toSet(), hasLength(2));
      expect(buses.map((bus) => bus.startDelay.inSeconds), [0, 8]);
    });

    test('there is a limit to how many can run', () async {
      final test = await ready();
      for (var i = 0; i < TestDriveController.mostBuses + 5; i++) {
        test.addBus(routeId: 'r1', towardsStart: false, speedKmh: 30);
      }

      expect(
        container.read(testDriveProvider).buses,
        hasLength(TestDriveController.mostBuses),
      );
    });

    test('removing a bus frees its number for the next one', () async {
      final test = await ready();
      test
        ..addBus(routeId: 'r1', towardsStart: false, speedKmh: 30)
        ..addBus(routeId: 'r1', towardsStart: false, speedKmh: 30)
        ..removeBus('device-test-1')
        ..addBus(routeId: 'r1', towardsStart: true, speedKmh: 30);

      expect(container.read(testDriveProvider).buses.map((bus) => bus.label), [
        'TEST 2',
        'TEST 1',
      ]);
    });

    test('real buses stay on the list beside the test buses', () async {
      final real = TrackedBus(
        bus: const Bus(
          id: 'joy',
          number: 'Joyonti',
          name: 'Joyonti',
          isActive: true,
        ),
        location: BusLocation(position: _north, updatedAt: now),
      );
      final both = ProviderContainer(
        overrides: [
          transportNetworkProvider.overrideWith((ref) async => _network),
          reportedBusesProvider.overrideWith((ref) => Stream.value([real])),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(() {
        both.read(testDriveProvider.notifier).stop();
        both.dispose();
      });
      await both.read(transportNetworkProvider.future);
      both.listen(trackedBusesProvider, (previous, next) {});
      await both.read(reportedBusesProvider.future);

      both.read(testDriveProvider.notifier)
        ..addBus(routeId: 'r1', towardsStart: false, speedKmh: 36)
        ..start();

      expect(
        both.read(trackedBusesProvider).value!.map((bus) => bus.bus.number),
        ['TEST 1', 'Joyonti'],
      );
    });
  });

  group('Which way a bus is going', () {
    final now = DateTime(2026, 11, 11, 9);
    const eta = EtaService();

    TrackedBus bus({required double heading, double speed = 10}) => TrackedBus(
      bus: const Bus(
        id: 'b',
        number: 'B1',
        name: 'Bus',
        routeId: 'r1',
        isActive: true,
      ),
      location: BusLocation(
        position: const GeoPoint(22.7045, 90.36),
        updatedAt: now,
        headingDegrees: heading,
        speedMetersPerSecond: speed,
        accuracyMeters: 8,
      ),
    );

    String? journey(TrackedBus tracked, {BusTrackingStatus? status}) =>
        busJourney(
          eta: eta,
          network: _network,
          tracked: tracked,
          status: status ?? BusTrackingStatus.live,
        );

    test('from the start of its route to the end', () {
      expect(journey(bus(heading: 0)), 'Club → University');
    });

    test('or the other way round', () {
      expect(journey(bus(heading: 180)), 'University → Club');
    });

    test('is not said when it cannot be told', () {
      // Standing still: the heading means nothing.
      expect(journey(bus(heading: 0, speed: 0)), isNull);
      // Driving across the road.
      expect(journey(bus(heading: 90)), isNull);
      // An old position.
      expect(
        journey(bus(heading: 0), status: BusTrackingStatus.delayed),
        isNull,
      );
      // No position at all.
      expect(
        journey(
          const TrackedBus(
            bus: Bus(
              id: 'b',
              number: 'B1',
              name: 'Bus',
              routeId: 'r1',
              isActive: true,
            ),
          ),
        ),
        isNull,
      );
    });
  });

  group('Test the system screen', () {
    Future<void> open(WidgetTester tester) async {
      await openTab(tester, 'Profile');
      await tester.ensureVisible(find.text('Test the system'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test the system'));
      await tester.pumpAndSettle();
    }

    testWidgets('says the buses are pretend and stay on this phone', (
      tester,
    ) async {
      await pumpApp(tester, network: _network);
      await open(tester);

      expect(find.text('Pretend buses, on this phone only'), findsOneWidget);
      expect(find.textContaining('Nothing is sent to the server'), findsOne);
      // Nothing to start yet.
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Start the test'),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a set of buses can be added, started, watched and stopped', (
      tester,
    ) async {
      final container = await pumpApp(tester, network: _network);
      await open(tester);

      await tester.tap(find.text('Add a set'));
      await tester.pumpAndSettle();
      expect(find.text('Test buses (2)'), findsOneWidget);
      expect(find.text('University → Club'), findsOneWidget);
      expect(find.text('Club → University'), findsOneWidget);
      expect(find.text('40 km/h · starts at once'), findsOneWidget);
      expect(find.text('29 km/h · starts after 8 s'), findsOneWidget);

      await tester.tap(find.text('Start the test'));
      await tester.pumpAndSettle();
      expect(find.text('Running'), findsOneWidget);
      expect(container.read(testDriveProvider).isRunning, isTrue);

      await tester.tap(find.text('Watch on the map'));
      await tester.pumpAndSettle();
      // On the map page: the test bus is listed, and the page says it is a
      // test.
      expect(find.text('Test mode: TEST buses are pretend'), findsOneWidget);
      expect(find.text('Bus TEST 1'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Test mode: TEST buses are pretend'), findsNothing);
      expect(find.text('Bus TEST 1'), findsNothing);
      expect(container.read(testDriveProvider).isRunning, isFalse);
    });

    testWidgets('one bus can be added with its own route, way and speed', (
      tester,
    ) async {
      final container = await pumpApp(tester, network: _network);
      await open(tester);

      await tester.tap(find.text('Add a bus'));
      await tester.pumpAndSettle();
      expect(find.text('Add a test bus'), findsOneWidget);
      // The other way round.
      await tester.tap(find.text('University → Club'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add this bus'));
      await tester.pumpAndSettle();

      final bus = container.read(testDriveProvider).buses.single;
      expect(bus.routeId, 'r1');
      expect(bus.towardsStart, isTrue);
      expect(bus.speedKmh, 40);
      expect(find.text('TEST 1'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove TEST 1'));
      await tester.pumpAndSettle();
      expect(container.read(testDriveProvider).buses, isEmpty);
    });

    testWidgets('says so when there is no route to drive along', (
      tester,
    ) async {
      await pumpApp(tester);
      await open(tester);

      expect(find.textContaining('no route on the map'), findsOneWidget);
      expect(find.text('Start the test'), findsNothing);
    });
  });
}
