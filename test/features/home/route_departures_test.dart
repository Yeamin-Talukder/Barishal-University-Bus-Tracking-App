import 'package:bu_bus_tracker/core/services/eta_service.dart';
import 'package:bu_bus_tracker/data/models/bus_route.dart';
import 'package:bu_bus_tracker/data/models/bus_stop.dart';
import 'package:bu_bus_tracker/data/models/geo_point.dart';
import 'package:bu_bus_tracker/data/models/transport_network.dart';
import 'package:bu_bus_tracker/features/home/application/route_departures.dart';
import 'package:bu_bus_tracker/features/home/presentation/widgets/timetable_buses.dart';
import 'package:bu_bus_tracker/features/map/application/map_selection.dart';
import 'package:bu_bus_tracker/features/map/application/map_view_state.dart';
import 'package:bu_bus_tracker/features/map/application/predicted_bus_layer.dart';
import 'package:bu_bus_tracker/features/prediction/domain/prediction.dart';
import 'package:bu_bus_tracker/features/schedule/domain/bus_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

// A route about one kilometre long, from the Club north to the University,
// with a stop half-way.
const _route = BusRoute(
  id: '01',
  name: 'Route 01',
  colorHex: '#E53945',
  startName: 'Club',
  endName: 'University',
  path: [
    GeoPoint(22.7000, 90.3600),
    GeoPoint(22.7045, 90.3600),
    GeoPoint(22.7090, 90.3600),
  ],
  stopIds: ['club', 'middle', 'university'],
  isActive: true,
);

const _network = TransportNetwork(
  origin: TransportDataOrigin.verified,
  stops: [
    BusStop(id: 'club', name: 'Club', position: GeoPoint(22.7000, 90.3600)),
    BusStop(id: 'middle', name: 'Middle', position: GeoPoint(22.7045, 90.3600)),
    BusStop(
      id: 'university',
      name: 'University',
      position: GeoPoint(22.7090, 90.3600),
    ),
  ],
  routes: [_route],
);

ScheduledTrip _trip(int hour, int minute, String buses) => ScheduledTrip(
  minutes: hour * 60 + minute,
  vehicles: LocalizedText(en: buses),
);

/// From the University: 9:00 Chitra, 10:00 "Boikali, BRTC-06".
/// From the Club: 9:10 Lota, 16:40 Jayanti.
final _schedule = BusSchedule(
  source: 'Test schedule',
  recordedOn: null,
  notes: const [],
  groups: const [
    PassengerGroup(id: 'student', name: 'Student'),
    PassengerGroup(id: 'staff', name: 'Staff'),
  ],
  timetables: [
    RouteTimetable(
      groupId: 'student',
      routeNumber: '01',
      stops: const [],
      departures: [
        DeparturePoint(
          from: const LocalizedText(en: 'University'),
          trips: [_trip(10, 0, 'Boikali, BRTC-06'), _trip(9, 0, 'Chitra')],
        ),
        DeparturePoint(
          from: const LocalizedText(en: 'Club'),
          trips: [_trip(9, 10, 'Lota'), _trip(16, 40, 'Jayanti')],
        ),
      ],
    ),
    // Another group's timetable names the same 9:00 departure, with one
    // more bus, and a route that is not on the map.
    RouteTimetable(
      groupId: 'staff',
      routeNumber: '01',
      stops: const [],
      departures: [
        DeparturePoint(
          from: const LocalizedText(en: 'University'),
          trips: [_trip(9, 0, 'Micro-05')],
        ),
      ],
    ),
    RouteTimetable(
      groupId: 'staff',
      routeNumber: '08',
      stops: const [],
      departures: [
        DeparturePoint(
          from: const LocalizedText(en: 'University'),
          trips: [_trip(9, 5, 'Ilisha')],
        ),
      ],
    ),
  ],
);

DateTime _at(int hour, int minute) => DateTime(2026, 11, 11, hour, minute);

