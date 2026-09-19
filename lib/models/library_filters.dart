// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// Which slice of the administrator's grid is being shown.
///
/// **Not a server filter**, which is why it is not part of [LibraryFilters]:
/// all three run the same query and differ only in which classified entries
/// are kept. The grid stays the administrator's view in every one of them.
enum LibraryView {
  /// What the child does not have yet — the giving workflow, and the default.
  toGive,

  /// Everything, shared or not.
  all,

  /// What the child can actually see: their labels, and — when the cap filter
  /// rides along — within their rating cap. Reached by tapping a face on the
  /// Kids screen.
  ///
  /// Deliberately a *state* rather than a mode the app remembers. Whether it
  /// should become permanent is a decision the owner has parked until it has
  /// been used, so nothing here persists it.
  given,
}

/// Which field the typed search term is matched against.
///
/// **Three modes rather than one box that searches everything, because
/// `/Items` ANDs its filters and has no OR.** A single box matching title *or*
/// person *or* studio would be a union of up to three server queries, and a
/// union cannot be paged by the server: page 2 of "title matches ∪ cast
/// matches" is not page 2 of anything Jellyfin will answer. Sieving a page
/// after it arrives is the other way out and is the thing this screen was
/// built not to do — the match is usually not in the first page.
enum SearchScope {
  /// The film's title. The default, so a parent who never touches the selector
  /// gets exactly the behaviour that existed before this mode did.
  title,

  /// Anyone credited — cast **and** crew, which is what the server does.
  ///
  /// **Named for what it matches rather than what a parent hoped for.** Bare
  /// `person=` matches every credit, and narrowing it to actors is possible
  /// only on 12.0.0: `personTypes` is *ignored* on 10.11.11 and *applied* on
  /// 12.0.0, measured in both directions. Calling this "Actor" would mean one
  /// label meaning two things depending on the server. Sending no
  /// `personTypes` at all makes the two versions behave identically, so this
  /// feature has no server-version branch in it.
  castAndCrew,

  /// The production studio.
  studio,
}

/// What the filter bar is asking the server for.
///
/// Every one of these is a **server-side** filter: `/Items` has the parameters,
/// so the grid asks rather than fetching everything and sieving it on the
/// phone. The one client-side filter in this screen is hide-shared, and only
/// because there is no `excludeTags` — see `LibraryRepository`.
class LibraryFilters {
  const LibraryFilters({
    this.type,
    this.genre,
    this.decade,
    this.withinCap = false,
    this.searchTerm,
    this.searchScope = SearchScope.title,
    this.resolvedSearchValue,
  });

  /// `Movie`, `Series` or `BoxSet`, or null for all three.
  final String? type;

  /// A genre name as the server spells it, from `/Genres`.
  final String? genre;

  /// The first year of a ten-year span: 1980, 1990, 2000.
  final int? decade;

  /// What the parent typed, matched by the **server** against the title (#73).
  ///
  /// Measured on a stock 10.11.11, because none of this is guessable and the
  /// repo has been bitten twice by a parameter that answered 200 while
  /// filtering nothing. **A server-side search plugin replaces every line
  /// below** — see `searchQueryParameters`:
  ///
  /// - **Title only.** Not the overview, not the cast, not tags, not genres.
  ///   Proven with a film whose overview says "Nothing like Paddington at all"
  ///   and which carries the tag `paddington`: searching Paddington does not
  ///   return it.
  /// - **Substring, anywhere in the title.** `add` finds Paddington and `eep`
  ///   finds Winter Sleep, so it is not anchored to a word start.
  /// - **Case- and accent-insensitive.** `amelie` finds `Amélie`.
  /// - **It ANDs with the other filters** rather than replacing them, checked
  ///   against `genres`, `years`, `tags` and `maxOfficialRating` in both
  ///   directions — matching and non-matching.
  /// - **`Recursive=true` is required.** Without it the same query answers
  ///   with folders — `Movies`, `Playlists` — rather than films.
  ///
  /// Null and empty mean the same thing to the server (everything), but the
  /// parameter is omitted when empty rather than sent blank: a request that
  /// says nothing is easier to read in a log than one that says nothing loudly.
  final String? searchTerm;

  /// Which field [searchTerm] is matched against.
  final SearchScope searchScope;

  /// The exact name [searchScope] needs, resolved from what the parent typed.
  ///
  /// **`person=` and `studios=` are exact-match, and this is measured rather
  /// than assumed**: `person=Tautou` returns nothing where
  /// `person=Audrey Tautou` returns the film. A parent types three letters, so
  /// the typed text cannot go to the server in these modes. `/Search/Hints`
  /// turns a substring into the exact, typed name, and the result lands here.
  ///
  /// Null in [SearchScope.title], where the server takes the substring itself.
  /// Null in the other two means *the resolve found nothing* — which is not
  /// the same as no filter, and [isImpossible] is what keeps those apart.
  final String? resolvedSearchValue;

  /// Hide titles rated above the selected child's cap.
  ///
  /// **A filter over the administrator's view, not a claim about what the child
  /// sees.** Measured on 10.11.11: `maxOfficialRating` lets an *unrated* title
  /// through at every cap, while a child whose policy sets
  /// `BlockUnratedItems: ['Movie']` cannot see it — two different mechanisms,
  /// and only the server knows the second. Ground rule 4 is why the copy for
  /// this says "above their limit" rather than "what they can see".
  final bool withinCap;

