import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/services/eta_service.dart';
import '../../../core/services/preferences_service.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../map/application/map_selection.dart';
import '../../map/application/map_view_state.dart';
import '../../prediction/domain/prediction.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../domain/widget_snapshot.dart';

/// A widget on the home screen and what it shows.
class PlacedWidget {
  const PlacedWidget({required this.id, required this.choice});
  final int id;
  final WidgetChoice choice;
}

/// A departure tapped on a widget, to be opened in the app.
class TappedDeparture {
  const TappedDeparture({
    required this.route,
    required this.from,
    required this.minutes,
  });
  final String route;
  final String from;
  final int minutes;

  static TappedDeparture? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final route = raw['route'];
    if (route is! String || route.isEmpty) return null;
    return TappedDeparture(
      route: route,
      from: raw['from'] as String? ?? '',
      minutes: (raw['minutes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Talks to the Android widget (`BusWidgetProvider.kt`).
abstract class HomeWidgetBridge {
  /// Redraws every placed widget from the saved timetable.
  Future<void> refresh();

  /// Asks Android to put a widget on the home screen. False when the
  /// launcher cannot.
  Future<bool> pin();

  /// The widgets on the home screen, each with its own choice.
  Future<List<PlacedWidget>> placed();

  /// Changes what one widget shows.
  Future<void> setChoice(int id, WidgetChoice choice);

  /// The departure the app was opened from, if a widget opened it. Asked
  /// once at start; later taps arrive through [onDepartureTapped].
  Future<TappedDeparture?> takeTappedDeparture();

  /// Called when a departure is tapped on a widget while the app runs.
  set onDepartureTapped(void Function(TappedDeparture departure)? handler);
}

class ChannelHomeWidgetBridge implements HomeWidgetBridge {
  ChannelHomeWidgetBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openDeparture') {
        final departure = TappedDeparture.fromMap(call.arguments);
        if (departure != null) _onTapped?.call(departure);
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel(
    'bd.ac.bu.bu_bus_tracker/home_widget',
  );

  void Function(TappedDeparture departure)? _onTapped;

  @override
  set onDepartureTapped(void Function(TappedDeparture departure)? handler) =>
      _onTapped = handler;

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
  Future<List<PlacedWidget>> placed() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('placed') ?? [];
      return [
        for (final item in raw.cast<Map>())
          PlacedWidget(
            id: (item['id'] as num).toInt(),
            choice: _decodeChoice(item['choice'] as String?),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> setChoice(int id, WidgetChoice choice) async {
    try {
      await _channel.invokeMethod<void>('setChoice', {
        'id': id,
        'choice': jsonEncode(choice.toJson()),
      });
    } catch (_) {}
  }

  @override
  Future<TappedDeparture?> takeTappedDeparture() async {
    try {
      return TappedDeparture.fromMap(
        await _channel.invokeMethod<Object?>('takeTappedDeparture'),
      );
    } catch (_) {
      return null;
    }
  }
}

WidgetChoice _decodeChoice(String? raw) {
  if (raw == null) return const WidgetChoice();
  try {
    return WidgetChoice.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  } catch (_) {
    return const WidgetChoice();
  }
}

/// Android only.
final homeWidgetBridgeProvider = Provider<HomeWidgetBridge?>((ref) {
  if (kIsWeb || !Platform.isAndroid) return null;
  return ChannelHomeWidgetBridge();
});

/// The choice a newly placed widget starts with: the one set up in
/// Profile before tapping "Add to home screen". Kept across restarts; the
/// widget reads it natively as "flutter.widget.choice".
final widgetChoiceProvider =
    NotifierProvider<WidgetChoiceController, WidgetChoice>(
      WidgetChoiceController.new,
    );

class WidgetChoiceController extends Notifier<WidgetChoice> {
  static const String storageKey = 'widget.choice';

  @override
  WidgetChoice build() =>
      _decodeChoice(ref.watch(sharedPreferencesProvider).getString(storageKey));

  Future<void> set(WidgetChoice choice) async {
    if (choice == state) return;
    state = choice;
    await ref
        .read(sharedPreferencesProvider)
        .setString(storageKey, jsonEncode(choice.toJson()));
  }
}

/// The timetable every widget reads, kept on the phone. Read natively from
/// Flutter's SharedPreferences file as "flutter.widget.timetable".
const String widgetTimetableKey = 'widget.timetable';

/// The saved timetable, as the widget's settings screen reads it.
WidgetTimetable? savedWidgetTimetable(String? raw) {
  if (raw == null) return null;
  try {
    final timetable = WidgetTimetable.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
    return timetable.isEmpty ? null : timetable;
  } catch (_) {
    return null;
  }
}

/// The timetable as the widgets see it, from the schedule the app is using.
final widgetTimetableProvider = Provider<WidgetTimetable?>((ref) {
  final schedule = ref.watch(busScheduleProvider).value;
  if (schedule == null) return null;
  final routes = ref.watch(transportNetworkProvider).value?.routes ?? const [];
  return WidgetTimetable.fromSchedule(
    schedule,
    routeColors: routeColorsOf(routes),
  );
});

/// Opens a departure tapped on a widget: its route on the map, shown the
/// way that bus goes, where "Which bus goes this way" lists it.
Future<void> openTappedDeparture(
  WidgetRef ref,
  GoRouter router,
  TappedDeparture departure,
) async {
  router.go(AppRoutes.home);
  final network = await ref.read(transportNetworkProvider.future);
  final route = network.routeById(departure.route);
  if (route == null) return;
  ref.read(mapSelectionProvider.notifier).selectRoute(route.id);
  final reversed =
      PredictionEngine.directionFrom(route, departure.from) ==
      TravelDirection.backward;
  // Picking a route resets the direction shown; set it after that.
  await Future<void>.delayed(Duration.zero);
  ref.read(routeShownReversedProvider.notifier).set(reversed);
}

/// Writes the timetable the widgets read whenever the schedule or the live
/// buses change (at most every 20 seconds for live changes), asks Android
/// to redraw, and opens departures tapped on a widget. Sits around the
/// app's tabs; draws nothing itself.
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
  String _lastLive = '';
  HomeWidgetBridge? _bridge;

  @override
  void dispose() {
    _debounce?.cancel();
    _bridge?.onDepartureTapped = null;
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
    final timetable = ref.read(widgetTimetableProvider);
    if (timetable == null) return;
    final buses = ref.read(reportedBusesProvider).value ?? const <TrackedBus>[];
    final config = ref.read(trackingConfigurationProvider);
    final now = DateTime.now();
    final live = liveCountsByRoute(
      buses,
      (location) =>
          config.statusOf(location?.updatedAt, now) == BusTrackingStatus.live,
    );
    final liveKey = jsonEncode(live);
    // Live counts change often; rewrite for them at most every 20 seconds.
    if (liveKey != _lastLive &&
        _lastWritten != null &&
        now.difference(_lastLiveWrite) < const Duration(seconds: 20)) {
      _debounce = Timer(
        const Duration(seconds: 20) - now.difference(_lastLiveWrite),
        _write,
      );
      return;
    }
    final json = jsonEncode(timetable.toJson(liveByRoute: live, now: now));
    // The time stamp changes every write; compare without it.
    final comparable = json.replaceFirst(RegExp(r'"writtenAt":\d+'), '');
    if (comparable == _lastWritten) return;
    _lastWritten = comparable;
    _lastLive = liveKey;
    _lastLiveWrite = now;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setString(widgetTimetableKey, json);
    // The single-choice snapshot of the first widget version.
    await preferences.remove('widget.data');
    await bridge.refresh();
  }

  void _open(TappedDeparture departure) {
    if (!mounted) return;
    unawaited(openTappedDeparture(ref, GoRouter.of(context), departure));
  }

  @override
  void initState() {
    super.initState();
    final bridge = _bridge = ref.read(homeWidgetBridgeProvider);
    if (bridge == null) return;
    bridge.onDepartureTapped = _open;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final tapped = await bridge.takeTappedDeparture();
      if (tapped != null) _open(tapped);
    });
    ref.listenManual(widgetTimetableProvider, (_, _) => _schedule());
    ref.listenManual(reportedBusesProvider, (_, _) => _schedule());
    _schedule();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
