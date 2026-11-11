import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/models/bus_stop.dart';
import '../../../data/repositories/stop_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';
import 'stop_editor_screen.dart';

/// Where an admin adds, moves, renames and deletes the stops.
///
/// The screen is only a convenience: the database refuses these changes
/// from anyone who is not an admin, whatever is shown here.
class AdminStopsScreen extends ConsumerWidget {
  const AdminStopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage stops')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.adminStopEditor),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add stop'),
            )
          : null,
      body: isAdmin
          ? const _StopLists()
          : const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Admins only',
              message:
                  'Only a transport office admin can change the stops. Sign '
                  'in with an admin account.',
            ),
    );
  }
}

class _StopLists extends ConsumerWidget {
  const _StopLists();

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BusStop stop,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${stop.name}?'),
        content: const Text(
          'The stop is removed from the map for everyone. This cannot be '
          'undone.',
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
    if (confirmed != true) return;
    try {
      await ref.read(stopRepositoryProvider).deleteStop(stop.id);
      messenger.showSnackBar(SnackBar(content: Text('${stop.name} deleted.')));
    } on StopWriteFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final stops = ref.watch(officialStopsProvider);
    final saved = stops.value ?? const <BusStop>[];
    final savedNames = {for (final stop in saved) stop.name.toLowerCase()};
    final suggestions = [
      for (final stop
          in ref.watch(suggestedStopsProvider).value ?? const <BusStop>[])
        if (!savedNames.contains(stop.name.toLowerCase())) stop,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        // Room for the Add stop button.
        96,
      ),
      children: [
        SectionCard(
          title: 'Stops on the map (${saved.length})',
          children: [
            if (stops.isLoading && !stops.hasValue)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (stops.hasError && !stops.hasValue)
              const ListTile(
                leading: Icon(Icons.cloud_off_rounded),
                title: Text('The stops could not be loaded'),
                subtitle: Text('Check the connection and open this again.'),
              )
            else if (saved.isEmpty)
              const ListTile(
                leading: Icon(Icons.location_off_rounded),
                title: Text('No stops yet'),
                subtitle: Text(
                  'Add one with the button below, or start from a suggested '
                  'position.',
                ),
              )
            else
              for (final stop in saved)
                ListTile(
                  leading: const Icon(Icons.location_on_rounded),
                  title: Text(stop.name),
                  subtitle: Text(
                    [
                      ?stop.description,
                      formatCoordinates(
                        stop.position.latitude,
                        stop.position.longitude,
                      ),
                    ].join('\n'),
                  ),
                  isThreeLine: stop.description != null,
                  onTap: () => context.push(
                    AppRoutes.adminStopEditor,
                    extra: StopDraft.edit(stop),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete ${stop.name}',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _confirmDelete(context, ref, stop),
                  ),
                ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          SectionCard(
            title: 'Suggested positions (${suggestions.length})',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Stops named in the official schedule, with positions '
                  'found by name in OpenStreetMap. They are not confirmed '
                  'and passengers do not see them. Open one, move the pin to '
                  'the right spot, and save it.',
                  style: muted,
                ),
              ),
              for (final stop in suggestions)
                ListTile(
                  leading: const Icon(Icons.help_outline_rounded),
                  title: Text(stop.name),
                  subtitle: Text(stop.description ?? ''),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(
                    AppRoutes.adminStopEditor,
                    extra: StopDraft.suggestion(stop),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
