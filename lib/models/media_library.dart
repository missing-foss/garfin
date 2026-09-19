// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// One of the server's libraries — "Films", "Shows" — as a place to count in.
///
/// **Listed as the child, not as the administrator.** Measured 2026-09-05 on
/// 10.11.11: `/UserViews` answers the same *name and id* for a library both can
/// open, which is what was already recorded here — but the **set** differs, five
/// libraries against one for a child enabled on only one of them. The recorded
/// claim was true and was being asked to support something it never said.
///
/// Listing the administrator's set and counting in it as the child does not
/// merely show a library that is not theirs: `/Items` with a `parentId` the
/// child cannot open answers **401**, and one of those rejects the whole batch.
/// See `docs/JELLYFIN-API.md` § Counting per library.
class MediaLibrary {
  const MediaLibrary({
    required this.id,
    required this.name,
    required this.collectionType,
  });

  final String id;
  final String name;

  /// Jellyfin's own `CollectionType` — `movies`, `tvshows`, `music`, `books`,
  /// `homevideos` — lowercased, and absent on a mixed folder.
  final String? collectionType;

  /// What Garfin counts in a library of this type, or null if it manages
  /// nothing there.
  ///
  /// **Garfin's whole notion of a title is `Movie` and `Series`**: the grid
  /// browses those two, and a tag written to a series is how a show is handed
  /// over. Sending `Movie,Series` at every library regardless — which is what
  /// this used to do — answered 0 for a music, book or home-video library that
  /// was not empty, and "0 given" reads exactly like "nothing here to give".
  ///
  /// So a library holding neither is not counted as zero. It is not
  /// [manageable] at all, and is left off the card.
  String? get countedTypes => switch (collectionType) {
        'movies' => 'Movie',
        'tvshows' => 'Series',
        // A mixed folder can hold both, so it is asked about both.
        null || 'folders' => 'Movie,Series',
        _ => null,
      };

  /// Whether Garfin can give or take anything in this library at all.
  bool get manageable => countedTypes != null;

  static MediaLibrary? fromJson(Map<String, dynamic> json) {
    final id = readString(json, 'Id');
    if (id == null || id.isEmpty) return null;
    return MediaLibrary(
      id: id,
      name: readString(json, 'Name') ?? '',
      collectionType: readString(json, 'CollectionType')?.toLowerCase(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaLibrary &&
      other.id == id &&
      other.name == name &&
      other.collectionType == collectionType;

  @override
  int get hashCode => Object.hash(id, name, collectionType);
}

/// What one child can see in one library.
class LibraryVisibleCount {
  const LibraryVisibleCount({required this.library, required this.visible});

  final MediaLibrary library;
  final int visible;
}
