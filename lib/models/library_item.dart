// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// One tile on the Library grid.
///
/// Read-only, like every model here. Nothing on this screen writes — the assign
/// sheet is step 5 — so there is no `toJson` and none should be added until
/// there is a write path that has been through ground rule 2.
class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.name,
    required this.type,
    required this.tags,
    this.primaryImageTag,
    this.officialRating,
    this.productionYear,
    this.runTimeTicks,
    this.productionLocations = const [],
    this.communityRating,
    this.criticRating,
    this.genres = const [],
    this.studios = const [],
    this.childCount,
    this.recursiveItemCount,
  });

  final String id;
  final String name;

  /// `Movie`, `Series`, `BoxSet`. Kept as the server's own string rather than
  /// an enum: an unknown type should render as a plain tile, not throw.
  final String type;

  /// **The scraper's tags and Garfin's labels, mixed, with no way to tell them
  /// apart from the list alone.**
  ///
  /// Measured on 10.11.11: tagging one film `kids-emma` left it holding
  /// `['missing person', 'kidnapping', 'alien abduction', 'government
  /// conspiracy', 'kids-emma', 'secret agent']` — Garfin's label is one entry
  /// among the metadata provider's.
  ///
  /// So this is never rendered. It is matched against the labels already known
  /// from each child's policy, and nothing else. Showing it raw would put
  /// "kidnapping" on a poster under a child's face.
  ///
  /// Requires `Fields=Tags` on the query: without it the key is **absent**
  /// from the response entirely, not empty.
  final List<String> tags;

  /// The poster's cache key, absent when the item has no image.
  final String? primaryImageTag;

  /// The item's certificate as a string — `PG`, `TV-14`. There is no numeric
  /// parental value on an item; `BaseItemDto` carries only this.
  ///
  /// Used for a *hint* about why the server hid something, never to decide
  /// whether it did. See `LibraryItemState`.
  final String? officialRating;

  final int? productionYear;

  /// How long the item runs, in the server's 100-nanosecond units.
  ///
  /// **Null means the server has no duration for it, not that it was not
  /// asked for.** Measured 2026-09-17 on 12.1.0: a list row carries
  /// `RunTimeTicks` *unasked* when the item has media streams — a generated 7 s
  /// file answered `70030000` — and omits the key entirely for a file with
  /// none. Writing a value through the item DTO does not stick; the server
  /// derives it. A `BoxSet` never has one. See `docs/JELLYFIN-API.md`
  /// § Duration and country of origin.
  final int? runTimeTicks;

  /// Where the item was made, as the metadata provider wrote it.
  ///
  /// **English country names, not codes, and a list** — `["United States"]`,
  /// `["Germany", "France"]` — empty far more often than not in a library of
  /// ripped files. Absent from a list row until `Fields=ProductionLocations`
  /// is asked for, which is why this defaults to empty rather than null: the
  /// caller cannot tell "not asked" from "none" and must not present either as
  /// a fact.
  final List<String> productionLocations;

  /// The audience score, **out of ten** — `8.3`.
  ///
  /// Measured 2026-09-18 on 12.1.0: arrives on a list row **unasked**, on a
  /// film and on a series alike. Null means the metadata has none.
  final double? communityRating;

  /// The critics score, **out of a hundred** — `89`, read as a percentage.
  ///
  /// A different scale from [communityRating], which is why the two are never
  /// formatted alike. Arrives unasked like it; measured present on a film and
  /// absent on the series fixture, which set none.
  final double? criticRating;

  /// Genre names, in the server's order. Absent from a list row until
  /// `Fields=Genres` is asked for, so empty cannot tell "none" from "not asked"
  /// — the same terms as [productionLocations].
  final List<String> genres;

  /// Studio names. The server sends `[{Name, Id}]` objects, not strings, and
  /// needs `Fields=Studios` on a list row. Only the names are kept: nothing here
  /// looks a studio up.
  final List<String> studios;

  /// How many children the server counts under this item — **one level down,
  /// not all the way**.
  ///
  /// Measured on 10.11.11, and the distinction is the whole reason
  /// [recursiveItemCount] exists beside it: for a `BoxSet` this is its films,
  /// but for a `Series` it is the **seasons**, and for a `Season` the episodes.
  /// A show with two seasons and five episodes reports `2` here. Absent for a
  /// `Movie` even when asked for.
  ///
  /// Null means the server was not asked — `Fields=ChildCount` — never that the
  /// item is empty.
  final int? childCount;

  /// How many items sit under this one **all the way down**.
  ///
  /// Measured: `5` for the same two-season show whose [childCount] is `2`, and
  /// equal to [childCount] for a `Season`, whose children are already episodes.
  /// Absent for a `Movie` even when requested, which is what makes a badge
  /// guarded on this field safe on a film without a type check.
  ///
  /// Requires `Fields=RecursiveItemCount`; absent otherwise, exactly like
  /// [childCount].
  final int? recursiveItemCount;

  bool get isCollection => type == 'BoxSet';

  /// Whether this is a series, which behaves unlike a collection in the one way
  /// that matters here.
  ///
  /// Measured: the policy filter **inherits from the series**, so a
  /// label on it reaches every season and episode inside — a series *is* an
  /// ancestor of its episodes, while a BoxSet is not an ancestor of its films.
  /// That is why one needs a cascade and the other does not.
  bool get isSeries => type == 'Series';

  /// A film, as opposed to a set or a series.
  bool get isMovie => type == 'Movie';

  /// Whether the assign sheet draws the detail head for this item: films and
  /// series (#160). A `BoxSet` stays out, as ruled on #145.
  bool get hasDetailHead => isMovie || isSeries;

  /// Whether this item carries [label], case-insensitively.
  ///
  /// Measured: the server's own `tags=` filter is case-insensitive —
  /// `tags=KIDS-EMMA` matches an item tagged `kids-emma`. Matching case
  /// sensitively here would disagree with the server about which items are
  /// shared, which is worse than either rule on its own.
  /// Whether this item carries **any** of [labels].
  ///
  /// A child may hold more than one shortlist tag, and the server matches *any*
  /// of them — `AllowedTags: ["kids-emma", "family-films"]` means an item
  /// tagged either one is visible to them. Checking only the first would call
  /// something "not given yet" that the child can already watch.
  ///
  /// Reading takes all of them; **writing takes one** — see
  /// `AssignRepository.labelFor`. The asymmetry is deliberate: matching has a
  /// right answer that the server defines, while choosing which label to add is
  /// a choice, and the first is as good as any.
  bool hasAnyLabel(Iterable<String> labels) =>
      labels.any((label) => hasLabel(label));

  bool hasLabel(String label) {
    final wanted = label.toLowerCase();
    for (final tag in tags) {
      if (tag.toLowerCase() == wanted) return true;
    }
    return false;
  }

  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
        id: readString(json, 'Id') ?? '',
        name: readString(json, 'Name') ?? '',
        type: readString(json, 'Type') ?? '',
        tags: readStringList(json, 'Tags'),
        primaryImageTag: _primaryImageTag(json),
        officialRating: readString(json, 'OfficialRating'),
        productionYear: readInt(json, 'ProductionYear'),
        runTimeTicks: readInt(json, 'RunTimeTicks'),
        productionLocations: readStringList(json, 'ProductionLocations'),
        communityRating: readDouble(json, 'CommunityRating'),
        criticRating: readDouble(json, 'CriticRating'),
        genres: readStringList(json, 'Genres'),
        studios: _names(json, 'Studios'),
        childCount: readInt(json, 'ChildCount'),
        recursiveItemCount: readInt(json, 'RecursiveItemCount'),
      );

  /// The `Name` of each object in a `[{Name, Id}]` list, skipping any without
  /// one.
  static List<String> _names(Map<String, dynamic> json, String field) {
    final value = readField(json, field);
    if (value is! List) return const [];
    return [
      for (final entry in value.whereType<Map<String, dynamic>>())
        if (readString(entry, 'Name') case final name? when name.isNotEmpty)
          name,
    ];
  }

  /// Items carry image tags in a map, unlike users which carry one string.
  static String? _primaryImageTag(Map<String, dynamic> json) {
    final tags = readMap(json, 'ImageTags');
    if (tags == null) return null;
    final value = readField(tags, 'Primary');
    return value is String && value.isNotEmpty ? value : null;
  }
}

/// What one item means for one selected child.
///
/// The three-way split for an allow-list child is the whole point of the
/// screen, and [givenButHidden] is the state that does not exist anywhere else:
/// a parent tags a film, the count does not move, and without this they have no
/// way to find out why.
enum LibraryItemState {
  /// Allow mode, no label. The child has not been given it.
  notGiven,

  /// Allow mode, label present, and the server does show it to them.
  given,

  /// Allow mode, label present, and the server **still** does not show it.
  ///
  /// The fact comes from the server. The *reason* does not — Jellyfin does not
  /// say why it hid something, and it could be the rating cap or
  /// `EnabledFolders`. Anything explaining this must offer a reason, not assert
  /// one.
  givenButHidden,

  /// Block mode, no label: the child can reach it. Nothing to do.
  available,

  /// Block mode, label present: taken away from them.
  blocked,

  /// No child selected, or one whose shortlist mode Garfin refuses to
  /// interpret. Ground rule 3 — with both lists live there is no correct verb,
  /// so there is no correct per-item answer either.
  unknown,
}
