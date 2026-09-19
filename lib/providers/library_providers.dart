// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/country_lookup.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/library_filters.dart';
import '../models/library_item.dart';
import '../models/kid_summary.dart';
import '../models/parental_rating.dart';
import '../repositories/jellyfin_api.dart';
import '../repositories/app_settings_store.dart';
import '../repositories/library_repository.dart';
import 'app_providers.dart';
import 'kids_providers.dart';
import 'settings_providers.dart';

/// Which child the parent is picking for, as an **id**, or null for Everyone.
///
/// Held here rather than in the screen so the assign sheet (step 5) inherits
/// it: `docs/UI-SPEC.md` says the selection "carries into the assign sheet",
/// and a selection owned by a widget would not survive the sheet being opened.
///
/// An id rather than the user, because the starting value comes from Settings
/// and a stored name would be the wrong key: names repeat on a Jellyfin server
/// and can be changed without the account changing. [pickedChildProvider]
/// resolves it against the accounts that actually exist, which is also what
/// makes a stored id for a deleted account degrade to Everyone rather than to
/// an error.
class PickingFor extends Notifier<String?> {
  @override
  /// **Everyone.** There is no stored starting child any more: arriving at the
  /// Library from the navigation means "the library", and arriving from a
  /// child's face sets the selection on the way in. A remembered default would
  /// answer a question the parent did not ask on every visit but the first.
  String? build() => null;

  /// The choice for this session, and only for this session.
  ///
  /// Nothing is written back, because there is nowhere to write it: the stored
  /// *starting child* is gone. This comment used to justify the absence by
  /// that setting — "a picker that quietly rewrote the default would make
  /// 'start on Emma' impossible to keep" — which outlived the thing it was
  /// about by one commit.
  ///
  /// The reason now is the one that replaced it: the Library opens on Everyone
  /// from the navigation and on a child from that child's face, so what the
  /// parent picked last time is not an input to either.
  void select(String? userId) => state = userId;
}

final pickingForProvider =
    NotifierProvider<PickingFor, String?>(PickingFor.new);

/// The selected child, once the accounts are known.
///
/// Null for Everyone, and also null while the accounts are still loading or if
/// the stored id names an account that is gone — the grid then shows every
/// tile as unknown, which is exactly what Everyone means and is the safe answer
/// to render before the policies have arrived.
final pickedChildProvider =
    Provider.family<JellyfinUser?, AuthSession>((ref, session) {
  final id = ref.watch(pickingForProvider);
  if (id == null) return null;
  final overview = ref.watch(kidsOverviewProvider(session)).asData?.value;
  for (final kid in overview?.shortlisted ?? const <KidSummary>[]) {
    if (kid.user.id == id) return kid.user;
  }
  return null;
});

/// Which slice of the grid is on screen.
///
/// Starts from Settings — `docs/DECISIONS.md` § Product shape: hiding what a
/// child already has turns the grid into a to-do list rather than an
/// inventory, which is why the stored default is on — and the Library's own
/// button moves it for this session only.
///
/// [LibraryView.given] is not reachable from that button. It is where a tap on
/// a child's face lands, and the button's job there is to get back out to the
/// grid the giving workflow needs.
class LibraryViewState extends Notifier<LibraryView> {
  @override
  LibraryView build() => ref.watch(settingsProvider).hideShared
      ? LibraryView.toGive
      : LibraryView.all;

  void set(LibraryView value) => state = value;

  /// The button's own move: out of whichever narrowing view is on, and back.
  void toggle() => state =
      state == LibraryView.all ? LibraryView.toGive : LibraryView.all;
}

final libraryViewProvider =
    NotifierProvider<LibraryViewState, LibraryView>(LibraryViewState.new);

/// The title the two-pane library is previewing beside the grid (#95).
///
/// Null is the panel's placeholder — nothing picked yet. Only ever set at
/// tablet widths: below `kTwoPaneBreakpoint` the same tap opens the modal
/// sheet, and the two surfaces must never both be live, or one write preview
/// would be applied from behind another.
///
/// The item rather than its id, because the panel needs the name and the type
/// to say what a write will touch before any request has been made — and
/// because a stale id would render an empty preview rather than nothing at all.
class AssignPanelSelection extends Notifier<AssignPanelTarget?> {
  @override
  AssignPanelTarget? build() => null;

