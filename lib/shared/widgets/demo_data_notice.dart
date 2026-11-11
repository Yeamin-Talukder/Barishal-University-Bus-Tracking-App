import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/transport_network.dart';

/// Shown wherever routes and stops that are not verified appear, so sample
/// data or unconfirmed positions can never be mistaken for official
/// information.
class DemoDataNotice extends StatelessWidget {
  const DemoDataNotice({this.origin = TransportDataOrigin.demo, super.key});

  /// What kind of unverified data is on screen.
  final TransportDataOrigin origin;

  static const String demoText = 'Demo data, not official routes';
  static const String unconfirmedText =
      'Unconfirmed stop positions, for checking only';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = theme.extension<AppSemanticColors>()!.warning;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: warning),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            origin == TransportDataOrigin.unconfirmed
                ? Icons.help_outline_rounded
                : Icons.science_rounded,
            size: 18,
            color: warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              origin == TransportDataOrigin.unconfirmed
                  ? unconfirmedText
                  : demoText,
              style: theme.textTheme.labelMedium?.copyWith(color: warning),
            ),
          ),
        ],
      ),
    );
  }
}
