import 'dart:async';
import 'dart:io';

import 'package:bu_bus_tracker/core/services/preferences_service.dart';
import 'package:bu_bus_tracker/core/theme/app_theme.dart';
import 'package:bu_bus_tracker/features/app_update/application/update_controller.dart';
import 'package:bu_bus_tracker/features/app_update/data/apk_downloader.dart';
import 'package:bu_bus_tracker/features/app_update/data/app_installer.dart';
import 'package:bu_bus_tracker/features/app_update/data/release_feed.dart';
import 'package:bu_bus_tracker/features/app_update/domain/app_release.dart';
import 'package:bu_bus_tracker/features/app_update/presentation/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = UpdateSource.downloadPrefix;

Map<String, Object?> _release(String tag, List<String> files, {bool pre = false, String body = ''}) => {
      'tag_name': tag,
      'name': 'BU Bus Tracker $tag',
      'prerelease': pre,
      'draft': false,
      'published_at': '2026-11-20T10:00:00Z',
      'html_url': 'https://github.com/x/y/releases/tag/$tag',
      'body': body,
      'assets': [
        for (final f in files)
          {'name': f, 'size': 1000, 'download_count': 3, 'browser_download_url': '$_base$tag/$f', 'digest': 'sha256:abc'},
      ],
    };

class _FakeFeed implements ReleaseFeed {
  _FakeFeed(this.json);
  Object? json;
  bool fail = false;
  @override
  Future<List<AppRelease>> fetch() async {
    if (fail) throw const ReleaseFeedException('offline');
    return parseReleases(json);
  }
}

class _FakeInstaller implements AppInstaller {
  bool allowed = true;
  final installed = <String>[];
  final _outcomes = StreamController<({InstallOutcome outcome, String? message})>.broadcast();
  void report(InstallOutcome o) => _outcomes.add((outcome: o, message: null));

  @override
  Future<InstalledApp> installedApp() async =>
      const InstalledApp(versionName: '1.0.0', versionCode: 2001, abis: ['arm64-v8a', 'armeabi-v7a']);
  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> openInstallPermission() async {}
  @override
  Future<void> install(String apkPath) async => installed.add(apkPath);
  @override
  Stream<({InstallOutcome outcome, String? message})> get outcomes => _outcomes.stream;
}

class _FakeDownloader implements ApkDownloader {
  Object? error;
  Completer<void>? gate;
  @override
  Future<File> download(ReleaseApk apk,
      {required void Function(int, int) onProgress, required void Function() onVerifying, required CancelToken cancel}) async {
    onProgress(0, apk.size);
    if (gate != null) await gate!.future;
    if (cancel.isCancelled) throw const DownloadCancelled();
    onProgress(apk.size, apk.size);
    onVerifying();
    if (error != null) throw error!;
    return File('/tmp/${apk.name}');
  }

  @override
  Future<void> clear() async {}
}

