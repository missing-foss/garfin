// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/age_suitability.dart';
import '../models/auth_session.dart';
import '../models/collection_set.dart';
import '../models/jellyfin_user.dart';
import '../models/country_lookup.dart';
import '../models/library_item.dart';
import '../models/parental_rating.dart';
import '../models/tag_diff.dart';
import '../providers/app_providers.dart';
import '../providers/assign_providers.dart';
import '../providers/assign_sheet_controller.dart';
import '../providers/collection_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';
import '../providers/settings_providers.dart';
import 'item_detail_head.dart';
import 'last_item_confirm.dart' as last_item;
import '../repositories/assign_repository.dart';
import 'adaptive_layout.dart';
import 'assign_result_toast.dart';
import 'batch_result_notice.dart';
import 'collection_given_line.dart';
import 'collection_prompt.dart' as collection_prompt;

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
  LibraryItem? fromCollection,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // The sheet's own route is what "close" means here. On a tablet the same
      // view sits in a panel with no route of its own (#95), which is why the
      // view asks to be closed rather than popping something itself.
      // Capped like every other surface (#95): between the rail breakpoint and
      // the two-pane one there is no panel yet, and a sheet is still allowed to
      // be 839dp wide.
      builder: (sheetContext) => ReadableWidth(
        child: AssignView(
          session: session,
          item: item,
          fromCollection: fromCollection,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );

/// The write preview itself, with no opinion about what it is shown in.
///
/// Two surfaces use it: the modal sheet above, on a phone, and `AssignPanel`
/// beside the grid on a tablet. Everything a surface owns — how it is dismissed
/// — arrives as [onClose]; everything the preview owns, including the pending
/// toggles that have not been written, lives in [assignSheetControllerProvider]
/// and goes away with it: nothing watches it once the view is gone.
class AssignView extends ConsumerStatefulWidget {
  const AssignView({
    super.key,
    required this.session,
    required this.item,
    required this.onClose,
    this.fromCollection,
  });

  final AuthSession session;
  final LibraryItem item;

  /// The set the parent was looking at when they picked [item], or null from
  /// the library grid.
  ///
  /// **Not "the sets this film belongs to".** A film can be in several, and
  /// `docs/DECISIONS.md` § Collections scopes the write to the one in front of
  /// the parent: repairing every set a film sits in would hand the child
  /// collections nobody offered them. This is how the write knows which
  /// container may follow the film.
  final LibraryItem? fromCollection;

  /// Called once the write is done and reported, and by the panel's own close
  /// button. Never called with anything pending: ground rule 1 means an
  /// unapplied toggle has written nothing, so dropping it costs nothing.
  final VoidCallback onClose;

  @override
  ConsumerState<AssignView> createState() => _AssignViewState();
}

class _AssignViewState extends ConsumerState<AssignView>
    implements AssignSheetHost {
  AssignSheetController get _controller =>
      ref.read(assignSheetControllerProvider(_request).notifier);

  AssignRequest get _request =>
      AssignRequest(session: widget.session, item: widget.item);

  CollectionRequest get _collectionRequest =>
      CollectionRequest(session: widget.session, collection: widget.item);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final rows = ref.watch(assignRowsProvider(_request));
    // Watched up here, not only where the rows are drawn: the pending toggles
    // live as long as the sheet does, rows loading or not.
    final sheet = ref.watch(assignSheetControllerProvider(_request));

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
          data: (data) => _body(context, sheet, _selectedFirst(data)),
        ),
      ),
    );
  }

  /// The child the parent is picking for, first; everyone else in the
  /// server's order after them.
  ///
  /// They picked that child because they are about to give them something, so
  /// their row is the one this sheet is opened for. With it at the top, a phone
  /// shows it without a scroll however many children follow.
  ///
  /// Ordered here rather than in [assignRowsProvider]: the rows are fetched
  /// once per item, and the parent can change whom they are picking for
  /// without anything having to be fetched again. Everyone means no child is
  /// picked, and the server's order stands.
  List<AssignRow> _selectedFirst(List<AssignRow> rows) {
    final picked = ref.watch(pickingForProvider);
    if (picked == null) return rows;
    return [
      ...rows.where((r) => r.child.id == picked),
      ...rows.where((r) => r.child.id != picked),
    ];
  }

  Widget _body(
    BuildContext context,
    AssignSheetState sheet,
    List<AssignRow> rows,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l10n.assignNoChildren, style: theme.textTheme.bodyLarge),
      );
    }

    final diff = sheet.diffFrom(rows);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // **Everything above Apply scrolls together, the head included**, so
        // the scrolling area is the whole sheet and Apply is the one thing
        // pinned. The notes and the preview joined the rows first (#95):
        // the notes are one line *per set a film belongs to* — deliberately
        // plural — and a film in several sets pushed Apply off the bottom,
        // 192px of overflow in a 600dp-tall window.
        //
        // The head used to stay outside, and on a phone it left the kids
        // whatever the poster did not take. Measured at 412x917dp, a Pixel 9
        // Pro: a 159dp window from three kids up, two rows of 72dp in view, and
        // at font size 1.3 a 67dp window — less than one row. A flick in a
        // window that short reaches the end at once.
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              // Films and series (#160); a BoxSet stays out, as ruled on #145.
              if (widget.item.hasDetailHead) ...[
                ItemDetailHead(
                  session: widget.session,
                  item: widget.item,
                  posterSize: ref.watch(settingsProvider).posterSize,
                  // The head draws the title centred under the poster (#155).
                  // Every other kind of item keeps the plain left-aligned one
                  // below.
                  title: Text(
                    widget.item.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  // Both empty until they arrive, and empty answers "no
                  // country named" for every rating — the rating still shows,
                  // alone — and no flag for any country, which then shows as
                  // its name.
                  ladderNames: ref
                          .watch(parentalRatingLadderProvider(widget.session))
                          .asData
                          ?.value
                          .ratings
                          .map((r) => r.name)
                          .toSet() ??
                      const {},
                  countries: ref
                          .watch(countriesProvider(widget.session))
                          .asData
                          ?.value ??
                      const CountryLookup.empty(),
                ),
                const SizedBox(height: 12),
              ] else
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
              for (final row in rows) _row(sheet, row),
              if (!diff.isEmpty) ...[
                const Divider(),
                Text(l10n.assignChangesHeading,
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                // The preview. Phrased by what it does to the child, not by
                // what it does to the tag — "Take from Sam" rather than "add
                // block-sam", because ground rule 3 means those are the same
                // act.
                for (final change in diff.changes)
                  Text(
                    change.givesAccess
                        ? l10n.assignWillGive(change.child.name)
                        : l10n.assignWillTake(change.child.name),
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),

        if (sheet.notice case final notice?) ...[
          Text(
            switch (notice.unreadable) {
              null => l10n.errorServer,
              final unreadable => l10n.assignBatchPreflightFailed(unreadable),
            },
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],

        if (sheet.unfinished case final unfinished?)
          _fixForward(sheet, unfinished)
        else
          FilledButton(
            onPressed: diff.isEmpty || sheet.busy
                ? null
                : () => _controller.apply(
                      this,
                      diff,
                      libraryTotal: rows.first.libraryTotal,
                      fromCollection: widget.fromCollection,
                    ),
            child: sheet.busy
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
  Widget _fixForward(AssignSheetState sheet, AssignUnfinished unfinished) =>
      BatchResultNotice(
        outcome: unfinished.outcome,
        diff: unfinished.diff,
        enabled: !sheet.busy,
        onFinish: () => _controller.finishUnfinished(this, unfinished),
        onReverse: () => _controller.reverseUnfinished(this, unfinished),
      );

  Widget _row(AssignSheetState sheet, AssignRow row) {
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

    // For a set, how much of it is already this child's (#107). Read off the
    // membership the sheet has already fetched, so it costs nothing, and it is
    // the state **now** — never what the pending toggle would make it. Ground
    // rule 1: this sheet previews, and a count that moved with the switch would
    // be a prediction dressed as a fact.
    final set = widget.item.isCollection
        ? ref.watch(collectionSetProvider(_collectionRequest)).asData?.value
        : null;
    final given = set == null
        ? null
        : CollectionGiven.of(
            labelled: set.members
                .where((m) => m.hasAnyLabel(row.child.policy.shortlistTags))
                .length,
            total: set.size,
            child: row.child,
          );

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: sheet.pending[row.child.id] ?? row.hasAccess,
      onChanged:
          sheet.busy ? null : (v) => _controller.toggle(row.child.id, v),
      title: Text(row.child.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The current count, from the server. Ground rules 1 and 4.
          Text(
            l10n.assignSees(row.child.name, row.visibleCount, row.libraryTotal),
            style: theme.textTheme.bodySmall,
          ),
          // And, for a set, how much of *this set* they already have. A
          // different question from the line above and deliberately its own
          // sentence: that one is what the server shows them across the whole
          // library, this one is what the parent has handed over here.
          if (given != null)
            Text(
              collectionGivenText(l10n, given, row.child.name),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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

  @override
  Future<bool> confirmLastItem(
    TagDiff diff, {
    required Set<String> touching,
  }) =>
      last_item.confirmLastItem(
        context,
        repository: ref.read(assignRepositoryProvider(widget.session)),
        diff: diff,
        touching: touching,
      );

  @override
  Future<bool?> askKeepSetTogether(CollectionSet set) =>
      collection_prompt.askKeepSetTogether(
        context,
        set: set,
        itemId: widget.item.id,
        itemName: widget.item.name,
      );

  /// Closes the sheet and reports the **verified** count, with Undo.
  ///
  /// The count is the one re-read after the write. When the rating cap
  /// swallowed the share this is the number that says so, instead of the app
  /// looking broken.
  @override
  void reportAndClose({
    required TagDiff diff,
    required Future<Map<String, int>> counts,
    required int libraryTotal,
    required Future<void> Function() undo,
    required Set<String> touching,
  }) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final first = diff.changes.first;
    // Undo can take a label away — the reverse of giving a child the one thing
    // they have — so it asks the last-item question as Apply does. By then
    // this sheet is gone, so the dialog is shown from the root navigator,
    // which outlives it.
    final dialogContext = Navigator.of(context, rootNavigator: true).context;
    final repository = ref.read(assignRepositoryProvider(widget.session));
    // And the refresh after it goes through the container, not this widget's
    // `ref`: on a phone the sheet is disposed by the time Undo is pressed, and
    // a disposed widget's `ref` throws. It used to — after the write had
    // landed — so even an Undo that worked refreshed nothing and never said
    // so.
    final container = ProviderScope.containerOf(context, listen: false);
    final session = widget.session;
    // Every child the write touched, once each and in the order the sheet
    // listed them. One sentence about the first was all a two-child write
    // ever reported: the second child's outcome went unspoken.
    final children = <String, JellyfinUser>{
      for (final change in diff.changes) change.child.id: change.child,
    }.values.toList(growable: false);

    // Resolved before closing: on the phone this pops the sheet's route, and a
    // `ScaffoldMessenger.of` looked up afterwards would be reading a context
    // that is on its way out.
    widget.onClose();
    messenger.showSnackBar(
      assignResultToast(
        // Direction-aware, because this sentence is said before any number is
        // known and "shared" is a lie about a removal. #51's review caught this
        // exact shape once already: copy written for one direction that reaches
        // both.
        //
        // A write to several children says "changes applied" until the counts
        // land, then one counted sentence per child: naming one of them in
        // the first sentence would be the same lie by omission.
        pending: children.length > 1
            ? l10n.assignDonePendingMixed
            : switch (diff.direction) {
                DiffDirection.added =>
                  l10n.assignDonePendingAdded(first.child.name),
                DiffDirection.removed =>
                  l10n.assignDonePendingRemoved(first.child.name),
                DiffDirection.mixed => l10n.assignDonePendingMixed,
              },
        verified: (counts) => [
          for (final child in children)
            l10n.assignResult(child.name, counts[child.id] ?? 0, libraryTotal),
        ].join('\n'),
        counts: counts,
        undoLabel: l10n.assignUndo,
        onUndo: () async {
          if (!dialogContext.mounted) return;
          if (!await last_item.confirmLastItem(
            dialogContext,
            repository: repository,
            diff: AssignRepository.reverse(diff),
            touching: touching,
          )) {
            return;
          }
          // A fresh forward write, never a restore (ground rule 5). And a
          // failure says so, as Activity's Undo does: unguarded, it was an
          // uncaught error, nothing moved, and no toast came — which looks
          // exactly like an Undo that worked and said nothing.
          try {
            await undo();
          } on Object {
            messenger.showSnackBar(SnackBar(content: Text(l10n.errorServer)));
            return;
          } finally {
            // Either way: a set's Undo can fail part-way, and what did land
            // should be on screen.
            container.read(libraryRevisionProvider.notifier).bump();
            container.invalidate(kidsOverviewProvider(session));
          }
          messenger.showSnackBar(SnackBar(content: Text(l10n.assignUndone)));
        },
      ),
    );
  }
}
