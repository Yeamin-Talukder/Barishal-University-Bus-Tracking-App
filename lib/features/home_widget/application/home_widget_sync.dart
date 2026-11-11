import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/preferences_service.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../domain/widget_snapshot.dart';

/// Talks to the Android widget (`BusWidgetProvider.kt`).
abstract class HomeWidgetBridge {
  /// Redraws every placed widget from the saved snapshot.
  Future<void> refresh();

  /// Asks Android to put a widget on the home screen. False when the
  /// launcher cannot.
  Future<bool> pin();

  /// How many of the app's widgets are on the home screen.
  Future<int> count();
}

class ChannelHomeWidgetBridge implements HomeWidgetBridge {
  static const MethodChannel _channel = MethodChannel(
    'bd.ac.bu.bu_bus_tracker/home_widget',
  );

  @override
  Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }

  @override
  Future<bool> pin() async {
    try {
      return await _channel.invokeMethod<bool>('pin') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> count() async {
    try {
      return await _channel.invokeMethod<int>('count') ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

/// Android only.
final homeWidgetBridgeProvider = Provider<HomeWidgetBridge?>((ref) {
  if (kIsWeb || !Platform.isAndroid) return null;
  return ChannelHomeWidgetBridge();
});

/// What the widget shows, kept across restarts.
final widgetChoiceProvider =
    NotifierProvider<WidgetChoiceController, WidgetChoice>(
      WidgetChoiceController.new,
    );

class WidgetChoiceController extends Notifier<WidgetChoice> {
  static const String storageKey = 'widget.choice';

  @override
  WidgetChoice build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return const WidgetChoice();
    try {
      return WidgetChoice.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return const WidgetChoice();
    }
  }

  Future<void> set(WidgetChoice choice) async {
    if (choice == state) return;
    state = choice;
    await ref
        .read(sharedPreferencesProvider)
        .setString(storageKey, jsonEncode(choice.toJson()));
  }
}

/// The snapshot the widget reads. The key is read natively from Flutter's
/// SharedPreferences file as "flutter.widget.data".
const String widgetDataKey = 'widget.data';

/// Writes the widget's snapshot whenever the schedule, the choice or the
/// live buses change, at most every 20 seconds for live changes, and asks
/// Android to redraw. Sits around the app's tabs; draws nothing itself.
class HomeWidgetSync extends ConsumerStatefulWidget {
  const HomeWidgetSync({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync> {
  Timer? _debounce;
  String? _lastWritten;
  DateTime _lastLiveWrite = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastLive = -1;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _write);
  }

  Future<void> _write() async {
    if (!mounted) return;
    final bridge = ref.read(homeWidgetBridgeProvider);
    if (bridge == null) return;
    final schedule = ref.read(busScheduleProvider).value;
    if (schedule == null) return;
    final choice = ref.read(widgetChoiceProvider);
    final routes = ref.read(transportNetworkProvider).value?.routes ?? const [];
    final buses = ref.read(reportedBusesProvider).value ?? const <TrackedBus>[];
    final config = ref.read(trackingConfigurationProvider);
    final now = DateTime.now();
    final live = liveBusCount(
      buses,
      choice,
      (location) =>
          config.statusOf(location?.updatedAt, now) == BusTrackingStatus.live,
    );
    // Live counts change often; rewrite for them at most every 20 seconds.
    if (live != _lastLive &&
        now.difference(_lastLiveWrite) < const Duration(seconds: 20) &&
        _lastLive >= 0) {
      _debounce = Timer(
        const Duration(seconds: 20) - now.difference(_lastLiveWrite),
        _write,
      );
      return;
    }
    final departures = widgetDepartures(
      schedule,
      choice,
      routeColors: routeColorsOf(routes),
    );
    final json = jsonEncode(
      widgetSnapshot(
        choice: choice,
        departures: departures,
        live: live,
        now: now,
      ),
    );
    // The time stamp changes every write; compare without it.
    final comparable = json.replaceFirst(RegExp(r'"writtenAt":\d+'), '');
    if (comparable == _lastWritten && live == _lastLive) return;
    _lastWritten = comparable;
    _lastLive = live;
    _lastLiveWrite = now;
    await ref.read(sharedPreferencesProvider).setString(widgetDataKey, json);
    await bridge.refresh();
  }

  @override
  void initState() {
    super.initState();
    if (ref.read(homeWidgetBridgeProvider) == null) return;
    ref.listenManual(
      busScheduleProvider,
      (_, _) => _schedule(),
      fireImmediately: true,
    );
    ref.listenManual(widgetChoiceProvider, (_, _) => _schedule());
    ref.listenManual(transportNetworkProvider, (_, _) => _schedule());
    ref.listenManual(reportedBusesProvider, (_, _) => _schedule());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
