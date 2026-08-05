// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/dto_json.dart';
import '../models/jellyfin_user.dart';
import '../models/tag_diff.dart';
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
  });

  final JellyfinApi _api;
  final String _adminUserId;

  /// The sheet's rows: whether the item carries each child's label, and what
  /// each child can see right now.
  Future<List<AssignRow>> rowsFor({
    required String itemId,
    required List<JellyfinUser> children,
  }) async {
    final item = await _api.fullItem(userId: _adminUserId, itemId: itemId);
    final tags = readStringList(item, 'Tags');
    final libraryTotal = await _api.visibleItemCount(userId: _adminUserId);

    final rows = <AssignRow>[];
    for (final child in children) {
      final label = labelFor(child);
      if (label == null) continue;
      rows.add(
        AssignRow(
          child: child,
          label: label,
          hasLabel: tags.any((t) => t.toLowerCase() == label.toLowerCase()),
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
      final item = await _api.fullItem(userId: _adminUserId, itemId: itemId);

      // Mutate one key. Everything else in the map is carried back verbatim —
      // no typed model in between, because a typed model is how a field goes
      // missing from a full-object replace.
      item['Tags'] = diff.applyTo(readStringList(item, 'Tags'));

      await _api.replaceItem(itemId: itemId, item: item);
    }

    // Ground rule 1: the count Garfin reports afterwards is the server's, asked
    // again, not the one it expected.
    final counts = <String, int>{};
    for (final change in diff.changes) {
      counts[change.child.id] =
          await _api.visibleItemCount(userId: change.child.id);
    }

    return AssignOutcome(counts: counts, applied: diff);
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
      apply(
        itemId: itemId,
        diff: TagDiff(
          diff.changes
              .map((c) => TagChange(
                    child: c.child,
                    label: c.label,
                    adding: !c.adding,
                  ))
              .toList(growable: false),
        ),
      );

  /// The label defining this child's shortlist, in the policy's own casing.
  ///
  /// Null when there is no single verb — ground rule 3 refuses to interpret an
  /// account with both lists populated, so it gets no row on the sheet.
  static String? labelFor(JellyfinUser child) {
    final tags = child.policy.shortlistTags;
    return tags.isEmpty ? null : tags.first;
  }
}
