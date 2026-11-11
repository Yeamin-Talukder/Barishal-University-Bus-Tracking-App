import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/repositories/announcement_repository.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_card.dart';
import '../../auth/application/session.dart';

/// Where an admin posts, changes, hides and deletes announcements.
///
/// The screen is only a convenience: the database refuses these changes
/// from anyone who is not an admin, whatever is shown here.
class AdminAnnouncementsScreen extends ConsumerWidget {
  const AdminAnnouncementsScreen({super.key});

  static const int maxTitleLength = 120;
  static const int maxMessageLength = 2000;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    Announcement? existing,
  ]) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => _AnnouncementDialog(existing: existing),
    );
    if (result == null) return;
    final repository = ref.read(announcementRepositoryProvider);
    try {
      if (result.delete) {
        await repository.deleteAnnouncement(existing!.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Announcement deleted.')),
        );
      } else {
        await repository.saveAnnouncement(result.announcement!);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.announcement!.isActive
                  ? 'Announcement is showing to passengers.'
                  : 'Announcement saved, hidden from passengers.',
            ),
          ),
        );
      }
    } on AnnouncementWriteFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final announcements = ref.watch(announcementsProvider);
    final all = announcements.value ?? const <Announcement>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.campaign_rounded),
              label: const Text('New announcement'),
            )
          : null,
      body: !isAdmin
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Admins only',
              message:
                  'Only a transport office admin can post announcements. '
                  'Sign in with an admin account.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                96,
              ),
              children: [
                SectionCard(
                  title: 'Announcements (${all.length})',
                  children: [
                    if (announcements.isLoading && !announcements.hasValue)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (all.isEmpty)
                      const ListTile(
                        leading: Icon(Icons.campaign_rounded),
                        title: Text('No announcements'),
                        subtitle: Text(
                          'Post one with the button below. Passengers see it '
                          'on the home screen when they open the app.',
                        ),
                      )
                    else
                      for (final announcement in all)
                        ListTile(
                          leading: Icon(
                            announcement.isActive
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                          title: Text(announcement.title),
                          subtitle: Text(
                            [
                              announcement.message,
                              [
                                announcement.isActive
                                    ? 'Showing to passengers'
                                    : 'Hidden',
                                if (announcement.createdAt != null)
                                  formatDate(announcement.createdAt!),
                              ].join(' · '),
                            ].join('\n'),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          onTap: () => _edit(context, ref, announcement),
                        ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _EditResult {
  const _EditResult.save(Announcement this.announcement) : delete = false;
  const _EditResult.delete() : announcement = null, delete = true;

  final Announcement? announcement;
  final bool delete;
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog({this.existing});

  final Announcement? existing;

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _message = TextEditingController(
    text: widget.existing?.message ?? '',
  );
  late bool _isActive = widget.existing?.isActive ?? true;
  bool _confirmingDelete = false;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _EditResult.save(
        Announcement(
          id: widget.existing?.id ?? '',
          title: _title.text.trim(),
          message: _message.text.trim(),
          isActive: _isActive,
          createdAt: widget.existing?.createdAt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;

    return AlertDialog(
      title: Text(isNew ? 'New announcement' : 'Announcement'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: isNew,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'No buses on Friday',
                ),
                maxLength: AdminAnnouncementsScreen.maxTitleLength,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a title.' : null,
              ),
              TextFormField(
                controller: _message,
                decoration: const InputDecoration(labelText: 'Message'),
                maxLength: AdminAnnouncementsScreen.maxMessageLength,
                minLines: 3,
                maxLines: 6,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter the message.' : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show to passengers'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              if (_confirmingDelete)
                Text(
                  'Delete it for good? To keep it for later, switch off '
                  '"Show to passengers" instead.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!isNew)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _confirmingDelete
                ? Navigator.of(context).pop(const _EditResult.delete())
                : setState(() => _confirmingDelete = true),
            child: Text(_confirmingDelete ? 'Yes, delete' : 'Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: Text(isNew ? 'Post' : 'Save')),
      ],
    );
  }
}
