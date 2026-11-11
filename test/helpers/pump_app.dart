import 'package:bu_bus_tracker/features/prediction/application/prediction_providers.dart';
import 'package:bu_bus_tracker/features/home/presentation/widgets/home_sheet.dart';
import 'package:bu_bus_tracker/app.dart';
import 'package:bu_bus_tracker/core/services/connectivity_service.dart';
import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:bu_bus_tracker/core/services/location_service.dart';
import 'package:bu_bus_tracker/core/services/preferences_service.dart';
import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/data/repositories/announcement_repository.dart';
import 'package:bu_bus_tracker/data/repositories/bus_location_repository.dart';
import 'package:bu_bus_tracker/data/repositories/bus_repository.dart';
import 'package:bu_bus_tracker/data/repositories/live_tracking_repository.dart';
import 'package:bu_bus_tracker/data/repositories/route_repository.dart';
import 'package:bu_bus_tracker/data/repositories/stop_repository.dart';
import 'package:bu_bus_tracker/data/repositories/transport_network_repository.dart';
import 'package:bu_bus_tracker/features/admin/data/driver_directory.dart';
import 'package:bu_bus_tracker/features/admin/data/people_repository.dart';
import 'package:bu_bus_tracker/features/admin/presentation/stop_position_picker.dart';
import 'package:bu_bus_tracker/features/auth/application/session.dart';
import 'package:bu_bus_tracker/features/auth/data/auth_repository.dart';
import 'package:bu_bus_tracker/features/auth/data/user_profile_repository.dart';
import 'package:bu_bus_tracker/features/auth/domain/user_profile.dart';
import 'package:bu_bus_tracker/features/driver/application/driver_location_source.dart';
import 'package:bu_bus_tracker/features/auth/presentation/account_section.dart';
import 'package:bu_bus_tracker/features/map/application/offline_map_service.dart';
import 'package:bu_bus_tracker/features/map/data/map_tile_repository.dart';
import 'package:bu_bus_tracker/features/map/presentation/university_map.dart';
import 'package:bu_bus_tracker/features/profile/presentation/profile_screen.dart';
import 'package:bu_bus_tracker/features/routes/presentation/routes_screen.dart';
import 'package:bu_bus_tracker/features/schedule/data/bus_schedule_repository.dart';
import 'package:bu_bus_tracker/features/schedule/domain/bus_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_fakes.dart';
import 'fakes.dart';
import 'announcement_fakes.dart';
import 'bus_fakes.dart';
import 'people_fakes.dart';
import 'schedule_fakes.dart';
import 'stop_fakes.dart';
import 'tracking_fakes.dart';

export 'auth_fakes.dart';
export 'fakes.dart';
export 'announcement_fakes.dart';
export 'bus_fakes.dart';
export 'people_fakes.dart';
export 'schedule_fakes.dart';
export 'stop_fakes.dart';
export 'tracking_fakes.dart';

/// Key of the widget that stands in for the native map in widget tests.
const Key fakeMapKey = Key('fake-map');

/// A small labelled sample network for tests.
const TransportNetwork sampleDemoNetwork = TransportNetwork(
  origin: TransportDataOrigin.demo,
  stops: [
    BusStop(id: 'a', name: 'Stop A', position: GeoPoint(22.66, 90.36)),
    BusStop(id: 'b', name: 'Stop B', position: GeoPoint(22.67, 90.35)),
  ],
  routes: [
    BusRoute(
      id: 'r1',
      name: 'Sample route',
      colorHex: '#D94A38',
      startName: 'Stop A',
      endName: 'Stop B',
      path: [GeoPoint(22.66, 90.36), GeoPoint(22.67, 90.35)],
      stopIds: ['a', 'b'],
      isActive: true,
    ),
  ],
);

