// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../repositories/app_settings_store.dart';
import 'jellyfin_user.dart';
import 'library_item.dart';
import 'tag_diff.dart';

/// A BoxSet and what is inside it.
///
/// A Jellyfin collection is a **container**: the child's policy filters the
/// films, not the box. Measured on 10.11.11, though, the container is not
/// irrelevant either: with no label on it the set is **invisible** to the
/// child rather than merely refused, so members given without it arrive loose.
/// See [CollectionGiven] for what is counted and [CollectionGiven.containerWantsLabel]
/// for which way the container has to move, which inverts with the mode.
///
/// (This sentence used to end "see [isGivenTo]", which was defined nowhere in
/// `lib/` or `test/` — a dartdoc link that resolved to nothing, in the file
/// whose subject is what the container's label means.)
class CollectionSet {
  const CollectionSet({required this.collection, required this.members});

  final LibraryItem collection;

  /// The films inside, from `GET /Items?parentId={id}`.
  ///
  /// Read-only rows. They are list results — 16 fields against 41 from a
  /// single-item `GET` — so nothing here may be posted back; the write path
  /// takes ids and fetches its own bodies (ground rule 2).
  final List<LibraryItem> members;

  int get size => members.length;

  List<String> get memberIds =>
      members.map((m) => m.id).toList(growable: false);

  /// The members other than [itemId] — what the "keep the set together?"
  /// dialog lists.
  List<LibraryItem> othersThan(String itemId) =>
      members.where((m) => m.id != itemId).toList(growable: false);
}

/// Whether writing [diff] to a film should ask about the sets it belongs to.
///
/// **The question only fires on additions**, which is ground rule 6 and
/// `docs/DECISIONS.md` § Collections: taking a label off one film never strips
/// the rest of the set. A cascade that ran in both directions would make an
/// unshare unpredictable — a parent taking one film back would silently take
/// four — and unpredictable is the worst thing a permission tool can be.
///
/// A diff that both gives and takes still asks: the giving half is a cascade,
/// and the taking half stays on the single film either way.
///
/// Asked **before** the sets are looked up, not after, so a removal does not
/// pay for an index it is forbidden to use.
bool cascadeAsks(TagDiff diff) => diff.additions.isNotEmpty;

/// What to do about the sets a film belongs to, before any dialog appears.
///
/// Ground rule 6 first, the parent's preference second: a removal never
/// cascades whatever Settings says, because that rule is about the app being
/// predictable rather than about taste.
///
/// [CascadePlan.none] is also what makes *just the one title* cheap — with no
/// cascade possible there is nothing to look up, and the collection index costs
/// 1 + N requests.
CascadePlan cascadePlanFor({
  required TagDiff diff,
  required CollectionPrompt prompt,
}) {
  if (!cascadeAsks(diff)) return CascadePlan.none;
  return switch (prompt) {
    CollectionPrompt.never => CascadePlan.none,
    CollectionPrompt.always => CascadePlan.all,
    CollectionPrompt.ask => CascadePlan.ask,
  };
}

/// The three answers to "does this write cover the rest of the set?".
enum CascadePlan {
  /// No set is touched, and none is looked up.
  none,

  /// Every set the film belongs to, without asking — the parent answered in
  /// Settings.
  all,

  /// Ask, once per set, listing the other titles and their ratings.
  ask,
}

/// Every collection on the server, with its membership.
///
/// Built once and kept: Garfin never changes membership, so nothing it does can
/// invalidate this.
class CollectionIndex {
  const CollectionIndex(this.sets);

  const CollectionIndex.empty() : sets = const [];

  final List<CollectionSet> sets;

  /// Which collections contain [itemId].
  ///
  /// **A film can belong to several**, and the list is built by walking every
  /// set because Jellyfin offers no way to ask the question directly — see
  /// `CollectionRepository`.
  List<CollectionSet> setsContaining(String itemId) => sets
      .where((set) => set.members.any((m) => m.id == itemId))
      .toList(growable: false);

  /// Every item that belongs to some collection, once.
  ///
  /// What the grid drops when it is standing sets in for their members (#144),
  /// and what the result line subtracts when it can — see
  /// `collapsedLibraryTotal`.
  Set<String> get allMemberIds => {
        for (final set in sets)
          for (final member in set.members) member.id,
      };

  CollectionSet? byId(String collectionId) {
    for (final set in sets) {
      if (set.collection.id == collectionId) return set;
    }
    return null;
  }
}

/// How much of a set carries one child's label, and which verb says so.
///
/// #107, and the half of it neither the parent nor the child could see: give
/// three films out of eight and nothing on any screen says the set is part-way
/// there. The set's own tile answers "not given", which is a true statement
/// about the **container** and a misleading one about the eight titles inside.
///
/// **This counts labels, not visibility.** "3 of 8 given" is a fact about what
/// the parent handed over; what the child can actually *see* is the server's
/// answer, tags and rating cap together, and computing that here is what ground
/// rule 4 forbids. The two numbers can legitimately differ, which is why they
/// never share a sentence.
///
/// **The verb inverts with the mode** (ground rule 3): the same label means
/// *given to* an allow-list child and *kept from* a block-list one, so a single
/// count with one verb would be exactly backwards for half of them. A child
/// Garfin refuses to interpret gets no answer at all rather than a guessed one.
class CollectionGiven {
  const CollectionGiven({
    required this.labelled,
    required this.total,
    required this.mode,
  });

  /// The child's answer for this set, or **null** when there is no verb to use
  /// — nobody picked, an account under no shortlist control, or one with both
  /// lists live.
  static CollectionGiven? of({
    required int labelled,
    required int total,
    required JellyfinUser? child,
  }) {
    final mode = child?.policy.shortlistMode;
    if (mode != ShortlistMode.allow && mode != ShortlistMode.block) return null;
    if (total == 0) return null;
    return CollectionGiven(labelled: labelled, total: total, mode: mode!);
  }

  /// How many members carry the label. Not how many the child can see.
  final int labelled;

  final int total;
  final ShortlistMode mode;

  /// How many members the child actually **has**, which is not [labelled].
  ///
  /// The inversion again: a label gives in allow mode and withholds in block
  /// mode, so a block-list child has the members that are *not* labelled.
  /// [labelled] stays a literal count of labels because that is what the
  /// sentence reports; this is the number the repair offer turns on.
  int get givenToChild =>
      mode == ShortlistMode.block ? total - labelled : labelled;

  /// Whether the container must carry the label for the child to open the set.
  ///
  /// True in allow mode, false in block mode — where the label is what shuts
  /// the set, so an openable container is an *unlabelled* one.
  bool get containerWantsLabel => mode == ShortlistMode.allow;

  bool get none => labelled == 0;
  bool get all => labelled == total;
}
