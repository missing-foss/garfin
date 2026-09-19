// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/collection_set.dart';
import '../models/library_item.dart';
import 'bounded_batch.dart';
import 'jellyfin_api.dart';

/// Reading collections. Nothing here writes.
///
/// **Jellyfin cannot answer "which collections contain this film".** Measured
/// on 10.11.11, and every plausible shortcut gives a wrong answer rather than
/// an error:
///
/// - `Fields=ParentId` on the film returns the **library folder**, the same id
///   for every film in the library.
/// - `GET /Items/{id}/Ancestors` returns that same folder chain; the BoxSet is
///   not in it.
/// - Recursing the Collections folder for `IncludeItemTypes=Movie` returns 0.
/// - `IncludeItemTypes=BoxSet&ancestorIds={filmId}` answers with **every**
///   BoxSet on the server, including ones that do not contain the film —
///   because `ancestorIds` is not one of `/Items`' 86 parameters and **an
///   unknown parameter is silently ignored**, which was confirmed directly
///   (`totalNonsense=42` answers 200). On a library with one collection that
///   wrong answer and the right answer are the same string.
///
/// So the map is built the only way that exists: list the BoxSets, then ask
/// each one what is in it. That is 1 + N calls, which is why [index] is built
/// once and cached rather than asked per sheet.
class CollectionRepository {
  const CollectionRepository({
    required this._api,
    required this._adminUserId,
  });

  final JellyfinApi _api;
  final String _adminUserId;

  /// Every collection with its membership.
  ///
  /// Read as the **administrator**, deliberately: the sheet has to know what is
  /// in a set in order to say "all 12 titles", including the ones the child
  /// cannot see yet. That is the whole point of the screen.
  Future<CollectionIndex> index() async {
    final collections = await _api.collections(userId: _adminUserId);

    // **An empty set is skipped before its membership is asked for** (#109).
    // This is `1 + N` requests over every collection on the server, so each
    // empty one is a whole round trip spent to be told "nothing" — a larger
    // saving than the grid's, which only pays for what is on screen.
    //
    // `childCount != 0` rather than `> 0`: the field is absent unless `Fields`
    // asks for it, and `null` means the server was not asked rather than that
    // the set is empty. `collections()` does ask, so this is the defensive
    // form of a condition that holds — which is the right way round.
    final worthAsking = collections
        .where((collection) => collection.childCount != 0)
        .toList(growable: false);

    final sets = await mapBounded<LibraryItem, CollectionSet>(
      worthAsking,
      (collection) async => CollectionSet(
        collection: collection,
        members: await _api.collectionMembers(
          userId: _adminUserId,
          collectionId: collection.id,
        ),
      ),
    );
    return CollectionIndex(sets);
  }

  /// One collection's membership, without building the whole index.
  ///
  /// What the sheet needs when a **collection** was tapped: the set is already
  /// identified, so there is nothing to search for.
  /// [sortBy] and [sortOrder] are the grid's, because this is what the
  /// collection screen draws. The index built above deliberately does not pass
  /// them: it is a membership lookup, and a set of ids has no order.
  Future<CollectionSet> setFor(
    LibraryItem collection, {
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
  }) async =>
      CollectionSet(
        collection: collection,
        members: await _api.collectionMembers(
          userId: _adminUserId,
          collectionId: collection.id,
          sortBy: sortBy,
          sortOrder: sortOrder,
        ),
      );

  /// The same, from an id alone — what the Activity log has.
  ///
  /// **Resolved now rather than replayed.** A log entry deliberately does not
  /// store the members it wrote to: a set can gain or lose titles between the
  /// write and the undo, and reversing against a captured list is the same
  /// mistake as posting a captured item body. The container is read singly,
  /// which also checks it still exists.
  Future<CollectionSet> setForId(String collectionId) async {
    final container = await _api.fullItem(
      userId: _adminUserId,
      itemId: collectionId,
    );
    return CollectionSet(
      collection: LibraryItem.fromJson(container),
      members: await _api.collectionMembers(
        userId: _adminUserId,
        collectionId: collectionId,
      ),
    );
  }
}
