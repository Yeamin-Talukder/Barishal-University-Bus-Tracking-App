import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/preferences_service.dart';
import '../data/apk_downloader.dart';
import '../data/app_installer.dart';
import '../data/release_feed.dart';
import '../domain/app_release.dart';

/// Android only: on iOS updates come from the App Store, and the web preview
/// has nothing to install.
final appInstallerProvider = Provider<AppInstaller?>((ref) {
  if (kIsWeb || !Platform.isAndroid) return null;
  return ChannelAppInstaller();
});
final releaseFeedProvider = Provider<ReleaseFeed>((ref) => GithubReleaseFeed());
final apkDownloaderProvider = Provider<ApkDownloader>(
  (ref) => HttpApkDownloader(),
);

/// Time, for tests.
final updateClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Where an update is. Each state carries what the screen needs.
sealed class UpdateState {
  const UpdateState();
}

/// Not checked yet in this run of the app.
class UpdateIdle extends UpdateState {
  const UpdateIdle({this.current});
  final AppVersion? current;
}

/// Updates are not handled inside the app on this platform.
class UpdateUnsupported extends UpdateState {
  const UpdateUnsupported();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking({this.current});
  final AppVersion? current;
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate({
    required this.current,
    required this.checkedAt,
    this.latest,
  });
  final AppVersion current;
  final DateTime checkedAt;

  /// The newest published version, which may be this one.
  final AppVersion? latest;
}

/// Something the person can act on: a release and the file for this phone.
sealed class UpdateWithRelease extends UpdateState {
  const UpdateWithRelease({
    required this.current,
    required this.release,
    required this.apk,
  });
  final AppVersion current;
  final AppRelease release;
  final ReleaseApk apk;
}

class UpdateAvailable extends UpdateWithRelease {
  const UpdateAvailable({
    required super.current,
    required super.release,
    required super.apk,
  });
}

class UpdateDownloading extends UpdateWithRelease {
  const UpdateDownloading({
    required super.current,
    required super.release,
    required super.apk,
    required this.received,
    required this.total,
    required this.bytesPerSecond,
  });
  final int received;
  final int total;
  final double bytesPerSecond;

  double? get fraction =>
      total > 0 ? (received / total).clamp(0, 1).toDouble() : null;
}

/// Checking the file against the SHA-256 GitHub published.
class UpdateVerifying extends UpdateWithRelease {
  const UpdateVerifying({
    required super.current,
    required super.release,
    required super.apk,
  });
}

class UpdateReady extends UpdateWithRelease {
  const UpdateReady({
    required super.current,
    required super.release,
    required super.apk,
    required this.file,
    this.note,
  });
  final String file;

  /// Shown above the button, e.g. after the install was cancelled.
  final String? note;
}

/// Android has to be told once that this app may install updates.
class UpdateNeedsPermission extends UpdateWithRelease {
  const UpdateNeedsPermission({
    required super.current,
    required super.release,
    required super.apk,
    required this.file,
  });
  final String file;
}

/// Handed to Android, which is asking the person to confirm.
class UpdateInstalling extends UpdateWithRelease {
  const UpdateInstalling({
    required super.current,
    required super.release,
    required super.apk,
    required this.file,
  });
  final String file;
}

class UpdateFailed extends UpdateState {
  const UpdateFailed({required this.message, this.current, this.retry});
  final String message;
  final AppVersion? current;

  /// What "Try again" goes back to: a release to download again, or null
  /// to check again.
  final UpdateWithRelease? retry;
}

class UpdateController extends Notifier<UpdateState> {
  static const String lastCheckKey = 'update.lastCheck';
  static const String laterKey = 'update.laterTag';

  InstalledApp? _app;
  CancelToken? _cancel;
  StreamSubscription<({InstallOutcome outcome, String? message})>? _outcomes;

