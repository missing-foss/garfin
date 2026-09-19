// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/library_count.dart';
import '../models/library_filters.dart';
import '../models/library_item.dart';
import '../repositories/jellyfin_api.dart' show searchQueryParameters;
import '../repositories/library_repository.dart';
import '../providers/collection_providers.dart';
import '../providers/library_providers.dart';
import '../repositories/jellyfin_exception.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/assign_panel.dart';
import '../widgets/error_notice.dart';
import '../widgets/library_filter_bar.dart';
import '../widgets/library_grid.dart';
import 'collection_screen.dart';

/// Build order step 4. The grid, and the child selector above it.
///
/// The grid is always the **administrator's** view. Selecting a child changes
/// what each tile *means*, never which tiles exist — which is what makes "not
/// given yet" answerable at all: an item the child cannot see has to still be
/// on the grid to be given to them.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(libraryControllerProvider(session));
    final child = ref.watch(pickedChildProvider(session));

    // **Started here so that Apply does not have to wait for it.**
    //
    // The collection index is 1 + N calls — list the sets, then ask each one
    // what is in it — and the assign sheet has to wait for it before writing,
    // or a parent is never asked a cascade question they were owed. Built when
    // the *sheet* opened, that wait lands squarely between the parent tapping
    // Apply and anything happening: at 162 collections it is 42 round trips
    // four wide.
    //
    // Started when the library appears instead, it runs while the parent is
    // still browsing, and is long finished by the time they pick a film. The
    // value is deliberately unused — this is a warm-up, not a read, and the
    // sheet still reads it properly through `setsContainingProvider`.
    //
    // Every one of those calls is a `GET /Items`, so this adds database reads
    // and no filesystem work — see `docs/JELLYFIN-API.md` on what a *write*
    // can cost.
    ref.watch(collectionIndexProvider(session));

    return LayoutBuilder(
      builder: (context, constraints) => _layout(
        context,
        // Decided on the space this screen is handed, which beside a
        // navigation rail is not the window (#95).
        twoPane: constraints.maxWidth >= kTwoPaneBreakpoint,
        feed: feed,
        child: child,
        l10n: l10n,
        ref: ref,
      ),
    );
  }

  /// The grid, and — on a tablet — the write preview beside it.
  ///
  /// The panel spans the full height rather than sitting under the filter bar:
  /// the bar and the child picker belong to the grid, and a preview tucked
  /// inside them would read as another filter.
  Widget _layout(
    BuildContext context, {
    required bool twoPane,
    required AsyncValue<LibraryFeed> feed,
    required JellyfinUser? child,
    required AppLocalizations l10n,
    required WidgetRef ref,
  }) {
    // **A feed for the wrong child cannot be shown at all when the view is
    // narrowed by that child.**
    //
    // `classifiedFor` already stops the previous child's *labels* being read as
    // this one's, by substituting `unknown` below. That is enough while the
    // grid holds every item and only the badges are per-child. It is not enough
    // in `toGive` or `given`, where the entries themselves were selected by the
    // previous child's classification: the rows on screen are the wrong rows,
    // and no substitution reaches that. Reported as "the displayed media are
    // not the correct one despite the fact that the library seems to reload".
    //
    // So this narrows what `skipLoadingOnReload` is allowed to keep — it does
    // not undo it. The case #94 protected is a refresh, where the child has not
    // changed and the two ids agree; only a change of child reaches this.
    final narrowedByChild = ref.watch(libraryViewProvider) != LibraryView.all;
    // `.value`, not `asData`: while a reload is in flight the state is an
    // `AsyncLoading` *carrying* the previous data, and `asData` is null for it.
    // Reading through `asData` would make every same-child refresh look like a
    // wrong-child feed and blank the grid — undoing #94 rather than narrowing
    // it.
    final feedIsForThisChild = feed.value?.classifiedFor == child?.id;
    // **Only a stale *success* is withheld.** `!feed.hasError` is not
    // defensive: without it this swallows the error branch too, because a
    // failure disagrees with the current child in both the ways that matter —
    // a first load that fails has no value at all, and a load that fails after
    // a switch retains the previous child's. Either way the parent gets an
    // indeterminate spinner instead of a sentence and a *Try again*, and no
    // control left on screen changes the view: the button that leaves a
    // narrowed grid lives in the `data:` branch.
    //
    // A spinner is an honest answer to *loading*. It is not one for *failed*,
    // and that is the same mistake this guard exists to correct one layer up.
    final showing = narrowedByChild && !feedIsForThisChild && !feed.hasError
        ? const AsyncValue<LibraryFeed>.loading()
        : feed;

    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibraryFilterBar(session: session),
        Expanded(
          child: showing.when(
            // **Not the default, and the default is wrong here (#93 review).**
            // The grid refreshes by watching `libraryRevisionProvider`, and a
            // dependency change emits a plain `AsyncLoading` — `isReloading`,
            // which `when` does *not* skip unless told. `ref.invalidate` used
            // to emit `AsyncData(prev, isRefreshing)`, which it skips by
            // default, so the swap would have replaced the tiles a parent was
            // looking at with a spinner on every write, every pull-to-refresh
            // and every Undo. The first load still shows one: `isReloading`
            // requires a previous value.
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ErrorNotice(
                      message: jellyfinErrorText(
                        l10n,
                        error is JellyfinException
                            ? error
                            : const JellyfinException(JellyfinErrorKind.server),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => refreshLibrary(ref),
                      child: Text(l10n.libraryRetry),
                    ),
                  ],
                ),
              ),
            ),
            data: (data) =>
                _Grid(session: session, feed: data, child: child, twoPane: twoPane),
          ),
        ),
      ],
    );

    if (!twoPane) return grid;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: grid),
        const VerticalDivider(width: 1, thickness: 1),
        SizedBox(
          width: kAssignPanelWidth,
          child: AssignPanel(session: session),
        ),
      ],
    );
  }
}