  /// [from] is the set the parent was looking at when they picked [item], and
  /// null everywhere else. It is not "the sets this film belongs to" — a film
  /// can be in several and this is the one in front of them, which is the only
  /// one the write is allowed to touch.
  void select(LibraryItem item, {LibraryItem? from}) =>
      state = AssignPanelTarget(item: item, from: from);

  /// After a write, when the panel is dismissed, and when a collection is
  /// opened — the pending toggles go with it, which is safe because ground rule
  /// 1 means nothing pending has been written.
  void clear() => state = null;
}

final assignPanelProvider =
    NotifierProvider<AssignPanelSelection, AssignPanelTarget?>(
  AssignPanelSelection.new,
);

/// What the two-pane panel is showing, and where it was opened from.
class AssignPanelTarget {
  const AssignPanelTarget({required this.item, this.from});

  final LibraryItem item;

  /// The collection the parent was browsing, or null from the library grid.
  final LibraryItem? from;
}

/// The server's rating ladder, for the age hint (#43).
///
/// Separate from the Kids screen's copy on purpose: a failure here must cost
/// the hint and nothing else. An empty ladder answers "not known" for every
/// rating, which is the honest degradation — see `suitabilityFor`.
final parentalRatingLadderProvider =
    FutureProvider.family<ParentalRatingLadder, AuthSession>((ref, session) async {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  try {
    return await api.parentalRatings();
  } on Object {
    return const ParentalRatingLadder.empty();
  }
});

/// The server's country list, read once per session.
///
/// Two uses on the item sheet: telling a certification prefix on an
/// `OfficialRating` from an ordinary hyphenated rung — see
/// `ratingCountryCode` — and turning country names into flags. Empty on
/// failure, which answers *no country named* for every rating and *no flag*
/// for every country. That is the honest degradation: the rating shows alone
/// and each country shows as its name, rather than a guess at either.
final countriesProvider =
    FutureProvider.family<CountryLookup, AuthSession>((ref, session) async {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  try {
    return await api.countries();
  } on Object {
    return const CountryLookup.empty();
  }
});

/// The API client the grid's vocabulary queries use.
///
/// Separate from the repository because these are not the grid's data — they
/// are the filter bar's menus, and a failure in one must not empty the other.
final libraryApiProvider =
    Provider.family<JellyfinApi, AuthSession>((ref, session) {
  return ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
});

final libraryRepositoryProvider =
    Provider.family<LibraryRepository, AuthSession>((ref, session) {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  return LibraryRepository(api: api, adminUserId: session.userId);
});

/// One signal that refreshes the Library, and the only one (#93).
///
/// The grid's page and the tagged count are two queries feeding **one
/// sentence** — "N things Emma hasn't got yet" is `total − tagged` — and they
/// were refreshed separately. Every post-write path invalidated the grid and
/// not the count, so a parent gave a child a title, watched the tile vanish,
/// and watched the number beside it stand still. The count is a `FutureProvider`
/// and so not auto-disposed: it stayed wrong until the app restarted, and no
/// gesture in the app could fix it.
///
/// Both halves watch this instead. Bumping it re-runs them **together**, which
/// is the fix for a second gap the per-site version would have left: the two
/// counts were independently timed, so the line could subtract a number taken
/// at one moment from a total taken at another. `LibraryCount` is careful that
/// both counts carry the same filters; the same argument applies to the moment.
///
/// **Nothing invalidates those two providers directly any more.** Naming them
/// at a call site is how the seventh site forgets one, and the symptom is a
/// quietly wrong number rather than an error —
/// `test/library_refresh_test.dart` reads the source and fails if a call site
/// starts naming them again.
class LibraryRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// Refetch the grid and the count, as one unit.
  void bump() => state = state + 1;
}

final libraryRevisionProvider =
    NotifierProvider<LibraryRevision, int>(LibraryRevision.new);

