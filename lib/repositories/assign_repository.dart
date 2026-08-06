// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../logging.dart';
import '../models/activity_entry.dart';
import '../models/dto_json.dart';
import '../models/jellyfin_user.dart';
import '../models/library_item.dart';
import '../models/tag_diff.dart';
import 'activity_store.dart';
import 'bounded_batch.dart';
import 'jellyfin_api.dart';

/// The result of applying a diff, as the **server** reports it afterwards.
class AssignOutcome {
  const AssignOutcome({required this.counts, required this.applied});

  /// Each child's visible count, re-fetched after the write.
  ///
  /// Ground rule 1: report the *verified* new count, not a predicted one. This
  /// is also what explains a share the rating cap swallowed — the tag landed,
  /// the number did not move, and the app can say so rather than looking
  /// broken.
  final Map<String, int> counts;

  final TagDiff applied;
}

/// What a collection write actually did, item by item.
///
/// Ground rule 5's "surface the exact state — 7 of 12 tagged". There is no
/// rolled-back variant of this class on purpose: the states it can describe are
/// the states the app is allowed to be in.
class BatchOutcome {
  const BatchOutcome({
    required this.written,
    required this.failed,
    required this.setMarked,
    required this.counts,
    required this.applied,
  });

  /// Member ids that took the change.
  final List<String> written;

  /// Member ids that did not. **These are not undone.** Retrying one is
  /// idempotent; undoing the others is another full-object replace each, on
  /// items that were fine.
  final List<String> failed;

  /// Whether the container itself now carries the change.
  ///
  /// Its own state, not a summary of the members', because the child can tell
  /// the difference: without it they get the films and no set to find them in.
  final bool setMarked;

  /// Each child's visible count, re-fetched afterwards (ground rule 1).
  final Map<String, int> counts;

  final TagDiff applied;

  /// Titles in the set. The container is not one — "7 of 12" is about films,
  /// which is the number the parent can check for themselves.
  int get total => written.length + failed.length;

  bool get isComplete => failed.isEmpty && setMarked;
}

/// The batch was abandoned before anything was written.
///
/// Ground rule 5's pre-flight: every member is read first, and one unreadable
/// member cancels the whole write. Reads are free, so this costs nothing and
/// catches the missing item, the permission problem and the unreachable server
/// while there is still nothing to regret.
class CollectionPreflightException implements Exception {
  const CollectionPreflightException(this.unreadable);

  /// The ids that could not be read. Nothing was written.
  final List<String> unreadable;

  @override
  String toString() =>
      'CollectionPreflightException(${unreadable.length} unreadable)';
}

/// A removal that would take a child's label off the last item carrying it.
///
/// Ground rule 1's hard warning. Their `AllowedTags` still lists the label; it
/// simply stops matching anything, so they see **nothing** — not everything.
class LastItemWarning {
  const LastItemWarning({required this.child, required this.label});

  final JellyfinUser child;
  final String label;
}

/// The write path.
///
/// **Ground rule 2 is enforced by the shape of this class, not by care.**
/// Nothing here accepts an item object. [apply] takes an item *id* and fetches
/// the full object itself, so a caller physically cannot hand it something that
/// came from a list query — and a list query returns 19 of 52 fields, which is
/// the wipe the rule exists to prevent.
class AssignRepository {
  const AssignRepository({
    required this._api,
    required this._adminUserId,
    // Defaulted rather than required, so every existing call site keeps the
    // behaviour it was written for: no extra call unless Settings asks.
    this._refreshAfterWrite = false,
    this._activity,
  });

  final JellyfinApi _api;
  final String _adminUserId;

  /// Settings → Labels → *refresh metadata after write*. Off by default, and
  /// slow when on: it is one more server round-trip per item, so a twelve-film
  /// set pays it twelve times. See [JellyfinApi.refreshItem] for why the
  /// dangerous parameter is not reachable from here.
  final bool _refreshAfterWrite;

  /// Where a completed action is recorded.
  ///
  /// **Here rather than at the call site**, so a future write path cannot ship
  /// without logging — the same reasoning that makes the pre-flight return ids
  /// rather than bodies. Null in tests that are not about the log.
  final ActivityStore? _activity;

