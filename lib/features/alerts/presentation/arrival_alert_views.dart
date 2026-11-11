import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../buses/presentation/arrival_text.dart';
import '../../map/application/map_selection.dart';
import '../application/arrival_alert.dart';

/// The minutes a passenger can ask to be warned at.
const List<int> alertMinuteChoices = [2, 5, 10];

/// A bell on a bus heading for a stop. Tapping it sets an alert for when
/// that bus is a few minutes away, or cancels the one that is set.
class ArrivalAlertButton extends ConsumerWidget {
  const ArrivalAlertButton({
    required this.busId,
    required this.busNumber,
    required this.stopId,
    required this.stopName,
    super.key,
  });

  final String busId;
  final String busNumber;
  final String stopId;
  final String stopName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final alert = ref.watch(arrivalAlertProvider.select((s) => s.alert));
    final isSet = alert != null && alert.isFor(busId: busId, stopId: stopId);

    return IconButton(
      tooltip: isSet
          ? 'Cancel the alert for Bus $busNumber'
          : 'Alert me when Bus $busNumber is near',
      isSelected: isSet,
      color: scheme.onSurfaceVariant,
      selectedIcon: Icon(
        Icons.notifications_active_rounded,
        color: scheme.primary,
      ),
      icon: const Icon(Icons.notifications_none_rounded),
      onPressed: () async {
        final alerts = ref.read(arrivalAlertProvider.notifier);
        if (isSet) {
          alerts.cancel();
          return;
        }
        final minutes = await showModalBottomSheet<int>(
          context: context,
          showDragHandle: true,
          builder: (context) =>
              _AlertChoice(busNumber: busNumber, stopName: stopName),
        );
        if (minutes == null) return;
        alerts.set(
          ArrivalAlert(
            busId: busId,
            busNumber: busNumber,
            stopId: stopId,
            stopName: stopName,
            minutes: minutes,
          ),
        );
      },
    );
  }
}

class _AlertChoice extends StatelessWidget {
  const _AlertChoice({required this.busNumber, required this.stopName});

  final String busNumber;
  final String stopName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert me about Bus $busNumber',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'When it is this far from $stopName:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final minutes in alertMinuteChoices)
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(minutes),
                    child: Text('$minutes min'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'The alert works while the app is open. It cannot ring '
                    'when the app is closed or the screen is off. It uses '
                    'the same estimate shown here, so it is given only '
                    'while the bus is live and moving.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A line over the map while an alert is being waited for, with the way
/// to cancel it.
class ArrivalAlertLabel extends ConsumerWidget {
  const ArrivalAlertLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(arrivalAlertProvider.select((s) => s.alert));
    if (alert == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_active_rounded,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Alert: Bus ${alert.busNumber}, ${alert.minutes} min before '
              '${alert.stopName}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: ref.read(arrivalAlertProvider.notifier).cancel,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSecondaryContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Tells the passenger when their alert comes due, on whichever tab they
/// are: a dialog, with a buzz and the system's alert sound.
class ArrivalAlertListener extends ConsumerWidget {
  const ArrivalAlertListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(arrivalAlertProvider.select((state) => state.notice), (
      previous,
      notice,
    ) {
      if (notice == null || notice.serial == previous?.serial) return;
      final alert = notice.alert;
      if (notice.outcome == AlertOutcome.due) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.notifications_active_rounded),
            title: Text('Bus ${alert.busNumber} is near'),
            content: Text(
              '${notice.travelTime == null ? 'It is close' : travelTimeText(notice.travelTime!)} '
              'to ${alert.stopName} (estimate).',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref
                      .read(mapSelectionProvider.notifier)
                      .selectBus(alert.busId);
                },
                child: const Text('Show bus'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      // The alert can no longer be given: say why, quietly.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              notice.outcome == AlertOutcome.passed
                  ? 'Alert ended: Bus ${alert.busNumber} has passed '
                        '${alert.stopName}.'
                  : 'Alert ended: Bus ${alert.busNumber} is no longer '
                        'being tracked.',
            ),
          ),
        );
    });
    return child;
  }
}
