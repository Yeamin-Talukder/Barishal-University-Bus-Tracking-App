import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/bus.dart';
import '../../../data/repositories/bus_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';
import '../../auth/domain/user_profile.dart';
import '../data/people_repository.dart';

/// Where an admin decides what each signed-in person may do: nothing
/// special, drive a bus, or administer the system.
///
/// The screen is only a convenience: the database refuses these changes
/// from anyone who is not an admin, whatever is shown here.
class AdminPeopleScreen extends ConsumerStatefulWidget {
  const AdminPeopleScreen({super.key});

  @override
  ConsumerState<AdminPeopleScreen> createState() => _AdminPeopleScreenState();
}

class _AdminPeopleScreenState extends ConsumerState<AdminPeopleScreen> {
  String _filter = '';

  /// The bus this person is assigned to drive, if any.
  Bus? _busOf(UserProfile person) =>
      (ref.read(registeredBusesProvider).value ?? const <Bus>[])
          .where((bus) => bus.driverUid == person.uid)
          .firstOrNull;

  Future<void> _change(UserProfile person) async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<({UserRole role, bool isActive})>(
      context: context,
      builder: (context) => _AccessDialog(person: person),
    );
    if (choice == null || !mounted) return;
    if (choice.role == person.role && choice.isActive == person.isActive) {
      return;
    }

    // Someone who can no longer drive must not stay assigned to a bus.
    final canDrive = choice.role == UserRole.driver && choice.isActive;
    final bus = canDrive ? null : _busOf(person);
    final needsConfirming = choice.role == UserRole.admin || bus != null;
    if (needsConfirming) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            choice.role == UserRole.admin && person.role != UserRole.admin
                ? 'Make ${person.name} an admin?'
                : 'Change ${person.name}?',
          ),
          content: Text(
            [
              if (choice.role == UserRole.admin &&
                  person.role != UserRole.admin)
                'An admin can change the stops, the schedule, the buses and '
                    'what every other person may do, including you.',
              if (bus != null)
                'They are the driver of bus ${bus.number}. They will be '
                    'removed from that bus.',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      if (bus != null) {
        await ref
            .read(busRepositoryProvider)
            .saveBus(
              Bus(
                id: bus.id,
                number: bus.number,
                name: bus.name,
                registrationNumber: bus.registrationNumber,
                routeId: bus.routeId,
                isActive: bus.isActive,
              ),
            );
      }
      await ref
          .read(peopleRepositoryProvider)
          .setAccess(person.uid, role: choice.role, isActive: choice.isActive);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            choice.isActive
                ? '${person.name} is now: ${choice.role.label}.'
                : '${person.name} is deactivated.',
          ),
        ),
      );
    } on BusWriteFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } on PeopleWriteFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!ref.watch(isAdminProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage people')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Admins only',
          message:
              'Only a transport office admin can change what people may do. '
              'Sign in with an admin account.',
        ),
      );
    }

    final people = ref.watch(peopleProvider);
    final everyone = people.value ?? const <UserProfile>[];
    final myUid = ref.watch(accountProvider).value?.uid;
    // Keeps the buses loaded, so a driver's bus is known when they change.
    ref.watch(registeredBusesProvider);

    final wanted = _filter.trim().toLowerCase();
    final shown = [
      for (final person in everyone)
        if (wanted.isEmpty ||
            person.name.toLowerCase().contains(wanted) ||
            person.email.toLowerCase().contains(wanted))
          person,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Manage people')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Text(
            'Everyone who has signed in with Google is listed here. A new '
            'account can do nothing special until you make it a driver or '
            'an admin.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Find by name or email',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _filter = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: wanted.isEmpty
                ? 'People (${everyone.length})'
                : 'People (${shown.length} of ${everyone.length})',
            children: [
              if (people.isLoading && !people.hasValue)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (people.hasError && !people.hasValue)
                const ListTile(
                  leading: Icon(Icons.cloud_off_rounded),
                  title: Text('The list could not be loaded'),
                  subtitle: Text('Check the connection and open this again.'),
                )
              else if (shown.isEmpty)
                ListTile(
                  leading: const Icon(Icons.person_search_rounded),
                  title: Text(
                    everyone.isEmpty ? 'Nobody has signed in yet' : 'No match',
                  ),
                )
              else
                for (final person in shown)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        person.name.isEmpty
                            ? '?'
                            : person.name[0].toUpperCase(),
                      ),
                    ),
                    title: Text(
                      person.uid == myUid
                          ? '${person.name} (you)'
                          : person.name,
                    ),
                    subtitle: Text(
                      [
                        person.email,
                        [
                          person.role.label,
                          if (!person.isActive) 'Deactivated',
                        ].join(' · '),
                      ].join('\n'),
                    ),
                    isThreeLine: true,
                    // An admin cannot lock themselves out by mistake.
                    enabled: person.uid != myUid,
                    trailing: person.uid == myUid
                        ? null
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: person.uid == myUid ? null : () => _change(person),
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'You cannot change your own access here, so there is always at '
            'least one admin.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks what a person may do and whether their account is active.
class _AccessDialog extends StatefulWidget {
  const _AccessDialog({required this.person});

  final UserProfile person;

  @override
  State<_AccessDialog> createState() => _AccessDialogState();
}

class _AccessDialogState extends State<_AccessDialog> {
  late UserRole _role = widget.person.role;
  late bool _isActive = widget.person.isActive;

  static const Map<UserRole, String> _explanations = {
    UserRole.student: 'No special access. Sees what every passenger sees.',
    UserRole.driver: 'Can be given a bus, and share its position on a trip.',
    UserRole.admin: 'Can change stops, the schedule, buses and people.',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.person.name),
      contentPadding: const EdgeInsets.only(top: AppSpacing.md),
      content: SingleChildScrollView(
        child: RadioGroup<UserRole>(
          groupValue: _role,
          onChanged: (role) => setState(() => _role = role ?? _role),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final role in UserRole.values)
                RadioListTile<UserRole>(
                  value: role,
                  title: Text(role.label),
                  subtitle: Text(_explanations[role]!),
                ),
              const Divider(),
              SwitchListTile(
                title: const Text('Account active'),
                subtitle: const Text(
                  'Switch off to take away all access without deleting the '
                  'account.',
                ),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((role: _role, isActive: _isActive)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