  /// The sheet's rows: whether the item carries each child's label, and what
  /// each child can see right now.
  ///
  /// When [members] is given the item is a collection, and "the child has it"
  /// means the whole set — the container **and** every member — rather than the
  /// container's own tags.
  ///
  /// **Both halves, and the container half is measured rather than assumed.**
  /// On 10.11.11, for an allow-list child:
  ///
  /// | container tagged | members tagged | films seen | the set itself |
  /// |---|---|---|---|
  /// | no  | yes | all of them | **absent**, and browsing it answers 401 |
  /// | yes | no  | none        | present, and **empty** |
  /// | yes | yes | all of them | present, with its films |
  ///
  /// So a set with only its members labelled is not finished: the child holds
  /// the films and cannot reach the set. Reporting that as given would put a
  /// half-shared set in the "done" pile, which is what `docs/DECISIONS.md`
  /// § Collections exists to prevent.
  Future<List<AssignRow>> rowsFor({
    required String itemId,
    required List<JellyfinUser> children,
    List<LibraryItem>? members,
  }) async {
    final item = await _api.fullItem(userId: _adminUserId, itemId: itemId);
    final tags = readStringList(item, 'Tags');
    final libraryTotal = await _api.visibleItemCount(userId: _adminUserId);

    final rows = <AssignRow>[];
    for (final child in children) {
      final label = labelFor(child);
      if (label == null) continue;
      // Read against *all* of the child's labels — the server matches any —
      // but write the one chosen by `labelFor`.
      final owned = child.policy.shortlistTags;
      final ownedLower = owned.map((t) => t.toLowerCase()).toSet();
      rows.add(
        AssignRow(
          child: child,
          label: label,
          hasLabel: members == null
              ? tags.any((t) => ownedLower.contains(t.toLowerCase()))
              // The container's tags come from the fresh read above rather than
              // from a list row, so the toggle reflects the server now.
              : members.isNotEmpty &&
                  tags.any((t) => ownedLower.contains(t.toLowerCase())) &&
                  members.every((m) => m.hasAnyLabel(owned)),
          visibleCount: await _api.visibleItemCount(userId: child.id),
          libraryTotal: libraryTotal,
        ),
      );
    }
    return rows;
  }

  /// Which removals in [diff] would strip a label off its last item.
  ///
  /// Asked **before** applying, because the warning must be readable before the
  /// write rather than explained after it.
  ///
  /// This is a count of items carrying the tag, which is a library query — not
  /// a visibility computation, so ground rule 4 is not in play and no rating
  /// cap enters into it. Garfin cannot empty `AllowedTags` itself (rule 8);
  /// what it can do is leave the label matching nothing.
  Future<List<LastItemWarning>> lastItemWarningsFor(TagDiff diff) async {
    final warnings = <LastItemWarning>[];

    for (final change in diff.changes) {
      // Only a removal can strip the last one. In block mode "removing the
      // label" is the act that *grants* access, and it cannot empty anything.
      if (change.adding) continue;
      if (change.child.policy.shortlistMode != ShortlistMode.allow) continue;

      final count = await _api.taggedItemCount(
        userId: _adminUserId,
        tag: change.label,
      );
      // Exactly one left, and this removal is it.
      if (count <= 1) {
        warnings.add(
          LastItemWarning(child: change.child, label: change.label),
        );
      }
    }

    return warnings;
  }

  /// Writes [diff] to one item, then re-reads what each child can see.
  ///
  /// The full-object round-trip, in the only order that is safe:
  ///
  /// 1. `GET /Users/{uid}/Items/{id}` — all 52 fields, fetched **here** so no
  ///    caller can substitute a list result
  /// 2. mutate `Tags` and nothing else
  /// 3. `POST /Items/{id}` with the whole object back
  ///
  /// The scraper's tags ride along untouched, which is not a nicety: measured,
  /// a film arrived carrying eighteen of them before Garfin added the
  /// nineteenth.
  Future<AssignOutcome> apply({
    required String itemId,
    required TagDiff diff,
  }) async {
    if (!diff.isEmpty) {
      final name = await _writeOne(itemId, diff);
      await _record(diff: diff, itemId: itemId, itemName: name);
    }
    return AssignOutcome(counts: await _countsFor(diff), applied: diff);
  }

