// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/library_filters.dart';
import '../models/kid_summary.dart';
import '../models/parental_rating.dart';
import '../repositories/jellyfin_api.dart';
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
  String? build() => ref.watch(settingsProvider).startingChildId;

  /// The choice for this session. Deliberately **not** written back to
  /// Settings: `docs/UI-SPEC.md` § Settings calls the stored one the *starting*
  /// child, and a picker that quietly rewrote the default would make "start on
  /// Emma" impossible to keep.
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

/// Whether already-shared items are hidden.
///
/// Starts from Settings, and the Library's own Show/Hide button moves it for
/// this session only. `docs/DECISIONS.md` § Product shape: hiding turns the
/// grid into a to-do list rather than an inventory, which is why the stored
/// default is on.
class HideShared extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsProvider).hideShared;

  void toggle() => state = !state;
}

final hideSharedProvider = NotifierProvider<HideShared, bool>(HideShared.new);

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
    this.loadingMore = false,
    this.moreFailed = false,
  });

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
        loadingMore: loadingMore ?? this.loadingMore,
        moreFailed: moreFailed ?? this.moreFailed,
      );
}

/// The grid's pages.
///
/// `build` re-runs whenever the child, the hide-shared toggle or a filter
/// changes, which is what resets paging on a filter change — there is no
/// separate "clear" to forget to call.
class LibraryController extends AsyncNotifier<LibraryFeed> {
  LibraryController(this.session);

  /// The family argument, handed in by the provider — Riverpod 3 gives it to
  /// the constructor rather than to `build`.
  final AuthSession session;

  @override
  Future<LibraryFeed> build() async {
    final slice = await _fetch(startIndex: 0);
    return LibraryFeed(
      entries: slice.entries,
      nextStartIndex: slice.nextStartIndex,
      hasMore: slice.hasMore,
      totalRecordCount: slice.totalRecordCount,
    );
  }

  Future<LibrarySlice> _fetch({required int startIndex}) =>
      ref.watch(libraryRepositoryProvider(session)).fetch(
            startIndex: startIndex,
            child: ref.watch(pickedChildProvider(session)),
            hideShared: ref.watch(hideSharedProvider),
            filters: ref.watch(libraryFiltersProvider),
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
      state = AsyncData(
        LibraryFeed(
          // Appended by id: a page fetched while an item was being written to
          // can overlap the previous one, and a duplicate key in a grid is a
          // crash rather than a cosmetic problem.
          entries: _appendNew(current.entries, slice.entries),
          nextStartIndex: slice.nextStartIndex,
          hasMore: slice.hasMore && slice.entries.isNotEmpty,
          totalRecordCount: current.totalRecordCount,
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
