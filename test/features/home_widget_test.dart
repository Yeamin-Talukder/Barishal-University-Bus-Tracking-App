import 'dart:convert';

import 'package:bu_bus_tracker/data/models/bus.dart';
import 'package:bu_bus_tracker/features/home_widget/application/home_widget_sync.dart';
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
        DeparturePoint(from: t('Notun Bazar'), trips: [trip(7, 45, '')]),
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

  test('the bus name leads; the route stands in when none is named', () {
    final all = widgetDepartures(schedule, const WidgetChoice());
    expect(all.first.headline, 'Chitra');
    expect(all[1].headline, 'Route 02');
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

  test('one timetable serves every widget, each with its own choice', () {
    final timetable = WidgetTimetable.fromSchedule(schedule);
    expect(timetable.groups.keys, containsAll(['student', 'teacher']));
    expect(timetable.departuresFor(const WidgetChoice(groupId: 'teacher')), [
      isA<WidgetDeparture>().having((d) => d.vehicles, 'bus', 'Micro-02'),
    ]);
    expect(timetable.routesFor('student'), ['01', '02']);
    expect(
      timetable.titleFor(const WidgetChoice(route: '01')),
      'Student · Route 01',
    );
  });

  test('the saved timetable reads back the same', () {
    final timetable = WidgetTimetable.fromSchedule(schedule);
    final json = jsonEncode(
      timetable.toJson(liveByRoute: {'01': 2}, now: DateTime(2026, 11, 14)),
    );
    final back = savedWidgetTimetable(json)!;
    expect(back.groups, timetable.groups);
    expect(back.departures, hasLength(timetable.departures.length));
    const choice = WidgetChoice(direction: WidgetDirection.toUniversity);
    expect(
      [for (final d in back.departuresFor(choice)) d.minutes],
      [for (final d in timetable.departuresFor(choice)) d.minutes],
    );
    expect((jsonDecode(json) as Map)['live'], {'01': 2});
    expect(savedWidgetTimetable(null), isNull);
    expect(savedWidgetTimetable('not json'), isNull);
  });

  group('the day', () {
    final departures = widgetDepartures(schedule, const WidgetChoice());

    test('with buses still to come', () {
      final day = WidgetDay.of(departures, 8 * 60);
      expect(day.leftToday, 3);
      expect(day.nextLabel, 'Next bus');
      expect(day.lastToday?.minutes, 840);
      expect(day.upcoming.map((u) => u.tomorrow), [false, false, false, true]);
    });

    test('with one bus left it is the last', () {
      final day = WidgetDay.of(departures, 13 * 60 + 30);
      expect(day.leftToday, 1);
      expect(day.nextLabel, 'Last bus today');
      expect(day.lastToday?.minutes, 840);
      // Tomorrow's first ones fill the list.
      expect(day.upcoming.skip(1).every((u) => u.tomorrow), isTrue);
      expect(day.upcoming[1].departure.minutes, 450);
    });

    test('after the last bus', () {
      final day = WidgetDay.of(departures, 20 * 60);
      expect(day.isOverForToday, isTrue);
      expect(day.nextLabel, 'No more buses today');
      expect(day.lastToday, isNull);
      expect(day.upcoming.first.tomorrow, isTrue);
      expect(day.upcoming.first.departure.minutes, 450);
    });

    test('with no buses at all', () {
      final day = WidgetDay.of(const [], 600);
      expect(day.upcoming, isEmpty);
      expect(day.isOverForToday, isFalse);
    });
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

  test('live buses are counted by route', () {
    Bus bus(String id, String? route) =>
        Bus(id: id, number: id, name: id, routeId: route, isActive: true);
    final buses = [
      TrackedBus(bus: bus('a', '01')),
      TrackedBus(bus: bus('b', '02')),
      TrackedBus(bus: bus('c', '01')),
      TrackedBus(bus: bus('d', null)),
    ];
    final live = liveCountsByRoute(buses, (_) => true);
    expect(live, {'01': 2, '02': 1});
    expect(liveCountFor(live, const WidgetChoice()), 3);
    expect(liveCountFor(live, const WidgetChoice(route: '01')), 2);
    expect(liveCountFor(live, const WidgetChoice(route: '07')), 0);
    expect(liveCountsByRoute(buses, (_) => false), isEmpty);
  });

  test('a tapped departure is read from what the widget sends', () {
    final d = TappedDeparture.fromMap({
      'route': '01',
      'from': 'University',
      'minutes': 795,
    })!;
    expect((d.route, d.from, d.minutes), ('01', 'University', 795));
    expect(TappedDeparture.fromMap({'route': ''}), isNull);
    expect(TappedDeparture.fromMap(null), isNull);
  });
}