/// A small made-up schedule for tests that are not about the schedule.
final BusSchedule sampleSchedule = BusSchedule(
  source: 'Test schedule',
  recordedOn: DateTime(2026, 11, 10),
  notes: const [],
  groups: const [PassengerGroup(id: 'student', name: 'Student')],
  timetables: const [
    RouteTimetable(
      groupId: 'student',
      routeNumber: '91',
      stops: [LocalizedText(bn: 'ক', en: 'Test Stop')],
      departures: [
        DeparturePoint(
          from: LocalizedText(bn: 'খ', en: 'Test Place'),
          trips: [
            ScheduledTrip(
              minutes: 510,
              vehicles: LocalizedText(bn: 'গ', en: 'Test Bus'),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Opens the Routes tab and its list of routes drawn on the map (the tab
/// opens on the schedule).
Future<void> openMapRoutes(WidgetTester tester) async {
  await openTab(tester, 'Routes');
  await tester.tap(find.widgetWithText(Tab, RoutesScreen.mapTab));
  await tester.pumpAndSettle();
}

/// Opens a bottom navigation tab. Found by its type because a tab's name can
/// also appear as a heading on screen.
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
}

/// Opens the Profile tab and scrolls to the drivers and staff section, which
/// sits below the settings passengers use.
Future<void> openAccountSection(WidgetTester tester) async {
  await openTab(tester, 'Profile');
  final section = find.byType(AccountSection);
  await tester.scrollUntilVisible(
    section,
    120,
    scrollable: find
        .descendant(
          of: find.byType(ProfileScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(section);
  await tester.pumpAndSettle();
}

/// Pumps the whole app with the native map, storage and backend replaced by
/// test doubles. Returns the container so tests can read providers.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  FirebaseStatus firebaseStatus = const FirebaseStatus(
    FirebaseAvailability.notConfigured,
  ),
  TransportNetwork network = TransportNetwork.empty,
  Future<TransportNetwork> Function()? loadNetwork,
  List<TrackedBus> buses = const [],
  DateTime? now,
  LocationService? locationService,
  MapTileRepository? mapTileRepository,
  ConnectivityService? connectivityService,
  AuthRepository? authRepository,
  UserProfileRepository? userProfileRepository,
  BusSchedule? schedule,
  StopRepository? stopRepository,
  TimetableRepository? timetableRepository,
  BusRepository? busRepository,
  List<UserProfile> drivers = const [],
  PeopleRepository? peopleRepository,
  AnnouncementRepository? announcementRepository,
  FakeTracking? tracking,
  DriverLocationSource? driverLocationSource,
  List<BusStop> suggestedStops = const [],
  Future<BusSchedule> Function()? loadSchedule,
}) async {
  SharedPreferences.setMockInitialValues({});
  final fakeTracking = tracking ?? FakeTracking();
  final preferences = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      firebaseStatusProvider.overrideWithValue(firebaseStatus),
      transportNetworkProvider.overrideWith(
        (ref) => loadNetwork == null ? Future.value(network) : loadNetwork(),
      ),
      reportedBusesProvider.overrideWith((ref) => Stream.value(buses)),
      // The real one ticks every two seconds for ever.
      predictionTickProvider.overrideWith((ref) => const Stream<int>.empty()),
      // The schedule built into the app. What passengers see also depends
      // on the timetables in the (fake) database.
      bundledScheduleProvider.overrideWith(
        (ref) => loadSchedule == null
            ? Future.value(schedule ?? sampleSchedule)
            : loadSchedule(),
      ),
      busRepositoryProvider.overrideWithValue(
        busRepository ?? FakeBusRepository(),
      ),
      driversProvider.overrideWith((ref) => Stream.value(drivers)),
      routeRepositoryProvider.overrideWithValue(
        const UnavailableRouteRepository(),
      ),
      liveTrackingRepositoryProvider.overrideWithValue(fakeTracking),
      trackingAccessProvider.overrideWithValue(fakeTracking),
      driverLocationSourceProvider.overrideWithValue(
        driverLocationSource ?? FakeDriverLocationSource(),
      ),
      announcementRepositoryProvider.overrideWithValue(
        announcementRepository ?? FakeAnnouncementRepository(),
      ),
      peopleRepositoryProvider.overrideWithValue(
        peopleRepository ?? FakePeopleRepository(),
      ),
      timetableRepositoryProvider.overrideWithValue(
        timetableRepository ?? FakeTimetableRepository(),
      ),
      if (now != null) clockProvider.overrideWithValue(() => now),
      mapTileRepositoryProvider.overrideWithValue(
        mapTileRepository ?? FakeMapTileRepository(),
      ),
      connectivityServiceProvider.overrideWithValue(
        connectivityService ?? FakeConnectivityService(),
      ),
      stopRepositoryProvider.overrideWithValue(
        stopRepository ?? FakeStopRepository(),
      ),
      suggestedStopsProvider.overrideWith((ref) => suggestedStops),
      stopPickerMapBuilderProvider.overrideWithValue(
        (context, initial, onMoved, moveTo) =>
            FakeStopPicker(initial: initial, onMoved: onMoved, moveTo: moveTo),
      ),
      // Never the real Firebase SDKs in a widget test.
      authRepositoryProvider.overrideWithValue(
        authRepository ?? FakeAuthRepository(),
      ),
      userProfileRepositoryProvider.overrideWithValue(
        userProfileRepository ?? FakeUserProfileRepository(),
      ),
      universityMapBuilderProvider.overrideWithValue(
        (context) => const ColoredBox(key: fakeMapKey, color: Colors.grey),
      ),
      if (locationService != null)
        locationServiceProvider.overrideWithValue(locationService),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const BuBusTrackerApp(),
    ),
  );
  if (loadNetwork == null) {
    await tester.pumpAndSettle();
  } else {
    // A test controlling the load decides when things settle.
    await tester.pump();
  }
  return container;
}

/// Narrows [finder] to the sheet over the map. A route's name is also on
/// its chip above the map, so a bare text finder would match twice.
Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(HomeSheet), matching: finder);
