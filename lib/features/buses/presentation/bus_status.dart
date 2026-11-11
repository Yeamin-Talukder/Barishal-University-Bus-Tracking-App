import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../shared/widgets/status_pill.dart';

/// How a bus's tracking status is worded and coloured everywhere.
extension BusTrackingStatusPresentation on BusTrackingStatus {
  String get label => switch (this) {
    BusTrackingStatus.live => 'Live',
    BusTrackingStatus.delayed => 'Delayed',
    BusTrackingStatus.offline => 'Offline',
  };

  Color color(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return switch (this) {
      BusTrackingStatus.live => semantic.success,
      BusTrackingStatus.delayed => semantic.warning,
      BusTrackingStatus.offline => semantic.offline,
    };
  }
}

/// The status of [tracked] right now.
BusTrackingStatus busStatusNow(WidgetRef ref, TrackedBus tracked) {
  return ref
      .watch(trackingConfigurationProvider)
      .statusOf(tracked.location?.updatedAt, ref.watch(clockProvider)());
}

/// "Updated 12 seconds ago", or a plain statement that nothing was received.
/// An old position is always described by its age, never as current.
String lastSeenText(WidgetRef ref, TrackedBus tracked) {
  final updatedAt = tracked.location?.updatedAt;
  if (updatedAt == null) return 'No position received yet';
  final age = ref.watch(clockProvider)().difference(updatedAt);
  return 'Updated ${formatAge(age.isNegative ? Duration.zero : age)}';
}

class BusStatusPill extends ConsumerWidget {
  const BusStatusPill({required this.tracked, super.key});

  final TrackedBus tracked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = busStatusNow(ref, tracked);
    return StatusPill(label: status.label, color: status.color(context));
  }
}
