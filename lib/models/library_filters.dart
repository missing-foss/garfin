// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

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
  });

  /// `Movie`, `Series` or `BoxSet`, or null for all three.
  final String? type;

  /// A genre name as the server spells it, from `/Genres`.
  final String? genre;

  /// The first year of a ten-year span: 1980, 1990, 2000.
  final int? decade;

  /// What the parent typed, matched by the **server** against the title (#73).
  ///
  /// Measured on 10.11.11, because none of this is guessable and the repo has
  /// been bitten twice by a parameter that answered 200 while filtering
  /// nothing:
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
      );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is LibraryFilters &&
      other.type == type &&
      other.genre == genre &&
      other.decade == decade &&
      other.withinCap == withinCap;

  @override
  int get hashCode => Object.hash(type, genre, decade, withinCap);
}
