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
    this.childCount,
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

  /// For a `BoxSet`, how many items it holds. Null for anything else.
  final int? childCount;

  bool get isCollection => type == 'BoxSet';

  /// Whether this is a series, which behaves unlike a collection in the one way
  /// that matters here.
  ///
  /// Measured for #53: the policy filter **inherits from the series**, so a
  /// label on it reaches every season and episode inside — a series *is* an
  /// ancestor of its episodes, while a BoxSet is not an ancestor of its films.
  /// That is why one needs a cascade and the other does not.
  bool get isSeries => type == 'Series';

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
        childCount: readInt(json, 'ChildCount'),
      );

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