  /// Writes [diff] across a whole collection: every member, and the container.
  ///
  /// **The container is not decoration.** Measured on 10.11.11 for an allow-list
  /// child: labelling only the members hands over the films while the set itself
  /// stays absent and browsing it answers 401, and labelling only the container
  /// hands over an **empty** set. Both halves, or the parent has not given what
  /// they think they gave.
  ///
  /// Three phases, in this order, and the order is the point:
  ///
  /// 1. **the container's removals** — before any member loses its label, so the
  ///    set stops claiming to be complete first;
  /// 2. **every member**, [batchConcurrency] at a time, each its own full-object
  ///    round-trip;
  /// 3. **the container's additions — last, and only if every member landed.**
  ///
  /// Phase 3 is what makes the container's label mean "the whole set is here".
  /// A partly-failed batch therefore leaves it off, the set reads as not-given
  /// on the grid, and it stays in the to-do list instead of looking finished —
  /// which is what `docs/DECISIONS.md` § Collections asks for, at the cost of no
  /// extra query.
  ///
  /// Nothing that succeeded is ever undone (ground rule 5). The failures come
  /// back in [BatchOutcome.failed] for the user to finish or reverse, both of
  /// which are idempotent and both of which they choose.
  ///
  /// Throws [CollectionPreflightException] — having written **nothing** — when
  /// any item cannot be read first.
  Future<BatchOutcome> applyToCollection({
    required String collectionId,
    required List<String> memberIds,
    required TagDiff diff,
  }) async {
    if (diff.isEmpty) {
      return BatchOutcome(
        written: const [],
        failed: const [],
        setMarked: true,
        counts: await _countsFor(diff),
        applied: diff,
      );
    }

    // Pre-flight, ground rule 5. Reads are free; a write is not.
    final unreadable = await _preflight(<String>[collectionId, ...memberIds]);
    if (unreadable.isNotEmpty) {
      log.warning('collection write abandoned: ${unreadable.length} of '
          '${memberIds.length + 1} items could not be read');
      throw CollectionPreflightException(unreadable);
    }

    final removals = TagDiff(diff.removals.toList(growable: false));
    final additions = TagDiff(diff.additions.toList(growable: false));

    var setMarked = true;
    // The container's own name, taken from whichever of its writes happened —
    // the Activity log needs it and the server has already sent it.
    String? collectionName;
    if (!removals.isEmpty) {
      collectionName = await _tryWrite(collectionId, removals);
      setMarked = collectionName != null;
    }

    final results = await mapBounded<String, ({String id, String? name})>(
      memberIds,
      (id) async => (id: id, name: await _tryWrite(id, diff)),
    );
    final written = [for (final r in results) if (r.name != null) r.id];
    final failed = [for (final r in results) if (r.name == null) r.id];

    if (!additions.isEmpty) {
      // Only when the whole set is actually there. This is the marker, so
      // writing it over a half-tagged set would be a lie the grid then repeats.
      if (failed.isNotEmpty) {
        setMarked = false;
      } else {
        collectionName = await _tryWrite(collectionId, additions);
        if (collectionName == null) setMarked = false;
      }
    }

    if (failed.isEmpty && setMarked) {
      // **Only a completed action is logged.** A partly-written set is not
      // something the parent did — it is a state they are still deciding about,
      // and the sheet keeps it on screen with *finish the rest* / *put it all
      // back*. Recording it as done would put an Undo behind a claim that is
      // not true yet.
      await _record(
        diff: diff,
        itemId: collectionId,
        itemName: collectionName ?? '',
        collectionSize: memberIds.length,
      );
    }

    return BatchOutcome(
      written: written,
      failed: failed,
      setMarked: setMarked,
      counts: await _countsFor(diff),
      applied: diff,
    );
  }

  /// Reads every item in the batch, and keeps none of them.
  ///
  /// **The bodies are discarded deliberately.** Handing a pre-flight body to the
  /// write would be re-posting a captured object — the thing ground rule 2 and
  /// the Undo rule both forbid — and it would be stale by exactly as long as the
  /// batch takes. Every write below fetches its own. This returns ids, so there
  /// is no body to be tempted by.
  Future<List<String>> _preflight(List<String> itemIds) async {
    final results = await mapBounded<String, String?>(itemIds, (id) async {
      try {
        await _api.fullItem(userId: _adminUserId, itemId: id);
        return null;
      } on Object {
        return id;
      }
    });
    return results.whereType<String>().toList(growable: false);
  }

  /// One full-object round-trip. The only place this app writes an item.
  ///
  /// Returns the item's own `Name`, because the Activity log needs one and the
  /// server has already sent it — asking a caller to pass a name in would be a
  /// second source of truth for what an item is called.
  Future<String> _writeOne(String itemId, TagDiff diff) async {
    final item = await _api.fullItem(userId: _adminUserId, itemId: itemId);

    // Mutate one key. Everything else in the map is carried back verbatim —
    // no typed model in between, because a typed model is how a field goes
    // missing from a full-object replace.
    item['Tags'] = diff.applyTo(readStringList(item, 'Tags'));

    await _api.replaceItem(itemId: itemId, item: item);
    final name = readString(item, 'Name') ?? '';

    if (_refreshAfterWrite) {
      try {
        await _api.refreshItem(itemId: itemId);
      } on Object catch (error) {
        // **A failed refresh is not a failed write.** The label is on the item;
        // letting this escape would put the item in `BatchOutcome.failed`, and
        // the fix-forward panel would then report a write that actually
        // succeeded as one that did not.
        log.info('metadata refresh after write failed: ${error.runtimeType}');
      }
    }
    return name;
  }