/// Text inside the "which bus" list. A stop's page names buses under its
/// predicted arrivals as well.
Finder inList(String text) =>
    find.descendant(of: find.byType(TimetableBuses), matching: find.text(text));

void main() {
  group('Which bus runs a departure', () {
    test('each departure names its buses and says which way it goes', () {
      final all = departuresOn(
        schedule: _schedule,
        route: _route,
        day: _at(0, 0),
      );

      expect(all.map((d) => d.at), [
        _at(9, 0),
        _at(9, 10),
        _at(10, 0),
        _at(16, 40),
      ]);
      // From the University the bus runs the route backwards, to the Club.
      expect(all[0].reversed, isTrue);
      expect((all[0].fromName, all[0].toName), ('University', 'Club'));
      expect(all[1].reversed, isFalse);
      expect((all[1].fromName, all[1].toName), ('Club', 'University'));
      expect(all[1].buses, 'Lota');
      expect(all[2].buses, 'Boikali, BRTC-06');
    });

    test('a departure two groups list is given once, with all its buses', () {
      final first = departuresOn(
        schedule: _schedule,
        route: _route,
        day: _at(0, 0),
      ).first;

      expect(first.buses, 'Chitra, Micro-05');
    });

    test('the next ones are those that have not left yet', () {
      List<String> next(DateTime now, {bool? reversed}) => [
        for (final d in upcomingDepartures(
          schedule: _schedule,
          route: _route,
          now: now,
          reversed: reversed,
        ))
          d.buses,
      ];

      expect(next(_at(8, 0)), ['Chitra, Micro-05', 'Lota', 'Boikali, BRTC-06']);
      // A bus is still at the stand a minute or two after its time.
      expect(next(_at(9, 2)).first, 'Chitra, Micro-05');
      expect(next(_at(9, 3)).first, 'Lota');
      // One way only. Tomorrow's first follows once today's have run out.
      expect(next(_at(8, 0), reversed: true), [
        'Chitra, Micro-05',
        'Boikali, BRTC-06',
        'Chitra, Micro-05',
      ]);
      expect(next(_at(8, 0), reversed: false), ['Lota', 'Jayanti', 'Lota']);
    });

    test('after the last bus of the day it is the first one tomorrow', () {
      final next = upcomingDepartures(
        schedule: _schedule,
        route: _route,
        now: _at(22, 0),
        count: 1,
      ).single;

      expect(next.buses, 'Chitra, Micro-05');
      expect(next.at, DateTime(2026, 11, 12, 9));
      expect(departsInText(next.at, _at(22, 0)), 'tomorrow');
    });

    test('a stop lists only the buses that pick up there', () {
      List<String> at(String stopId) => [
        for (final d in upcomingDeparturesAt(
          schedule: _schedule,
          network: _network,
          stop: _network.stopById(stopId)!,
          now: _at(8, 0),
        ))
          '${d.buses} to ${d.toName}',
      ];

      // At the Club, the bus from the University only sets people down.
      expect(at('club'), ['Lota to University']);
      expect(at('university'), ['Chitra, Micro-05 to Club']);
      expect(at('middle'), ['Chitra, Micro-05 to Club', 'Lota to University']);
    });

    test('how long until it leaves is said in words', () {
      expect(departsInText(_at(9, 0), _at(9, 0)), 'now');
      expect(departsInText(_at(9, 0), _at(9, 1)), 'now');
      expect(departsInText(_at(9, 0), _at(8, 48)), 'in 12 min');
      expect(departsInText(_at(10, 5), _at(9, 0)), 'in 1 h 5 min');
      expect(departsInText(_at(11, 0), _at(9, 0)), 'in 2 h');
    });
  });

  group('Bus names on the screen', () {
    testWidgets('a route says which buses go next, each way', (tester) async {
      final container = await pumpApp(
        tester,
        network: _network,
        schedule: _schedule,
        now: _at(8, 48),
      );
      container.read(mapSelectionProvider.notifier).selectRoute('01');
      await tester.pumpAndSettle();

      expect(find.text('Which bus goes this way'), findsOneWidget);
      // Shown from the Club to the University first.
      // Three are listed: after today's two it is tomorrow's first.
      expect(inList('Lota'), findsNWidgets(2));
      expect(inList('Jayanti'), findsOneWidget);
      expect(inList('9:10 AM'), findsNWidgets(2));
      expect(inList('tomorrow'), findsOneWidget);
      expect(inList('in 22 min'), findsOneWidget);
      expect(inList('Chitra, Micro-05'), findsNothing);

      // The other way round, it is the University's buses.
      container.read(routeShownReversedProvider.notifier).toggle();
      await tester.pumpAndSettle();
      expect(inList('Chitra, Micro-05'), findsWidgets);
      expect(inList('Boikali, BRTC-06'), findsOneWidget);
      expect(inList('in 12 min'), findsOneWidget);
      expect(inList('Lota'), findsNothing);
    });

    testWidgets('a stop says which bus to take there', (tester) async {
      final container = await pumpApp(
        tester,
        network: _network,
        schedule: _schedule,
        now: _at(8, 48),
      );
      container.read(mapSelectionProvider.notifier).selectStop('university');
      await tester.pumpAndSettle();

      expect(find.text('Which bus to take here'), findsOneWidget);
      expect(inList('Chitra, Micro-05'), findsOneWidget);
      expect(inList('Route 01 → Club'), findsOneWidget);
      expect(inList('Sets off from this stop'), findsOneWidget);
      // The bus from the Club ends here.
      expect(inList('Lota'), findsNothing);
      expect(
        find.textContaining('From the timetable, not a live position.'),
        findsOneWidget,
      );
    });

    testWidgets('a stop on the way says where the bus sets off from', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        schedule: _schedule,
        now: _at(8, 48),
      );
      container.read(mapSelectionProvider.notifier).selectStop('middle');
      await tester.pumpAndSettle();

      expect(inList('Lota'), findsOneWidget);
      expect(inList('Sets off from Club, then comes this way'), findsOneWidget);
      expect(
        inList('Sets off from University, then comes this way'),
        findsOneWidget,
      );
    });

    testWidgets('with no timetable for it, a route shows no such list', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        network: _network,
        schedule: const BusSchedule(
          source: 'Empty',
          recordedOn: null,
          notes: [],
          groups: [],
          timetables: [],
        ),
        now: _at(8, 48),
      );
      container.read(mapSelectionProvider.notifier).selectRoute('01');
      await tester.pumpAndSettle();

      expect(find.text('Which bus goes this way'), findsNothing);
      expect(find.textContaining('Stops'), findsWidgets);
    });

    test('a predicted bus on the map is named as the timetable names it', () {
      PredictedBus bus(String? vehicles, PredictionBasis basis) => PredictedBus(
        id: 'p',
        label: basis == PredictionBasis.lastSeen ? 'Chitra' : 'Route 01',
        routeId: '01',
        routeName: 'Route 01',
        direction: TravelDirection.forward,
        position: const GeoPoint(22.7, 90.36),
        lineBearingDegrees: 0,
        alongMeters: 0,
        basis: basis,
        basedOn: _at(9, 0),
        fromName: 'Club',
        toName: 'University',
        usesLearnedSpeed: false,
        vehicles: vehicles,
      );

      expect(
        PredictedBusLayer.markerName(
          bus('Boikali, BRTC-06', PredictionBasis.timetable),
        ),
        'Boikali, BRTC-06',
      );
      // "One of these six" is too long to sit under a marker.
      expect(
        PredictedBusLayer.markerName(
          bus(
            'Lota/Kirtankhola/Payra/Chitra/Boikali/Jayanti',
            PredictionBasis.timetable,
          ),
        ),
        'Route 01',
      );
      expect(
        PredictedBusLayer.markerName(bus(null, PredictionBasis.timetable)),
        'Route 01',
      );
      // A bus that was seen keeps its own number.
      expect(
        PredictedBusLayer.markerName(bus(null, PredictionBasis.lastSeen)),
        'Chitra',
      );
    });
  });
}
