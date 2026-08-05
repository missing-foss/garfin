// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/jellyfin_user.dart';
import '../models/library_item.dart';
import '../models/library_page.dart';
import 'jellyfin_api.dart';

/// One tile, with what it means for the child currently being picked for.
class LibraryEntry {
  const LibraryEntry({required this.item, required this.state});

  final LibraryItem item;
  final LibraryItemState state;

  /// Whether this counts as already handed over, for the hide-shared filter.
  ///
  /// **[LibraryItemState.givenButHidden] is deliberately included.** The label
  /// is on the item; the parent has done the thing. That it is not reaching the
  /// child is a separate problem, and one the screen explains rather than
  /// re-lists as outstanding work.
  bool get isShared =>
      state == LibraryItemState.given ||
      state == LibraryItemState.givenButHidden ||
      state == LibraryItemState.blocked;
}

/// A screenful of the grid, plus where to resume.
class LibrarySlice {
  const LibrarySlice({
    required this.entries,
    required this.nextStartIndex,
    required this.hasMore,
    required this.totalRecordCount,
  });

  final List<LibraryEntry> entries;
  final int nextStartIndex;
  final bool hasMore;

  /// Everything the admin can see, before hide-shared removes anything. The
  /// denominator, and honestly *the admin's* view rather than "the library" —
  /// an administrator has a policy too.
  final int totalRecordCount;
}

/// The Library grid's data.
///
/// Two decisions from #44 live here, and both are load-bearing:
///
/// **Hide-shared filters client-side over an enlarged window.** There is no
/// `excludeTags` on `/Items` — 86 parameters and not one of them excludes by
/// tag. The server-side alternative, `excludeItemIds`, is a comma-delimited
/// query string that grows with the *shared* set, which is the set that grows
/// with use: around 240 ids is roughly 8 KB, Kestrel's default request-line
/// limit, and a parent who has shared 300 titles would get a 414 rather than a
/// wrong answer.
///
/// **The visibility diff decorates and never filters.** Hide-shared may remove
/// tiles; the server's answer about what a child can see may only change how
/// one looks. Hiding a given-but-invisible film would hide the single case this
/// screen exists to explain.
class LibraryRepository {
  const LibraryRepository({
    required this._api,
    required this._adminUserId,
  });

  final JellyfinApi _api;
  final String _adminUserId;

  /// How many items to ask for when the answer is going to be filtered.
  ///
  /// Filtering client-side means a request for one screenful can come back
  /// almost empty, so ask for more than a screenful when hiding is on. This is
  /// a window size, not a page size — [fetch] keeps going until it has enough.
  static const pageSize = 24;
  static const filteringWindow = 96;

  /// How many times to refill before giving up and returning a short screen.
  ///
  /// A library where nearly everything is shared would otherwise walk the whole
  /// thing to fill one screen. A short screen with more still to come is a
  /// worse answer than a full one, and a much better answer than a stalled UI —
  /// and the caller can simply ask again.
  static const maxRefills = 5;

  /// At least one screenful, for [child] or for everyone when null.
  ///
  /// May return more than [pageSize] and deliberately does not trim: a window
  /// that survived filtering is already fetched and already classified, so
  /// discarding the surplus would only mean asking for it again.
  ///
  /// The grid itself is always built from the **administrator's** view, so
  /// selecting a child changes what tiles *mean*, never which exist. That is
  /// what makes "not given yet" answerable: an item the child cannot see is
  /// still on the grid to be given.
  Future<LibrarySlice> fetch({
    required int startIndex,
    JellyfinUser? child,
    bool hideShared = false,
  }) async {
    final label = _labelFor(child);
    final filtering = hideShared && label != null;

    final collected = <LibraryEntry>[];
    var cursor = startIndex;
    var total = 0;
    var hasMore = true;
    var refills = 0;

    while (hasMore && collected.length < pageSize && refills <= maxRefills) {
      final page = await _api.libraryPage(
        userId: _adminUserId,
        startIndex: cursor,
        limit: filtering ? filteringWindow : pageSize,
      );
      total = page.totalRecordCount;
      cursor = page.nextStartIndex;
      hasMore = page.hasMore;

      final entries = await _classify(page, child: child, label: label);
      collected.addAll(filtering ? entries.where((e) => !e.isShared) : entries);
      refills++;

      // Nothing came back at all — the server has run out, and looping again
      // would spin on an empty response rather than terminate.
      if (page.items.isEmpty) break;
    }

    return LibrarySlice(
      entries: collected,
      nextStartIndex: cursor,
      hasMore: hasMore,
      totalRecordCount: total,
    );
  }

  /// Attaches per-child meaning to a page.
  ///
  /// The one network call here is the visibility question, and it is only asked
  /// when it can change an answer: allow-mode children, where an item can be
  /// given and still not arrive. For a block-mode child the label *is* the
  /// answer — the tag takes it away — so there is nothing to ask.
  Future<List<LibraryEntry>> _classify(
    LibraryPage page, {
    required JellyfinUser? child,
    required String? label,
  }) async {
    if (child == null || label == null) {
      return page.items
          .map((item) =>
              LibraryEntry(item: item, state: LibraryItemState.unknown))
          .toList(growable: false);
    }

    final mode = child.policy.shortlistMode;

    if (mode == ShortlistMode.block) {
      return page.items
          .map((item) => LibraryEntry(
                item: item,
                state: item.hasLabel(label)
                    ? LibraryItemState.blocked
                    : LibraryItemState.available,
              ))
          .toList(growable: false);
    }

    if (mode != ShortlistMode.allow) {
      // `none` has no label to match, and `conflicting` has two opposite verbs
      // live at once — ground rule 3 refuses to pick one, so there is no
      // per-item answer either.
      return page.items
          .map((item) =>
              LibraryEntry(item: item, state: LibraryItemState.unknown))
          .toList(growable: false);
    }

    final labelled = page.items.where((i) => i.hasLabel(label)).toList();

    // Only the labelled ones can be in the surprising state, so only they need
    // asking about. An unlabelled item is not given, and why the server would
    // or would not show it is not a question this screen asks.
    var visible = <String>{};
    if (labelled.isNotEmpty) {
      try {
        visible = await _api.visibleIds(
          userId: child.id,
          ids: labelled.map((i) => i.id).toList(growable: false),
        );
      } on Object {
        // The grid is still useful without the overlay. Treating a failed
        // lookup as "hidden" would invent a problem; treating it as visible is
        // the same answer the screen gave before this feature existed.
        visible = labelled.map((i) => i.id).toSet();
      }
    }

    return page.items
        .map((item) => LibraryEntry(
              item: item,
              state: !item.hasLabel(label)
                  ? LibraryItemState.notGiven
                  : visible.contains(item.id)
                      ? LibraryItemState.given
                      : LibraryItemState.givenButHidden,
            ))
        .toList(growable: false);
  }

  /// The one label that defines this child's shortlist, or null when there is
  /// no single answer.
  ///
  /// Ground rule 3: a child with both lists populated has no correct verb, so
  /// they get no label here and every tile reads as unknown.
  static String? _labelFor(JellyfinUser? child) {
    if (child == null) return null;
    final tags = child.policy.shortlistTags;
    return tags.isEmpty ? null : tags.first;
  }
}
