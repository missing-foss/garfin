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
  });

  /// `Movie`, `Series` or `BoxSet`, or null for all three.
  final String? type;

  /// A genre name as the server spells it, from `/Genres`.
  final String? genre;

  /// The first year of a ten-year span: 1980, 1990, 2000.
  final int? decade;

  /// Hide titles rated above the selected child's cap.
  ///
  /// **A filter over the administrator's view, not a claim about what the child
  /// sees.** Measured on 10.11.11: `maxOfficialRating` lets an *unrated* title
  /// through at every cap, while a child whose policy sets
  /// `BlockUnratedItems: ['Movie']` cannot see it — two different mechanisms,
  /// and only the server knows the second. Ground rule 4 is why the copy for
  /// this says "above their limit" rather than "what they can see".
  final bool withinCap;

  bool get isEmpty =>
      type == null && genre == null && decade == null && !withinCap;

  int get activeCount => [
        type != null,
        genre != null,
        decade != null,
        withinCap,
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
  }) =>
      LibraryFilters(
        // `_keep` rather than null-means-keep, so a filter can be *cleared*.
        // With the usual pattern, "no genre" and "leave the genre alone" are
        // the same argument and one of them becomes unreachable.
        type: identical(type, _keep) ? this.type : type as String?,
        genre: identical(genre, _keep) ? this.genre : genre as String?,
        decade: identical(decade, _keep) ? this.decade : decade as int?,
        withinCap: withinCap ?? this.withinCap,
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
