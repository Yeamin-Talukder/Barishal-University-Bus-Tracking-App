import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

ThemeMode? _themeMode(WidgetTester tester) {
  return tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;
}

/// Taps a bottom navigation destination. Found by its type because a tab's
/// name can also appear as a heading on screen.
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
}

/// Scrolls the Profile list until [text] is on screen.
Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the map with four destinations', (tester) async {
    await pumpApp(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.byKey(fakeMapKey), findsOneWidget);
  });

  testWidgets('bottom navigation switches between the tabs', (tester) async {
    await pumpApp(tester);

    await _openTab(tester, 'Routes');
    expect(find.widgetWithText(Tab, 'Schedule'), findsOneWidget);
    expect(find.text('Route 91'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'On the map'));
    await tester.pumpAndSettle();
    expect(find.text('No routes on the map yet'), findsOneWidget);

    await _openTab(tester, 'Stops');
    expect(find.text('No stops yet'), findsOneWidget);

    await _openTab(tester, 'Profile');
    expect(find.text('Appearance'), findsOneWidget);

    await _openTab(tester, 'Home');
    expect(find.text('No live buses'), findsOneWidget);
  });

  testWidgets('choosing a theme on the profile tab applies it', (tester) async {
    await pumpApp(tester);
    // Dark is the app's own look until someone chooses otherwise.
    expect(_themeMode(tester), ThemeMode.dark);

    await _openTab(tester, 'Profile');
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.light);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.dark);
  });

  testWidgets('profile says when the tracking service is not set up', (
    tester,
  ) async {
    await pumpApp(tester);

    await _openTab(tester, 'Profile');
    await _scrollTo(tester, 'Tracking service not set up');

    expect(find.text('Tracking service not set up'), findsOneWidget);
  });

  testWidgets('profile says when the tracking service is connected', (
    tester,
  ) async {
    await pumpApp(
      tester,
      firebaseStatus: const FirebaseStatus(FirebaseAvailability.ready),
    );

    await _openTab(tester, 'Profile');
    await _scrollTo(tester, 'Connected to the tracking service');

    expect(find.text('Connected to the tracking service'), findsOneWidget);
  });
}
