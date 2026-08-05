// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'library_item.dart';
import 'tag_diff.dart';

/// A BoxSet and what is inside it.
///
/// A Jellyfin collection is a **container**: the child's policy filters the
/// films, not the box. Measured on 10.11.11, though, the container is not
/// irrelevant either — see [isGivenTo].
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

  CollectionSet? byId(String collectionId) {
    for (final set in sets) {
      if (set.collection.id == collectionId) return set;
    }
    return null;
  }
}