  /// [_writeOne], reporting rather than throwing, so one failure does not
  /// discard what the rest of the batch did. Null means it failed.
  Future<String?> _tryWrite(String itemId, TagDiff diff) async {
    try {
      return await _writeOne(itemId, diff);
    } on Object catch (error) {
      // No id in the log line: it is a library item, but it is still the
      // parent's data and the failure is legible without it.
      log.warning('a collection member write failed: ${error.runtimeType}');
      return null;
    }
  }

  /// Writes one Activity entry per child the action touched.
  ///
  /// Per **child**, because a single Apply that hands a film to Emma and takes
  /// it from Sam is two things a parent did, and "Handed to Emma" cannot say
  /// both. Per **action** rather than per item, because a twelve-film
  /// collection is one thing they did.
  ///
  /// A failure here is logged and swallowed: the library write already
  /// succeeded, and letting a preferences problem surface as a failed write
  /// would be a lie in the more alarming direction.
  Future<void> _record({
    required TagDiff diff,
    required String itemId,
    required String itemName,
    int? collectionSize,
  }) async {
    final activity = _activity;
    if (activity == null) return;
    try {
      for (final change in diff.changes) {
        await activity.add(
          ActivityEntry(
            itemId: itemId,
            itemName: itemName,
            childId: change.child.id,
            childName: change.child.name,
            label: change.label,
            // What it did to the child, not to the tag — ground rule 3 makes
            // those opposites for a block-list account.
            gaveAccess: change.givesAccess,
            at: DateTime.now(),
            collectionSize: collectionSize,
          ),
        );
      }
    } on Object catch (error) {
      log.warning('could not record an activity entry: ${error.runtimeType}');
    }
  }

  /// Ground rule 1: the count Garfin reports afterwards is the server's, asked
  /// again, not the one it expected.
  Future<Map<String, int>> _countsFor(TagDiff diff) async {
    final counts = <String, int>{};
    for (final change in diff.changes) {
      counts[change.child.id] =
          await _api.visibleItemCount(userId: change.child.id);
    }
    return counts;
  }

  /// Reverses [diff] as a **fresh forward write**.
  ///
  /// Ground rule 5, and the part that reads as a contradiction until you see
  /// it: a button labelled Undo beside a rule saying "never undo" is the same
  /// thing, because both are idempotent forward writes. What the rule forbids
  /// is silent automatic rollback of a batch, not an explicit user-initiated
  /// reversal.
  ///
  /// **Garfin never re-posts a previously captured item body.** This re-reads
  /// the item and inverts the change against whatever is there *now*, so a
  /// concurrent edit by someone else survives instead of being clobbered by a
  /// stale snapshot.
  Future<AssignOutcome> undo({
    required String itemId,
    required TagDiff diff,
  }) =>
      apply(itemId: itemId, diff: reverse(diff));

  /// Undo across a whole set, which is the same forward write repeated.
  ///
  /// Reversing an addition makes it a removal, so [applyToCollection]'s
  /// ordering flips with it on its own: the container's label comes **off
  /// first**, and the set stops claiming to hold films it is about to lose.
  Future<BatchOutcome> undoCollection({
    required String collectionId,
    required List<String> memberIds,
    required TagDiff diff,
  }) =>
      applyToCollection(
        collectionId: collectionId,
        memberIds: memberIds,
        diff: reverse(diff),
      );

  /// The same changes, pointing the other way.
  static TagDiff reverse(TagDiff diff) => TagDiff(
        diff.changes
            .map((c) => TagChange(
                  child: c.child,
                  label: c.label,
                  adding: !c.adding,
                ))
            .toList(growable: false),
      );

  /// The label to **write**, in the policy's own casing.
  ///
  /// One label, deliberately, even when the child holds several: adding a tag
  /// is a choice and the first is as good as any. *Reading* uses all of them,
  /// because there the server defines the right answer — see
  /// `LibraryItem.hasAnyLabel`.
  ///
  /// Null when there is no single verb — ground rule 3 refuses to interpret an
  /// account with both lists populated, so it gets no row on the sheet.
  static String? labelFor(JellyfinUser child) {
    final tags = child.policy.shortlistTags;
    return tags.isEmpty ? null : tags.first;
  }
}
