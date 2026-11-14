import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/section_card.dart';
import '../application/home_widget_sync.dart';
import '../domain/widget_snapshot.dart';
import 'widget_choice_editor.dart';

/// Profile → "Home-screen widget": the widgets already on the home screen,
/// each with its own choice that can be changed here, and a new widget to
/// set up and add.
class HomeWidgetSection extends ConsumerStatefulWidget {
  const HomeWidgetSection({super.key});

  @override
  ConsumerState<HomeWidgetSection> createState() => _HomeWidgetSectionState();
}

class _HomeWidgetSectionState extends ConsumerState<HomeWidgetSection>
    with WidgetsBindingObserver {
  List<PlacedWidget> _placed = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the home screen after adding or changing a widget.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final placed = await ref.read(homeWidgetBridgeProvider)?.placed() ?? [];
    if (mounted) setState(() => _placed = placed);
  }

  Future<void> _pin() async {
    final ok = await ref.read(homeWidgetBridgeProvider)?.pin() ?? false;
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Long-press your home screen, tap Widgets, and find BU Bus Tracker.',
          ),
        ),
      );
    }
  }

  Future<void> _change(PlacedWidget placed, WidgetTimetable timetable) async {
    final chosen = await showModalBottomSheet<WidgetChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) =>
          _ChangeSheet(timetable: timetable, initial: placed.choice),
    );
    if (chosen == null || chosen == placed.choice) return;
    await ref.read(homeWidgetBridgeProvider)?.setChoice(placed.id, chosen);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(homeWidgetBridgeProvider) == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final choice = ref.watch(widgetChoiceProvider);
    final timetable =
        ref.watch(widgetTimetableProvider) ?? WidgetTimetable.empty;

    return SectionCard(
      title: 'Home-screen widget',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your next bus on the home screen, with its name, a live '
                'countdown and the last bus of the day. Each widget can '
                'show different buses.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_placed.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'On your home screen',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final (index, placed) in _placed.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _PlacedTile(
                      number: index + 1,
                      title: timetable.titleFor(placed.choice),
                      subtitle: placed.choice.direction.label,
                      onChange: () => _change(placed, timetable),
                    ),
                  ),
                Row(
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'You can also change a widget by tapping its title, '
                        'or long-pressing it and choosing Settings.',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                _placed.isEmpty ? 'Set up your widget' : 'Add another widget',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              WidgetChoiceEditor(
                timetable: timetable,
                choice: choice,
                onChanged: ref.read(widgetChoiceProvider.notifier).set,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _pin,
                  icon: Icon(
                    _placed.isEmpty
                        ? Icons.widgets_rounded
                        : Icons.add_to_home_screen_rounded,
                  ),
                  label: Text(
                    _placed.isEmpty
                        ? 'Add to home screen'
                        : 'Add another to home screen',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlacedTile extends StatelessWidget {
  const _PlacedTile({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.onChange,
  });

  final int number;
  final String title;
  final String subtitle;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onChange,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.widgets_rounded,
                  size: 18,
                  color: theme.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Widget $number · $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onChange, child: const Text('Change')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Changes what one placed widget shows.
class _ChangeSheet extends StatefulWidget {
  const _ChangeSheet({required this.timetable, required this.initial});
  final WidgetTimetable timetable;
  final WidgetChoice initial;

  @override
  State<_ChangeSheet> createState() => _ChangeSheetState();
}

class _ChangeSheetState extends State<_ChangeSheet> {
  late WidgetChoice _choice = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Change widget',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          WidgetChoiceEditor(
            timetable: widget.timetable,
            choice: _choice,
            onChanged: (c) => setState(() => _choice = c),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_choice),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
