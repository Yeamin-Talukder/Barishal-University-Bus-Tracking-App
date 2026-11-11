import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../data/repositories/bus_location_repository.dart';
import '../../../../data/repositories/transport_network_repository.dart';
import '../../../../shared/widgets/info_tile.dart';
import '../../../../shared/widgets/stop_badge.dart';
import '../../../buses/presentation/arrival_text.dart';
import '../../../map/application/map_camera_controller.dart';
import '../../../map/application/map_selection.dart';
import '../../../map/application/university_map_configuration_provider.dart';
import '../../../schedule/data/bus_schedule_repository.dart';
import '../../application/nearest_stop.dart';
import '../../application/route_departures.dart';
import '../../application/stop_arrivals.dart';

/// The three stops nearest to the passenger: how far each is, the next bus
/// there and when to set off for it. Three, because the closest stop may
/// not be on the route the passenger wants.
///
/// Until the passenger has shared their position it is a single row that
/// offers to find the stop. The position is read on this device and never
/// sent anywhere. While the card is showing it is read again now and then,
/// so the answer follows the passenger as they walk.
class NearestStopCard extends ConsumerStatefulWidget {
  const NearestStopCard({super.key});

  @override
  ConsumerState<NearestStopCard> createState() => _NearestStopCardState();
}

class _NearestStopCardState extends ConsumerState<NearestStopCard> {
  static const Duration _refreshEvery = Duration(seconds: 30);

  bool _locating = false;
  String? _problem;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // Someone who already shared their position gets fresh answers.
    if (ref.read(userPositionProvider) != null) _startRefreshing();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  void _startRefreshing() {
    _refresh ??= Timer.periodic(_refreshEvery, (_) {
      // Not while the app is in the background.
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      unawaited(_locate(quiet: true));
    });
  }

  /// Reads the position. [quiet] is a refresh in the background: it shows
  /// no spinner and keeps the last answer if it fails.
  Future<void> _locate({bool quiet = false}) async {
    if (_locating) return;
    if (!quiet) {
      setState(() {
        _locating = true;
        _problem = null;
      });
    } else {
      _locating = true;
    }
    final result = await ref.read(locationServiceProvider).currentLocation();
    if (!mounted) return;
    _locating = false;
    switch (result) {
      case LocationFound(:final position):
        final config = ref.read(universityMapConfigurationProvider);
        if (!config.isWithinCoverage(position.latitude, position.longitude)) {
          ref.read(userPositionProvider.notifier).clear();
          setState(
            () => _problem = 'You are outside the area the buses cover.',
          );
          return;
        }
        ref.read(userLocationVisibleProvider.notifier).show();
        ref
            .read(userPositionProvider.notifier)
            .set(position, ref.read(clockProvider)());
        _startRefreshing();
        setState(() => _problem = null);
      case LocationUnavailable():
        if (quiet) {
          setState(() {});
        } else {
          setState(() => _problem = result.message);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final user = ref.watch(userPositionProvider);
    final nearby = ref.watch(nearestStopsProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    // A position found by the map's own button starts the refreshing too.
    ref.listen(userPositionProvider, (previous, next) {
      if (next != null) _startRefreshing();
    });

    final Widget child;
    if (nearby.isEmpty) {
      final message =
          _problem ??
          (user != null
              ? 'No bus stop within ${distanceText(nearestStopWithinMeters)} '
                    'of you.'
              : 'See which stop is closest and when to leave for the bus.');
      child = Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: semantic.info.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.near_me_rounded, color: semantic.info),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stop nearest to you',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(message, style: muted),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _locating
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : FilledButton.tonal(
                  onPressed: _locate,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(user == null ? 'Find' : 'Retry'),
                ),
        ],
      );
    } else {
      final age = ref.watch(clockProvider)().difference(user!.at);
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(Icons.near_me_rounded, size: 18, color: semantic.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    nearby.length == 1
                        ? 'Stop nearest to you'
                        : 'Stops nearest to you',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final (index, near) in nearby.indexed) ...[
            if (index > 0)
              const Divider(
                height: 1,
                indent: AppSpacing.md,
                endIndent: AppSpacing.md,
              ),
            _NearStopRow(
              near: near,
              // The closest one stands out.
              isNearest: index == 0,
              onTap: () => ref
                  .read(mapSelectionProvider.notifier)
                  .selectStop(near.stop.id),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text(
              // A position that could not be refreshed is said to be old.
              age > const Duration(minutes: 2)
                  ? 'Distances are in a straight line. Your position is '
                        '${age.inMinutes} min old.'
                  : 'Distances are in a straight line.',
              style: muted,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: nearby.isEmpty
          ? SoftCard(child: child)
          : SoftCard(padding: EdgeInsets.zero, child: child),
    );
  }
}

/// One stop near the passenger: its name, the walk to it, and the next
/// bus there. Tapping it opens the stop.
class _NearStopRow extends ConsumerWidget {
  const _NearStopRow({
    required this.near,
    required this.isNearest,
    required this.onTap,
  });

  final NearestStop near;
  final bool isNearest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>()!;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final now = ref.watch(clockProvider)();
    final walk = near.walkingTime;
    final walkMinutes = (walk.inSeconds / 60).round().clamp(1, 999);
    final nextBus = ref.watch(stopArrivalsProvider(near.stop.id)).firstOrNull;
    // With no live bus to estimate, the timetable still says which bus
    // comes next and when it sets off.
    final schedule = ref.watch(busScheduleProvider).value;
    final network = ref.watch(transportNetworkProvider).value;
    final scheduled = nextBus != null || schedule == null || network == null
        ? null
        : upcomingDeparturesAt(
            schedule: schedule,
            network: network,
            stop: near.stop,
            now: now,
            count: 1,
          ).firstOrNull;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StopBadge(size: isNearest ? 44 : 36),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    near.stop.name,
                    style:
                        (isNearest
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.titleSmall)
                            ?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.directions_walk_rounded,
                        size: 15,
                        color: semantic.info,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${distanceText(near.distanceMeters)} away · '
                          'about $walkMinutes min on foot',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.directions_bus_rounded,
                        size: 15,
                        color: nextBus != null
                            ? semantic.success
                            : scheduled != null
                            ? semantic.info
                            : semantic.muted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: nextBus != null
                            ? Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text:
                                          'Bus ${nextBus.bus.bus.number}: '
                                          '${arrivalText(nextBus.estimate)}. ',
                                    ),
                                    TextSpan(
                                      text: leaveAdviceText(
                                        leaveAdvice(
                                          walk: walk,
                                          busIn: nextBus.estimate.travelTime,
                                        ),
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                style: theme.textTheme.bodySmall,
                              )
                            : scheduled != null
                            ? Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(text: 'Timetable: '),
                                    TextSpan(
                                      text: scheduled.buses,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' · ${scheduled.routeName} to '
                                          '${scheduled.toName}, leaves '
                                          '${scheduled.fromName} at '
                                          '${formatClockTime(scheduled.at.hour * 60 + scheduled.at.minute)} '
                                          '(${departsInText(scheduled.at, now)}).',
                                    ),
                                  ],
                                ),
                                style: theme.textTheme.bodySmall,
                              )
                            : Text(
                                'No bus can be estimated for this stop right '
                                'now.',
                                style: muted,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
