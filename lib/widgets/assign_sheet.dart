// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/age_suitability.dart';
import '../models/auth_session.dart';
import '../models/collection_set.dart';
import '../models/jellyfin_user.dart';
import '../models/library_item.dart';
import '../models/parental_rating.dart';
import '../models/tag_diff.dart';
import '../providers/app_providers.dart';
import '../providers/assign_providers.dart';
import '../providers/collection_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';
import '../providers/settings_providers.dart';
import '../repositories/assign_repository.dart';
import 'assign_result_toast.dart';
import 'batch_result_notice.dart';
import 'collection_prompt.dart';

/// Build order steps 5 and 6. The only place a tag write is previewed and
/// applied.
///
/// Ground rule 1: **no write on toggle.** Toggling builds a diff; the diff is
/// shown; Apply performs it. And the count on each row is the child's *current*
/// server-computed one, never a prediction — predicting it would mean
/// simulating the rating cap, which rule 4 forbids because it goes wrong
/// silently.
///
/// A collection writes to every title inside **and** to the collection itself,
/// with a pre-flight first and no rollback after — see
/// `AssignRepository.applyToCollection` for the ordering and why it is that way
/// round.
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

/// A collection write that did not finish, kept so the parent can choose what
/// happens next.
///
/// Ground rule 5: never a silent rollback. The two offers are *finish the rest*
/// and *remove all*, both idempotent and both theirs to make.
class _Unfinished {
  const _Unfinished({
    required this.set,
    required this.outcome,
    required this.diff,
    required this.libraryTotal,
  });

  final CollectionSet set;
  final BatchOutcome outcome;
  final TagDiff diff;

  /// Carried so a retry can report the same denominator the first attempt
  /// would have: the rows it came from are gone by then.
  final int libraryTotal;
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  /// Pending toggles, by child id. Nothing here has been written.
  final _pending = <String, bool>{};
  bool _applying = false;
  _Unfinished? _unfinished;
  String? _notice;

  AssignRequest get _request =>
      AssignRequest(session: widget.session, item: widget.item);

  CollectionRequest get _collectionRequest =>
      CollectionRequest(session: widget.session, collection: widget.item);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final rows = ref.watch(assignRowsProvider(_request));

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

