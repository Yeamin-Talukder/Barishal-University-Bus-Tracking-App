import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/preferences_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../application/home_widget_sync.dart';
import '../domain/widget_snapshot.dart';
import 'widget_choice_editor.dart';

/// The settings screen of one home-screen widget: opened by long-pressing
/// the widget and choosing Settings, by tapping the widget's title, or by
/// the launcher when the widget is added on Android 11 and older.
///
/// It runs on its own, without the rest of the app (no sign-in, no map),
/// so it opens quickly. It reads the timetable the app saved for the
/// widgets, or the timetable bundled with the app when the app has not
/// been opened yet.
class WidgetConfigApp extends ConsumerWidget {
  const WidgetConfigApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Widget settings',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ref.watch(themeModeProvider),
    home: const _WidgetConfigScreen(),
  );
}

/// The channel the widget's settings activity (`WidgetConfigActivity.kt`)
/// listens on.
const MethodChannel _channel = MethodChannel(
  'bd.ac.bu.bu_bus_tracker/widget_config',
);

final _configTimetableProvider = FutureProvider<WidgetTimetable>((ref) async {
  final saved = savedWidgetTimetable(
    ref.watch(sharedPreferencesProvider).getString(widgetTimetableKey),
  );
  if (saved != null) return saved;
  final bundled = await ref
      .watch(busScheduleRepositoryProvider)
      .fetchSchedule();
  return WidgetTimetable.fromSchedule(bundled);
});

class _WidgetConfigScreen extends ConsumerStatefulWidget {
  const _WidgetConfigScreen();

  @override
  ConsumerState<_WidgetConfigScreen> createState() =>
      _WidgetConfigScreenState();
}

class _WidgetConfigScreenState extends ConsumerState<_WidgetConfigScreen> {
  int? _id;
  WidgetChoice? _choice;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final target = await _channel.invokeMapMethod<String, Object?>('target');
      final id = (target?['id'] as num?)?.toInt();
      final raw = target?['choice'] as String?;
      setState(() {
        _id = id;
        _choice = raw == null
            ? ref.read(widgetChoiceProvider)
            : WidgetChoice.fromJson(
                (jsonDecode(raw) as Map).cast<String, Object?>(),
              );
      });
    } catch (_) {
      setState(() => _choice = ref.read(widgetChoiceProvider));
    }
  }

  Future<void> _save() async {
    final id = _id;
    final choice = _choice;
    if (id == null || choice == null) return;
    setState(() => _saving = true);
    try {
      await _channel.invokeMethod<void>('save', {
        'id': id,
        'choice': jsonEncode(choice.toJson()),
      });
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timetable = ref.watch(_configTimetableProvider).value;
    final choice = _choice;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: _cancel,
        ),
        title: const Text('Widget settings'),
      ),
      body: timetable == null || choice == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  'Choose which buses this widget shows. Other widgets keep '
                  'their own choice.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                WidgetChoiceEditor(
                  timetable: timetable,
                  choice: choice,
                  onChanged: (c) => setState(() => _choice = c),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.lg),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _id == null || _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save'),
          ),
        ),
      ),
    );
  }
}
