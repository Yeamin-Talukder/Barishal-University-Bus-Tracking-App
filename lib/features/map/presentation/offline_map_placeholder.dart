import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/offline_map_service.dart';
import '../domain/offline_map_state.dart';

/// Shown in place of the map while the offline map is not ready: being
/// prepared, removed by the user, interrupted or failed.
class OfflineMapPlaceholder extends ConsumerWidget {
  const OfflineMapPlaceholder({required this.state, super.key});

  final OfflineMapState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(offlineMapServiceProvider.notifier);
    final background = Theme.of(context).colorScheme.surfaceContainerLow;

    final Widget content = switch (state.status) {
      OfflineMapStatus.checking ||
      OfflineMapStatus.ready => const _Preparing(progress: null),
      OfflineMapStatus.installing => _Preparing(progress: state.progress),
      OfflineMapStatus.notInstalled => EmptyState(
        icon: Icons.download_for_offline_rounded,
        title: 'The map is not on this device',
        message:
            'Install it to see the campus, routes and buses. It comes with '
            'the app, so no internet is needed.',
        action: FilledButton.icon(
          onPressed: service.install,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Install map'),
        ),
      ),
      OfflineMapStatus.interrupted => EmptyState(
        icon: Icons.pause_circle_outline_rounded,
        title: 'Map installation was interrupted',
        message: 'Continue to finish saving the map on this device.',
        action: FilledButton.icon(
          onPressed: service.install,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Continue'),
        ),
      ),
      OfflineMapStatus.needsUpdate => EmptyState(
        icon: Icons.system_update_alt_rounded,
        title: 'A newer map is available',
        message:
            'This version of the app comes with newer map data. Update the '
            'map to keep using it.',
        action: FilledButton.icon(
          onPressed: service.install,
          icon: const Icon(Icons.system_update_alt_rounded),
          label: const Text('Update map'),
        ),
      ),
      OfflineMapStatus.failed => EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'The map could not be opened',
        message:
            state.errorMessage ??
            'The map data on this device could not be prepared.',
        action: FilledButton.icon(
          onPressed: service.install,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
    };

    return ColoredBox(color: background, child: content);
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing({required this.progress});

  /// From 0 to 1, or null when the amount of work is not known yet.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = progress == null ? null : (progress! * 100).round();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Preparing the map', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              percent == null ? 'One moment' : '$percent%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