/// Refresh the Library: the grid and the count that describes it, together.
///
/// The one call every screen makes — after a write, on pull-to-refresh, on
/// *Try again*, and when a setting changes what the grid should show.
void refreshLibrary(WidgetRef ref) =>
    ref.read(libraryRevisionProvider.notifier).bump();

/// How many items carry the selected child's labels, under the active filters.
///
/// The other half of the result line's arithmetic (#81); the grid's own
/// `TotalRecordCount` is the first half and is already in hand, so this is one
/// `Limit=0` query and not a second page fetch.
///
/// **Filters are threaded on purpose.** The number is subtracted from a total
/// the server computed under those filters, and a subtraction across two
/// populations answers with something that looks perfectly reasonable. The
/// rating cap rides along only when the cap chip is on, matching what
/// `libraryPage` does with it.
///
/// Zero for a child with no labels to match — [UserPolicy.shortlistTags] is
/// empty for a conflicting account, and asking `tags=` for nothing would count
/// the whole library.
final taggedItemCountProvider =
    FutureProvider.family<int, AuthSession>((ref, session) async {
  // Refetched with the grid, never on its own — see [libraryRevisionProvider].
  ref.watch(libraryRevisionProvider);

  final child = ref.watch(pickedChildProvider(session));
  final labels = child?.policy.shortlistTags ?? const <String>[];
  if (labels.isEmpty) return 0;

  return ref.watch(libraryApiProvider(session)).taggedItemCount(
        userId: session.userId,
        tags: labels,
        // The same object the grid query uses. This total is subtracted from
        // that query's, so the two must be asking about one population (#81)
        // -- including the branch below, which both sites take together.
        filters: await _filtersForQuery(ref, session),
        maxParentalRating: child!.policy.maxParentalRating,
      );
});

/// The filters with the exact name `person=` / `studios=` need filled in.
///
/// **`libraryFiltersProvider` holds what the parent asked for; this holds what
/// the server can be asked.** Those differ in two of the three scopes, because
/// `person=` and `studios=` are exact-match and a parent types a substring.
/// Splitting them keeps the notifier synchronous and free of the session, and
/// keeps the resolve in one place rather than at each of the three call sites
/// that reach the server.
///
/// **`resolvedSearchValue` and `LibraryFilters.isImpossible` mean something
/// only on the object this yields.** On the raw filters the value is always
/// null, so `isImpossible` there would read true for every unresolved
/// cast-or-studio search — which is why nothing reads it from the notifier.
///
/// A failed resolve yields filters whose search cannot match, and the API layer
/// answers empty without asking. It does **not** fall back to an unfiltered
/// query, which would return the whole library for a name nobody is credited
/// under.
final resolvedLibraryFiltersProvider =
    FutureProvider.family<LibraryFilters, AuthSession>((ref, session) async {
  final filters = ref.watch(libraryFiltersProvider);
  if (filters.searchScope == SearchScope.title || !filters.hasSearch) {
    return filters;
  }
  try {
    final name = await ref.watch(libraryApiProvider(session)).resolveSearchName(
          userId: session.userId,
          term: filters.searchTerm!,
          scope: filters.searchScope,
        );
    return filters.copyWith(resolvedSearchValue: name);
  } on Object {
    // A resolve that failed is not a resolve that found nothing, but the grid
    // shows the same empty result either way and there is nothing a parent can
    // do differently. Failing to empty rather than to the whole library is the
    // safe direction: the other one silently answers a question nobody asked.
    return filters.copyWith(resolvedSearchValue: null);
  }
});

/// The filters to send, resolved only when a resolve is actually needed.
///
/// **The branch matters and is here so both query sites take the same one.**
/// Awaiting the resolver unconditionally adds an async hop to every grid load,
/// including the overwhelmingly common case of no search at all — which
/// reorders the screen's requests against each other. That is not theoretical:
/// doing it unconditionally turned three `library_count_test` cases red,
/// because the grid and the tagged count swapped places in the sequence.
///
/// So a title search, or no search, returns synchronously and the screen
/// behaves exactly as it did before this feature existed.
Future<LibraryFilters> _filtersForQuery(Ref ref, AuthSession session) {
  final filters = ref.watch(libraryFiltersProvider);
  if (!filters.needsResolve) return Future.value(filters);
  return ref.watch(resolvedLibraryFiltersProvider(session).future);
}

