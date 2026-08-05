// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/age_suitability.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/library_item.dart';
import '../models/parental_rating.dart';
import '../models/tag_diff.dart';
import '../providers/app_providers.dart';
import '../providers/assign_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';

/// Build order step 5. The only place a tag write is previewed and applied.
///
/// Ground rule 1: **no write on toggle.** Toggling builds a diff; the diff is
/// shown; Apply performs it. And the count on each row is the child's *current*
/// server-computed one, never a prediction — predicting it would mean
/// simulating the rating cap, which rule 4 forbids because it goes wrong
/// silently.
Future<void> showAssignSheet(
  BuildContext context, {
  required AuthSession session,
  required LibraryItem item,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AssignSheet(session: session, item: item),
    );

class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.session, required this.item});

  final AuthSession session;
  final LibraryItem item;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  /// Pending toggles, by child id. Nothing here has been written.
  final _pending = <String, bool>{};
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final rows = ref.watch(assignRowsProvider(
      AssignRequest(session: widget.session, itemId: widget.item.id),
    ));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: rows.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.errorServer, style: theme.textTheme.bodyLarge),
          ),
          data: (data) => _body(context, data),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<AssignRow> rows) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l10n.assignNoChildren, style: theme.textTheme.bodyLarge),
      );
    }

    final diff = _diffFrom(rows);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.item.name, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(l10n.assignTitle, style: theme.textTheme.bodyMedium),

        // Collections cascade at step 6. Saying so beats labelling the
        // container and appearing to have done something — a BoxSet is a
        // container and the policy filters the films inside it.
        if (widget.item.isCollection) ...[
          const SizedBox(height: 12),
          Text(
            l10n.assignCollectionNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],

        const SizedBox(height: 12),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [for (final row in rows) _row(row)],
          ),
        ),

        if (!diff.isEmpty) ...[
          const Divider(),
          Text(l10n.assignChangesHeading, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          // The preview. Phrased by what it does to the child, not by what it
          // does to the tag — "Take from Sam" rather than "add block-sam",
          // because ground rule 3 means those are the same act.
          for (final change in diff.changes)
            Text(
              change.givesAccess
                  ? l10n.assignWillGive(change.child.name)
                  : l10n.assignWillTake(change.child.name),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
        ],

        FilledButton(
          onPressed: diff.isEmpty || _applying
              ? null
              : () => _apply(diff, rows.first.libraryTotal),
          child: _applying
              ? const SizedBox(
                  height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.assignApply),
        ),
      ],
    );
  }

  Widget _row(AssignRow row) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final ladder =
        ref.watch(parentalRatingLadderProvider(widget.session)).asData?.value ??
            const ParentalRatingLadder.empty();
    final birthYear = ref.watch(birthYearStoreProvider).read(row.child.id);
    final suitability = suitabilityFor(
      item: widget.item,
      ladder: ladder,
      childAge: birthYear == null
          ? null
          : guaranteedAge(birthYear: birthYear, today: DateTime.now()),
    );

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _pending[row.child.id] ?? row.hasAccess,
      onChanged: _applying
          ? null
          : (v) => setState(() => _pending[row.child.id] = v),
      title: Text(row.child.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The current count, from the server. Ground rules 1 and 4.
          Text(
            l10n.assignSees(row.child.name, row.visibleCount, row.libraryTotal),
            style: theme.textTheme.bodySmall,
          ),
          // The #43 hint, on the row where the decision is made — which is what
          // that issue asked for and could not have until this sheet existed.
          if (suitability != AgeSuitability.suitsAge)
            Text(
              suitability == AgeSuitability.aboveAge
                  ? l10n.libraryHintAboveAge(row.child.name)
                  : l10n.libraryHintUnknownAge,
              style: theme.textTheme.bodySmall?.copyWith(
                color: suitability == AgeSuitability.aboveAge
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// Turns the pending toggles into the writes they imply.
  ///
  /// The inversion lives in [TagChange.givesAccess]; here the only question is
  /// whether the *label* goes on or comes off, which for a block-list child is
  /// the opposite of what the switch appears to say.
  TagDiff _diffFrom(List<AssignRow> rows) {
    final changes = <TagChange>[];
    for (final row in rows) {
      final wanted = _pending[row.child.id];
      if (wanted == null || wanted == row.hasAccess) continue;
      changes.add(
        TagChange(
          child: row.child,
          label: row.label,
          // Allow mode: access means the label is present. Block mode: access
          // means it is absent.
          adding: row.child.policy.shortlistMode == ShortlistMode.allow
              ? wanted
              : !wanted,
        ),
      );
    }
    return TagDiff(changes);
  }

  Future<void> _apply(TagDiff diff, int libraryTotal) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final request =
        AssignRequest(session: widget.session, itemId: widget.item.id);
    final repository = ref.read(assignRepositoryProvider(widget.session));

    // Ground rule 1's hard warning, asked before the write and impossible to
    // apply past without having read it.
    final warnings = await repository.lastItemWarningsFor(diff);
    if (!mounted) return;
    for (final warning in warnings) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.assignLastItemTitle(warning.child.name)),
          content: Text(l10n.assignLastItemBody(warning.child.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.assignLastItemConfirm),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    setState(() => _applying = true);
    try {
      final outcome = await repository.apply(itemId: widget.item.id, diff: diff);
      if (!mounted) return;

      // Everything downstream is stale now: the grid's tags, the counts, the
      // sheet's own rows.
      ref.invalidate(assignRowsProvider(request));
      ref.invalidate(librarySliceProvider(widget.session));
      ref.invalidate(kidsOverviewProvider(widget.session));

      navigator.pop();

      final first = diff.changes.first;
      messenger.showSnackBar(
        SnackBar(
          // The **verified** count, re-read after the write. When the rating
          // cap swallowed the share this is the number that says so, instead of
          // the app looking broken.
          content: Text(l10n.assignResult(
            first.child.name,
            outcome.counts[first.child.id] ?? 0,
            libraryTotal,
          )),
          action: SnackBarAction(
            label: l10n.assignUndo,
            onPressed: () async {
              // A fresh forward write, never a restore (ground rule 5).
              await repository.undo(itemId: widget.item.id, diff: diff);
              ref.invalidate(librarySliceProvider(widget.session));
              ref.invalidate(kidsOverviewProvider(widget.session));
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.assignUndone)),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }
}
