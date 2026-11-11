import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../data/repositories/bus_location_repository.dart';
import '../../../../shared/widgets/info_tile.dart';
import '../../../../shared/widgets/stop_badge.dart';
import '../../../buses/presentation/arrival_text.dart';
import '../../../map/application/map_camera_controller.dart';
import '../../../map/application/map_selection.dart';
import '../../../map/application/university_map_configuration_provider.dart';
import '../../application/nearest_stop.dart';
import '../../application/stop_arrivals.dart';

/// The stop nearest to the passenger, how far it is, the next bus there and
/// when to set off for it.
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
    final nearest = ref.watch(nearestStopProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    // A position found by the map's own button starts the refreshing too.
    ref.listen(userPositionProvider, (previous, next) {
      if (next != null) _startRefreshing();
    });

    final Widget child;
    if (nearest == null) {
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
      final arrivals = ref.watch(stopArrivalsProvider(nearest.stop.id));
      final nextBus = arrivals.firstOrNull;
      final walk = nearest.walkingTime;
      final walkMinutes = (walk.inSeconds / 60).round().clamp(1, 999);
      final age = ref.watch(clockProvider)().difference(user!.at);
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StopBadge(size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stop nearest to you', style: muted),
                    Text(
                      nearest.stop.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.directions_walk_rounded,
                size: 17,
                color: semantic.info,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'About ${distanceText(nearest.distanceMeters)} away in a '
                  'straight line, roughly $walkMinutes min on foot',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.directions_bus_rounded,
                size: 17,
                color: nextBus == null ? semantic.muted : semantic.success,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: nextBus == null
                    ? Text(
                        'No bus can be estimated for this stop right now.',
                        style: muted,
                      )
                    : Text.rich(
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
                      ),
              ),
            ],
          ),
          // A position that could not be refreshed is said to be old.
          if (age > const Duration(minutes: 2))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Your position is ${age.inMinutes} min old.',
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
      child: SoftCard(
        onTap: nearest == null
            ? null
            : () => ref
                  .read(mapSelectionProvider.notifier)
                  .selectStop(nearest.stop.id),
        child: child,
      ),
    );
  }
}