/// What the filter bar is asking for. Reset by the bar's own Reset.
class LibraryFilterState extends Notifier<LibraryFilters> {
  @override
  LibraryFilters build() => const LibraryFilters();

  void set(LibraryFilters value) => state = value;

  /// The text search (#73), normalised on the way in.
  ///
  /// Whitespace-only becomes null rather than being stored: the server treats
  /// `searchTerm=%20` as no filter at all (measured), so keeping it would leave
  /// a "1 filter" badge over an unfiltered grid, and `isEmpty` — which the tune
  /// button's highlight reads — would disagree with what the parent sees.
  ///
  /// **Idempotent on purpose.** A debounce can fire with the same text the
  /// filter already holds; re-setting identical state would invalidate the
  /// library controller and re-fetch the page for nothing.
  void setSearch(String value) {
    final trimmed = value.trim();
    final next = trimmed.isEmpty ? null : trimmed;
    if (next == state.searchTerm) return;
    state = state.copyWith(searchTerm: next);
  }

  /// Which field the typed term is matched against.
  ///
  /// The text is kept. Switching scope with something already typed is the
  /// whole point of the control — a parent who typed a name into Title and got
  /// nothing should be one tap from asking the right question, not retyping it.
  ///
  /// Idempotent for the same reason [setSearch] is: re-setting identical state
  /// invalidates the library controller and re-fetches a page for nothing.
  void setScope(SearchScope value) {
    if (value == state.searchScope) return;
    state = state.copyWith(searchScope: value);
  }

  void reset() => state = const LibraryFilters();
}

final libraryFiltersProvider =
    NotifierProvider<LibraryFilterState, LibraryFilters>(
        LibraryFilterState.new);

/// The genres this library actually has, for the chip's menu.
///
/// Empty on failure **and** when the server's genre index has nothing in it —
/// measured, those are indistinguishable from here — so the chip hides rather
/// than offering an empty menu or claiming the library has no genres.
final libraryGenresProvider =
    FutureProvider.family<List<String>, AuthSession>((ref, session) async {
  try {
    return await ref.watch(libraryApiProvider(session)).genres(
          userId: session.userId,
        );
  } on Object {
    return const [];
  }
});

/// The decades present, newest first, derived from the years the server lists.
final libraryDecadesProvider =
    FutureProvider.family<List<int>, AuthSession>((ref, session) async {
  try {
    final years = await ref.watch(libraryApiProvider(session)).years(
          userId: session.userId,
        );
    final decades = {for (final year in years) (year ~/ 10) * 10}.toList()
      ..sort((a, b) => b.compareTo(a));
    return decades;
  } on Object {
    return const [];
  }
});