  /// Whether anything is actually narrowing the grid.
  ///
  /// A search of pure whitespace is not: the server treats it as no filter at
  /// all (measured — `searchTerm=%20` returns the whole library), so counting
  /// it as active would put a "1 filter" badge on an unfiltered grid.
  bool get hasSearch => (searchTerm ?? '').trim().isNotEmpty;

  /// Whether this search needs `/Search/Hints` before it can be sent.
  ///
  /// **False for every title search and every unfiltered grid**, and callers
  /// rely on that to stay synchronous. Awaiting a resolve that is not needed
  /// is not merely wasteful: it delays the grid's first request by an async
  /// hop and reorders it against the other queries the screen issues. Measured
  /// — doing so unconditionally turned three passing count tests red, because
  /// the count and the grid swapped places in the sequence.
  bool get needsResolve =>
      searchScope != SearchScope.title && hasSearch;

  /// A search that cannot match anything, because nothing resolved.
  ///
  /// **The grid must show an empty result rather than run the query without
  /// the filter.** Dropping an unresolvable `person=` would send a query with
  /// no person filter at all, and the server would cheerfully return the whole
  /// library — a search for a name nobody is credited under would look exactly
  /// like a search that was never applied. That is the failure this whole
  /// screen exists to avoid, arriving through a different door.
  bool get isImpossible =>
      searchScope != SearchScope.title &&
      hasSearch &&
      (resolvedSearchValue ?? '').isEmpty;

  bool get isEmpty =>
      type == null && genre == null && decade == null && !withinCap &&
      !hasSearch;

  int get activeCount => [
        type != null,
        genre != null,
        decade != null,
        withinCap,
        hasSearch,
      ].where((on) => on).length;

  /// The years a decade covers, for the `years=` parameter.
  ///
  /// **Comma-delimited, and that is measured rather than assumed.** On the same
  /// server `genres=` and `tags=` take `|` and treat a comma as part of the
  /// value — silently returning 0 — while `years=` takes a comma and answers
  /// **400** to a pipe. One is wrong loudly and the other quietly, so neither
  /// delimiter is a house style: it is per parameter.
  List<int> get decadeYears =>
      decade == null ? const [] : [for (var i = 0; i < 10; i++) decade! + i];

  LibraryFilters copyWith({
    Object? type = _keep,
    Object? genre = _keep,
    Object? decade = _keep,
    bool? withinCap,
    Object? searchTerm = _keep,
    SearchScope? searchScope,
    Object? resolvedSearchValue = _keep,
  }) =>
      LibraryFilters(
        // `_keep` rather than null-means-keep, so a filter can be *cleared*.
        // With the usual pattern, "no genre" and "leave the genre alone" are
        // the same argument and one of them becomes unreachable.
        type: identical(type, _keep) ? this.type : type as String?,
        genre: identical(genre, _keep) ? this.genre : genre as String?,
        decade: identical(decade, _keep) ? this.decade : decade as int?,
        withinCap: withinCap ?? this.withinCap,
        searchTerm:
            identical(searchTerm, _keep) ? this.searchTerm : searchTerm as String?,
        searchScope: searchScope ?? this.searchScope,
        resolvedSearchValue: identical(resolvedSearchValue, _keep)
            ? this.resolvedSearchValue
            : resolvedSearchValue as String?,
      );

  static const _keep = Object();

  /// **Every field that narrows the grid must be in here, [searchTerm]
  /// included.**
  ///
  /// This is not a formality. `libraryFiltersProvider` is a `Notifier` holding
  /// one of these, and Riverpod decides whether to notify its listeners by
  /// comparing the old state with the new — so a field left out of `==` is a
  /// field that **cannot change anything**. `searchTerm` was omitted, and the
  /// consequence was not a stale badge or a missed rebuild somewhere subtle:
  /// typing in the search field updated the filter, the grid never re-fetched,
  /// and the whole of #73 filtered nothing. Measured on this branch — with the
  /// term out of `==`, setting a search issues **zero** requests; with it in,
  /// one, carrying `searchTerm`.
  ///
  /// `test/library_search_test.dart` pins the end-to-end version of that: the
  /// server is asked. Comparing the two objects would not have caught it, since
  /// the objects were the thing that was wrong.
  @override
  bool operator ==(Object other) =>
      other is LibraryFilters &&
      other.type == type &&
      other.genre == genre &&
      other.decade == decade &&
      other.withinCap == withinCap &&
      other.searchTerm == searchTerm &&
      // Both of these narrow the grid, so both are here. Switching Title ->
      // Cast & crew changes nothing about the typed text and everything about
      // what is asked for; left out of `==`, the provider would not notify and
      // the selector would be inert in exactly the way `searchTerm` once was.
      other.searchScope == searchScope &&
      other.resolvedSearchValue == resolvedSearchValue;

  @override
  int get hashCode =>
      Object.hash(type, genre, decade, withinCap, searchTerm, searchScope,
          resolvedSearchValue);
}
