import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatting.dart';
import '../../../shared/widgets/section_card.dart';
import '../application/offline_map_service.dart';
import '../domain/offline_map_state.dart';

/// The Profile section for the offline map: what is on the device, and the
/// actions that apply to it.
class OfflineMapSection extends ConsumerWidget {
  const OfflineMapSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineMapServiceProvider);

    return SectionCard(
      title: 'Offline map',
      children: [
        _StatusTile(state: state),
        if (state.status == OfflineMapStatus.installing)
          _InstallProgress(progress: state.progress),
        if (state.manifest != null) ...[
          const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
          _Details(state: state),
        ],
        if (state.canManage) _Actions(state: state),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.state});

  final OfflineMapState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;

    final (icon, color, title, subtitle) = switch (state.status) {
      OfflineMapStatus.checking => (
        Icons.hourglass_empty_rounded,
        semantic.muted,
        'Checking the map',
        'Looking at what is saved on this device.',
      ),
      OfflineMapStatus.ready when !state.canManage => (
        Icons.public_rounded,
        semantic.muted,
        'Browser preview',
        'The map is loaded from the preview server. Offline use is for '
            'the Android and iOS apps.',
      ),
      OfflineMapStatus.ready when state.integrity == MapIntegrity.damaged => (
        Icons.error_outline_rounded,
        scheme.error,
        'The saved map is damaged',
        'Install it again to repair it.',
      ),
      OfflineMapStatus.ready => (
        Icons.offline_pin_rounded,
        semantic.success,
        'Ready for offline use',
        state.integrity == MapIntegrity.verified
            ? 'Checked just now: the saved map is complete.'
            : 'The map works without an internet connection.',
      ),
      OfflineMapStatus.installing => (
        Icons.downloading_rounded,
        scheme.primary,
        'Installing the map',
        '${(state.progress * 100).round()}% saved to this device.',
      ),
      OfflineMapStatus.interrupted => (
        Icons.pause_circle_outline_rounded,
        semantic.warning,
        'Installation interrupted',
        'Continue to finish saving the map.',
      ),
      OfflineMapStatus.needsUpdate => (
        Icons.system_update_alt_rounded,
        semantic.warning,
        'Needs an update',
        'This version of the app comes with newer map data.',
      ),
      OfflineMapStatus.notInstalled => (
        Icons.cloud_off_rounded,
        semantic.muted,
        'Not on this device',
        'Install the map to use the map screen. No internet is needed.',
      ),
      OfflineMapStatus.failed => (
        Icons.error_outline_rounded,
        scheme.error,
        'Something went wrong',
        state.errorMessage ?? 'The map could not be prepared.',
      ),
    };

    return SettingsTile(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
    );
  }
}

class _InstallProgress extends StatelessWidget {
  const _InstallProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: LinearProgressIndicator(value: progress, minHeight: 6),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.state});

  final OfflineMapState state;

  @override
  Widget build(BuildContext context) {
    final manifest = state.manifest!;
    final dataDate = manifest.dataDate;
    final installed = state.installedVersion;
    final size = manifest.bounds.sizeKm;

    final rows = <(String, String)>[
      (
        'Area',
        'The bus routes, about ${size.northSouth.round()} by '
            '${size.eastWest.round()} km',
      ),
      (
        'Map data',
        dataDate == null
            ? 'OpenStreetMap'
            : 'OpenStreetMap, ${formatDate(dataDate)}',
      ),
      (
        'Version',
        installed == null || installed == state.bundledVersion
            ? '${state.bundledVersion}'
            : '$installed installed, ${state.bundledVersion} available',
      ),
      if (state.canManage)
        (
          'On this device',
          state.bytesOnDevice == 0
              ? 'Nothing'
              : formatBytes(state.bytesOnDevice),
        ),
    ];

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(value, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.state});

  final OfflineMapState state;

  Future<void> _verify(BuildContext context, OfflineMapService service) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await service.verify();
    if (result == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result == MapIntegrity.verified
                ? 'The saved map is complete.'
                : 'The saved map is damaged. Install it again to repair it.',
          ),
        ),
      );
  }

  void _checkForUpdate(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'This is the newest map for this version of the app. Newer map '
            'data arrives with app updates.',
          ),
        ),
      );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    OfflineMapService service,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the map?'),
        content: const Text(
          'The map screen will not work until the map is installed again. '
          'Installing it does not need internet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await service.remove();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(offlineMapServiceProvider.notifier);
    final damaged = state.integrity == MapIntegrity.damaged;

    final buttons = switch (state.status) {
      OfflineMapStatus.checking => const <Widget>[],
      OfflineMapStatus.installing => [
        OutlinedButton(
          onPressed: service.cancelInstall,
          child: const Text('Cancel'),
        ),
      ],
      OfflineMapStatus.ready when damaged => [
        FilledButton(
          onPressed: service.reinstall,
          child: const Text('Install again'),
        ),
      ],
      OfflineMapStatus.ready => [
        OutlinedButton(
          onPressed: () => _verify(context, service),
          child: const Text('Check map'),
        ),
        OutlinedButton(
          onPressed: () => _checkForUpdate(context),
          child: const Text('Check for update'),
        ),
        TextButton(
          onPressed: () => _confirmRemove(context, service),
          child: const Text('Remove'),
        ),
      ],
      OfflineMapStatus.notInstalled => [
        FilledButton(
          onPressed: service.install,
          child: const Text('Install map'),
        ),
      ],
      OfflineMapStatus.interrupted => [
        FilledButton(onPressed: service.install, child: const Text('Continue')),
        TextButton(
          onPressed: () => _confirmRemove(context, service),
          child: const Text('Remove'),
        ),
      ],
      OfflineMapStatus.needsUpdate => [
        FilledButton(
          onPressed: service.install,
          child: const Text('Update map'),
        ),
      ],
      OfflineMapStatus.failed => [
        FilledButton(
          onPressed: service.install,
          child: const Text('Try again'),
        ),
      ],
    };
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: buttons,
        ),
      ),
    );
  }
}