/// One page in, and everything gathered so far.
class LibraryFeed {
  const LibraryFeed({
    required this.entries,
    required this.nextStartIndex,
    required this.hasMore,
    required this.totalRecordCount,
    this.classifiedFor,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  /// **The child every [LibraryEntry.state] in here was computed against**, or
  /// null for Everyone (#96).
  ///
  /// A feed is only meaningful for one child, and until this field existed
  /// nothing said so — the invariant held by accident, because switching child
  /// blanked the grid to a spinner and there was never a stale feed on screen
  /// to misread. #94 stopped the blanking, correctly, and the accident stopped
  /// with it: for as long as the new query is in flight the previous child's
  /// tiles are on screen while every label around them has already changed.
  ///
  /// Measured, one frame after selecting Léo with Emma's feed still current:
  ///
  ///     Paddington. Leo has this, but the server isn't showing it to them.
  ///
  /// He had never been given it. The screen compares this against the current
  /// selection and says nothing per-child until they agree.
  final String? classifiedFor;

  final List<LibraryEntry> entries;
  final int nextStartIndex;
  final bool hasMore;
  final int totalRecordCount;

  /// A page is on its way. The grid keeps what it has and shows a spinner
  /// under it rather than replacing the screen — losing the tiles a parent was
  /// looking at is a worse answer than a slow one.
  final bool loadingMore;

  /// The *next* page failed. What is already on screen is still good, so this
  /// offers a retry instead of throwing the screen away.
  final bool moreFailed;

  LibraryFeed copyWith({
    List<LibraryEntry>? entries,
    int? nextStartIndex,
    bool? hasMore,
    bool? loadingMore,
    bool? moreFailed,
  }) =>
      LibraryFeed(
        entries: entries ?? this.entries,
        nextStartIndex: nextStartIndex ?? this.nextStartIndex,
        hasMore: hasMore ?? this.hasMore,
        totalRecordCount: totalRecordCount,
        // Never rewritten by a copy: the entries carry a classification, and
        // whose it is is a property of them rather than of this call.
        classifiedFor: classifiedFor,
        loadingMore: loadingMore ?? this.loadingMore,
        moreFailed: moreFailed ?? this.moreFailed,
      );
}

/// The grid's pages.
///
/// `build` re-runs whenever the child, the hide-shared toggle or a filter
/// changes, which is what resets paging on a filter change — there is no
/// separate "clear" to forget to call.
///
/// **A refresh is not a filter change, and used to be treated as one.** The
/// same `build` also re-runs when [libraryRevisionProvider] is bumped, which is
/// what the assign sheet does after a write. Rebuilding at one page then threw
/// away every page the parent had scrolled to — not the scroll offset, the
/// *entries* — so applying a share eight pages down handed back a grid holding
/// the first page only. Scrolling could not recover it, because there was
/// nothing there to scroll through until it paged in again.
///
/// So the window is remembered and restored, and the condition for restoring is
/// **that nothing else changed**: a different child, view or filter must still
/// come back at page one, because that is a different list rather than the same
/// one seen again.
class LibraryController extends AsyncNotifier<LibraryFeed> {
  LibraryController(this.session);

  /// The family argument, handed in by the provider — Riverpod 3 gives it to
  /// the constructor rather than to `build`.
  final AuthSession session;

  /// What the last build was a list *of*.
  ///
  /// A record rather than a hand-rolled class: Dart gives it structural
  /// equality, and every part already compares by value — `LibraryFilters`
  /// deliberately so, since Riverpod uses that to decide whether to refetch.
  ///
  /// Null before the first build, which is why the first one never restores.
  ({
    String? childId,
    LibraryView view,
    LibraryFilters filters,
    (String, String) sort,
  })? _lastList;

  /// How many entries the feed held when it was last left alone.
  ///
  /// Kept on the notifier rather than in the state: the state is what `build`
  /// replaces, so anything asked *before* rebuilding has to outlive it.
  /// Riverpod keeps the notifier instance across a dependency-driven rebuild,
  /// which is what makes this survive exactly as long as the grid is on screen.
  int _loaded = 0;

  @override
  Future<LibraryFeed> build() async {
    // The other half of the refresh unit (#93). Watched here rather than
    // invalidated from six call sites, so the grid and the count that
    // describes it can never be refreshed apart.
    ref.watch(libraryRevisionProvider);

    // Read here as well as inside `_fetch`, so the feed can record whose
    // classification it carries (#96).
    final child = ref.watch(pickedChildProvider(session));

    // Same list as last time? Then this rebuild is a refresh, and the window
    // that was open is asked for again. Anything else is a new list and starts
    // at the top — which is the behaviour the paging reset was there to give,
    // and it is kept rather than traded away.
    final list = (
      childId: child?.id,
      view: ref.watch(libraryViewProvider),
      filters: ref.watch(libraryFiltersProvider),
      // **The sort belongs in this record, not only in the query.** Changing
      // it makes a different list, so it must start at the top: restoring a
      // window of N entries under a new order would hand back the first N of
      // a list the parent has never seen the start of.
      sort: _sort(),
    );
    final same = _lastList == list;
    _lastList = list;

    final slice = await _fetch(
      startIndex: 0,
      want: same ? _loaded : LibraryRepository.pageSize,
    );
    _loaded = slice.entries.length;
    return LibraryFeed(
      entries: slice.entries,
      nextStartIndex: slice.nextStartIndex,
      hasMore: slice.hasMore,
      totalRecordCount: slice.totalRecordCount,
      classifiedFor: child?.id,
    );
  }

  /// **Deliberately not `async`.** Marking it so would wrap the body in a
  /// microtask even when nothing is awaited, delaying the grid's request by a
  /// hop and reordering it against the other queries this screen issues.
  /// Measured: it turns three `library_count_test` cases red. A search that
  /// needs resolving takes the `.then` path and accepts the hop, because there
  /// it is buying something.
  Future<LibrarySlice> _fetch({
    required int startIndex,
    int want = LibraryRepository.pageSize,
  }) {
    final filters = ref.watch(libraryFiltersProvider);
    if (!filters.needsResolve) return _fetchWith(filters, startIndex, want);
    return ref
        .watch(resolvedLibraryFiltersProvider(session).future)
        .then((resolved) => _fetchWith(resolved, startIndex, want));
  }

  /// The order the grid is in, as the two strings the query sends.
  ///
  /// Read in one place so the record `build` compares and the query it issues
  /// can never disagree about what is on screen.
  (String, String) _sort() {
    final settings = ref.watch(settingsProvider);
    return (
      librarySortBy(settings.librarySort),
      librarySortOrder(descending: settings.librarySortDescending),
    );
  }

  Future<LibrarySlice> _fetchWith(
    LibraryFilters filters,
    int startIndex,
    int want,
  ) =>
      ref.watch(libraryRepositoryProvider(session)).fetch(
            sortBy: _sort().$1,
            sortOrder: _sort().$2,
            startIndex: startIndex,
            // Never below one page: `_loaded` is zero before anything has
            // been fetched, and a restore of zero would ask for nothing at all.
            want: want < LibraryRepository.pageSize
                ? LibraryRepository.pageSize
                : want,
            child: ref.watch(pickedChildProvider(session)),
            view: ref.watch(libraryViewProvider),
            filters: filters,
          );

  /// The next page, appended.
  ///
  /// Ignored while one is already in flight or when the server has run out —
  /// a scroll listener fires far more often than a page arrives, and without
  /// this the same window would be requested a dozen times.
  Future<void> loadMore() async {
    final feed = state.asData?.value;
    if (feed == null || feed.loadingMore || !feed.hasMore) return;

    state = AsyncData(feed.copyWith(loadingMore: true, moreFailed: false));
    try {
      final slice = await _fetch(startIndex: feed.nextStartIndex);
      final current = state.asData?.value ?? feed;
      final grown = _appendNew(current.entries, slice.entries);
      // The window grew, so the amount a refresh has to restore grew with it.
      // Recorded here as well as in `build`, because a refresh that followed a
      // scroll would otherwise restore the window as it was before the scroll.
      _loaded = grown.length;
      state = AsyncData(
        LibraryFeed(
          // Appended by id: a page fetched while an item was being written to
          // can overlap the previous one, and a duplicate key in a grid is a
          // crash rather than a cosmetic problem.
          entries: grown,
          nextStartIndex: slice.nextStartIndex,
          hasMore: slice.hasMore && slice.entries.isNotEmpty,
          totalRecordCount: current.totalRecordCount,
          // A page appended to this feed was classified for the same child:
          // changing the selection rebuilds rather than appending.
          classifiedFor: current.classifiedFor,
        ),
      );
    } on Object {
      final current = state.asData?.value ?? feed;
      state = AsyncData(current.copyWith(loadingMore: false, moreFailed: true));
    }
  }

  static List<LibraryEntry> _appendNew(
    List<LibraryEntry> existing,
    List<LibraryEntry> incoming,
  ) {
    final seen = {for (final entry in existing) entry.item.id};
    return [
      ...existing,
      ...incoming.where((entry) => seen.add(entry.item.id)),
    ];
  }
}

final libraryControllerProvider =
    AsyncNotifierProvider.family<LibraryController, LibraryFeed, AuthSession>(
        LibraryController.new);
