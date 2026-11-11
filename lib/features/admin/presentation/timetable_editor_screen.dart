import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatting.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';
import '../../schedule/data/bus_schedule_repository.dart';
import '../../schedule/domain/bus_schedule.dart';

/// What the timetable editor starts from.
@immutable
class TimetableDraft {
  const TimetableDraft._(this.timetable);

  /// A new route for [groupId], with nothing in it yet.
  TimetableDraft.create(String groupId)
    : this._(
        RouteTimetable(
          groupId: groupId,
          routeNumber: '',
          stops: const [],
          departures: const [],
        ),
      );

  /// An existing route's timetable being changed.
  const TimetableDraft.edit(RouteTimetable timetable) : this._(timetable);

  final RouteTimetable timetable;
}

/// Adds a route's timetable or changes one: its number, where and when its
/// buses leave, and its stops. Nothing is saved until "Save route".
class TimetableEditorScreen extends ConsumerStatefulWidget {
  const TimetableEditorScreen({this.draft, super.key});

  /// Null to add a route for the first group.
  final TimetableDraft? draft;

  static const int maxRouteLength = 10;

  @override
  ConsumerState<TimetableEditorScreen> createState() =>
      _TimetableEditorScreenState();
}

class _TimetableEditorScreenState extends ConsumerState<TimetableEditorScreen> {
  late final RouteTimetable _original;
  late final TextEditingController _route;
  late String _groupId;
  late List<LocalizedText> _stops;
  late List<DeparturePoint> _departures;

  bool _busy = false;
  bool _changed = false;
  String? _error;

  bool get _isNew => _original.id.isEmpty;

  @override
  void initState() {
    super.initState();
    _original =
        (widget.draft ??
                TimetableDraft.create(BusSchedule.standardGroups.first.id))
            .timetable;
    _groupId = _original.groupId;
    _route = TextEditingController(text: _original.routeNumber);
    _stops = [..._original.stops];
    _departures = [..._original.departures];
  }

  @override
  void dispose() {
    _route.dispose();
    super.dispose();
  }

  void _edit(VoidCallback change) => setState(() {
    change();
    _changed = true;
    _error = null;
  });

  // ---- departure places and trips ------------------------------------

  Future<void> _addPlace() async {
    final place = await _askForText(
      title: 'Add departure place',
      hint: 'Where the buses leave from, for example University',
    );
    if (place == null) return;
    _edit(() => _departures.add(DeparturePoint(from: place, trips: const [])));
  }

  Future<void> _renamePlace(int index) async {
    final place = await _askForText(
      title: 'Departure place',
      initial: _departures[index].from,
    );
    if (place == null) return;
    _edit(
      () => _departures[index] = DeparturePoint(
        from: place,
        trips: _departures[index].trips,
      ),
    );
  }

  Future<void> _removePlace(int index) async {
    final point = _departures[index];
    if (point.trips.isNotEmpty) {
      final confirmed = await _confirm(
        title: 'Remove ${point.from.primary}?',
        message:
            'Its ${point.trips.length} departures are removed with it. '
            'Nothing changes for passengers until you save the route.',
        action: 'Remove',
      );
      if (!confirmed) return;
    }
    _edit(() => _departures.removeAt(index));
  }

  void _setTrips(int index, List<ScheduledTrip> trips) {
    final sorted = [...trips]..sort((a, b) => a.minutes.compareTo(b.minutes));
    _departures[index] = DeparturePoint(
      from: _departures[index].from,
      trips: sorted,
    );
  }

  Future<void> _addTrip(int index) async {
    final trip = await showDialog<ScheduledTrip>(
      context: context,
      builder: (context) => const _TripDialog(),
    );
    if (trip == null) return;
    _edit(() => _setTrips(index, [..._departures[index].trips, trip]));
  }

  Future<void> _editTrip(int index, int tripIndex) async {
    final trips = _departures[index].trips;
    final trip = await showDialog<ScheduledTrip>(
      context: context,
      builder: (context) => _TripDialog(initial: trips[tripIndex]),
    );
    if (trip == null) return;
    _edit(() => _setTrips(index, [...trips]..[tripIndex] = trip));
  }

  void _removeTrip(int index, int tripIndex) => _edit(
    () => _setTrips(index, [..._departures[index].trips]..removeAt(tripIndex)),
  );

  // ---- stops ----------------------------------------------------------

  Future<void> _addStop() async {
    final stop = await _askForText(
      title: 'Add stop',
      hint: 'Stops are listed from one end of the route to the other',
    );
    if (stop == null) return;
    _edit(() => _stops.add(stop));
  }

