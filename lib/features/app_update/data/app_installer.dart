import 'dart:async';

import 'package:flutter/services.dart';

/// This copy of the app as Android sees it.
class InstalledApp {
  const InstalledApp({
    required this.versionName,
    required this.versionCode,
    required this.abis,
  });

  final String versionName;
  final int versionCode;

  /// The phone's ABIs, most preferred first (e.g. arm64-v8a, armeabi-v7a).
  final List<String> abis;
}

/// What Android's package installer reported after an install was started.
enum InstallOutcome {
  /// Android is showing its "Do you want to update this app?" screen.
  confirming,
  success,

  /// The person tapped Cancel on Android's screen.
  cancelled,

  /// Signed with a different key than the installed app.
  conflict,
  incompatible,
  storage,
  blocked,
  invalid,
  failure,
}

/// Talks to Android's own installer through `MainActivity`. The APK is
/// handed to Android's PackageInstaller from inside the app; Android then
/// asks the person to confirm, as it does for every app not from a store.
abstract class AppInstaller {
  Future<InstalledApp> installedApp();

  /// Whether Android lets this app install updates ("Install unknown apps").
  Future<bool> canInstall();

  /// Opens Android's "Install unknown apps" switch for this app.
  Future<void> openInstallPermission();

  Future<void> install(String apkPath);

  Stream<({InstallOutcome outcome, String? message})> get outcomes;
}

class ChannelAppInstaller implements AppInstaller {
  ChannelAppInstaller() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'installStatus') return;
      final args = (call.arguments as Map?) ?? const {};
      final outcome = switch (args['status']) {
        'confirm' => InstallOutcome.confirming,
        'success' => InstallOutcome.success,
        'aborted' => InstallOutcome.cancelled,
        'conflict' => InstallOutcome.conflict,
        'incompatible' => InstallOutcome.incompatible,
        'storage' => InstallOutcome.storage,
        'blocked' => InstallOutcome.blocked,
        'invalid' => InstallOutcome.invalid,
        _ => InstallOutcome.failure,
      };
      _outcomes.add((outcome: outcome, message: args['message'] as String?));
    });
  }

  static const MethodChannel _channel = MethodChannel('bd.ac.bu.bu_bus_tracker/app_update');
  final _outcomes = StreamController<({InstallOutcome outcome, String? message})>.broadcast();

  @override
  Future<InstalledApp> installedApp() async {
    final info = await _channel.invokeMapMethod<String, Object?>('appInfo') ?? const {};
    return InstalledApp(
      versionName: '${info['versionName'] ?? '0.0.0'}',
      versionCode: (info['versionCode'] as num?)?.toInt() ?? 0,
      abis: [for (final abi in (info['abis'] as List?) ?? const []) '$abi'],
    );
  }

  @override
  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallPermission() => _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<void> install(String apkPath) => _channel.invokeMethod<void>('install', {'path': apkPath});

  @override
  Stream<({InstallOutcome outcome, String? message})> get outcomes => _outcomes.stream;
}
