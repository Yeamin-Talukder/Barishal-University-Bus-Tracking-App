import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../shared/widgets/info_tile.dart';
import '../application/prediction_providers.dart';
import '../domain/prediction.dart';

/// "9:42 AM" for a moment today.
String predictedClockText(DateTime at) =>
    formatClockTime(at.hour * 60 + at.minute);

/// What a prediction rests on, in a few words.
String predictionBasisText(PredictedBus bus, DateTime now) {
  switch (bus.basis) {
    case PredictionBasis.timetable:
      return 'From the timetable: left at ${predictedClockText(bus.basedOn)}';
    case PredictionBasis.lastSeen:
      final age = now.difference(bus.basedOn);
      return 'From where it was last seen, '
          '${formatAge(age.isNegative ? Duration.zero : age)}';
  }
}

/// The round badge of a predicted bus: an outline, not a filled disc, so
/// it is not taken for a live one.
class PredictedBadge extends StatelessWidget {
  const PredictedBadge({this.size = 44, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).extension<AppSemanticColors>()!.info;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.6),
      ),
      child: Icon(Icons.update_rounded, color: color, size: size * 0.5),
    );
  }
}

/// The predicted buses, in the sheet over the map: where buses probably
/// are when there is no live position for them. Takes no space when there
/// is nothing to predict.
class PredictedBusesSection extends ConsumerWidget {
  const PredictedBusesSection({required this.onRouteSelected, super.key});

  /// Called with a route's id when its predicted bus is tapped.
  final ValueChanged<String> onRouteSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buses = ref.watch(predictedBusesProvider);
    if (buses.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = theme.extension<AppSemanticColors>()!.info;
    final now = ref.watch(clockProvider)();
    final assumesSpeed = buses.any((bus) => !bus.usesLearnedSpeed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Predicted buses'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: info),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  assumesSpeed
                      ? 'Not live. Worked out on this phone from the '
                            'timetable, assuming about 20 km/h until real '
                            'trips have been seen.'
                      : 'Not live. Worked out on this phone from the '
                            'timetable and from how fast buses have been '
                            'seen to go.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final (index, bus) in buses.indexed)
          Padding(
            key: ValueKey(bus.id),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: Appear(
              delay: Duration(milliseconds: 50 * index),
              child: _PredictedBusCard(
                bus: bus,
                now: now,
                onTap: () => onRouteSelected(bus.routeId),
              ),
            ),
          ),
      ],
    );
  }
}

class _PredictedBusCard extends StatelessWidget {
  const _PredictedBusCard({
    required this.bus,
    required this.now,
    required this.onTap,
  });

  final PredictedBus bus;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = theme.extension<AppSemanticColors>()!.info;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final nextStop = bus.nextStopName;
    final nextAt = bus.nextStopAt;

    return SoftCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PredictedBadge(),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        bus.basis == PredictionBasis.lastSeen
                            ? 'Bus ${bus.label}'
                            : bus.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: info.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Text(
                        'Predicted',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: info,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.near_me_rounded, size: 14, color: info),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${bus.fromName} → ${bus.toName}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: info,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(predictionBasisText(bus, now), style: muted),
                if (bus.vehicles != null && bus.vehicles!.isNotEmpty)
                  Text('Named in the timetable: ${bus.vehicles}', style: muted),
                if (nextStop != null && nextAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Should reach $nextStop about '
                    '${predictedClockText(nextAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// The predicted arrivals at a stop: times from the timetable and from
/// buses last seen on their way. Takes no space when there are none.
class PredictedArrivalsSection extends ConsumerWidget {
  const PredictedArrivalsSection({required this.stopId, super.key});

  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arrivals = ref.watch(predictedArrivalsProvider(stopId));
    if (arrivals.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = theme.extension<AppSemanticColors>()!.info;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Predicted arrivals'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (index, arrival) in arrivals.indexed) ...[
                  if (index > 0)
                    const Divider(
                      height: 1,
                      indent: AppSpacing.md,
                      endIndent: AppSpacing.md,
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 92,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: info.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Text(
                            '~ ${predictedClockText(arrival.at)}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: info,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                arrival.label == null
                                    ? arrival.routeName
                                    : 'Bus ${arrival.label} · '
                                          '${arrival.routeName}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${arrival.fromName} → ${arrival.toName}',
                                style: muted,
                              ),
                              Text(
                                arrival.basis == PredictionBasis.timetable
                                    ? 'From the timetable'
                                    : 'From where it was last seen',
                                style: muted,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: Text(
            'Predictions, not live times. The timetable does not say on '
            'which days it runs.',
            style: muted,
          ),
        ),
      ],
    );
  }
}

/// The Profile tab's controls for predictions: on or off, what has been
/// learned, and a way to forget it.
class PredictionSettings extends ConsumerWidget {
  const PredictionSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final show = ref.watch(showPredictionsProvider);
    final memory = ref.watch(predictionLearnerProvider);
    final learned = memory.profile.speeds.length;
    final samples = memory.profile.sampleCount;
    final savedAt = memory.savedAt;

    final learnedText = learned == 0
        ? 'Nothing learned yet. Until buses have been seen live, about '
              '20 km/h is assumed.'
        : 'Speeds learned for $learned route '
              '${learned == 1 ? 'direction' : 'directions'}, from $samples '
              '${samples == 1 ? 'stretch' : 'stretches'} of real trips.';
    final savedText = savedAt == null
        ? 'Nothing saved on this phone yet.'
        : 'Saved on this phone at ${predictedClockText(savedAt)}. '
              'Works with no connection.';

    return Column(
      children: [
        SwitchListTile(
          value: show,
          onChanged: (value) =>
              ref.read(showPredictionsProvider.notifier).set(value),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          secondary: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.update_rounded, color: scheme.primary, size: 21),
          ),
          title: Text(
            'Show predicted buses',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Where a bus probably is when there is no live position, from '
            'the timetable and where it was last seen. Always marked as '
            'predicted.',
          ),
        ),
        const Divider(
          height: 1,
          indent: AppSpacing.lg,
          endIndent: AppSpacing.lg,
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(learnedText, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                savedText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (learned > 0 || memory.lastSeen.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(predictionLearnerProvider.notifier).clear(),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('Forget what was learned'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
