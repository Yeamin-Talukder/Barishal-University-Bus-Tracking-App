import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/coordinate_parser.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/models/geo_point.dart';
import '../../../data/repositories/stop_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/application/session.dart';
import '../../map/application/university_map_configuration_provider.dart';
import '../../map/presentation/map_attribution.dart';
import 'stop_position_picker.dart';

/// What the stop editor starts from.
@immutable
class StopDraft {
  const StopDraft._({
    required this.id,
    required this.name,
    required this.description,
    required this.position,
    required this.isSuggestion,
  });

  /// An existing stop being changed.
  StopDraft.edit(BusStop stop)
    : this._(
        id: stop.id,
        name: stop.name,
        description: stop.description,
        position: stop.position,
        isSuggestion: false,
      );

  /// A new stop starting from an unconfirmed position. It is saved as a new
  /// stop: the suggestion's id is not kept.
  StopDraft.suggestion(BusStop stop)
    : this._(
        id: '',
        name: stop.name,
        description: null,
        position: stop.position,
        isSuggestion: true,
      );

  /// Empty for a new stop.
  final String id;
  final String name;
  final String? description;
  final GeoPoint position;
  final bool isSuggestion;
}

/// Adds a stop or changes one: its name, an optional note, and its position,
/// chosen by moving the map until the pin is on the stop.
class StopEditorScreen extends ConsumerStatefulWidget {
  const StopEditorScreen({this.draft, super.key});

  /// Null to add a new stop from scratch.
  final StopDraft? draft;

  static const int maxNameLength = 80;

  @override
  ConsumerState<StopEditorScreen> createState() => _StopEditorScreenState();
}

class _StopEditorScreenState extends ConsumerState<StopEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final GeoPoint _initial;
  late GeoPoint _position;

  /// Tells the map to move, after coordinates are pasted.
  final ValueNotifier<GeoPoint?> _moveTo = ValueNotifier<GeoPoint?>(null);

  bool _busy = false;
  String? _error;

  bool get _isNew => (widget.draft?.id ?? '').isEmpty;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    final config = ref.read(universityMapConfigurationProvider);
    _initial =
        draft?.position ??
        GeoPoint(config.centerLatitude, config.centerLongitude);
    _position = _initial;
    _name = TextEditingController(text: draft?.name ?? '');
    _description = TextEditingController(text: draft?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _moveTo.dispose();
    super.dispose();
  }

  Future<void> _copyCoordinates() async {
    final messenger = ScaffoldMessenger.of(context);
    final text = coordinatesToText(_position);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text('Copied $text')));
  }

  /// Asks for coordinates, typed or pasted from Google Maps, and moves the
  /// pin there.
  Future<void> _pasteCoordinates() async {
    final config = ref.read(universityMapConfigurationProvider);
    final position = await showDialog<GeoPoint>(
      context: context,
      builder: (context) => _CoordinatesDialog(
        isWithinCoverage: (point) =>
            config.isWithinCoverage(point.latitude, point.longitude),
      ),
    );
    if (position == null || !mounted) return;
    setState(() {
      _position = position;
      _error = null;
    });
    // A new object each time, so pasting the same place twice still moves.
    _moveTo.value = GeoPoint(position.latitude, position.longitude);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final config = ref.read(universityMapConfigurationProvider);
    if (!config.isWithinCoverage(_position.latitude, _position.longitude)) {
      setState(
        () => _error =
            'That position is outside the area the map covers. Move the pin '
            'closer to the university.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final description = _description.text.trim();
    final stop = BusStop(
      id: widget.draft?.id ?? '',
      name: _name.text.trim(),
      description: description.isEmpty ? null : description,
      position: _position,
    );
    try {
      await ref.read(stopRepositoryProvider).saveStop(stop);
      messenger.showSnackBar(SnackBar(content: Text('${stop.name} saved.')));
      if (mounted) context.pop();
    } on StopWriteFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    if (!ref.watch(isAdminProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stop')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Admins only',
          message: 'Only a transport office admin can change the stops.',
        ),
      );
    }

    final buildMap = ref.watch(stopPickerMapBuilderProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Add stop' : 'Edit stop')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: buildMap(
                      context,
                      _initial,
                      (position) => setState(() => _position = position),
                      _moveTo,
                    ),
                  ),
                  // The pin's tip marks the centre of the map. It never takes
                  // touches, so the map under it stays draggable.
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: FractionalTranslation(
                          translation: Offset(0, -0.5),
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 44,
                            color: AppColors.mintDeep,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black38),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    child: MapAttribution(),
                  ),
                ],
              ),
            ),
            Material(
              elevation: 8,
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.draft?.isSuggestion ?? false
                            ? 'This position was found by name and is not '
                                  'confirmed. Move the map until the pin is '
                                  'exactly where the bus stops.'
                            : 'Move the map until the pin is exactly where '
                                  'the bus stops.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.xs,
                        children: [
                          Text(
                            formatCoordinates(
                              _position.latitude,
                              _position.longitude,
                            ),
                            key: const Key('stop-editor-position'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy coordinates',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            onPressed: _copyCoordinates,
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _busy ? null : _pasteCoordinates,
                            icon: const Icon(
                              Icons.content_paste_rounded,
                              size: 18,
                            ),
                            label: const Text('Paste coordinates'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Stop name',
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        maxLength: StopEditorScreen.maxNameLength,
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter the stop\'s name.'
                            : null,
                      ),
                      TextFormField(
                        controller: _description,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          hintText: 'Bangla name, landmark, side of the road',
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.done,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_isNew ? 'Add stop' : 'Save changes'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for coordinates as text and returns the position they describe.
class _CoordinatesDialog extends StatefulWidget {
  const _CoordinatesDialog({required this.isWithinCoverage});

  final bool Function(GeoPoint point) isWithinCoverage;

  @override
  State<_CoordinatesDialog> createState() => _CoordinatesDialogState();
}

class _CoordinatesDialogState extends State<_CoordinatesDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Fill in what was just copied, when it is a position.
    _fillFromClipboard(onlyIfCoordinates: true);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _fillFromClipboard({bool onlyIfCoordinates = false}) async {
    String? copied;
    try {
      copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      // Some browsers refuse clipboard access; typing still works.
    }
    if (!mounted) return;
    if (copied == null || copied.trim().isEmpty) {
      if (!onlyIfCoordinates) {
        setState(() => _error = 'Nothing is copied. Type the coordinates.');
      }
      return;
    }
    if (onlyIfCoordinates && parseCoordinates(copied) == null) return;
    setState(() {
      _text.text = copied!.trim();
      _error = null;
    });
  }

  void _submit() {
    final input = _text.text.trim();
    final point = parseCoordinates(input);
    if (point == null) {
      setState(
        () => _error = input.contains('goo.gl')
            ? 'A short link does not contain the position. In Google Maps, '
                  'copy the coordinates instead.'
            : 'These are not coordinates. Example: 22.690260, 90.359400',
      );
      return;
    }
    if (!widget.isWithinCoverage(point)) {
      setState(
        () => _error =
            'That place is outside the area the map covers, around the '
            'university.',
      );
      return;
    }
    Navigator.of(context).pop(point);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste coordinates'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'In Google Maps, press and hold the place, then copy the numbers '
            'shown, or copy a full Google Maps link.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _text,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Coordinates',
              hintText: '22.690260, 90.359400',
              errorText: _error,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _fillFromClipboard,
              ),
            ),
            keyboardType: TextInputType.text,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Move pin')),
      ],
    );
  }
}