  @override
  UpdateState build() {
    ref.onDispose(() {
      _cancel?.cancel();
      _outcomes?.cancel();
    });
    final installer = ref.watch(appInstallerProvider);
    if (installer == null) return const UpdateUnsupported();
    _outcomes = installer.outcomes.listen(_onInstallOutcome);
    return const UpdateIdle();
  }

  AppInstaller get _installer => ref.read(appInstallerProvider)!;

  /// The version installed now, once known.
  AppVersion? get currentVersion =>
      _app == null ? null : AppVersion.tryParse(_app!.versionName);

  /// Looks for a newer release. Automatic checks ([userAsked] false) happen
  /// at most every [autoCheckEvery] and are silent when they fail.
  Future<void> check({bool userAsked = false}) async {
    if (state is UpdateUnsupported) return;
    if (state is UpdateDownloading ||
        state is UpdateVerifying ||
        state is UpdateInstalling) {
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    final now = ref.read(updateClockProvider)();
    // An automatic check runs once per start of the app; it reads the
    // website's copy of the release list, which has no rate limit.
    if (!userAsked && state is! UpdateIdle) return;
    state = UpdateChecking(current: currentVersion);
    try {
      _app ??= await _installer.installedApp();
      final current = currentVersion ?? const AppVersion(0, 0, 0);
      final releases = await ref.read(releaseFeedProvider).fetch();
      await prefs.setString(lastCheckKey, now.toIso8601String());
      final found = findUpdate(releases, current: current, abis: _app!.abis);
      if (found == null) {
        final latest = releases.isEmpty
            ? null
            : releases.map((r) => r.version).reduce((a, b) => a > b ? a : b);
        state = UpdateUpToDate(
          current: current,
          checkedAt: now,
          latest: latest,
        );
        await ref.read(apkDownloaderProvider).clear();
      } else {
        state = UpdateAvailable(
          current: current,
          release: found.release,
          apk: found.apk,
        );
      }
    } catch (error) {
      if (!userAsked) {
        // A failed background check stays quiet; the Profile tab can retry.
        state = UpdateIdle(current: currentVersion);
        return;
      }
      state = UpdateFailed(
        current: currentVersion,
        message: 'Could not check for updates. Check your internet connection and try again.',
      );
    }
  }

  /// Whether an automatic check should offer this release, i.e. the person
  /// has not chosen "Later" for it.
  bool shouldOffer(AppRelease release) =>
      ref.read(sharedPreferencesProvider).getString(laterKey) != release.tag;

  /// "Later": not offered again on start-up until a newer release appears.
  Future<void> later() async {
    final s = state;
    if (s is UpdateWithRelease) {
      await ref
          .read(sharedPreferencesProvider)
          .setString(laterKey, s.release.tag);
    }
  }

  Future<void> download() async {
    final s = state;
    final UpdateWithRelease from = switch (s) {
      UpdateAvailable() || UpdateReady() => s as UpdateWithRelease,
      UpdateFailed(retry: final UpdateWithRelease r) => r,
      _ => throw StateError('Nothing to download.'),
    };
    final cancel = _cancel = CancelToken();
    final started = DateTime.now();
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    state = UpdateDownloading(
      current: from.current,
      release: from.release,
      apk: from.apk,
      received: 0,
      total: from.apk.size,
      bytesPerSecond: 0,
    );
    try {
      final file = await ref
          .read(apkDownloaderProvider)
          .download(
            from.apk,
            cancel: cancel,
            onProgress: (received, total) {
              final now = DateTime.now();
              // Enough for a smooth bar without rebuilding on every packet.
              if (received != total &&
                  now.difference(lastEmit) < const Duration(milliseconds: 80)) {
                return;
              }
              lastEmit = now;
              final seconds = now.difference(started).inMilliseconds / 1000;
              state = UpdateDownloading(
                current: from.current,
                release: from.release,
                apk: from.apk,
                received: received,
                total: total,
                bytesPerSecond: seconds > 0.3 ? received / seconds : 0,
              );
            },
            onVerifying: () {
              state = UpdateVerifying(
                current: from.current,
                release: from.release,
                apk: from.apk,
              );
            },
          );
      state = UpdateReady(
        current: from.current,
        release: from.release,
        apk: from.apk,
        file: file.path,
      );
      await install();
    } on DownloadCancelled {
      state = UpdateAvailable(
        current: from.current,
        release: from.release,
        apk: from.apk,
      );
    } on ChecksumMismatch {
      state = UpdateFailed(
        current: from.current,
        retry: UpdateAvailable(
          current: from.current,
          release: from.release,
          apk: from.apk,
        ),
        message:
            'The downloaded file did not match the published one, so it was not installed. '
            'Please try again.',
      );
    } on DownloadFailed catch (error) {
      state = UpdateFailed(
        current: from.current,
        retry: UpdateAvailable(
          current: from.current,
          release: from.release,
          apk: from.apk,
        ),
        message: error.message,
      );
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  void cancelDownload() => _cancel?.cancel();

  /// Hands the downloaded file to Android, asking for the install permission
  /// first when Android needs it.
  Future<void> install() async {
    final UpdateWithRelease s;
    final String file;
    switch (state) {
      case final UpdateReady ready:
        s = ready;
        file = ready.file;
      case final UpdateNeedsPermission waiting:
        s = waiting;
        file = waiting.file;
      default:
        return;
    }
    if (!await _installer.canInstall()) {
      state = UpdateNeedsPermission(
        current: s.current,
        release: s.release,
        apk: s.apk,
        file: file,
      );
      return;
    }
    state = UpdateInstalling(
      current: s.current,
      release: s.release,
      apk: s.apk,
      file: file,
    );
    try {
      await _installer.install(file);
    } catch (error) {
      state = UpdateFailed(
        current: s.current,
        retry: UpdateReady(
          current: s.current,
          release: s.release,
          apk: s.apk,
          file: file,
        ),
        message: 'Android could not start the install. Please try again.',
      );
    }
  }

  Future<void> openInstallPermission() => _installer.openInstallPermission();

  /// Back from Android's settings or its confirmation screen.
  Future<void> onResumed() async {
    final s = state;
    if (s is UpdateNeedsPermission && await _installer.canInstall()) {
      state = UpdateReady(
        current: s.current,
        release: s.release,
        apk: s.apk,
        file: s.file,
      );
      await install();
    }
  }

  void _onInstallOutcome(({InstallOutcome outcome, String? message}) event) {
    final s = state;
    if (s is! UpdateInstalling) return;
    UpdateReady ready(String note) => UpdateReady(
      current: s.current,
      release: s.release,
      apk: s.apk,
      file: s.file,
      note: note,
    );
    switch (event.outcome) {
      case InstallOutcome.confirming || InstallOutcome.success:
        break; // Android takes over; on success the app restarts as the new version.
      case InstallOutcome.cancelled:
        state = ready(
          'The install was cancelled. You can install it whenever you like.',
        );
      case InstallOutcome.conflict:
        state = UpdateFailed(
          current: s.current,
          message:
              'This version is signed with a different key than the one on your phone, so '
              'Android will not update over it. Uninstall the app once, then install the new '
              'version from the website.',
        );
      case InstallOutcome.storage:
        state = ready(
          'There is not enough free space to install the update. Free some space and try again.',
        );
      case InstallOutcome.incompatible:
        state = UpdateFailed(
          current: s.current,
          message: 'This version does not work on this phone.',
        );
      case InstallOutcome.blocked:
        state = ready(
          'The install was blocked on this phone (for example by a work profile or Play Protect).',
        );
      case InstallOutcome.invalid || InstallOutcome.failure:
        state = UpdateFailed(
          current: s.current,
          retry: UpdateAvailable(
            current: s.current,
            release: s.release,
            apk: s.apk,
          ),
          message: 'Android could not install the update. Please try again.',
        );
    }
  }
}
