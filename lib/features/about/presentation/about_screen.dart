import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/info_tile.dart';
import '../../../shared/widgets/section_card.dart';
import '../../app_update/application/update_controller.dart';
import '../../app_update/domain/app_release.dart';

/// The developer and the project's links.
abstract final class AboutLinks {
  static const String developerName = 'Yeamin Talukder';
  static const String developerHandle = UpdateSource.owner;
  static const String developerGithub =
      'https://github.com/${UpdateSource.owner}';
  static const String sourceCode =
      'https://github.com/${UpdateSource.owner}/${UpdateSource.repo}';
  static const String website =
      'https://yeamin-talukder.github.io/${UpdateSource.repo}/';
  static const String issues = '$sourceCode/issues/new/choose';
}

/// Opens a link in the phone's browser (Android), or copies it.
Future<void> openLink(BuildContext context, String url) async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await const MethodChannel('bd.ac.bu.bu_bus_tracker/app_update')
          .invokeMethod<void>('openUrl', {'url': url});
      return;
    } catch (_) {}
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copied')));
  }
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    ref.watch(updateControllerProvider);
    final version = ref.read(updateControllerProvider.notifier).currentVersion;
    const gap = SizedBox(height: AppSpacing.xl);
    const line = Divider(
      height: 1,
      indent: AppSpacing.lg,
      endIndent: AppSpacing.lg,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Appear(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 96,
                    height: 96,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  AppConstants.appShortName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  version == null
                      ? AppConstants.appName
                      : '${AppConstants.appName} · version $version',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Bus schedules, stops, live buses and an offline map for University of Barishal '
                  'students, teachers and staff. Free and open source.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          gap,
          const Appear(
            delay: Duration(milliseconds: 80),
            child: _DeveloperCard(),
          ),
          gap,
          Appear(
            delay: const Duration(milliseconds: 160),
            child: SectionCard(
              title: 'Project',
              children: [
                _LinkTile(
                  icon: Icons.code_rounded,
                  title: 'Source code',
                  url: AboutLinks.sourceCode,
                ),
                line,
                _LinkTile(
                  icon: Icons.language_rounded,
                  title: 'Website and downloads',
                  url: AboutLinks.website,
                ),
                line,
                _LinkTile(
                  icon: Icons.bug_report_rounded,
                  title: 'Report a problem or suggest an idea',
                  url: AboutLinks.issues,
                ),
              ],
            ),
          ),
          gap,
          Appear(
            delay: const Duration(milliseconds: 240),
            child: SectionCard(
              title: 'Credits',
              children: [
                const SettingsTile(
                  icon: Icons.map_rounded,
                  title: 'Map data © OpenStreetMap contributors',
                  subtitle: 'Open Database License. Map drawn with MapLibre.',
                ),
                line,
                const SettingsTile(
                  icon: Icons.gavel_rounded,
                  title: 'MIT License',
                  subtitle: 'The app\'s code is free to use, change and share.',
                ),
                line,
                SettingsTile(
                  icon: Icons.description_rounded,
                  title: 'Open-source licences',
                  subtitle: 'The libraries the app is built with.',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConstants.appShortName,
                    applicationVersion: version?.toString(),
                  ),
                ),
              ],
            ),
          ),
          gap,
          Center(
            child: Text(
              'Made with Flutter for University of Barishal',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.accent.withValues(alpha: 0.16),
            scheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(color: theme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DEVELOPER',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.accent, width: 2),
                ),
                // Initials, not a photo (the owner's choice).
                child: CircleAvatar(
                  backgroundColor: theme.accent.withValues(alpha: 0.16),
                  child: Text(
                    'YT',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AboutLinks.developerName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${AboutLinks.developerHandle}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Design and development',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      openLink(context, AboutLinks.developerGithub),
                  icon: const Icon(Icons.person_search_rounded),
                  label: const Text('GitHub profile'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openLink(context, AboutLinks.sourceCode),
                  icon: const Icon(Icons.code_rounded),
                  label: const Text('Source code'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, required this.url});
  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: () => openLink(context, url),
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Link copied')));
        }
      },
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: theme.accent, size: 21),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        url.replaceFirst('https://', ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.open_in_new_rounded,
        size: 18,
        color: theme.colorScheme.outline,
      ),
    );
  }
}
