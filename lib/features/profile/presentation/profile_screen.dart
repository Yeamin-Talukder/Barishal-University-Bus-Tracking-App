import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/firebase_bootstrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_location_repository.dart';
import '../../../data/repositories/transport_network_repository.dart';
import '../../auth/domain/user_profile.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/info_tile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';
import '../../auth/presentation/account_section.dart';
import '../../driver/presentation/driver_section.dart';
import '../../map/application/university_map_configuration_provider.dart';
import '../../app_update/presentation/app_update_section.dart';
import '../../map/presentation/offline_map_section.dart';
import '../../prediction/presentation/predicted_buses_section.dart';
import 'widgets/theme_mode_selector.dart';

/// Who the app is for, appearance, the offline map, trying the app out,
/// staff sign-in and the state of the tracking service.
///
/// The notifications section is added with that feature, so nothing here is
/// a dead control.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseStatus = ref.watch(firebaseStatusProvider);
    const gap = SizedBox(height: AppSpacing.xl);
    const line = Divider(
      height: 1,
      indent: AppSpacing.lg,
      endIndent: AppSpacing.lg,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      // Not a lazy list: the page is short, and every section should be
      // there to scroll to.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Appear(child: _AppHeader()),
            gap,
            SectionCard(
              title: 'Appearance',
              children: [
                SettingsTile(
                  icon: Icons.palette_rounded,
                  title: 'Theme',
                  subtitle: switch (ref.watch(themeModeProvider)) {
                    ThemeMode.dark => "Dark, the app's own look.",
                    ThemeMode.light => 'Light, on cool white.',
                    ThemeMode.system => "Follows this phone's setting.",
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: ThemeModeSelector(),
                ),
              ],
            ),
            gap,
            const OfflineMapSection(),
            gap,
            const SectionCard(
              title: 'Predictions',
              children: [PredictionSettings()],
            ),
            gap,
            SectionCard(
              title: 'Try it out',
              children: [
                SettingsTile(
                  icon: Icons.science_rounded,
                  title: 'Test the system',
                  subtitle:
                      'Run pretend buses on this phone to see the app at work. '
                      'Nobody else sees them.',
                  onTap: () => context.push(AppRoutes.testDrive),
                ),
              ],
            ),
            gap,
            const AccountSection(),
            gap,
            // Shown to drivers only; takes no space for anyone else.
            const DriverSection(),
            if (ref.watch(isAdminProvider)) ...[
              SectionCard(
                title: 'Administration',
                children: [
                  SettingsTile(
                    icon: Icons.edit_location_alt_rounded,
                    title: 'Manage stops',
                    subtitle: 'Add, move, rename or delete stops.',
                    onTap: () => context.push(AppRoutes.adminStops),
                  ),
                  line,
                  SettingsTile(
                    icon: Icons.edit_calendar_rounded,
                    title: 'Manage schedule',
                    subtitle: 'Change routes, departure times and buses.',
                    onTap: () => context.push(AppRoutes.adminSchedule),
                  ),
                  line,
                  SettingsTile(
                    icon: Icons.directions_bus_rounded,
                    title: 'Manage buses',
                    subtitle: 'Add buses, and set their route and driver.',
                    onTap: () => context.push(AppRoutes.adminBuses),
                  ),
                  line,
                  SettingsTile(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Manage people',
                    subtitle: 'Make someone a driver or an admin, or deactivate them.',
                    onTap: () => context.push(AppRoutes.adminPeople),
                  ),
                  line,
                  SettingsTile(
                    icon: Icons.campaign_rounded,
                    title: 'Announcements',
                    subtitle: 'Post a notice to every passenger.',
                    onTap: () => context.push(AppRoutes.adminAnnouncements),
                  ),
                ],
              ),
              gap,
            ],
            SectionCard(
              title: 'Service',
              children: [_BackendStatusTile(status: firebaseStatus)],
            ),
            gap,
            const AppUpdateSection(),
            gap,
            SectionCard(
              title: 'About',
              children: [
                SettingsTile(
                  icon: Icons.info_rounded,
                  title: 'About BU Bus Tracker',
                  subtitle: 'The developer, the source code and the credits.',
                  onTap: () => context.push(AppRoutes.about),
                ),
              ],
            ),
            gap,
            // What the app is and whose map it draws.
            Center(
              child: Column(
                children: [
                  Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Map data © OpenStreetMap contributors',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The top of the page: what the app is, who is using it, and the service
/// at a glance (how many routes and stops there are and how many buses are
/// live right now).
class _AppHeader extends ConsumerWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A tonal card: the accent's own container colour, with the text made
    // for it, so it reads the same at every corner in both themes.
    final onBrand = scheme.onPrimaryContainer;
    final config = ref.watch(universityMapConfigurationProvider);

    final account = ref.watch(accountProvider).value;
    final role = ref.watch(userProfileProvider).value?.role;
    final who = account == null
        ? 'Passenger · no account needed'
        : 'Signed in · ${(role ?? UserRole.student).label}';

    final network = ref.watch(transportNetworkProvider).value;
    final buses = ref.watch(trackedBusesProvider).value ?? const <TrackedBus>[];
    final tracking = ref.watch(trackingConfigurationProvider);
    final now = ref.watch(clockProvider)();
    final liveCount = buses
        .where(
          (bus) =>
              tracking.statusOf(bus.location?.updatedAt, now) ==
              BusTrackingStatus.live,
        )
        .length;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: scheme.primaryContainer,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Stack(
        children: [
          // Two soft discs give the card some depth without a picture.
          Positioned(
            top: -70,
            right: -50,
            child: _Disc(
              size: 190,
              color: scheme.primary.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            bottom: -90,
            left: -40,
            child: _Disc(
              size: 170,
              color: scheme.primary.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      // The one solid spot of accent on the card.
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.directions_bus_rounded,
                        color: scheme.onPrimary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConstants.appShortName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: onBrand,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            config.universityName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onBrand.withValues(alpha: 0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            config.universityNameBangla,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onBrand.withValues(alpha: 0.75),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        account == null
                            ? Icons.person_rounded
                            : Icons.verified_user_rounded,
                        size: 15,
                        color: onBrand,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          who,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: onBrand,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // The service at a glance.
                Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        _Stat(
                          value: network == null
                              ? '–'
                              : '${network.routes.length}',
                          label: 'routes',
                          color: onBrand,
                        ),
                        VerticalDivider(
                          width: 1,
                          color: onBrand.withValues(alpha: 0.18),
                        ),
                        _Stat(
                          value: network == null
                              ? '–'
                              : '${network.stops.length}',
                          label: 'stops',
                          color: onBrand,
                        ),
                        VerticalDivider(
                          width: 1,
                          color: onBrand.withValues(alpha: 0.18),
                        ),
                        _Stat(
                          value: '$liveCount',
                          label: 'live now',
                          color: onBrand,
                          dot: liveCount > 0
                              ? theme.extension<AppSemanticColors>()!.success
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// One number with what it counts under it.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    this.dot,
  });

  final String value;
  final String label;
  final Color color;

  /// A small dot beside the number, in this colour, when given.
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              AnimatedSwitcher(
                duration: AppMotion.quick,
                child: Text(
                  value,
                  key: ValueKey(value),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendStatusTile extends StatelessWidget {
  const _BackendStatusTile({required this.status});

  final FirebaseStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;

    final (icon, color, title, subtitle) = switch (status.availability) {
      FirebaseAvailability.ready => (
        Icons.cloud_done_rounded,
        semantic.success,
        'Connected to the tracking service',
        'Live bus tracking can be used.',
      ),
      FirebaseAvailability.notConfigured => (
        Icons.cloud_off_rounded,
        semantic.muted,
        'Tracking service not set up',
        'Sign-in and live bus tracking are unavailable in this build.',
      ),
      FirebaseAvailability.failed => (
        Icons.error_outline_rounded,
        scheme.error,
        'Could not reach the tracking service',
        'Sign-in and live bus tracking are unavailable right now.',
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
