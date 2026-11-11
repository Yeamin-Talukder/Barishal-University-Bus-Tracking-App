import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/section_card.dart';
import '../application/update_controller.dart';
import 'update_sheet.dart';

/// Profile → "App updates": the installed version, the update state, and a
/// button that checks or continues the update in the sheet.
class AppUpdateSection extends ConsumerWidget {
  const AppUpdateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    if (state is UpdateUnsupported) return const SizedBox.shrink();
    final controller = ref.read(updateControllerProvider.notifier);
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>()!;
    final version = controller.currentVersion;

    final (String subtitle, Color color, IconData icon, String action) = switch (state) {
      UpdateAvailable(:final release) => ('Version ${release.version} is ready to download.', theme.accent, Icons.system_update_rounded, 'Update'),
      UpdateDownloading(:final fraction) => ('Downloading… ${fraction == null ? '' : '${(fraction * 100).floor()}%'}', theme.accent, Icons.downloading_rounded, 'Open'),
      UpdateVerifying() => ('Checking the download…', theme.accent, Icons.verified_user_rounded, 'Open'),
      UpdateReady() || UpdateNeedsPermission() || UpdateInstalling() =>
        ('The update is downloaded and ready to install.', theme.accent, Icons.install_mobile_rounded, 'Install'),
      UpdateUpToDate(:final checkedAt) => ('Up to date · checked ${_ago(checkedAt)}', semantic.success, Icons.check_circle_rounded, 'Check'),
      UpdateFailed() => ('The last check or update did not finish.', theme.colorScheme.error, Icons.error_outline_rounded, 'Retry'),
      UpdateChecking() => ('Checking for updates…', theme.accent, Icons.sync_rounded, 'Open'),
      _ => ('Updates install right here in the app.', theme.accent, Icons.system_update_rounded, 'Check'),
    };
    final highlight = state is UpdateAvailable || state is UpdateReady || state is UpdateNeedsPermission;

    Future<void> open() async {
      if (state is UpdateIdle || state is UpdateUpToDate || (state is UpdateFailed && state.retry == null)) {
        controller.check(userAsked: true);
      }
      await showUpdateSheet(context);
    }

    return SectionCard(
      title: 'App updates',
      children: [
        ListTile(
          onTap: open,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          leading: AnimatedContainer(
            duration: AppMotion.standard,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: AnimatedSwitcher(
              duration: AppMotion.quick,
              child: Icon(icon, key: ValueKey(icon), color: color, size: 21),
            ),
          ),
          title: Text(
            version == null ? 'BU Bus Tracker' : 'Version $version',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: AnimatedSwitcher(
            duration: AppMotion.quick,
            layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
            child: Text(subtitle, key: ValueKey(subtitle)),
          ),
          trailing: highlight
              ? FilledButton(onPressed: open, child: Text(action))
              : OutlinedButton(onPressed: open, child: Text(action)),
        ),
      ],
    );
  }

  static String _ago(DateTime time) {
    final d = DateTime.now().difference(time);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Checks for an update once, a few seconds after the app starts, and
/// offers it in the sheet unless the person chose "Later" for that version.
class UpdateLauncher extends ConsumerStatefulWidget {
  const UpdateLauncher({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<UpdateLauncher> createState() => _UpdateLauncherState();
}

class _UpdateLauncherState extends ConsumerState<UpdateLauncher> {
  bool _offered = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Not on iOS or the web preview, where the app is not updated this way.
    if (ref.read(updateControllerProvider) is UpdateUnsupported) return;
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) ref.read(updateControllerProvider.notifier).check();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(updateControllerProvider, (previous, next) {
      if (_offered || next is! UpdateAvailable || previous is! UpdateChecking) return;
      if (!ref.read(updateControllerProvider.notifier).shouldOffer(next.release)) return;
      _offered = true;
      showUpdateSheet(context);
    });
    return widget.child;
  }
}