        for (final line in _scopeNotes(l10n)) ...[
          const SizedBox(height: 12),
          Text(
            line,
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

        if (_notice != null) ...[
          Text(
            _notice!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],

        if (_unfinished case final unfinished?)
          _fixForward(unfinished)
        else
          FilledButton(
            onPressed: diff.isEmpty || _applying
                ? null
                : () => _apply(diff, rows.first.libraryTotal),
            child: _applying
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.assignApply),
          ),
      ],
    );
  }

  /// The lines that say what a write here will actually touch.
  ///
  /// For a collection: every title inside, and the collection itself. For a
  /// film: the sets it belongs to — **plural on purpose**, because a film can
  /// be in several and assuming one would leave the others unmentioned.
  List<String> _scopeNotes(AppLocalizations l10n) {
    // A series needs no cascade and gets no warning — it gets the opposite,
    // because "will they get the episodes?" is the question a parent actually
    // has and the measured answer is yes (#53).
    if (widget.item.isSeries) return [l10n.assignSeriesNote];
    if (widget.item.isCollection) {
      final set = ref.watch(collectionSetProvider(_collectionRequest));
      final size = set.asData?.value.size;
      return size == null ? const [] : [l10n.assignCollectionNote(size)];
    }
    return [
      for (final set in ref.watch(setsContainingProvider(_collectionRequest)))
        l10n.assignPartOfSet(set.collection.name, set.size),
    ];
  }

  /// Ground rule 5's fix-forward offer, in place of Apply.
  ///
  /// The words live in [BatchResultNotice], which has to know which way the
  /// change went: reversing an addition removes labels and reversing a removal
  /// puts them back, and the container being left marked or unmarked means
  /// opposite things to the child.
  Widget _fixForward(_Unfinished unfinished) => BatchResultNotice(
        outcome: unfinished.outcome,
        diff: unfinished.diff,
        enabled: !_applying,
        // The same write again. Tag writes are idempotent, so the titles that
        // landed are untouched and the ones that did not are retried — which is
        // the whole of "retry that item".
        onFinish: () => _runBatch(
          unfinished.set,
          unfinished.diff,
          libraryTotal: unfinished.libraryTotal,
        ),
        // A fresh forward write in the other direction, not a restore.
        onReverse: () => _runBatch(
          unfinished.set,
          AssignRepository.reverse(unfinished.diff),
          libraryTotal: unfinished.libraryTotal,
        ),
      );

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

    // Ground rule 1's hard warning, asked before the write and impossible to
    // apply past without having read it.
    if (!await _confirmLastItem(diff)) return;
    if (!mounted) return;

    if (widget.item.isCollection) {
      final set = ref.read(collectionSetProvider(_collectionRequest)).asData?.value;
      if (set == null) {
        // Without the membership there is no safe write: labelling the
        // container alone gives the child an empty collection.
        setState(() => _notice = l10n.errorServer);
        return;
      }
      await _runBatch(set, diff, libraryTotal: libraryTotal);
      return;
    }

    // A film. Ask about each set it belongs to — additions only, because
    // removing a label never cascades (ground rule 6).
    final sets = await _askAboutSets(diff);
    if (sets == null || !mounted) return;

    if (sets.isEmpty) {
      await _runSingle(diff, libraryTotal);
      return;
    }
    for (final set in sets) {
      final finished = await _runBatch(set, diff, libraryTotal: libraryTotal);
      if (!finished || !mounted) return;
    }
  }

  /// The last-item warning, once per removal that would cause it.
  ///
  /// False means the parent backed out, and nothing is written.
  Future<bool> _confirmLastItem(TagDiff diff) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(assignRepositoryProvider(widget.session));
    final warnings = await repository.lastItemWarningsFor(diff);

    for (final warning in warnings) {
      if (!mounted) return false;
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
      if (proceed != true) return false;
    }
    return true;
  }

  /// Asks, once per set this film belongs to, whether to keep it together.
  ///
  /// Null means the parent dismissed a dialog rather than answering it, which
  /// cancels the whole write — a dismissal is not "just this one".
  Future<List<CollectionSet>?> _askAboutSets(TagDiff diff) async {
    // Ground rule 6 and Settings → Labels, in one place. `none` decides without
    // a lookup, which is what keeps *just the one title* cheap.
    final plan = cascadePlanFor(
      diff: diff,
      prompt: ref.read(settingsProvider).collectionPrompt,
    );
    if (plan == CascadePlan.none) return const [];

    final accepted = <CollectionSet>[];
    final candidates = await _sets();
    if (!mounted) return null;
    for (final set in candidates) {
      if (plan == CascadePlan.all) {
        // The parent has already answered this question, once, in Settings.
        accepted.add(set);
        continue;
      }
      if (!mounted) return null;
      final answer = await askKeepSetTogether(
        context,
        set: set,
        itemId: widget.item.id,
        itemName: widget.item.name,
      );
      if (answer == null) return null;
      if (answer) accepted.add(set);
    }
    return accepted;
  }

  /// The sets this film belongs to, **waited for** rather than read as-is.
  ///
  /// The note under the header can afford to appear late; the cascade question
  /// cannot. Reading the index while it was still loading would answer "no
  /// sets", skip the prompt, and quietly write the single film — a question the
  /// parent was owed and never saw. The index is usually warm by now; when it
  /// is not, this is the one place worth waiting.
  ///
  /// An index that failed to build answers "no sets", which declines to cascade
  /// rather than guessing — the same thing a parent pressing *Just this one*
  /// would get.
  Future<List<CollectionSet>> _sets() async {
    try {
      final index =
          await ref.read(collectionIndexProvider(widget.session).future);
      return index.setsContaining(widget.item.id);
    } on Object {
      return const [];
    }
  }

  Future<void> _runSingle(TagDiff diff, int libraryTotal) async {
    final repository = ref.read(assignRepositoryProvider(widget.session));
    setState(() {
      _applying = true;
      _notice = null;
    });
    try {
      final outcome = await repository.apply(itemId: widget.item.id, diff: diff);
      if (!mounted) return;
      _refreshEverything();
      _reportAndClose(
        diff: diff,
        counts: outcome.counts,
        libraryTotal: libraryTotal,
        undo: () => repository.undo(itemId: widget.item.id, diff: diff),
      );
    } on Object {
      // A failure has to say so on the sheet. Left to the framework it becomes
      // an uncaught async error: the spinner stops, nothing changes, and the
      // parent cannot tell that from a write that did nothing.
      if (mounted) setState(() => _notice = AppLocalizations.of(context).errorServer);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// One collection write, and what to show for each way it can end.
  ///
  /// Returns whether the set finished; a partly-written set keeps the sheet
  /// open with the fix-forward offer rather than closing over the top of it.
  Future<bool> _runBatch(
    CollectionSet set,
    TagDiff diff, {
    required int libraryTotal,
  }) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(assignRepositoryProvider(widget.session));

    setState(() {
      _applying = true;
      _notice = null;
    });
    try {
      final outcome = await repository.applyToCollection(
        collectionId: set.collection.id,
        memberIds: set.memberIds,
        diff: diff,
      );
      if (!mounted) return false;
      _refreshEverything();

      if (!outcome.isComplete) {
        setState(() => _unfinished = _Unfinished(
              set: set,
              outcome: outcome,
              diff: diff,
              libraryTotal: libraryTotal,
            ));
        return false;
      }

      _reportAndClose(
        diff: diff,
        // Already resolved: a collection write is many writes, so the single
        // count at the end is a small share of it and deferring gains nothing.
        counts: Future<Map<String, int>>.value(outcome.counts),
        libraryTotal: libraryTotal,
        undo: () => repository.undoCollection(
          collectionId: set.collection.id,
          memberIds: set.memberIds,
          diff: diff,
        ),
      );
      return true;
    } on CollectionPreflightException catch (error) {
      // Nothing was written, and saying so is the whole point: the parent needs
      // to know the set is untouched rather than half-done.
      if (!mounted) return false;
      setState(() {
        _unfinished = null;
        _notice = l10n.assignBatchPreflightFailed(error.unreadable.length);
      });
      return false;
    } on Object {
      // Anything else — the counts re-fetch, a dropped connection — leaves the
      // set in whatever state the writes reached. Say something rather than
      // stopping the spinner and looking finished.
      if (mounted) setState(() => _notice = l10n.errorServer);
      return false;
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// Everything downstream is stale after a write: the grid's tags, the counts,
  /// the sheet's own rows.
  void _refreshEverything() {
    ref.invalidate(assignRowsProvider(_request));
    refreshLibrary(ref);
    ref.invalidate(kidsOverviewProvider(widget.session));
  }

  /// Closes the sheet and reports the **verified** count, with Undo.
  ///
  /// The count is the one re-read after the write. When the rating cap
  /// swallowed the share this is the number that says so, instead of the app
  /// looking broken.
  void _reportAndClose({
    required TagDiff diff,
    required Future<Map<String, int>> counts,
    required int libraryTotal,
    required Future<void> Function() undo,
  }) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final first = diff.changes.first;

    navigator.pop();
    messenger.showSnackBar(
      assignResultToast(
        // Direction-aware, because this sentence is said before any number is
        // known and "shared" is a lie about a removal. #51's review caught this
        // exact shape once already: copy written for one direction that reaches
        // both.
        pending: switch (diff.direction) {
          DiffDirection.added => l10n.assignDonePendingAdded(first.child.name),
          DiffDirection.removed =>
            l10n.assignDonePendingRemoved(first.child.name),
          DiffDirection.mixed => l10n.assignDonePendingMixed,
        },
        verified: (counts) => l10n.assignResult(
          first.child.name,
          counts[first.child.id] ?? 0,
          libraryTotal,
        ),
        counts: counts,
        undoLabel: l10n.assignUndo,
        onUndo: () async {
          // A fresh forward write, never a restore (ground rule 5).
          await undo();
          refreshLibrary(ref);
          ref.invalidate(kidsOverviewProvider(widget.session));
          messenger.showSnackBar(SnackBar(content: Text(l10n.assignUndone)));
        },
      ),
    );
  }
}
