import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';
import '../data/driver_directory.dart';
import 'admin_buses_screen.dart';

/// Adds a bus or changes one: its number and name, the route it runs, who
/// drives it, and whether it is in service.
class BusEditorScreen extends ConsumerStatefulWidget {
  const BusEditorScreen({this.draft, super.key});

  /// Null to add a new bus.
  final BusDraft? draft;

  static const int maxNumberLength = 20;
  static const int maxNameLength = 80;

  @override
  ConsumerState<BusEditorScreen> createState() => _BusEditorScreenState();
}

class _BusEditorScreenState extends ConsumerState<BusEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _name;
  late final TextEditingController _registration;
  String? _routeId;
  String? _driverUid;
  bool _isActive = true;

  bool _busy = false;
  String? _error;

  Bus? get _original => widget.draft?.bus;

  /// A bus offered from the schedule has no id yet, so it is new too.
  bool get _isNew => (_original?.id ?? '').isEmpty;

  @override
  void initState() {
    super.initState();
    final bus = _original;
    _number = TextEditingController(text: bus?.number ?? '');
    _name = TextEditingController(text: bus?.name ?? '');
    _registration = TextEditingController(text: bus?.registrationNumber ?? '');
    _routeId = bus?.routeId;
    _driverUid = bus?.driverUid;
    _isActive = bus?.isActive ?? true;
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _registration.dispose();
    super.dispose();
  }

  /// A reason the bus cannot be saved as it stands, or null.
  String? _problem() {
    final others = [
      for (final bus
          in ref.read(registeredBusesProvider).value ?? const <Bus>[])
        if (bus.id != _original?.id) bus,
    ];
    final number = _number.text.trim().toLowerCase();
    if (others.any((bus) => bus.number.toLowerCase() == number)) {
      return 'Another bus already has the number ${_number.text.trim()}.';
    }
    final driver = _driverUid;
    if (driver != null) {
      final taken = others.where((bus) => bus.driverUid == driver).firstOrNull;
      if (taken != null) {
        return 'That driver already has bus ${taken.number}. A driver can '
            'have one bus; remove them from that bus first.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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
    final bus = Bus(
      id: _original?.id ?? '',
      number: _number.text.trim(),
      name: _name.text.trim(),
      registrationNumber: _registration.text.trim(),
      routeId: _routeId,
      driverUid: _driverUid,
      isActive: _isActive,
    );
    try {
      await ref.read(busRepositoryProvider).saveBus(bus);
      messenger.showSnackBar(
        SnackBar(content: Text('Bus ${bus.number} saved.')),
      );
      if (mounted) context.pop();
    } on BusWriteFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final bus = _original!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete bus ${bus.number}?'),
        content: const Text(
          'The bus is removed for everyone. This cannot be undone. To keep '
          'it for later, switch off "In service" instead.',
        ),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(busRepositoryProvider).deleteBus(bus.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Bus ${bus.number} deleted.')),
      );
      if (mounted) context.pop();
    } on BusWriteFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!ref.watch(isAdminProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bus')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Admins only',
          message: 'Only a transport office admin can change the buses.',
        ),
      );
    }

    final routes = {
      ...ref.watch(scheduleRouteNumbersProvider),
      ?_routeId,
    }.toList()..sort();
    final drivers = ref.watch(driversProvider).value ?? const [];
    final knownDriver = drivers.any((driver) => driver.uid == _driverUid);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add bus' : 'Edit bus ${_original!.number}'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete this bus',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
                title: 'Bus',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _number,
                          decoration: const InputDecoration(
                            labelText: 'Bus number',
                            hintText: 'BRTC-05',
                          ),
                          maxLength: BusEditorScreen.maxNumberLength,
                          textInputAction: TextInputAction.next,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter the bus number.'
                              : null,
                        ),
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            hintText: 'Chitra',
                          ),
                          maxLength: BusEditorScreen.maxNameLength,
                          textInputAction: TextInputAction.next,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter the name of the bus.'
                              : null,
                        ),
                        TextFormField(
                          controller: _registration,
                          decoration: const InputDecoration(
                            labelText: 'Registration number (optional)',
                          ),
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: 'Assignment',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String?>(
                          key: const Key('bus-route'),
                          initialValue: _routeId,
                          decoration: const InputDecoration(labelText: 'Route'),
                          items: [
                            const DropdownMenuItem(child: Text('No route')),
                            for (final route in routes)
                              DropdownMenuItem(
                                value: route,
                                child: Text('Route $route'),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            _routeId = value;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        DropdownButtonFormField<String?>(
                          key: const Key('bus-driver'),
                          initialValue: _driverUid,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Driver',
                          ),
                          items: [
                            const DropdownMenuItem(child: Text('No driver')),
                            for (final driver in drivers)
                              DropdownMenuItem(
                                value: driver.uid,
                                child: Text(
                                  '${driver.name} (${driver.email})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (_driverUid != null && !knownDriver)
                              DropdownMenuItem(
                                value: _driverUid,
                                child: const Text(
                                  'Current driver (no longer in the list)',
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            _driverUid = value;
                            _error = null;
                          }),
                        ),
                        if (drivers.isEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'There are no drivers yet. Someone becomes a '
                            'driver when they have signed in and an admin '
                            'changes their role to driver.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('In service'),
                    subtitle: const Text(
                      'Switch off to hide the bus from passengers without '
                      'deleting it.',
                    ),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_isNew ? 'Add bus' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