void main() {
  group('Versions', () {
    test('compare part by part, a pre-release below its release', () {
      AppVersion v(String s) => AppVersion.tryParse(s)!;
      expect(v('1.0.10') > v('1.0.9'), isTrue);
      expect(v('v1.1.0') > v('1.0.0+7'), isTrue);
      expect(v('1.1.0') > v('1.1.0-beta'), isTrue);
      expect(v('1.2') == v('1.2.0'), isTrue);
      expect(AppVersion.tryParse('latest'), isNull);
    });
  });

  group('Choosing the update', () {
    final releases = parseReleases({
      'releases': [
        _release('v1.2.0-beta', ['app-v1.2.0-arm64.apk'], pre: true),
        _release('v1.1.0', ['app-v1.1.0-arm64.apk', 'app-v1.1.0-armv7.apk']),
        _release('v1.0.0', ['app-v1.0.0-arm64.apk']),
      ],
    });

    test('takes the newest newer release with a build for the phone', () {
      final found = findUpdate(releases, current: const AppVersion(1, 0, 0), abis: ['arm64-v8a']);
      expect(found!.release.tag, 'v1.1.0');
      expect(found.apk.build, ApkBuild.arm64);
    });

    test('a 32-bit phone gets the 32-bit build', () {
      final found = findUpdate(releases, current: const AppVersion(1, 0, 0), abis: ['armeabi-v7a']);
      expect(found!.apk.name, 'app-v1.1.0-armv7.apk');
    });

    test('pre-releases only when asked for', () {
      final found = findUpdate(releases,
          current: const AppVersion(1, 1, 0), abis: ['arm64-v8a'], includePreReleases: true);
      expect(found!.release.tag, 'v1.2.0-beta');
      expect(findUpdate(releases, current: const AppVersion(1, 1, 0), abis: ['arm64-v8a']), isNull);
    });

    test('files from anywhere else are never offered', () {
      final foreign = parseReleases([
        {
          'tag_name': 'v9.0.0',
          'assets': [
            {'name': 'evil-arm64.apk', 'size': 1, 'browser_download_url': 'https://example.com/evil-arm64.apk'},
          ],
        },
      ]);
      expect(findUpdate(foreign, current: const AppVersion(1, 0, 0), abis: ['arm64-v8a']), isNull);
    });

    test('release notes lose their Markdown', () {
      expect(plainReleaseNotes('## New\n\n- **Faster** map\n- See [the site](https://x)\n\n\n'), 'New\n\n• Faster map\n• See the site');
    });
  });

  group('Update controller', () {
    late _FakeFeed feed;
    late _FakeInstaller installer;
    late _FakeDownloader downloader;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      feed = _FakeFeed({
        'releases': [_release('v1.1.0', ['app-v1.1.0-arm64.apk'])],
      });
      installer = _FakeInstaller();
      downloader = _FakeDownloader();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        releaseFeedProvider.overrideWithValue(feed),
        appInstallerProvider.overrideWithValue(installer),
        apkDownloaderProvider.overrideWithValue(downloader),
      ]);
      addTearDown(container.dispose);
    });

    UpdateController notifier() => container.read(updateControllerProvider.notifier);
    UpdateState state() => container.read(updateControllerProvider);

    test('finds the update, downloads it and hands it to Android', () async {
      await notifier().check();
      expect(state(), isA<UpdateAvailable>());
      await notifier().download();
      expect(state(), isA<UpdateInstalling>());
      expect(installer.installed.single, endsWith('app-v1.1.0-arm64.apk'));
    });

    test('up to date when nothing newer is published', () async {
      feed.json = {
        'releases': [_release('v1.0.0', ['app-v1.0.0-arm64.apk'])],
      };
      await notifier().check(userAsked: true);
      expect(state(), isA<UpdateUpToDate>());
    });

    test('asks for the install permission first, then installs on return', () async {
      installer.allowed = false;
      await notifier().check();
      await notifier().download();
      expect(state(), isA<UpdateNeedsPermission>());
      installer.allowed = true;
      await notifier().onResumed();
      expect(state(), isA<UpdateInstalling>());
    });

    test('a file that does not match its checksum is not installed', () async {
      downloader.error = const ChecksumMismatch();
      await notifier().check();
      await notifier().download();
      expect(state(), isA<UpdateFailed>());
      expect((state() as UpdateFailed).retry, isA<UpdateAvailable>());
      expect(installer.installed, isEmpty);
    });

    test('cancelling the download goes back to the offer', () async {
      downloader.gate = Completer<void>();
      await notifier().check();
      final running = notifier().download();
      await Future<void>.delayed(Duration.zero);
      expect(state(), isA<UpdateDownloading>());
      notifier().cancelDownload();
      downloader.gate!.complete();
      await running;
      expect(state(), isA<UpdateAvailable>());
    });

    test('a cancelled install keeps the file ready', () async {
      await notifier().check();
      await notifier().download();
      installer.report(InstallOutcome.cancelled);
      await Future<void>.delayed(Duration.zero);
      expect(state(), isA<UpdateReady>());
    });

    test('a different signing key explains what to do', () async {
      await notifier().check();
      await notifier().download();
      installer.report(InstallOutcome.conflict);
      await Future<void>.delayed(Duration.zero);
      expect((state() as UpdateFailed).message, contains('Uninstall the app once'));
    });

    test('a failed automatic check stays quiet; "Later" stops the offer', () async {
      feed.fail = true;
      await notifier().check();
      expect(state(), isA<UpdateIdle>());
      feed.fail = false;
      await notifier().check(userAsked: true);
      final offer = state() as UpdateAvailable;
      expect(notifier().shouldOffer(offer.release), isTrue);
      await notifier().later();
      expect(notifier().shouldOffer(offer.release), isFalse);
    });
  });

  testWidgets('the sheet offers the update with its notes and size', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      releaseFeedProvider.overrideWithValue(_FakeFeed({
        'releases': [_release('v1.1.0', ['app-v1.1.0-arm64.apk'], body: '- Faster map')],
      })),
      appInstallerProvider.overrideWithValue(_FakeInstaller()),
      apkDownloaderProvider.overrideWithValue(_FakeDownloader()),
    ]);
    addTearDown(container.dispose);
    await container.read(updateControllerProvider.notifier).check();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: UpdateSheet())),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('1.1.0'), findsOneWidget);
    expect(find.text('• Faster map'), findsOneWidget);
    expect(find.textContaining('Download and install'), findsOneWidget);
  });
}
