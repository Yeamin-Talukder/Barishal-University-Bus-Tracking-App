import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_bootstrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../application/session.dart';
import '../data/auth_repository.dart';
import '../domain/user_profile.dart';

/// The Profile section for drivers and transport office staff: who is signed
/// in, or how to sign in. Passengers never need it.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  static const String title = 'Drivers and staff';
  static const String signInLabel = 'Sign in with Google';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAvailable = ref.watch(firebaseStatusProvider).isReady;
    final account = ref.watch(accountProvider);
    final profile = ref.watch(userProfileProvider).value;

    final Widget content;
    if (!isAvailable) {
      content = const ListTile(
        leading: Icon(Icons.person_off_rounded),
        title: Text('Sign-in is not available'),
        subtitle: Text('This build is not connected to the tracking service.'),
      );
    } else if (account.isLoading && !account.hasValue) {
      content = const ListTile(
        leading: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        title: Text('Checking your account'),
      );
    } else if (account.value == null) {
      content = const _SignedOut();
    } else {
      content = _SignedIn(account: account.value!, profile: profile);
    }

    return SectionCard(title: AccountSection.title, children: [content]);
  }
}

class _SignedOut extends ConsumerStatefulWidget {
  const _SignedOut();

  @override
  ConsumerState<_SignedOut> createState() => _SignedOutState();
}

class _SignedOutState extends ConsumerState<_SignedOut> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider).signInWithGoogle();
      // Read the profile afresh: the listener that started when the account
      // appeared may have run before the profile had been written.
      ref.invalidate(userProfileProvider);
    } on SignInCancelled {
      // They closed the Google window. Nothing to say.
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.badge_rounded,
                  color: theme.colorScheme.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You do not need an account',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Anyone can see the map, routes, stops and buses. Only '
                      'drivers and transport office staff sign in, with '
                      'their Google account. The transport office then turns '
                      'on their access.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (error != null) ...[
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : _signIn,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.login_rounded),
              label: const Text(AccountSection.signInLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.account, required this.profile});

  final AuthAccount account;
  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>()!;
    final profile = this.profile;
    final name = profile?.name.isNotEmpty == true
        ? profile!.name
        : (account.displayName ?? account.email);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.14),
            foregroundColor: theme.colorScheme.primary,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
          ),
          title: Text(name),
          subtitle: Text(account.email),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (profile != null)
                StatusPill(
                  label: profile.role.label,
                  color: theme.colorScheme.primary,
                ),
              if (profile != null && !profile.isActive)
                StatusPill(
                  label: 'Deactivated',
                  color: theme.colorScheme.error,
                ),
              if (profile?.studentId != null)
                Text(
                  'Student ID ${profile!.studentId}',
                  style: theme.textTheme.bodySmall,
                ),
              if (profile == null)
                StatusPill(
                  label: 'Profile not set up',
                  color: semantic.warning,
                ),
            ],
          ),
        ),
        if (profile != null &&
            profile.isActive &&
            profile.role == UserRole.student)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              'This account has no driver or admin access. The transport '
              'office turns that on.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: OutlinedButton.icon(
            onPressed: () => ref.read(sessionControllerProvider).signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}
