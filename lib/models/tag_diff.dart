// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'jellyfin_user.dart';

/// What toggling one child's row would do to one item's tags.
///
/// The only place a write is previewed (ground rule 1). Nothing writes on
/// toggle; this accumulates until the parent applies it.
class TagChange {
  const TagChange({
    required this.child,
    required this.label,
    required this.adding,
  });

  final JellyfinUser child;

  /// The label to write, **in the casing the child's policy uses**.
  ///
  /// Measured on 10.11.11: the server stores tag casing verbatim and does not
  /// fold it. The `tags=` filter is case-insensitive, so writing the wrong
  /// casing breaks nothing Garfin does — it just leaves `KIDS-EMMA` sitting
  /// beside `kids-emma` in the parent's own Jellyfin tag list. Ground rule 3's
  /// casing instruction is about the data staying tidy, not about matching.
  final String label;

  /// Whether the label is going on or coming off.
  ///
  /// **Not the same as giving or taking away.** Ground rule 3: for a block-list
  /// child adding the label *removes* their access. [givesAccess] is the
  /// question a human is actually asking.
  final bool adding;

  /// Whether this change hands the item to the child or takes it away.
  ///
  /// The inversion, in one place. `adding` a label gives access in allow mode
  /// and removes it in block mode.
  bool get givesAccess => switch (child.policy.shortlistMode) {
        ShortlistMode.allow => adding,
        ShortlistMode.block => !adding,
        // Ground rule 3 refuses to interpret a conflicting account, and there
        // is no shortlist at all in `none`. Neither should reach here — the
        // sheet only offers rows for children with a single verb — so this is
        // a belt-and-braces answer rather than a meaningful one.
        ShortlistMode.none || ShortlistMode.conflicting => adding,
      };
}

/// Which way a diff points, once it has to be described rather than performed.
///
/// A half-finished collection write is reported in words, and the words are not
/// symmetric: labels left **on** the container mean the child sees an empty
/// set, labels left **off** it mean they see the films but cannot reach the
/// set. Describing one as the other is worse than saying nothing, because it
/// sends the parent to check the wrong thing.
enum DiffDirection {
  /// Labels went on.
  added,

  /// Labels came off.
  removed,

  /// Both, across different children. Nothing directional can be said.
  mixed,
}

/// Every pending change for one item, across all the children on the sheet.
class TagDiff {
  const TagDiff(this.changes);

  const TagDiff.empty() : changes = const [];

  final List<TagChange> changes;

  bool get isEmpty => changes.isEmpty;

  Iterable<TagChange> get additions => changes.where((c) => c.adding);

  Iterable<TagChange> get removals => changes.where((c) => !c.adding);

  /// Which way this diff points, for copy that has to say what happened.
  ///
  /// **On the labels, not on access.** Ground rule 3 makes those different
  /// things — adding a label gives access in allow mode and takes it away in
  /// block mode — and this is used to describe *the item*, which is where the
  /// labels went on or came off. What the change means to a child is
  /// [TagChange.givesAccess], and that is what the preview lines above the
  /// button use.
  ///
  /// An empty diff answers [DiffDirection.mixed], the direction that claims
  /// nothing. Nothing should ask: an empty diff is never written.
  DiffDirection get direction {
    if (isEmpty) return DiffDirection.mixed;
    if (removals.isEmpty) return DiffDirection.added;
    if (additions.isEmpty) return DiffDirection.removed;
    return DiffDirection.mixed;
  }

  /// Applies this diff to a tag list, preserving everything else on it.
  ///
  /// The scraper's tags are in the same list — measured, one film arrived
  /// carrying eighteen of them — so this must be a surgical add and remove
  /// rather than a replacement.
  ///
  /// Removal is case-insensitive because the stored casing may not match the
  /// policy's; addition uses the policy's casing. Between them a label written
  /// wrongly in the past still comes off cleanly.
  List<String> applyTo(List<String> existing) {
    final result = List<String>.from(existing);

    for (final change in changes) {
      final wanted = change.label.toLowerCase();
      result.removeWhere((tag) => tag.toLowerCase() == wanted);
      if (change.adding) result.add(change.label);
    }

    return result;
  }
}

/// The state of one child's row on the sheet.
class AssignRow {
  const AssignRow({
    required this.child,
    required this.label,
    required this.hasLabel,
    required this.visibleCount,
    required this.libraryTotal,
  });

  final JellyfinUser child;
  final String label;

  /// Whether the item currently carries this child's label.
  final bool hasLabel;

  /// What the **server** says this child can see right now.
  ///
  /// Ground rule 4, and ground rule 1's "current count, never a predicted one".
  /// Predicting the result would mean simulating the server's policy
  /// evaluation, rating cap included, which is the thing rule 4 forbids because
  /// it goes wrong silently.
  final int visibleCount;

  final int libraryTotal;

  /// Whether the child can reach this item today, in the human sense.
  bool get hasAccess => switch (child.policy.shortlistMode) {
        ShortlistMode.allow => hasLabel,
        ShortlistMode.block => !hasLabel,
        ShortlistMode.none || ShortlistMode.conflicting => false,
      };
}
