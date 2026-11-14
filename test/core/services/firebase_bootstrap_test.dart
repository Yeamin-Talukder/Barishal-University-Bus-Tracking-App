import 'dart:io';

import 'package:bu_bus_tracker/core/services/firebase_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initializeFirebase', () {
    test('reports ready when Firebase starts', () async {
      final status = await initializeFirebase(initialize: () async {});

      expect(status.availability, FirebaseAvailability.ready);
      expect(status.isReady, isTrue);
    });

    test('reports not configured when there are no options', () async {
      // What the FlutterFire options throw on a platform that has none.
      final status = await initializeFirebase(
        initialize: () async =>
            throw UnsupportedError('Not configured for this platform.'),
      );

      expect(status.availability, FirebaseAvailability.notConfigured);
      expect(status.isReady, isFalse);
      expect(status.detail, contains('Not configured'));
    });

    // The real options are not published: git holds a placeholder (see
    // FIREBASE_SETUP.md), so this reads the file as text instead of naming
    // its fields, and only checks a copy made by `flutterfire configure`.
    final options = File('lib/firebase_options.dart').readAsStringSync();
    final isPlaceholder = !options.contains('static const FirebaseOptions');
    test(
      'the generated options point at the bus tracker project',
      () {
        expect(options, contains("projectId: 'bus-tracker-162c0'"));
        expect(options, contains('asia-southeast1'));
      },
      skip: isPlaceholder
          ? 'lib/firebase_options.dart is the placeholder from git'
          : false,
    );

    test('reports failed, without throwing, for any other error', () async {
      final status = await initializeFirebase(
        initialize: () async => throw Exception('network down'),
      );

      expect(status.availability, FirebaseAvailability.failed);
      expect(status.detail, contains('network down'));
    });
  });
}
