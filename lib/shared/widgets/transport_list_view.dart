import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../data/models/transport_network.dart';
import '../../data/repositories/transport_network_repository.dart';
import 'demo_data_notice.dart';
import 'empty_state.dart';
import 'skeleton_list.dart';

/// The shared body of the Routes and Stops tabs: loading skeleton, error
/// with retry, empty state, or the list with its notices.
class TransportListView<T> extends ConsumerWidget {
  const TransportListView({
    required this.itemsOf,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    super.key,
  });

  final List<T> Function(TransportNetwork network) itemsOf;
  final Widget Function(BuildContext context, TransportNetwork network, T item)
  itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(transportNetworkProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: network.when(
        // A change to the stops reloads the list; keep showing it meanwhile.
        skipLoadingOnReload: true,
        loading: () => const SkeletonList(key: ValueKey('loading')),
        error: (error, stackTrace) => EmptyState(
          key: const ValueKey('error'),
          icon: Icons.error_outline_rounded,
          title: 'This list could not be loaded',
          message: 'The route data on this device could not be read.',
          action: FilledButton.icon(
            onPressed: () {
              ref
                ..invalidate(transportRepositoryProvider)
                ..invalidate(transportNetworkProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (network) {
          final items = itemsOf(network);
          if (items.isEmpty) {
            return EmptyState(
              key: const ValueKey('empty'),
              icon: emptyIcon,
              title: emptyTitle,
              message: emptyMessage,
            );
          }

          final theme = Theme.of(context);
          return ListView(
            key: const ValueKey('list'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              if (network.needsNotice)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DemoDataNotice(origin: network.origin),
                  ),
                ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: itemBuilder(context, network, item),
                ),
              if (network.problems.isNotEmpty)
                Text(
                  '${network.problems.length} entries in the route data were '
                  'skipped because they are invalid.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