  Future<void> _renameStop(int index) async {
    final stop = await _askForText(title: 'Stop', initial: _stops[index]);
    if (stop == null) return;
    _edit(() => _stops[index] = stop);
  }

  void _moveStop(int index, int by) => _edit(() {
    final stop = _stops.removeAt(index);
    _stops.insert(index + by, stop);
  });

  // ---- dialogs ---------------------------------------------------------

  Future<LocalizedText?> _askForText({
    required String title,
    LocalizedText? initial,
    String? hint,
  }) => showDialog<LocalizedText>(
    context: context,
    builder: (context) =>
        _TextPairDialog(title: title, initial: initial, hint: hint),
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ---- saving and deleting --------------------------------------------

  String? _problem() {
    final route = _route.text.trim();
    if (route.isEmpty) return 'Enter the route number.';
    if (route.length > TimetableEditorScreen.maxRouteLength) {
      return 'Use ${TimetableEditorScreen.maxRouteLength} characters or fewer '
          'for the route number.';
    }
    final others = ref.read(officialTimetablesProvider).value ?? const [];
    final taken = others.any(
      (other) =>
          other.id != _original.id &&
          other.groupId == _groupId &&
          other.routeNumber.trim().toLowerCase() == route.toLowerCase(),
    );
    if (taken) {
      return 'This group already has a route $route. Open that one to '
          'change it.';
    }
    if (_departures.isEmpty) {
      return 'Add at least one departure place.';
    }
    for (final point in _departures) {
      if (point.trips.isEmpty) {
        return 'Add a departure time for ${point.from.primary}, or remove '
            'that place.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final timetable = RouteTimetable(
      id: _original.id,
      groupId: _groupId,
      routeNumber: _route.text.trim(),
      stops: _stops,
      departures: _departures,
    );
    try {
      await ref.read(timetableRepositoryProvider).saveTimetable(timetable);
      messenger.showSnackBar(
        SnackBar(content: Text('Route ${timetable.routeNumber} saved.')),
      );
      _changed = false;
      if (mounted) context.pop();
    } on ScheduleWriteFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      title: 'Delete route ${_original.routeNumber}?',
      message: 'Its timetable is removed for everyone. This cannot be undone.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(timetableRepositoryProvider).deleteTimetable(_original.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Route ${_original.routeNumber} deleted.')),
      );
      _changed = false;
      if (mounted) context.pop();
    } on ScheduleWriteFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final discard = await _confirm(
      title: 'Discard your changes?',
      message: 'The changes to this route have not been saved.',
      action: 'Discard',
    );
    if (discard && mounted) {
      _changed = false;
      context.pop();
    }
  }

  // ---- screen ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    if (!ref.watch(isAdminProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Route')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Admins only',
          message: 'Only a transport office admin can change the schedule.',
        ),
      );
    }

    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isNew ? 'Add route' : 'Edit route ${_original.routeNumber}',
          ),
          actions: [
            if (!_isNew)
              IconButton(
                tooltip: 'Delete this route',
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        // Not a lazy list: a timetable is short, and every row has to exist
        // for its controls to be reachable.
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Route',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final group in BusSchedule.standardGroups)
                              ButtonSegment(
                                value: group.id,
                                label: Text(group.name),
                                // A saved route stays with its group.
                                enabled: _isNew || group.id == _groupId,
                              ),
                          ],
                          selected: {_groupId},
                          onSelectionChanged: (selection) =>
                              _edit(() => _groupId = selection.first),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _route,
                          decoration: const InputDecoration(
                            labelText: 'Route number',
                            hintText: '01',
                          ),
                          maxLength: TimetableEditorScreen.maxRouteLength,
                          onChanged: (_) => _edit(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              for (final (index, point) in _departures.indexed) ...[
                const SizedBox(height: AppSpacing.xl),
                SectionCard(
                  title: 'From ${point.from.primary}',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.trip_origin_rounded),
                      title: Text(point.from.primary),
                      subtitle: point.from.secondary == null
                          ? null
                          : Text(point.from.secondary!),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip:
                                'Rename departure place ${point.from.primary}',
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: () => _renamePlace(index),
                          ),
                          IconButton(
                            tooltip:
                                'Remove departure place ${point.from.primary}',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _removePlace(index),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    for (final (tripIndex, trip) in point.trips.indexed)
                      ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 76,
                          child: Text(
                            formatClockTime(trip.minutes),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        title: Text(trip.vehicles.primary),
                        subtitle: trip.vehicles.secondary == null
                            ? null
                            : Text(trip.vehicles.secondary!),
                        onTap: () => _editTrip(index, tripIndex),
                        trailing: IconButton(
                          tooltip:
                              'Remove the ${formatClockTime(trip.minutes)} '
                              'departure from ${point.from.primary}',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => _removeTrip(index, tripIndex),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: TextButton.icon(
                          key: Key('add-trip-$index'),
                          onPressed: () => _addTrip(index),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add departure'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _addPlace,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add departure place'),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: 'Stops (${_stops.length})',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'In order from one end of the route to the other. The '
                        'first and last are where the route starts and ends.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                  for (final (index, stop) in _stops.indexed)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 13,
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      title: Text(stop.primary),
                      subtitle: stop.secondary == null
                          ? null
                          : Text(stop.secondary!),
                      onTap: () => _renameStop(index),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Move stop ${stop.primary} up',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.arrow_upward_rounded),
                            onPressed: index == 0
                                ? null
                                : () => _moveStop(index, -1),
                          ),
                          IconButton(
                            tooltip: 'Move stop ${stop.primary} down',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.arrow_downward_rounded),
                            onPressed: index == _stops.length - 1
                                ? null
                                : () => _moveStop(index, 1),
                          ),
                          IconButton(
                            tooltip: 'Remove stop ${stop.primary}',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () =>
                                _edit(() => _stops.removeAt(index)),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: TextButton.icon(
                        onPressed: _addStop,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add stop'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Always on screen, however long the timetable is.
        bottomNavigationBar: Material(
          elevation: 8,
          color: theme.colorScheme.surface,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Save route'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a name in English, in Bangla, or both.
class _TextPairDialog extends StatefulWidget {
  const _TextPairDialog({required this.title, this.initial, this.hint});

  final String title;
  final LocalizedText? initial;
  final String? hint;

  @override
  State<_TextPairDialog> createState() => _TextPairDialogState();
}

class _TextPairDialogState extends State<_TextPairDialog> {
  late final TextEditingController _english = TextEditingController(
    text: widget.initial?.en ?? '',
  );
  late final TextEditingController _bangla = TextEditingController(
    text: widget.initial?.bn ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _english.dispose();
    _bangla.dispose();
    super.dispose();
  }

  void _submit() {
    final text = LocalizedText(
      en: _english.text.trim(),
      bn: _bangla.text.trim(),
    );
    if (text.isEmpty) {
      setState(() => _error = 'Enter a name in English or in Bangla.');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hint != null) ...[
            Text(widget.hint!),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            controller: _english,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Name in English',
              errorText: _error,
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _bangla,
            decoration: const InputDecoration(labelText: 'Name in Bangla'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}

/// Asks for one departure: its time and the buses named for it.
class _TripDialog extends StatefulWidget {
  const _TripDialog({this.initial});

  final ScheduledTrip? initial;

  @override
  State<_TripDialog> createState() => _TripDialogState();
}

class _TripDialogState extends State<_TripDialog> {
  late final TextEditingController _time = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatClockTime(widget.initial!.minutes),
  );
  late final TextEditingController _english = TextEditingController(
    text: widget.initial?.vehicles.en ?? '',
  );
  late final TextEditingController _bangla = TextEditingController(
    text: widget.initial?.vehicles.bn ?? '',
  );
  String? _timeError;
  String? _busesError;

  @override
  void dispose() {
    _time.dispose();
    _english.dispose();
    _bangla.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final current = parseClockTime(_time.text) ?? 8 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _time.text = formatClockTime(picked.hour * 60 + picked.minute);
      _timeError = null;
    });
  }

  void _submit() {
    final minutes = parseClockTime(_time.text);
    final vehicles = LocalizedText(
      en: _english.text.trim(),
      bn: _bangla.text.trim(),
    );
    setState(() {
      _timeError = minutes == null
          ? 'Enter a time, for example 8:30 AM or 16:05.'
          : null;
      _busesError = vehicles.isEmpty ? 'Enter the bus or buses.' : null;
    });
    if (minutes == null || vehicles.isEmpty) return;
    Navigator.of(context)
        .pop(ScheduledTrip(minutes: minutes, vehicles: vehicles));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add departure' : 'Departure'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _time,
              autofocus: widget.initial == null,
              decoration: InputDecoration(
                labelText: 'Time',
                hintText: '8:30 AM',
                errorText: _timeError,
                suffixIcon: IconButton(
                  tooltip: 'Choose on a clock',
                  icon: const Icon(Icons.schedule_rounded),
                  onPressed: _pickTime,
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _english,
              decoration: InputDecoration(
                labelText: 'Buses',
                hintText: 'Chitra, BRTC-05',
                errorText: _busesError,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _bangla,
              decoration: const InputDecoration(labelText: 'Buses in Bangla'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}