/// The result line, from the two server counts and the child's mode.
///
/// [tagged] is null until the count arrives, and stays null if it failed. Both
/// mean the same thing here: there is no per-child number to state yet, so the
/// line falls back to the library's own count rather than to a guess or a
/// spinner.
/// [hiddenMembers] is how many films the grid is standing collections in for
/// (#144), and [exactCollapse] says whether subtracting them is sound: the
/// index knows membership, not which members a genre, decade, search or cap
/// would have kept. Ruled *"option 1, narrowed"* — subtract where it is exact,
/// and otherwise leave the server's own number, which may read higher than the
/// grid.
///
/// [searching] adds *sorted by relevance* (ruled, option A). The server orders
/// a `searchTerm` query by its own relevance and ignores `SortBy` — measured on
/// stock 10.11.11 and 12.1.0 — so the sort chosen in Settings does nothing
/// while one is active, and nothing else on this screen would say so.
///
/// **Only a title search sends `searchTerm`.** Cast & crew and studio send
/// exact-match `person=` / `studios=` filters, which have no text to rank
/// against and were not measured, so the line claims nothing for them.
String _resultLine(
  AppLocalizations l10n, {
  required LibraryFeed feed,
  required JellyfinUser? child,
  required int? tagged,
  int hiddenMembers = 0,
  bool exactCollapse = false,
  bool searching = false,
}) {
  final count = libraryCountFor(
    total: collapsedLibraryTotal(
      total: feed.totalRecordCount,
      hiddenMembers: hiddenMembers,
      exact: exactCollapse,
    ),
    tagged: tagged ?? 0,
    child: tagged == null ? null : child,
  );

  final line = switch (count.kind) {
    LibraryCountKind.everything => l10n.libraryItemCount(count.count),
    LibraryCountKind.notYetGiven =>
      l10n.libraryNotYetGiven(count.count, child!.name),
    LibraryCountKind.withheld => l10n.libraryWithheld(count.count, child!.name),
  };
  return searching ? l10n.libraryResultByRelevance(line) : line;
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.session,
    required this.feed,
    required this.child,
    required this.twoPane,
  });

  final AuthSession session;
  final LibraryFeed feed;
  final JellyfinUser? child;

  /// Whether the write preview has a panel to open into. Passed down rather
  /// than measured again here: one widget decides the layout, and a tap that
  /// disagreed with it would open a sheet on top of the panel.
  final bool twoPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(libraryViewProvider);

    // The columns, the age hint's rating ladder and the faces (#43, #84) moved
    // into `LibraryGrid` with #83, so that a collection's members are decorated
    // by the same code rather than by a second copy of it.

    // The result line's other half (#81). Null while it is in flight or if it
    // failed — the line then says what the *library* holds, which is true
    // either way, rather than holding a number back behind a spinner or
    // showing a wrong one. Same shape as #68's verified count: state what you
    // know, replace it when the server answers.
    final tagged = ref.watch(taggedItemCountProvider(session)).asData?.value;

    // **A collection stands in for its members** (#144, ruled: BoxSets only,
    // and only when no type filter is active — with one, the parent asked for
    // films *or* sets and the set standing in may not be on the grid).
    //
    // Done here rather than in the feed on purpose. The feed's fetches are the
    // grid's own paging, and making them wait on the collection index couples
    // two independent queries: measured, it also made the index's 1 + N
    // requests race the grid's pages, which broke twenty-one tests that had
    // never mentioned collections. The index is already watched by this
    // screen; this is the layer that has both.
    //
    // The page therefore arrives full and is drawn short. `hasMore` and
    // `loadMore` are untouched, so scrolling still pages on the server's
    // totals.
    // **The gate is "nothing narrows the grid", not "no type filter".** A set
    // can fail a filter its members pass: a search matches a film's title and
    // not the set's name, a genre or a decade is carried by the members and
    // not the container, and a picked child may be able to see a member while
    // the set is above their cap. In every one of those the set is not on the
    // grid to stand for anything, so hiding the member shows the parent
    // nothing at all for a title that exists — the failure #131 was opened to
    // fix, arriving from the other side.
    //
    // It is the same condition the count line needs to subtract soundly, and
    // for the same reason. One flag, used twice.
    final filters = ref.watch(libraryFiltersProvider);
    final collapsing = filters.isEmpty && child == null;
    final memberIds = collapsing
        ? (ref
                .watch(collectionIndexProvider(session))
                .asData
                ?.value
                .allMemberIds ??
            const <String>{})
        : const <String>{};
    final hiddenMembers = memberIds.length;
    // **A search finds a set through the film inside it** (#147, ruled: add the
    // set, and put it first).
    //
    // `searchTerm` matches substrings of an item's **own** title, so a set is
    // returned when its name shares the term — *Paddington* finds *Paddington
    // Collection* — and missed when it does not: *Bear Films* holding
    // *Paddington* is invisible to that query. This adds the missing ones from
    // the collection index, and `shown` keeps a set the server already
    // returned from appearing twice.
    //
    // Nothing the parent typed is removed: the film they searched for stays,
    // and the set is an extra way in, labelled so a row nobody asked for
    // explains itself.
    //
    // Only while a search is active. With no search the grid is collapsing
    // members into their sets instead, which is the opposite operation.
    final index = ref.watch(collectionIndexProvider(session)).asData?.value;
    final foundSets = <LibraryEntry>[];
    final notes = <String, String>{};
    if (filters.hasSearch && index != null) {
      final shown = {for (final entry in feed.entries) entry.item.id};
      for (final entry in feed.entries) {
        for (final set in index.setsContaining(entry.item.id)) {
          if (shown.add(set.collection.id)) {
            foundSets.add(LibraryEntry(
              item: set.collection,
              // Not classified for this child: the set was never in the
              // server's answer, so nothing here knows what it is to them.
              state: LibraryItemState.unknown,
            ));
            notes[set.collection.id] = l10n.librarySearchInCollection;
          }
        }
      }
    }

    final collapsed = memberIds.isEmpty
        ? feed.entries
        : [
            for (final entry in feed.entries)
              if (entry.item.isCollection || !memberIds.contains(entry.item.id))
                entry,
          ];

    if (feed.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            // "Nothing left to give" and "nothing here at all" are different
            // facts, and only one of them is a reason to check the server.
            // "Nothing left to give", "they cannot see anything yet" and
            // "nothing here at all" are three different facts, and only the
            // last is a reason to check the server.
            switch (view) {
              LibraryView.toGive
                  when child != null && feed.totalRecordCount > 0 =>
                l10n.libraryNothingLeft(child!.name),
              LibraryView.given when child != null =>
                l10n.libraryNothingGiven(child!.name),
              _ => l10n.libraryEmpty,
            },
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // Says what has *not been handed over*, never what the child
                  // can see. The second is the server's answer, tags and cap
                  // together, and claiming it here is what ground rule 4
                  // forbids.
                  //
                  // **Both numbers are the server's** (#81). This line used to
                  // read `feed.entries.length` — the page buffer — so it
                  // counted what had been scrolled into view and, with
                  // "Show shared" on, counted titles the child already had.
                  // It is now `total − tagged`, both from `/Items` under the
                  // same filters.
                  _resultLine(
                    l10n,
                    feed: feed,
                    child: child,
                    tagged: tagged,
                    hiddenMembers: hiddenMembers,
                    // The same flag that gates the collapse: subtracting is
                    // sound exactly when every member the index knows is a row
                    // the grid would otherwise have drawn.
                    exactCollapse: collapsing,
                    // Derived from what goes on the wire rather than from
                    // `hasSearch`, which is true in every scope: only the
                    // title scope sends `searchTerm`, the measured case.
                    searching: searchQueryParameters(filters)
                        .containsKey('searchTerm'),
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              // The way out of a narrowed grid, and in [LibraryView.given]
              // that is its whole job: a face tap lands here, and the giving
              // workflow lives in the view this returns to.
              // **`Flexible`, and it is not decoration** — the same lesson
              // this file already learned on the kid card's heading row. The
              // third label is longer than the two it joined ("Show what's
              // left to give" against "Show shared"), and at 360dp it
              // overflowed the row by 34px, which a widget test caught as a
              // rendering assertion rather than as a wrong pixel.
              if (child != null)
                Flexible(
                  child: TextButton(
                    onPressed: () => ref
                        .read(libraryViewProvider.notifier)
                        .set(switch (view) {
                          LibraryView.given => LibraryView.toGive,
                          LibraryView.toGive => LibraryView.all,
                          LibraryView.all => LibraryView.toGive,
                        }),
                    child: Text(
                      switch (view) {
                        LibraryView.given => l10n.libraryShowToGive,
                        LibraryView.toGive => l10n.libraryShowShared,
                        LibraryView.all => l10n.libraryHideShared,
                      },
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => refreshLibrary(ref),
            child: NotificationListener<ScrollNotification>(
              // Paging by scroll position rather than by a sentinel widget:
              // the last tile of a 3-wide grid can be built long before it is
              // anywhere near the viewport, and asking then would fetch pages
              // nobody has scrolled to.
              onNotification: (notification) {
                final metrics = notification.metrics;
                if (metrics.axis != Axis.vertical) return false;
                if (metrics.pixels >= metrics.maxScrollExtent - 600) {
                  ref
                      .read(libraryControllerProvider(session).notifier)
                      .loadMore();
                }
                return false;
              },
              child: LibraryGrid(
                session: session,
                child: child,
                // A collection is a place, not an action (#83): tapping one
                // opens it. Every other tile still opens the write preview,
                // and nothing is written until Apply — ground rule 1.
                onTap: (item) => openFor(
                  context,
                  ref,
                  session: session,
                  item: item,
                  twoPane: twoPane,
                ),
                // **Says nothing about a child until the tiles are that
                // child's** (#96). While a new selection's query is in flight
                // the previous child's feed is still on screen — #94 keeps it
                // there rather than blanking the grid, which is right — and
                // every per-child marker on it was computed for somebody else.
                // Measured before the fix: a tile said "Leo has this, but the
                // server isn't showing it to them" about a title he had never
                // been given.
                //
                // **Only what the feed decided.** The state badge and the
                // held-back sentence come from `_classify`, which ran for the
                // previous child, so they wait. The age hint does not: it is
                // computed from the current child's age and the item's own
                // rating, so it is already about the child on screen —
                // suppressing it would remove a true statement and make the
                // hint flicker. The avatar row (#84) is untouched for the same
                // reason: it says who *has* the title, which is not relative to
                // the selection at all. Both live in `LibraryGrid`, which is
                // why this substitutes the *entry* and leaves the rest alone.
                notes: notes,
                entries: feed.classifiedFor == child?.id
                    ? [...foundSets, ...collapsed]
                    : [
                        ...foundSets,
                        for (final entry in collapsed)
                          LibraryEntry(
                            item: entry.item,
                            state: LibraryItemState.unknown,
                          ),
                      ],
              ),
            ),
          ),
        ),
        // The tail: a spinner while the next page is on its way, or a retry if
        // it failed. The tiles already fetched stay on screen either way —
        // throwing the grid away because page four did not arrive would be a
        // worse answer than a slow one.
        if (feed.loadingMore)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (feed.moreFailed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(
              child: TextButton(
                onPressed: () => ref
                    .read(libraryControllerProvider(session).notifier)
                    .loadMore(),
                child: Text(l10n.libraryRetry),
              ),
            ),
          ),
      ],
    );
  }
}
