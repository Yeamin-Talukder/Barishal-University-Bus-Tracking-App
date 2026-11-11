import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/features/home_widget/domain/widget_snapshot.dart';
import 'package:bu_bus_tracker/features/schedule/domain/bus_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

LocalizedText t(String en) => LocalizedText(en: en);
ScheduledTrip trip(int h, int m, String v) =>
    ScheduledTrip(minutes: h * 60 + m, vehicles: t(v));

final schedule = BusSchedule(
  source: 'test',
  recordedOn: null,
  notes: const [],
  groups: BusSchedule.standardGroups,
  timetables: [
    RouteTimetable(
      groupId: 'student',
      routeNumber: '01',
      stops: [t('Barishal Club'), t('Kathaltola'), t('University')],
      departures: [
        DeparturePoint(
          from: t('University'),
          trips: [trip(13, 15, 'Jayanti'), trip(8, 30, 'Boikali')],
        ),
        DeparturePoint(
          from: t('Barishal Club'),
          trips: [trip(7, 30, 'Chitra')],
        ),
      ],
    ),
    RouteTimetable(
      groupId: 'student',
      routeNumber: '02',
      stops: const [],
      departures: [
        DeparturePoint(from: t('Notun Bazar'), trips: [trip(7, 45, 'BRTC-05')]),
        DeparturePoint(from: t('University'), trips: [trip(14, 0, 'BRTC-05')]),
      ],
    ),
    RouteTimetable(
      groupId: 'teacher',
      routeNumber: '04',
      stops: const [],
      departures: [
        DeparturePoint(from: t('University'), trips: [trip(9, 0, 'Micro-02')]),
      ],
    ),
  ],
);

void main() {
  test('every departure for the group, in time order, with where it goes', () {
    final all = widgetDepartures(
      schedule,
      const WidgetChoice(),
      routeColors: {'01': '#F2994A'},
    );
    expect([for (final d in all) d.minutes], [450, 465, 510, 795, 840]);
    final first = all.first;
    expect(first.route, '01');
    expect(first.from, 'Barishal Club');
    expect(first.to, 'University');
    expect(first.colorHex, '#F2994A');
    // A route without a stop list goes to its other departure place.
    expect(all[1].to, 'University');
    // Teacher routes are not in the student widget.
    expect(all.any((d) => d.route == '04'), isFalse);
  });

  test('one route only', () {
    final r = widgetDepartures(schedule, const WidgetChoice(route: '02'));
    expect(r.map((d) => d.route).toSet(), {'02'});
  });

  test('to campus and from campus', () {
    final to = widgetDepartures(
      schedule,
      const WidgetChoice(direction: WidgetDirection.toUniversity),
    );
    expect(to.every((d) => d.to == 'University'), isTrue);
    expect(to, hasLength(2));
    final from = widgetDepartures(
      schedule,
      const WidgetChoice(direction: WidgetDirection.fromUniversity),
    );
    expect(from.every((d) => d.from == 'University'), isTrue);
    expect(from, hasLength(3));
  });

  test('the snapshot carries the title, live count and departures', () {
    const choice = WidgetChoice(
      route: '01',
      direction: WidgetDirection.toUniversity,
    );
    final json = widgetSnapshot(
      choice: choice,
      departures: widgetDepartures(schedule, choice),
      live: 2,
      now: DateTime(2026, 11, 12, 8),
    );
    expect(json['title'], 'Student · Route 01');
    expect(json['subtitle'], 'To campus');
    expect(json['live'], 2);
    expect((json['departures'] as List).single, containsPair('veh', 'Chitra'));
  });

  test('the choice survives a restart', () {
    const choice = WidgetChoice(
      groupId: 'staff',
      route: '05',
      direction: WidgetDirection.fromUniversity,
    );
    expect(WidgetChoice.fromJson(choice.toJson()), choice);
    expect(WidgetChoice.fromJson(const {}), const WidgetChoice());
  });

  test('live buses are counted only on the chosen route', () {
    Bus bus(String id, String? route) =>
        Bus(id: id, number: id, name: id, routeId: route, isActive: true);
    final buses = [
      TrackedBus(bus: bus('a', '01')),
      TrackedBus(bus: bus('b', '02')),
      TrackedBus(bus: bus('c', '01')),
    ];
    bool live(BusLocation? _) => true;
    expect(liveBusCount(buses, const WidgetChoice(), live), 3);
    expect(liveBusCount(buses, const WidgetChoice(route: '01'), live), 2);
    expect(
      liveBusCount(buses, const WidgetChoice(route: '01'), (_) => false),
      0,
    );
  });
}
