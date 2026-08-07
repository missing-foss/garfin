// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'jellyfin_user.dart';
import 'kid_summary.dart';
import 'library_item.dart';

/// One child whose face goes on a poster, because they already have the title.
///
/// A face rather than a name because the grid is scanned, not read: `UI-SPEC`
/// asks for "avatars of the children who have it" on a tile roughly 110dp wide.
/// [avatarUrl] is null for a child with no picture, exactly as on the Kids
/// screen — `UserAvatar` then shows their initial (#79).
class ItemHolder {
  const ItemHolder({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  /// Kept for the widget key and for tests; the row itself renders a picture.
  final String userId;

  final String name;

  /// Null when the user has no picture. Same rule as [KidSummary.avatarUrl] —
  /// key-*absence* on the server's response, not a URL that would 404.
  final String? avatarUrl;
}

/// Which children have been **given** [item], out of [children].
///
/// "Given" is the whole claim, and it is deliberately smaller than "can watch"
/// (ground rule 4). An avatar means the child's label is on the item. Whether
/// the item actually reaches them is the server's answer, tags and rating cap
/// together, and the app never predicts it. That distinction already exists as
/// [LibraryItemState.givenButHidden] — but only for the *selected* child,
/// because knowing it for everyone would cost a per-child query per title. So
/// the avatars say given, and the held-back nuance stays with the selected
/// child's badge, one corner away.
///
/// **Block-list children are left out, not marked.** For [ShortlistMode.block]
/// a matching tag means the title is *withheld* from that child, so their face
/// on a poster would say the exact opposite of what the row says everywhere
/// else — and a reader scanning a grid does not stop to check which verb this
/// particular child is under. A row with one meaning is worth more than a row
/// with two.
///
/// [ShortlistMode.conflicting] accounts are out for the reason ground rule 3
/// gives: with both lists live there is no correct verb, so there is no correct
/// per-item answer either. [ShortlistMode.none] has no label to match.
///
/// This is a join over data already in memory — the grid asks for `Fields=Tags`
/// on every item, and every child's labels and picture arrive with the Kids
/// overview — so it costs no request. That is also why it lives here rather
/// than on `LibraryEntry`: computing it inside `LibraryRepository.fetch` would
/// tie the grid's *fetch* to the Kids overview, and re-fetch a library page —
/// measured at up to half a second in #68 — every time a write invalidated it.
/// The age hint (#43) is passed into the tile the same way, for the same
/// reason.
List<ItemHolder> holdersOf({
  required LibraryItem item,
  required List<KidSummary> children,
}) =>
    <ItemHolder>[
      for (final child in children)
        if (child.mode == ShortlistMode.allow && item.hasAnyLabel(child.tags))
          ItemHolder(
            userId: child.user.id,
            name: child.user.name,
            avatarUrl: child.avatarUrl,
          ),
    ];
