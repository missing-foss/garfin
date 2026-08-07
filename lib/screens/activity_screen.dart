// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/activity_entry.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/tag_diff.dart';
import '../providers/activity_providers.dart';
import '../providers/assign_providers.dart';
import '../providers/collection_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';

/// Build order step 8 (#57). What Garfin did, newest first.
///
/// **A record of this app's writes, not of the library's history.** Measured:
/// Jellyfin's own activity log gains nothing when an item's metadata is
/// written, so there is nothing to read history back from — a label added in
/// the web admin or from a second phone cannot appear here. The empty state
/// says so, because a log that looks complete and is not would be worse than
/// no log.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(activityLogProvider);

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.activityEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.activityScope,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: entries.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          // The scope note lives at the end of the list as well as on the empty
          // state: it is the caveat someone needs when the list is long enough
          // to look authoritative.
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              l10n.activityScope,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        return _EntryTile(session: session, entry: entries[index]);
      },
    );
  }
}

class _EntryTile extends ConsumerStatefulWidget {
  const _EntryTile({required this.session, required this.entry});

  final AuthSession session;
  final ActivityEntry entry;

  @override
  ConsumerState<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends ConsumerState<_EntryTile> {
  bool _undoing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final entry = widget.entry;

    return ListTile(
      leading: Icon(
        entry.isCollection ? Icons.collections_outlined : Icons.movie_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(entry.itemName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Phrased by what it did to the child. Ground rule 3: for a
            // block-list account, adding a label and giving access are
            // opposites, and this screen speaks the parent's language.
            entry.gaveAccess
                ? l10n.activityHandedTo(entry.childName)
                : l10n.activityTakenFrom(entry.childName),
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            entry.isCollection
                ? l10n.activityWhenCollection(
                    _relative(l10n, entry.at), entry.collectionSize!)
                : _relative(l10n, entry.at),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: _undoing
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: _undo,
              child: Text(l10n.assignUndo),
            ),
    );
  }

  /// "4 minutes ago", from the entry's own timestamp.
  String _relative(AppLocalizations l10n, DateTime at) {
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) return l10n.activityJustNow;
    if (elapsed.inHours < 1) return l10n.activityMinutesAgo(elapsed.inMinutes);
    if (elapsed.inDays < 1) return l10n.activityHoursAgo(elapsed.inHours);
    if (elapsed.inDays < 7) return l10n.activityDaysAgo(elapsed.inDays);
    return DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(at);
  }

  /// Undo, as a **fresh forward write** — the same act the assign sheet's Undo
  /// performs, which is why an entry stays undoable however old it is.
  ///
  /// For a collection the membership is **re-resolved now** rather than
  /// replayed from the entry: a set can gain or lose titles between the write
  /// and the undo, and a captured list would be the same mistake as a captured
  /// item body.
  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final entry = widget.entry;
    final repository = ref.read(assignRepositoryProvider(widget.session));

    // The child as they are **now**: their shortlist mode decides whether
    // reversing means adding the label or removing it, and it can have changed
    // in Jellyfin since the write.
    final overview =
        ref.read(kidsOverviewProvider(widget.session)).asData?.value;
    final child = overview?.shortlisted
        .map((k) => k.user)
        .where((u) => u.id == entry.childId)
        .firstOrNull;
    if (child == null) {
      // The account is gone, or Garfin can no longer interpret its shortlist.
      // Guessing a verb here is exactly what ground rule 3 forbids.
      messenger.showSnackBar(SnackBar(content: Text(l10n.activityUndoUnknown)));
      return;
    }

    // The diff that *reverses* the entry, expressed in what it does to the
    // child: `TagChange.adding` is about the label, `givesAccess` about the
    // child, and for a block-list account those differ.
    final reverse = TagDiff([
      TagChange(
        child: child,
        label: entry.label,
        adding: child.policy.shortlistMode == ShortlistMode.allow
            ? !entry.gaveAccess
            : entry.gaveAccess,
      ),
    ]);

    setState(() => _undoing = true);
    try {
      if (entry.isCollection) {
        final set = await ref
            .read(collectionRepositoryProvider(widget.session))
            .setForId(entry.itemId);
        await repository.applyToCollection(
          collectionId: entry.itemId,
          memberIds: set.memberIds,
          diff: reverse,
        );
      } else {
        await repository.apply(itemId: entry.itemId, diff: reverse);
      }
      if (!mounted) return;
      ref.invalidate(activityLogProvider);
      refreshLibrary(ref);
      ref.invalidate(kidsOverviewProvider(widget.session));
      messenger.showSnackBar(SnackBar(content: Text(l10n.assignUndone)));
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorServer)));
      }
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }
}
