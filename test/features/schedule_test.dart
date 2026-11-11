import 'dart:io';

import 'package:bu_bus_tracker/features/schedule/presentation/schedule_view.dart';
import 'package:bu_bus_tracker/core/utils/formatting.dart';
import 'package:bu_bus_tracker/features/schedule/data/bus_schedule_parser.dart';
import 'package:bu_bus_tracker/features/schedule/domain/bus_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// The schedule file that ships with the app.
BusSchedule _official() => const BusScheduleParser().parse(
  File('assets/data/schedule.json').readAsStringSync(),
);

String _minimal({
  String time = '08:30',
  String group = 'student',
  String trips = '',
}) {
  final tripList = trips.isEmpty
      ? '[{"time": "$time", "vehicles": {"bn": "ক", "en": "A"}}]'
      : trips;
  return '''
{
  "groups": [{"id": "student", "name": "Student"}],
  "timetables": [{
    "group": "$group",
    "route": "01",
    "stops": [],
    "departures": [{"from": {"bn": "খ", "en": "B"}, "trips": $tripList}]
  }]
}''';
}

void main() {
  group('formatClockTime', () {
    test('writes twelve-hour times', () {
      expect(formatClockTime(0), '12:00 AM');
      expect(formatClockTime(7 * 60 + 45), '7:45 AM');
      expect(formatClockTime(12 * 60), '12:00 PM');
      expect(formatClockTime(12 * 60 + 10), '12:10 PM');
      expect(formatClockTime(22 * 60), '10:00 PM');
    });
  });

  group('The official schedule file', () {
    test('has every group, route and departure that was recorded', () {
      final schedule = _official();

      expect(schedule.groups.map((group) => group.name), [
        'Student',
        'Teacher',
        'Staff',
      ]);
      expect(schedule.timetablesFor('student').map((t) => t.routeNumber), [
        '01',
        '02',
        '03',
      ]);
      expect(schedule.timetablesFor('teacher').map((t) => t.routeNumber), [
        '04',
        '05',
        '06',
        '07',
      ]);
      expect(schedule.timetablesFor('staff').map((t) => t.routeNumber), [
        '04',
        '05',
        '06',
        '08',
      ]);

      final departures = schedule.timetables
          .expand((timetable) => timetable.departures)
          .expand((point) => point.trips);
      expect(departures, hasLength(101));
      expect(schedule.recordedOn, DateTime(2026, 11, 10));
    });

    test('reads student route 01 as written', () {
      final route = _official().timetablesFor('student').first;

      expect(route.stops.map((stop) => stop.bn), [
        'বরিশাল ক্লাব',
        'বাংলাবাজার মোড়',
        'নুরিয়া স্কুল',
        'আমতলার মোড়',
        'রুপাতলী হাউজিং',
        'কাঠালতলা',
        'টোলঘর',
        'বিশ্ববিদ্যালয়',
      ]);
      expect(route.departures.map((point) => point.from.en), [
        'University',
        'Barishal Club',
      ]);
      expect(route.departures[0].trips, hasLength(12));
      expect(route.departures[1].trips, hasLength(13));

      final first = route.departures[0].trips.first;
      expect(first.minutes, 8 * 60 + 30);
      expect(first.vehicles.bn, 'বৈকালি, বিআরটিসি-০৬');
      expect(first.vehicles.en, 'Boikali, BRTC-06');
    });

    test('lists stops only for the routes whose stops were published', () {
      final schedule = _official();

      for (final timetable in schedule.timetables) {
        final expectStops = timetable.groupId == 'student';
        expect(
          timetable.stops.isNotEmpty,
          expectStops,
          reason: '${timetable.groupId} route ${timetable.routeNumber}',
        );
      }
    });

    test('has each place\'s departures in time order', () {
      for (final timetable in _official().timetables) {
        for (final point in timetable.departures) {
          final times = [for (final trip in point.trips) trip.minutes];
          expect(
            times,
            [...times]..sort(),
            reason:
                '${timetable.groupId} route ${timetable.routeNumber} from '
                '${point.from.en}',
          );
        }
      }
    });

    test('has no Bangla left in the English text, and no empty text', () {
      final bangla = RegExp(r'[ঀ-৿]');
      for (final timetable in _official().timetables) {
        final texts = [
          ...timetable.stops,
          for (final point in timetable.departures) ...[
            point.from,
            for (final trip in point.trips) trip.vehicles,
          ],
        ];
        for (final text in texts) {
          expect(bangla.hasMatch(text.en), isFalse, reason: text.en);
          expect(bangla.hasMatch(text.bn), isTrue, reason: text.bn);
        }
      }
    });
  });

  group('BusScheduleParser', () {
    const parser = BusScheduleParser();

    test('reads a minimal schedule', () {
      final schedule = parser.parse(_minimal());

      expect(
        schedule.timetables.single.departures.single.trips.single.minutes,
        510,
      );
      expect(schedule.recordedOn, isNull);
    });

    test('refuses a time that is not a time', () {
      for (final time in ['8:30', '25:00', '08:61', 'soon']) {
        expect(
          () => parser.parse(_minimal(time: time)),
          throwsFormatException,
          reason: time,
        );
      }
    });

    test('refuses a timetable for a group that does not exist', () {
      expect(
        () => parser.parse(_minimal(group: 'visitors')),
        throwsFormatException,
      );
    });

    test('refuses a departure place with no trips', () {
      expect(() => parser.parse(_minimal(trips: '[]')), throwsFormatException);
    });

    test('refuses text that is not JSON', () {
      expect(() => parser.parse('not json'), throwsFormatException);
    });
  });

  group('Routes tab, schedule', () {
    testWidgets('opens on the schedule, on the first student route', (
      tester,
    ) async {
      await pumpApp(tester, schedule: _official());
      await openTab(tester, 'Routes');

      expect(find.widgetWithText(ChoiceChip, 'Route 01'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Route 03'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Route 04'), findsNothing);
      expect(find.text('From University  ·  বিশ্ববিদ্যালয়'), findsOneWidget);
      // 8:30 AM leaves from both ends of the route.
      expect(find.text('8:30 AM'), findsWidgets);
      expect(find.text('Boikali, BRTC-06'), findsWidgets);
      expect(find.text('বৈকালি, বিআরটিসি-০৬'), findsWidgets);
    });

    testWidgets('choosing a route shows that route', (tester) async {
      await pumpApp(tester, schedule: _official());
      await openTab(tester, 'Routes');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Route 02'));
      await tester.pumpAndSettle();

      expect(find.text('7:45 AM'), findsOneWidget);
      expect(find.text('Sugandha'), findsWidgets);
      expect(find.text('Boikali, BRTC-06'), findsNothing);
    });

    testWidgets('choosing a group shows its routes', (tester) async {
      await pumpApp(tester, schedule: _official());
      await openTab(tester, 'Routes');

      await tester.tap(find.text('Teacher'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Route 04'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Route 07'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Route 01'), findsNothing);
      expect(find.text('2:00 PM'), findsOneWidget);
      expect(find.text('Micro-04'), findsOneWidget);

      await tester.tap(find.text('Staff'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Route 08'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Route 07'), findsNothing);
      // Staff route 04: one departure each way, both by Agunmukha. One
      // direction is shown at a time.
      expect(find.text('Chowmatha Mor  →  University'), findsOneWidget);
      expect(find.text('Agunmukha'), findsOneWidget);
      expect(find.text('8:30 AM'), findsOneWidget);

      await tester.tap(find.byTooltip('Switch direction'));
      await tester.pumpAndSettle();
      expect(find.text('University  →  Chowmatha Mor'), findsOneWidget);
      expect(find.text('Agunmukha'), findsOneWidget);
      expect(find.text('4:05 PM'), findsOneWidget);
      expect(find.text('8:30 AM'), findsNothing);
    });

    testWidgets('the direction switch shows the other way\'s departures', (
      tester,
    ) async {
      await pumpApp(tester, schedule: _official());
      await openTab(tester, 'Routes');

      // Student route 01 opens on the buses leaving the University.
      expect(find.text('University  →  Barishal Club'), findsOneWidget);
      expect(find.text('From University  ·  বিশ্ববিদ্যালয়'), findsOneWidget);
      expect(find.text('12 departures'), findsOneWidget);
      expect(find.text('9:30 AM'), findsOneWidget);
      expect(find.text('7:30 AM'), findsNothing);

      await tester.tap(find.byTooltip('Switch direction'));
      await tester.pumpAndSettle();

      expect(find.text('Barishal Club  →  University'), findsOneWidget);
      expect(find.text('University  →  Barishal Club'), findsNothing);
      expect(find.text('13 departures'), findsOneWidget);
      expect(find.text('7:30 AM'), findsOneWidget);
      expect(find.text('9:30 AM'), findsNothing);

      // And back again.
      await tester.tap(find.byTooltip('Switch direction'));
      await tester.pumpAndSettle();
      expect(find.text('University  →  Barishal Club'), findsOneWidget);

      // Another route starts from its own first direction.
      await tester.tap(find.byTooltip('Switch direction'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Route 02'));
      await tester.pumpAndSettle();
      expect(
        find.text('University  →  Notun Bazar (Tempo Stand)'),
        findsOneWidget,
      );
    });

    test('where a direction is going, and which way round its stops run', () {
      final route01 = _official().timetables.firstWhere(
        (timetable) =>
            timetable.groupId == 'student' && timetable.routeNumber == '01',
      );
      final fromUniversity = route01.departures.first;
      final fromClub = route01.departures.last;

      expect(scheduleDestination(route01, fromUniversity), 'Barishal Club');
      expect(scheduleDestination(route01, fromClub), 'University');
      // The stops are listed from Barishal Club to the University.
      expect(scheduleRunsBackwards(route01, fromClub), isFalse);
      expect(scheduleRunsBackwards(route01, fromUniversity), isTrue);

      // A route that lists no stops: the other departure place.
      final staff04 = _official().timetables.firstWhere(
        (timetable) =>
            timetable.groupId == 'staff' && timetable.routeNumber == '04',
      );
      expect(
        scheduleDestination(staff04, staff04.departures.first),
        'University',
      );
      expect(scheduleRunsBackwards(staff04, staff04.departures.first), isFalse);
    });

    testWidgets('switching direction keeps the place scrolled to', (
      tester,
    ) async {
      await pumpApp(tester, schedule: _official());
      await openTab(tester, 'Routes');
      final list = find
          .descendant(
            of: find.byKey(const ValueKey('schedule')),
            matching: find.byType(Scrollable),
          )
          .first;
      double scrolled() => tester.state<ScrollableState>(list).position.pixels;

      await tester.drag(
        find.byKey(const ValueKey('schedule')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final before = scrolled();
      expect(before, greaterThan(300));

      await tester.tap(find.byTooltip('Switch direction'));
      // Part-way through, the old and the new times are both there: one
      // fades out as the other fades in.
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.textContaining('From University'), findsOneWidget);
      expect(find.textContaining('From Barishal Club'), findsOneWidget);
      await tester.pumpAndSettle();

      // The other direction, at the same place on the page.
      expect(find.text('Barishal Club  →  University'), findsOneWidget);
      expect(find.textContaining('From University'), findsNothing);
      expect(scrolled(), before);
    });

    test('student route 02 lists every place it calls at', () {
      final route02 = _official().timetables.firstWhere(
        (timetable) =>
            timetable.groupId == 'student' && timetable.routeNumber == '02',
      );

      // From Karim Kutir it runs by Chowmatha and then as routes 01 and 03
      // do, as the owner described.
      expect(route02.stops.map((stop) => stop.primary), [
        'Notun Bazar (Tempo Stand)',
        'Munshi Garage',
        'Opsonin Mor',
        'Bottola Mor',
        'Karim Kutir',
        'Chowmatha Mor',
        'Thana Council Main Gate',
        'Amtala Mor',
        'Rupatoli Housing',
        'Kathaltola',
        'Toll Ghar',
        'University',
      ]);
    });

    testWidgets('a route with one departure place has nothing to switch', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Routes');

      expect(find.text('From Test Place'), findsOneWidget);
      expect(find.byTooltip('Switch direction'), findsNothing);
    });

    testWidgets('lists the stops, or says the schedule does not give them', (
      tester,
    ) async {
      await pumpApp(tester, schedule: _official());
      await openTab(tester, 'Routes');

      final stops = find.text('Stops on route 01');
      await tester.scrollUntilVisible(
        stops,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('schedule')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.scrollUntilVisible(
        find.text('Barishal Club  ⇄  University'),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('schedule')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('in both directions'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Toll Ghar'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('schedule')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('টোলঘর'), findsOneWidget);

      // The route runs between its first and last places, both ways.
      await tester.scrollUntilVisible(
        find.text('University'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('schedule')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Start / end'), findsWidgets);

      await tester.drag(
        find.byKey(const ValueKey('schedule')),
        const Offset(0, 5000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teacher'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not list the stops'), findsOneWidget);
    });

    testWidgets('who you are and the route stay in reach while scrolling', (
      tester,
    ) async {
      await pumpApp(tester, schedule: _official());
      await openTab(tester, 'Routes');
      final teacher = find.text('Teacher');
      final chip = find.widgetWithText(ChoiceChip, 'Route 02');
      final teacherAt = tester.getTopLeft(teacher);
      final chipAt = tester.getTopLeft(chip);

      // Scroll the timetable a long way down.
      await tester.drag(
        find.byKey(const ValueKey('schedule')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      // Both selectors are exactly where they were, and still work.
      expect(tester.getTopLeft(teacher), teacherAt);
      expect(tester.getTopLeft(chip), chipAt);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      // The new timetable is shown from its top.
      expect(find.text('Student route 02'), findsOneWidget);
    });

    testWidgets('says where the schedule comes from and what it leaves out', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTab(tester, 'Routes');

      // The note is at the foot of the timetable: scroll down to it.
      await tester.scrollUntilVisible(
        find.textContaining('as of 10 November 2026'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('schedule')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('as of 10 November 2026'), findsOneWidget);
      expect(
        find.textContaining('does not say on which days it applies'),
        findsOneWidget,
      );
    });

    testWidgets('a schedule that cannot be read is explained and retried', (
      tester,
    ) async {
      var attempts = 0;
      await pumpApp(
        tester,
        loadSchedule: () async {
          attempts++;
          if (attempts == 1) throw const FormatException('bad file');
          return sampleSchedule;
        },
      );
      await openTab(tester, 'Routes');

      expect(find.text('The schedule could not be loaded'), findsOneWidget);
      expect(find.textContaining('bad file'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Route 91'), findsOneWidget);
    });

    testWidgets('an empty schedule says so', (tester) async {
      await pumpApp(
        tester,
        schedule: const BusSchedule(
          source: '',
          recordedOn: null,
          notes: [],
          groups: [],
          timetables: [],
        ),
      );
      await openTab(tester, 'Routes');

      expect(find.text('No schedule yet'), findsOneWidget);
    });
  });
}
