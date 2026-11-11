import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../application/update_controller.dart';
import '../domain/app_release.dart';

/// Opens the update sheet. The whole update happens in it: download,
/// checking the file, and handing it to Android's installer.
Future<void> showUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const UpdateSheet(),
  );
}

class UpdateSheet extends ConsumerStatefulWidget {
  const UpdateSheet({super.key});

  @override
  ConsumerState<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<UpdateSheet>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Back from Android's "Install unknown apps" switch.
    if (lifecycle == AppLifecycleState.resumed) {
      ref.read(updateControllerProvider.notifier).onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: AppMotion.standard,
      curve: AppMotion.emphasized,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _StatusBadge(state: state)),
            const SizedBox(height: AppSpacing.lg),
            _Switch(
              child: Text(
                _title(state),
                key: ValueKey(_title(state)),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Switch(
              child: Text(
                _subtitle(state),
                key: ValueKey(_subtitle(state)),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (state is UpdateWithRelease) ...[
              const SizedBox(height: AppSpacing.lg),
              _VersionRow(state: state),
            ],
            const SizedBox(height: AppSpacing.lg),
            _Switch(
              child: _Body(key: ValueKey(state.runtimeType), state: state),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Actions(state: state, controller: controller),
            if (state is UpdateWithRelease) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    size: 15,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'From the project\'s GitHub releases, checked before installing. '
                      'Your settings stay.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _title(UpdateState s) => switch (s) {
    UpdateIdle() || UpdateChecking() => 'Checking for updates',
    UpdateUnsupported() => 'Updates',
    UpdateUpToDate() => "You're up to date",
    UpdateAvailable() => 'Update available',
    UpdateDownloading() => 'Downloading update',
    UpdateVerifying() => 'Checking the download',
    UpdateReady() => 'Ready to install',
    UpdateNeedsPermission() => 'One more step',
    UpdateInstalling() => 'Installing',
    UpdateFailed() => "The update didn't finish",
  };

  static String _subtitle(UpdateState s) => switch (s) {
    UpdateIdle() || UpdateChecking() => 'Looking for a newer version…',
    UpdateUnsupported() =>
      'On this device the app is updated through its store.',
    UpdateUpToDate(:final current) => 'Version $current is the newest version.',
    UpdateAvailable() => 'A new version of BU Bus Tracker is ready for you.',
    UpdateDownloading() =>
      'Keep the app open. You can use your phone meanwhile.',
    UpdateVerifying() => 'Making sure the file is exactly the published one.',
    UpdateReady(:final note) =>
      note ?? 'The update has downloaded and checked out.',
    UpdateNeedsPermission() => 'Android asks you once to allow BU Bus Tracker to install its own updates.',
    UpdateInstalling() => 'Tap Update on the screen Android shows. The app restarts as the new version.',
    UpdateFailed(:final message) => message,
  };
}

/// Cross-fades and slightly lifts changing content.
class _Switch extends StatelessWidget {
  const _Switch({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

/// The round badge at the top: its icon follows the state, a ring shows the
/// download's progress, and a soft pulse marks an update waiting.
class _StatusBadge extends StatefulWidget {
  const _StatusBadge({required this.state});
  final UpdateState state;

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _animate => switch (widget.state) {
    UpdateAvailable() ||
    UpdateChecking() ||
    UpdateIdle() ||
    UpdateVerifying() ||
    UpdateInstalling() => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (_animate && !reduce) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>()!;
    final s = widget.state;
    final (IconData icon, Color color) = switch (s) {
      UpdateUpToDate() => (Icons.check_circle_rounded, semantic.success),
      UpdateAvailable() => (Icons.system_update_rounded, theme.accent),
      UpdateDownloading() => (Icons.download_rounded, theme.accent),
      UpdateVerifying() => (Icons.verified_user_rounded, theme.accent),
      UpdateReady() => (Icons.install_mobile_rounded, theme.accent),
      UpdateNeedsPermission() => (Icons.lock_open_rounded, semantic.warning),
      UpdateInstalling() => (Icons.install_mobile_rounded, theme.accent),
      UpdateFailed() => (Icons.error_rounded, theme.colorScheme.error),
      UpdateUnsupported() => (Icons.store_rounded, semantic.muted),
      UpdateIdle() || UpdateChecking() => (Icons.sync_rounded, theme.accent),
    };
    final spinning =
        s is UpdateChecking || s is UpdateIdle || s is UpdateVerifying;
    final fraction = s is UpdateDownloading ? s.fraction : null;

    return SizedBox.square(
      dimension: 108,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Pulse: a ring that grows and fades.
              if (_pulse.isAnimating && !spinning)
                Container(
                  width: 76 + 30 * t,
                  height: 76 + 30 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.45 * (1 - t)),
                      width: 2,
                    ),
                  ),
                ),
              // Progress ring while downloading; a turning arc while working.
              SizedBox.square(
                dimension: 92,
                child: s is UpdateDownloading
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(end: fraction ?? 0),
                        duration: const Duration(milliseconds: 260),
                        builder: (_, value, _) => CircularProgressIndicator(
                          value: fraction == null ? null : value,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.15),
                        ),
                      )
                    : spinning
                    ? Transform.rotate(
                        angle: t * 2 * math.pi,
                        child: CircularProgressIndicator(
                          value: 0.28,
                          strokeWidth: 4,
                          strokeCap: StrokeCap.round,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.12),
                        ),
                      )
                    : null,
              ),
              AnimatedContainer(
                duration: AppMotion.standard,
                curve: AppMotion.emphasized,
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.28),
                      color.withValues(alpha: 0.12),
                    ],
                  ),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: AnimatedSwitcher(
                  duration: AppMotion.standard,
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: Tween<double>(begin: 0.4, end: 1).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: s is UpdateDownloading
                      ? Text(
                          fraction == null
                              ? '…'
                              : '${(fraction * 100).floor()}%',
                          key: const ValueKey('pct'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        )
                      : Icon(icon, key: ValueKey(icon), size: 34, color: color),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "1.0.0 → 1.1.0" and the file for this phone.
class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.state});
  final UpdateWithRelease state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(String text, {bool strong = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: strong
            ? theme.accent.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: strong
              ? theme.accent.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: strong ? theme.accent : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            chip(state.current.toString()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.outline,
              ),
            ),
            chip(state.release.version.toString(), strong: true),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${state.apk.build.label} build · ${formatBytes(state.apk.size)}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, super.key});
  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = state;
    switch (s) {
      case UpdateAvailable(:final release):
        final notes = plainReleaseNotes(release.notes);
        if (notes.isEmpty) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: theme.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    "What's new",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ),
              ),
            ],
          ),
        );
      case UpdateDownloading(
        :final received,
        :final total,
        :final bytesPerSecond,
        :final fraction,
      ):
        final left = bytesPerSecond > 0 && total > received
            ? (total - received) / bytesPerSecond
            : null;
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction ?? 0),
                duration: const Duration(milliseconds: 260),
                builder: (_, value, _) => LinearProgressIndicator(
                  value: fraction == null ? null : value,
                  minHeight: 10,
                  color: theme.accent,
                  backgroundColor: theme.accent.withValues(alpha: 0.14),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '${formatBytes(received)} of ${formatBytes(total)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text(
                  [
                    if (bytesPerSecond > 0)
                      '${formatBytes(bytesPerSecond.round())}/s',
                    if (left != null) _timeLeft(left),
                  ].join(' · '),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        );
      case UpdateNeedsPermission():
        return _Steps(
          steps: const [
            (Icons.touch_app_rounded, 'Tap "Allow installs" below.'),
            (Icons.toggle_on_rounded, 'Turn on "Allow from this source".'),
            (
              Icons.keyboard_return_rounded,
              'Come back: the install continues by itself.',
            ),
          ],
        );
      case UpdateInstalling():
        return _Steps(
          steps: const [
            (
              Icons.system_update_rounded,
              'Android shows "Do you want to update this app?"',
            ),
            (
              Icons.check_circle_outline_rounded,
              'Tap Update. Your settings and saved data stay.',
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  static String _timeLeft(double seconds) {
    if (seconds < 60) return '${seconds.ceil()} s left';
    return '${(seconds / 60).ceil()} min left';
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps});
  final List<(IconData, String)> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final (i, (icon, text)) in steps.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 18, color: theme.accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.controller});
  final UpdateState state;
  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).maybePop();
    final s = state;

    final (Widget? primary, Widget? secondary) = switch (s) {
      UpdateAvailable() => (
        FilledButton.icon(
          onPressed: controller.download,
          icon: const Icon(Icons.download_rounded),
          label: Text('Download and install · ${formatBytes(s.apk.size)}'),
        ),
        TextButton(
          onPressed: () {
            controller.later();
            close();
          },
          child: const Text('Later'),
        ),
      ),
      UpdateDownloading() => (
        null,
        OutlinedButton.icon(
          onPressed: controller.cancelDownload,
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel download'),
        ),
      ),
      UpdateReady() => (
        FilledButton.icon(
          onPressed: controller.install,
          icon: const Icon(Icons.install_mobile_rounded),
          label: const Text('Install now'),
        ),
        TextButton(onPressed: close, child: const Text('Later')),
      ),
      UpdateNeedsPermission() => (
        FilledButton.icon(
          onPressed: controller.openInstallPermission,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Allow installs'),
        ),
        TextButton(onPressed: close, child: const Text('Not now')),
      ),
      UpdateInstalling() => (
        null,
        TextButton(
          onPressed: controller.install,
          child: const Text("Android's screen didn't open? Try again"),
        ),
      ),
      UpdateFailed(:final retry) => (
        FilledButton.icon(
          onPressed: retry == null
              ? () => controller.check(userAsked: true)
              : retry is UpdateReady
              ? controller.install
              : controller.download,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
        TextButton(onPressed: close, child: const Text('Close')),
      ),
      UpdateUpToDate() => (
        FilledButton.icon(
          onPressed: close,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Done'),
        ),
        TextButton(
          onPressed: () => controller.check(userAsked: true),
          child: const Text('Check again'),
        ),
      ),
      UpdateIdle() ||
      UpdateChecking() ||
      UpdateVerifying() ||
      UpdateUnsupported() => (null, null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primary != null) SizedBox(height: 52, child: primary),
        if (primary != null && secondary != null)
          const SizedBox(height: AppSpacing.sm),
        ?secondary,
      ],
    );
  }
}

/// "35.6 MB", "820 KB".
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}
