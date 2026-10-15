// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collection_set.dart';
import '../models/jellyfin_user.dart';
import '../models/library_item.dart';
import '../models/tag_diff.dart';
import '../repositories/app_settings_store.dart';
import '../repositories/assign_repository.dart';
import 'assign_providers.dart';
import 'collection_providers.dart';
import 'kids_providers.dart';
import 'library_providers.dart';
import 'settings_providers.dart';

/// A collection write that did not finish, kept so the parent can choose what
/// happens next.
///
/// Ground rule 5: never a silent rollback. The two offers are *finish the rest*
/// and *remove all*, both idempotent and both theirs to make.
class AssignUnfinished {
  const AssignUnfinished({
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

/// What the sheet says above Apply when a write went wrong.
///
/// Kept as a kind rather than a sentence so the words stay with the widget,
/// which has the locale.
class AssignNotice {
  /// The server failed, or the membership a write needs could not be read.
  const AssignNotice.serverError() : unreadable = null;

  /// A collection's pre-flight could not read [unreadable] titles, so nothing
  /// was written.
  const AssignNotice.preflightFailed(int this.unreadable);

  final int? unreadable;

  @override
  bool operator ==(Object other) =>
      other is AssignNotice && other.unreadable == unreadable;

  @override
  int get hashCode => unreadable.hashCode;
}

/// Everything the assign sheet holds between a toggle and the write.
class AssignSheetState {
  const AssignSheetState({
    this.pending = const {},
    this.applying = false,
    this.preparing = false,
    this.unfinished,
    this.notice,
  });

  /// Pending toggles, by child id. Nothing here has been written.
  final Map<String, bool> pending;

  /// A write is running.
  final bool applying;

  /// Waiting on something Apply needs *before* it can write.
  ///
  /// The collection index is 1 + N calls — list the sets, then ask each what is
  /// in it — and the cascade question has to wait for it rather than read it
  /// half-built, or a parent is never asked a cascade question they were owed.
  /// That wait is real work and used to happen with the button still reading
  /// *Apply* and nothing on screen: no spinner, because [applying] is only set
  /// once the write starts, and the write is the fast part. Reported as the app
  /// doing nothing at the moment it is doing its main job.
  ///
  /// Separate from [applying] rather than folded into it because the write
  /// paths manage that flag themselves, and one of them clears it between the
  /// sets of a batch.
  final bool preparing;

  final AssignUnfinished? unfinished;
  final AssignNotice? notice;

  /// A tap is being processed — either half of it.
  bool get busy => applying || preparing;

  /// Turns the pending toggles into the writes they imply.
  ///
  /// The inversion lives in [TagChange.givesAccess]; here the only question is
  /// whether the *label* goes on or comes off, which for a block-list child is
  /// the opposite of what the switch appears to say.
  TagDiff diffFrom(List<AssignRow> rows) {
    final changes = <TagChange>[];
    for (final row in rows) {
      final wanted = pending[row.child.id];
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

  AssignSheetState _with({
    Map<String, bool>? pending,
    bool? applying,
    bool? preparing,
    AssignUnfinished? Function()? unfinished,
    AssignNotice? Function()? notice,
  }) => AssignSheetState(
    pending: pending ?? this.pending,
    applying: applying ?? this.applying,
    preparing: preparing ?? this.preparing,
    unfinished: unfinished == null ? this.unfinished : unfinished(),
    notice: notice == null ? this.notice : notice(),
  );
}

/// What the apply flow needs from whatever shows the sheet: the questions it
/// asks the parent, and the report once a write is done.
///
/// The questions are dialogs and the report is a toast and a close, so they
/// belong to the widget; the order they are asked in, and what each answer
/// leads to, is [AssignSheetController]'s.
abstract interface class AssignSheetHost {
  /// Whether the sheet is still on screen. Each step after a wait checks it, as
  /// the widget did when the flow lived there.
  bool get mounted;

  /// The last-item warning. See `confirmLastItem`.
  Future<bool> confirmLastItem(TagDiff diff, {required Set<String> touching});

  /// Whether to keep [set] together. Null means the dialog was dismissed.
  Future<bool?> askKeepSetTogether(CollectionSet set);

  /// Closes the sheet and reports the **verified** count, with Undo.
  void reportAndClose({
    required TagDiff diff,
    required Future<Map<String, int>> counts,
    required int libraryTotal,
    required Future<void> Function() undo,
    required Set<String> touching,
  });
}

/// The assign sheet's apply flow, out of the widget so it can be driven
/// without one.
final assignSheetControllerProvider = NotifierProvider.autoDispose
    .family<AssignSheetController, AssignSheetState, AssignRequest>(
      AssignSheetController.new,
    );

class AssignSheetController extends Notifier<AssignSheetState> {
  AssignSheetController(this.request);

  final AssignRequest request;

  LibraryItem get _item => request.item;

  @override
  AssignSheetState build() => const AssignSheetState();

  /// A switch moved. Nothing is written.
  void toggle(String childId, bool value) {
    state = state._with(pending: {...state.pending, childId: value});
  }

  /// Apply: whatever [diff] means for this item, asked about and written.
  ///
  /// [fromCollection] is the set the parent was looking at when they picked
  /// the item, or null from the library grid.
  Future<void> apply(
    AssignSheetHost host,
    TagDiff diff, {
    required int libraryTotal,
    LibraryItem? fromCollection,
  }) async {
    bool alive() => ref.mounted && host.mounted;

    if (_item.isCollection) {
      // **Waited for**, not read as it stands. Read as it stood, a membership
      // still loading was reported as "the server ran into a problem" — a
      // server error that had not happened, for a tap a moment too early.
      final set = await _awaitSet(host, _item);
      if (!alive()) return;
      if (set == null) {
        // Without the membership there is no safe write: labelling the
        // container alone gives the child an empty collection. And now the
        // error is real: the membership could not be read.
        state = state._with(notice: () => const AssignNotice.serverError());
        return;
      }
      // Ground rule 1's hard warning, asked before the write and impossible
      // to apply past without having read it. For a set it has to know the
      // whole set: a removal takes the label off every member and the
      // container, and a child whose only label is on those has nothing left.
      if (!await _confirmLastItem(host, diff, touching: wholeSet(set))) return;
      if (!alive()) return;
      await _runBatch(host, set, diff, libraryTotal: libraryTotal);
      return;
    }

    // A film: the warning for the one item. A removal never cascades (ground
    // rule 6), so this is all it takes the label off.
    if (!await _confirmLastItem(host, diff, touching: {_item.id})) return;
    if (!alive()) return;

    // A film. Ask about each set it belongs to — additions only, because
    // removing a label never cascades (ground rule 6).
    final sets = await _askAboutSets(host, diff);
    if (sets == null || !alive()) return;

    if (sets.isEmpty) {
      // Not necessarily "just this film". If the parent is standing inside a
      // set, the container of THAT set follows the films they gave from it --
      // otherwise the child gets the film loose and the set stays invisible to
      // them, which is the defect this entry exists for.
      //
      // Only the set in front of them. A film in three sets would otherwise
      // hand over three collections nobody offered.
      //
      // `CollectionPrompt.never` is excluded deliberately and keeps its
      // documented meaning -- *treat a film in a set as a film*. A parent who
      // set that has said they want the film alone, and this is the one place
      // that answer is expressible.
      final prompt = ref.read(settingsProvider).collectionPrompt;
      if (fromCollection != null &&
          prompt != CollectionPrompt.never &&
          diff.additions.isNotEmpty) {
        final originSet = await _awaitSet(host, fromCollection);
        if (!alive()) return;
        if (originSet != null) {
          await _runPartial(host, originSet, diff, libraryTotal: libraryTotal);
          return;
        }
        // Membership unavailable: fall through to the single write rather than
        // guess at siblings. A loose film is the status quo; a container
        // written without knowing what else is in the set is not.
      }
      await _runSingle(host, diff, libraryTotal);
      return;
    }
    for (final set in sets) {
      final finished = await _runBatch(
        host,
        set,
        diff,
        libraryTotal: libraryTotal,
      );
      if (!finished || !alive()) return;
    }
  }

  /// Ground rule 5's *finish the rest*: the same write again. Tag writes are
  /// idempotent, so the titles that landed are untouched and the ones that did
  /// not are retried — which is the whole of "retry that item".
  Future<void> finishUnfinished(
    AssignSheetHost host,
    AssignUnfinished unfinished,
  ) => _runBatch(
    host,
    unfinished.set,
    unfinished.diff,
    libraryTotal: unfinished.libraryTotal,
  );

  /// Ground rule 5's *remove all*: a fresh forward write in the other
  /// direction, not a restore. Reversing an addition is a removal, and it can
  /// strip a child's last label exactly as Apply can.
  Future<void> reverseUnfinished(
    AssignSheetHost host,
    AssignUnfinished unfinished,
  ) async {
    final reversed = AssignRepository.reverse(unfinished.diff);
    if (!await _confirmLastItem(
      host,
      reversed,
      touching: wholeSet(unfinished.set),
    )) {
      return;
    }
    if (!ref.mounted || !host.mounted) return;
    await _runBatch(
      host,
      unfinished.set,
      reversed,
      libraryTotal: unfinished.libraryTotal,
    );
  }

  /// Every item a write to [set] takes a label off: the members and the
  /// container.
  static Set<String> wholeSet(CollectionSet set) => {
    set.collection.id,
    ...set.memberIds,
  };

  AssignRepository get _repository =>
      ref.read(assignRepositoryProvider(request.session));

  /// Sets [preparing] for the length of [work], so the button shows a spinner
  /// while the tap waits on something before it can write.
  Future<T> _preparingFor<T>(
    AssignSheetHost host,
    Future<T> Function() work,
  ) async {
    state = state._with(preparing: true);
    try {
      return await work();
    } finally {
      if (ref.mounted && host.mounted) state = state._with(preparing: false);
    }
  }

  /// The last-item warning, from this sheet.
  ///
  /// **Busy while it asks.** The question is one or two server queries per
  /// removal before any dialog can appear, and asked with the button still
  /// reading *Apply* that was a round trip of a tap doing nothing visible —
  /// the symptom [AssignSheetState.preparing] exists for.
  Future<bool> _confirmLastItem(
    AssignSheetHost host,
    TagDiff diff, {
    required Set<String> touching,
  }) =>
      _preparingFor(host, () => host.confirmLastItem(diff, touching: touching));

  /// Asks, once per set this film belongs to, whether to keep it together.
  ///
  /// Null means the parent dismissed a dialog rather than answering it, which
  /// cancels the whole write — a dismissal is not "just this one".
  Future<List<CollectionSet>?> _askAboutSets(
    AssignSheetHost host,
    TagDiff diff,
  ) async {
    // Ground rule 6 and Settings → Labels, in one place. `none` decides without
    // a lookup, which is what keeps *just the one title* cheap.
    final plan = cascadePlanFor(
      diff: diff,
      prompt: ref.read(settingsProvider).collectionPrompt,
    );
    if (plan == CascadePlan.none) return const [];

    final accepted = <CollectionSet>[];
    final candidates = await _sets(host);
    if (!ref.mounted || !host.mounted) return null;
    for (final set in candidates) {
      if (plan == CascadePlan.all) {
        // The parent has already answered this question, once, in Settings.
        accepted.add(set);
        continue;
      }
      if (!ref.mounted || !host.mounted) return null;
      final answer = await host.askKeepSetTogether(set);
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
  Future<List<CollectionSet>> _sets(AssignSheetHost host) =>
      _preparingFor(host, () async {
        try {
          final index = await ref.read(
            collectionIndexProvider(request.session).future,
          );
          return index.setsContaining(_item.id);
        } on Object {
          return const [];
        }
      });

  /// The membership of [collection], waited for.
  ///
  /// Null when it cannot be read. From a film, the caller then writes the film
  /// alone rather than writing a container without knowing what else is
  /// inside — a partial give that guesses at siblings is worse than the loose
  /// film it replaces.
  ///
  /// Also the membership of the set this sheet is *for*, when it is one:
  /// Apply waits for it the same way rather than reading it half-loaded.
  Future<CollectionSet?> _awaitSet(
    AssignSheetHost host,
    LibraryItem collection,
  ) {
    final request = CollectionRequest(
      session: this.request.session,
      collection: collection,
    );
    return _preparingFor(host, () async {
      try {
        return await ref.read(collectionSetProvider(request).future);
      } on Object {
        return null;
      }
    });
  }

  /// One film and the container of the set it was given from — nothing else.
  ///
  /// The same repository call a whole-set write uses, handed a single member.
  /// Phase 3's condition is *what this write was asked to do*, so the container
  /// follows as soon as that one film lands; the siblings are passed so a
  /// removal can tell whether any label would be left behind.
  Future<void> _runPartial(
    AssignSheetHost host,
    CollectionSet set,
    TagDiff diff, {
    required int libraryTotal,
  }) async {
    final repository = _repository;
    final siblings = set.memberIds
        .where((id) => id != _item.id)
        .toList(growable: false);

    _startWrite();
    try {
      final outcome = await repository.applyToCollection(
        collectionId: set.collection.id,
        memberIds: <String>[_item.id],
        diff: diff,
        siblingIds: siblings,
      );
      if (!ref.mounted || !host.mounted) return;
      _refreshEverything();
      host.reportAndClose(
        diff: diff,
        counts: Future<Map<String, int>>.value(outcome.counts),
        libraryTotal: libraryTotal,
        undo: () => repository.undoCollection(
          collectionId: set.collection.id,
          memberIds: <String>[_item.id],
          diff: diff,
        ),
        // The film and the container it was given from: what the partial
        // write labelled, and so what its Undo takes back.
        touching: {set.collection.id, _item.id},
      );
    } on Object {
      _say(host, const AssignNotice.serverError());
    } finally {
      _endWrite(host);
    }
  }

  Future<void> _runSingle(
    AssignSheetHost host,
    TagDiff diff,
    int libraryTotal,
  ) async {
    final repository = _repository;
    _startWrite();
    try {
      final outcome = await repository.apply(itemId: _item.id, diff: diff);
      if (!ref.mounted || !host.mounted) return;
      _refreshEverything();
      host.reportAndClose(
        diff: diff,
        counts: outcome.counts,
        libraryTotal: libraryTotal,
        undo: () => repository.undo(itemId: _item.id, diff: diff),
        touching: {_item.id},
      );
    } on Object {
      // A failure has to say so on the sheet. Left to the framework it becomes
      // an uncaught async error: the spinner stops, nothing changes, and the
      // parent cannot tell that from a write that did nothing.
      _say(host, const AssignNotice.serverError());
    } finally {
      _endWrite(host);
    }
  }

  /// One collection write, and what to show for each way it can end.
  ///
  /// Returns whether the set finished; a partly-written set keeps the sheet
  /// open with the fix-forward offer rather than closing over the top of it.
  Future<bool> _runBatch(
    AssignSheetHost host,
    CollectionSet set,
    TagDiff diff, {
    required int libraryTotal,
  }) async {
    final repository = _repository;

    _startWrite();
    try {
      final outcome = await repository.applyToCollection(
        collectionId: set.collection.id,
        memberIds: set.memberIds,
        diff: diff,
      );
      if (!ref.mounted || !host.mounted) return false;
      _refreshEverything();

      if (!outcome.isComplete) {
        state = state._with(
          unfinished: () => AssignUnfinished(
            set: set,
            outcome: outcome,
            diff: diff,
            libraryTotal: libraryTotal,
          ),
        );
        return false;
      }

      host.reportAndClose(
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
        touching: wholeSet(set),
      );
      return true;
    } on CollectionPreflightException catch (error) {
      // Nothing was written, and saying so is the whole point: the parent needs
      // to know the set is untouched rather than half-done.
      if (!ref.mounted || !host.mounted) return false;
      state = state._with(
        unfinished: () => null,
        notice: () => AssignNotice.preflightFailed(error.unreadable.length),
      );
      return false;
    } on Object {
      // Anything else — the counts re-fetch, a dropped connection — leaves the
      // set in whatever state the writes reached. Say something rather than
      // stopping the spinner and looking finished.
      _say(host, const AssignNotice.serverError());
      return false;
    } finally {
      _endWrite(host);
    }
  }

  void _startWrite() => state = state._with(applying: true, notice: () => null);

  void _endWrite(AssignSheetHost host) {
    if (ref.mounted && host.mounted) state = state._with(applying: false);
  }

  void _say(AssignSheetHost host, AssignNotice notice) {
    if (ref.mounted && host.mounted) state = state._with(notice: () => notice);
  }

  /// Everything downstream is stale after a write: the grid's tags, the counts,
  /// the sheet's own rows.
  void _refreshEverything() {
    ref.invalidate(assignRowsProvider(request));
    ref.read(libraryRevisionProvider.notifier).bump();
    ref.invalidate(kidsOverviewProvider(request.session));
  }
}
