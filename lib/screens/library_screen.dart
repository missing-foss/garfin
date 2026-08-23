// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/library_count.dart';
import '../models/library_item.dart';
import '../repositories/library_repository.dart';
import '../providers/library_providers.dart';
import '../repositories/jellyfin_exception.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/assign_panel.dart';
import '../widgets/error_notice.dart';
import '../widgets/library_filter_bar.dart';
import '../widgets/library_grid.dart';
import '../widgets/picking_for_row.dart';
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
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickingForRow(session: session),
        LibraryFilterBar(session: session),
        Expanded(
          child: feed.when(
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
String _resultLine(
  AppLocalizations l10n, {
  required LibraryFeed feed,
  required JellyfinUser? child,
  required int? tagged,
}) {
  final count = libraryCountFor(
    total: feed.totalRecordCount,
    tagged: tagged ?? 0,
    child: tagged == null ? null : child,
  );

  return switch (count.kind) {
    LibraryCountKind.everything => l10n.libraryItemCount(count.count),
    LibraryCountKind.notYetGiven =>
      l10n.libraryNotYetGiven(count.count, child!.name),
    LibraryCountKind.withheld => l10n.libraryWithheld(count.count, child!.name),
  };
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
    final hideShared = ref.watch(hideSharedProvider);

    // The columns, the age hint's rating ladder and the faces (#43, #84) moved
    // into `LibraryGrid` with #83, so that a collection's members are decorated
    // by the same code rather than by a second copy of it.

    // The result line's other half (#81). Null while it is in flight or if it
    // failed — the line then says what the *library* holds, which is true
    // either way, rather than holding a number back behind a spinner or
    // showing a wrong one. Same shape as #68's verified count: state what you
    // know, replace it when the server answers.
    final tagged = ref.watch(taggedItemCountProvider(session)).asData?.value;

    if (feed.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            // "Nothing left to give" and "nothing here at all" are different
            // facts, and only one of them is a reason to check the server.
            hideShared && child != null && feed.totalRecordCount > 0
                ? l10n.libraryNothingLeft(child!.name)
                : l10n.libraryEmpty,
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
                  _resultLine(l10n, feed: feed, child: child, tagged: tagged),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (child != null)
                TextButton(
                  onPressed: () =>
                      ref.read(hideSharedProvider.notifier).toggle(),
                  child: Text(
                    hideShared
                        ? l10n.libraryShowShared
                        : l10n.libraryHideShared,
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
                entries: feed.classifiedFor == child?.id
                    ? feed.entries
                    : [
                        for (final entry in feed.entries)
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
