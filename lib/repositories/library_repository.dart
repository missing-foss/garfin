// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/jellyfin_user.dart';
import '../models/library_filters.dart';
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

/// A page of the grid, plus where to resume.
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

  /// One page of the grid.
  ///
  /// **240, not a screenful.** Measured on a 412dp phone at the regular poster
  /// size: `maxCrossAxisExtent: 175` gives three columns and about three rows
  /// on screen, so nine tiles are visible and 240 is roughly **27 screens** of
  /// scrolling between fetches. At 24 it was under three, so the grid asked the
  /// server for more rows every couple of flicks.
  ///
  /// The cost of asking for ten times as many is not ten times: measured on
  /// 10.11.11 against 1500 films, `Limit=24` answers in 26 ms and `Limit=240`
  /// in 34 ms, because the per-request constant dominates at 24. See
  /// `docs/JELLYFIN-API.md` § *how large a `Limit` costs what*.
  ///
  /// It also crosses a threshold that has nothing to do with the server: `dio`
  /// decodes a response body **off the main isolate only above 50 KB**
  /// (`FusedTransformer(contentLengthIsolateThreshold: 50 * 1024)`). A 24-row
  /// page is 11.9 KB and is decoded on the UI thread; a 240-row page is 118.9
  /// KB and is not. So the bigger page moves work off the thread that draws.
  static const pageSize = 240;

  /// How many items to ask for when the answer is going to be filtered.
  ///
  /// Filtering client-side means a request can come back with fewer rows than
  /// it returned, so [fetch] keeps going until it has enough — this is a window
  /// size, not a page size.
  ///
  /// **Equal to [pageSize] now, where it used to be four times it.** That
  /// multiple bought a single round trip when a quarter of the rows survived,
  /// and it was the right trade against a 24-row page: one extra request was
  /// expensive, 96 rows were cheap. At 240 the trade inverts. Most of a
  /// library is *not* given to any one child, so survival is usually high, and
  /// asking for 960 to keep 240 would over-fetch by four on the common path to
  /// save one refill on the rare one. The refill loop already handles the rare
  /// one, and the budget below is sized so it can.
  static const filteringWindow = pageSize;

  /// How many requests one call may make before giving up and returning a
  /// short screen: one initial page plus five refills.
  ///
  /// **This is the budget for one page.** A call asking for a restored
  /// window gets more, in proportion — see [fetch]'s `want`. Holding it at six
  /// for a window of ten pages would return a third of it and report success,
  /// which is the failure mode a partial fix has: it looks like the bug, only
  /// less often.
  ///
  /// A library where nearly everything is shared would otherwise walk the whole
  /// thing to fill one screen. A short screen with more still to come is a
  /// worse answer than a full one, and a much better answer than a stalled UI —
  /// and the caller can simply ask again.
  ///
  /// Counted as *fetches* rather than refills because the counter increments
  /// after every request including the first. Naming it for refills while
  /// counting fetches is what made the old `<=` guard read as an off-by-one.
  static const maxFetches = 6;

  /// At least one page, for [child] or for everyone when null.
  ///
  /// May return more than [pageSize] and deliberately does not trim: a window
  /// that survived filtering is already fetched and already classified, so
  /// discarding the surplus would only mean asking for it again.
  ///
  /// The grid itself is always built from the **administrator's** view, so
  /// selecting a child changes what tiles *mean*, never which exist. That is
  /// what makes "not given yet" answerable: an item the child cannot see is
  /// still on the grid to be given.
  ///
  /// **[view] narrows what is kept, and never what is asked for.** All three
  /// views run the same query as the administrator and differ only in which
  /// classified entries survive — so [LibraryView.given] is a lens on that one
  /// view rather than a second one, and switching back costs nothing and loses
  /// nothing. Re-querying as the child would have produced the same list while
  /// quietly deleting the administrator's, which is what every "not given yet"
  /// number is computed against.
  /// [want] is how many entries to come back with, and defaults to one
  /// page. The grid asks for more only to **restore a window it already
  /// had** — a refresh after a write rebuilds this provider, and rebuilding it
  /// at one page throws away every page the parent scrolled to.
  Future<LibrarySlice> fetch({
    required int startIndex,
    int want = pageSize,
    JellyfinUser? child,
    // Defaulted to [LibraryView.all] because that is what `hideShared: false`
    // meant, and a default that narrows is a default that hides items from
    // every caller who did not think about it.
    LibraryView view = LibraryView.all,
    LibraryFilters filters = const LibraryFilters(),
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
  }) async {
    final labels = _labelsFor(child);
    // Both narrowing views need a label to narrow by; with none, every item
    // classifies the same way and the window would page through the whole
    // library to collect either everything or nothing.
    final filtering = view != LibraryView.all && labels.isNotEmpty;

    final collected = <LibraryEntry>[];
    var cursor = startIndex;
    var total = 0;
    var hasMore = true;
    var fetches = 0;

    // One request's worth, and a budget of one extra request per page of
    // window asked for. Dividing by [pageSize] rather than by the request size
    // is deliberate: it bounds the call in pages of *result*, which is what a
    // caller asked for, and stays right whether or not the server honours a
    // large limit in one go.
    final perRequest = filtering ? filteringWindow : want;
    final budget = maxFetches + (want ~/ pageSize);

    while (hasMore && collected.length < want && fetches < budget) {
      final page = await _api.libraryPage(
        userId: _adminUserId,
        startIndex: cursor,
        sortBy: sortBy,
        sortOrder: sortOrder,
        // **A restore is one request when nothing is being filtered out.**
        //
        // Measured on 10.11.11 against 1500 films, with a control alongside:
        // `Limit=1500` answers in about 77 ms and `Limit=5000` returns
        // everything that exists rather than erroring, so there is no ceiling
        // to discover by being refused one. The same 1440 rows cost ~88 ms in
        // one call and ~1553 ms as sixty calls of 24 down a kept-alive
        // connection — well over ten times, of which 23 ms is per-request
        // constant, so the gap is the server's work rather than the bench's.
        //
        // Whole milliseconds and "well over ten times" on purpose: four sweeps
        // of the same fixture moved these by several ms and the ratio between
        // fifteen and eighteen. `docs/JELLYFIN-API.md` § *how large a `Limit`
        // costs what* carries one run in full, and is the copy to update — a
        // number kept in two places drifts, which is how this comment spent a
        // push disagreeing with that section.
        //
        // Server-side only. Nothing here measures what parsing 743 KB and
        // classifying 1500 entries costs on a phone.
        //
        // The filtering case keeps its window: entries are dropped after they
        // arrive, so the refills are what make the count come out right, and
        // asking for `want` there would still need them.
        limit: perRequest,
        filters: filters,
        // The cap is the child's own, straight out of their policy. Asking the
        // server to apply it is not a visibility computation — it is a filter
        // over the administrator's view, and the copy says so.
        maxParentalRating: child?.policy.maxParentalRating,
      );
      total = page.totalRecordCount;
      cursor = page.nextStartIndex;
      hasMore = page.hasMore;

      // **A collection with nothing in it is dropped before anything else.**
      // There is nothing in it to give or withhold, its assign sheet would have
      // no members to write to, and the share ring is already suppressed for
      // it — so the tile could only ever be a row a parent cannot act on.
      //
      // It also saves a request rather than only a row: the grid asks for one
      // membership per *visible* collection tile, and an empty set's answer can
      // only ever be "nothing". A row that is never drawn never asks.
      //
      // Measured on 10.11.11: an empty `BoxSet` reports `ChildCount: 0`, the
      // field present rather than omitted, and `/Items` has no server-side way
      // to exclude them — 86 query parameters and none about child counts.
      // `null` therefore means *the server did not say*, which is not the same
      // as empty and is kept.
      //
      // **The window is not widened for this, and the loop above is why.** A
      // dropped row can leave a page short in any view, including `all`; the
      // `collected.length < want` condition simply fetches again, and the
      // retry costs a round trip only when an empty set actually appears,
      // which is rare.
      //
      // This used to add that widening to [filteringWindow] everywhere would
      // make every parent pay a page four times the size. That price is gone:
      // the window is now the same number as the page, so widening would cost
      // nothing. The reason stands on the loop alone.
      final worthDrawing = page.items
          .where((item) => !item.isCollection || item.childCount != 0)
          .toList(growable: false);

      final entries =
          await _classify(worthDrawing, child: child, labels: labels);
      collected.addAll(switch (filtering ? view : LibraryView.all) {
        LibraryView.toGive => entries.where((e) => !e.isShared),
        LibraryView.given => entries.where((e) => e.isShared),
        LibraryView.all => entries,
      });
      fetches++;

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

  /// Attaches per-child meaning to items the caller already has.
  ///
  /// Takes a plain list rather than a [LibraryPage] because the grid is no
  /// longer the only caller: a collection's members arrive from
  /// `GET /Items?parentId=`, with the same `Fields=Tags` this needs, and a set
  /// browsed on its own screen has to mean the same thing there as it does on
  /// the grid. See [classifyItems].
  ///
  /// The one network call here is the visibility question, and it is only asked
  /// when it can change an answer: allow-mode children, where an item can be
  /// given and still not arrive. For a block-mode child the label *is* the
  /// answer — the tag takes it away — so there is nothing to ask.
  Future<List<LibraryEntry>> _classify(
    List<LibraryItem> items, {
    required JellyfinUser? child,
    required List<String> labels,
  }) async {
    if (child == null || labels.isEmpty) {
      return items
          .map((item) =>
              LibraryEntry(item: item, state: LibraryItemState.unknown))
          .toList(growable: false);
    }

    final mode = child.policy.shortlistMode;

    if (mode == ShortlistMode.block) {
      return items
          .map((item) => LibraryEntry(
                item: item,
                state: item.hasAnyLabel(labels)
                    ? LibraryItemState.blocked
                    : LibraryItemState.available,
              ))
          .toList(growable: false);
    }

    if (mode != ShortlistMode.allow) {
      // `none` has no label to match, and `conflicting` has two opposite verbs
      // live at once — ground rule 3 refuses to pick one, so there is no
      // per-item answer either.
      return items
          .map((item) =>
              LibraryEntry(item: item, state: LibraryItemState.unknown))
          .toList(growable: false);
    }

    final labelled = items.where((i) => i.hasAnyLabel(labels)).toList();

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

    return items
        .map((item) => LibraryEntry(
              item: item,
              state: !item.hasAnyLabel(labels)
                  ? LibraryItemState.notGiven
                  : visible.contains(item.id)
                      ? LibraryItemState.given
                      : LibraryItemState.givenButHidden,
            ))
        .toList(growable: false);
  }

  /// The same per-child meaning, for items fetched somewhere other than the
  /// grid — today, one collection's members (#83).
  ///
  /// Exists so a member tile inside a set says exactly what the same title says
  /// on the grid. Duplicating the allow/block inversion here instead would be
  /// ground rule 3 implemented twice, and the second copy is the one that drifts.
  ///
  /// The labels are the child's own, read the same way the grid reads them, so
  /// a caller cannot pass the wrong shortlist by accident.
  Future<List<LibraryEntry>> classifyItems(
    List<LibraryItem> items, {
    required JellyfinUser? child,
  }) =>
      _classify(items, child: child, labels: _labelsFor(child));

  /// Every label defining this child's shortlist.
  ///
  /// All of them, because the server matches any: a child holding
  /// `["kids-emma", "family-films"]` can see an item tagged either. Reading
  /// only the first would report "not given yet" for something they already
  /// watch — a wrong answer on the screen whose whole job is that answer.
  ///
  /// Empty for a child with both lists populated: ground rule 3 refuses to pick
  /// a verb, so every tile reads as unknown.
  static List<String> _labelsFor(JellyfinUser? child) =>
      child == null ? const [] : child.policy.shortlistTags;
}
