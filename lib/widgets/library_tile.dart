// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/age_suitability.dart';
import '../models/item_holder.dart';
import '../models/library_item.dart';
import '../repositories/library_repository.dart';
import 'user_avatar.dart';

/// One poster on the grid.
///
/// Nothing here renders `LibraryItem.tags`. That list is the metadata
/// provider's as much as Garfin's — measured, a tagged film also carried
/// "kidnapping" and "alien abduction" — so only the derived [LibraryEntry.state]
/// reaches the screen.
class LibraryTile extends StatelessWidget {
  const LibraryTile({
    super.key,
    required this.entry,
    required this.serverUrl,
    this.childName,
    this.childId,
    this.holders = const [],
    this.suitability = AgeSuitability.unknown,
  });

  final LibraryEntry entry;
  final String serverUrl;

  /// The selected child, for the sentence explaining a held-back item.
  final String? childName;

  /// The selected child's id, so the spoken label does not name them twice.
  ///
  /// An id rather than [childName]: names repeat on a Jellyfin server and can
  /// be changed without the account changing, which is the same reason
  /// `pickedChildProvider` keys on one.
  final String? childId;

  /// The children who already have this title (#84), for the avatar row.
  ///
  /// Everyone who has it, not just the selected child — the parent scanning the
  /// grid without picking anyone is the case this exists for. See [holdersOf]
  /// for what "have" means here and who is deliberately left out of it.
  final List<ItemHolder> holders;

  /// The age hint (#43). **Advice, and it never changes which tiles appear.**
  ///
  /// [AgeSuitability.suitsAge] shows nothing: the grid is a to-do list, and
  /// marking the majority case would be noise. Only "above their age" and
  /// "not known" are worth a parent's attention, and the second is worth it
  /// precisely because it is not a pass.
  final AgeSuitability suitability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final item = entry.item;

    return Semantics(
      label: _semanticLabel(l10n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _Poster(item: item, serverUrl: serverUrl),
                ),
                // The state badge and the faces share the top edge, laid out
                // against each other rather than pinned to opposite corners.
                //
                // Opposite corners was the first attempt and it collides:
                // rendered at 110dp — narrower still at four columns, where a
                // tile is ~83dp — "Held back" and three faces both want the
                // same middle. Nothing errors, the faces simply paint over the
                // badge. **The badge wins the argument**: it is the answer
                // about the selected child, and the row shrinks to whatever is
                // left, down to nothing.
                Positioned(
                  top: 4,
                  left: 4,
                  right: 4,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_badge(l10n) case final badge?)
                          ConstrainedBox(
                            // Bounded by the tile rather than by the row's
                            // free space: a `Flexible` here would split the
                            // width evenly and wrap a badge that had room.
                            // This only caps the pathological case, where the
                            // badge wraps instead of overflowing.
                            constraints:
                                BoxConstraints(maxWidth: constraints.maxWidth),
                            child: _Badge(label: badge, tone: _tone(theme)),
                          ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            // The faces are already in the tile's own semantic
                            // label, in full. Left in the tree they would read
                            // as a string of stray initials between the title
                            // and the badge.
                            child: ExcludeSemantics(
                              child: _HolderRow(holders: holders),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // The bottom edge, laid out against itself for the same
                // reason as the top (#89). Pinned to opposite corners, the
                // age hint and the collection count want the same middle on
                // anything narrower than a two-column tile: rendered at 83dp
                // and at 118dp the count painted straight over the hint and
                // spilled past the poster, with nothing erroring and no
                // assertion failing, because both were inside the tile.
                //
                // A `Wrap` rather than the top edge's shrink-to-fit, because
                // neither of these can shrink: they are words. When both do
                // not fit on one line the count takes the line **below**,
                // which costs a little poster and keeps both facts. The top
                // edge drops faces instead because a face has a `+N` that can
                // stand for it; a number has nothing that stands for it.
                //
                // The alignment depends on what is in the row, and that is
                // not cosmetic: `spaceBetween` has nothing to distribute with
                // one child, so it puts it at the start — which moved a lone
                // collection count from the right corner to the left on every
                // tile with **no child selected**, the state the app opens in.
                // Caught in review, and only because a test was written for
                // the one case every other test had a child in.
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Wrap(
                    alignment: _ageHint(l10n) == null
                        ? WrapAlignment.end
                        : WrapAlignment.spaceBetween,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (_ageHint(l10n) case final hint?)
                        _Badge(
                          label: hint,
                          tone: suitability == AgeSuitability.aboveAge
                              ? theme.colorScheme.tertiaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                        ),
                      if (item.isCollection && item.childCount != null)
                        _Badge(
                          label: l10n.libraryCollectionCount(item.childCount!),
                          tone: theme.colorScheme.surfaceContainerHighest,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// The age hint, or null when there is nothing useful to say.
  ///
  /// Silent with no child selected — there is no age to compare against — and
  /// silent when the title suits, because that is most of the grid.
  String? _ageHint(AppLocalizations l10n) {
    if (childName == null) return null;
    return switch (suitability) {
      AgeSuitability.aboveAge => l10n.libraryHintAboveAge(childName!),
      AgeSuitability.unknown => l10n.libraryHintUnknownAge,
      AgeSuitability.suitsAge => null,
    };
  }

  String? _badge(AppLocalizations l10n) => switch (entry.state) {
        LibraryItemState.given => l10n.libraryBadgeGiven,
        LibraryItemState.givenButHidden => l10n.libraryBadgeHeldBack,
        LibraryItemState.blocked => l10n.libraryBadgeBlocked,
        // Not-given is the default state of the grid, and badging it would
        // put a marker on almost every tile — noise rather than signal.
        LibraryItemState.notGiven ||
        LibraryItemState.available ||
        LibraryItemState.unknown =>
          null,
      };

  Color _tone(ThemeData theme) => switch (entry.state) {
        LibraryItemState.givenButHidden => theme.colorScheme.errorContainer,
        LibraryItemState.blocked => theme.colorScheme.surfaceContainerHighest,
        _ => theme.colorScheme.primaryContainer,
      };

  /// What a screen reader says, including the explanation a sighted user gets
  /// from tapping.
  ///
  /// The held-back sentence **offers** the reason rather than asserting it: the
  /// server does not say why it hid an item, and a folder permission is
  /// indistinguishable from a rating cap here.
  String _semanticLabel(AppLocalizations l10n) {
    final name = entry.item.name;
    final shared = _holderSentence(l10n);
    if (entry.state == LibraryItemState.givenButHidden && childName != null) {
      return <String>[
        name,
        l10n.libraryHeldBackExplanation(childName!),
        ?shared,
      ].join('. ');
    }
    final parts = <String>[name, ?_badge(l10n), ?_ageHint(l10n), ?shared];
    return parts.join('. ');
  }

  /// Who *else* has it, said in words.
  ///
  /// **Every one of them, not the ones the row had space for.** The `+N` exists
  /// because a poster is ~118dp wide and narrower beside a badge; a spoken
  /// label has no edge to run out of, and "and two others" would be a worse
  /// answer than the two names. On the narrowest tile the row shows nothing at
  /// all and this sentence is the only place the faces survive.
  ///
  /// **The selected child is left out, because the badge has just spoken about
  /// them.** Otherwise the label reads "Given. Given to Emma", and the
  /// held-back one reads as a contradiction — "the server isn't showing it to
  /// them … Given to Emma" — to anyone who has not internalised the
  /// given-versus-visible split this app is built on. Their face still goes in
  /// the row: the row says who has it, the sentence adds who else.
  ///
  /// Says *given*, like the avatars themselves: the label is on the item. See
  /// [holdersOf] — whether the title reaches the child is the server's answer,
  /// and ground rule 4 keeps this app out of it.
  String? _holderSentence(AppLocalizations l10n) {
    final others = holders.where((h) => h.userId != childId).toList();
    if (others.isEmpty) return null;
    return l10n.libraryHolders(others.map((h) => h.name).join(', '));
  }
}

/// The faces along the top edge of a poster.
///
/// Discreet by design: 22dp circles, overlapped, three at most, plus a `+N`
/// circle for the rest. The tile's job is the title; this is a glance-level
/// answer to "who already has this", which is the question a parent has
/// *before* picking a child — see #84.
///
/// **How many it draws is measured, not assumed.** A tile is ~118dp wide at
/// three columns and ~83dp at four, and the state badge beside it is between
/// "Given" and "Held back" wide — in French, wider. So the row takes whatever
/// width it is handed and fills it: every circle is the same size and overlaps
/// by the same amount, which makes the arithmetic exact rather than an
/// estimate that has to be right at every text scale.
class _HolderRow extends StatelessWidget {
  const _HolderRow({required this.holders});

  final List<ItemHolder> holders;

  /// Three faces, then the rest become one `+N`. A fourth face on an 83dp
  /// poster leaves no poster.
  static const _maxFaces = 3;

  static const _radius = 9.0;
  static const _ring = 2.0;
  static const _diameter = (_radius + _ring) * 2;

  /// How much of a circle the next one covers. Overlapping says "a group" at a
  /// glance in a way a spaced row does not, and it is what makes three fit.
  static const _overlap = 6.0;

  /// The width [count] circles need: each costs the uncovered part, and the
  /// last one shows whole.
  static double _widthFor(int count) =>
      count <= 0 ? 0 : (count - 1) * (_diameter - _overlap) + _diameter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (holders.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // How many circles fit, one more than the faces because the `+N` is
        // one too.
        final slots = _slotsIn(constraints.maxWidth);
        final showsEveryone =
            holders.length <= slots && holders.length <= _maxFaces;

        // **A `+N` is never drawn alone.** Everywhere else it means "N more
        // than the faces you can see"; with no face beside it the same glyph
        // would mean "N in total", and the tile where that happens is the
        // smallest one — the worst place to change what a symbol means. So
        // the last rung before nothing is one face and a count, and below
        // that the row says nothing rather than something ambiguous. The
        // screen reader is told at every width; that sentence is on the tile,
        // not here.
        if (!showsEveryone && slots < 2) return const SizedBox.shrink();

        return _circles(
          theme,
          l10n,
          faces: showsEveryone ? holders.length : slots - 1,
        );
      },
    );
  }

  Widget _circles(
    ThemeData theme,
    AppLocalizations l10n, {
    required int faces,
  }) {
    final hidden = holders.length - faces;
    final circles = faces + (hidden > 0 ? 1 : 0);

    return SizedBox(
      width: _widthFor(circles),
      height: _diameter,
      child: Stack(
        children: [
          for (var i = 0; i < circles; i++)
            Positioned(
              left: i * (_diameter - _overlap),
              child: Container(
                // A ring in the surface colour, because a dark avatar over a
                // dark poster is one shape rather than two — and posters are
                // arbitrary images, so there is no colour to design against.
                padding: const EdgeInsets.all(_ring),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                ),
                child: i < faces
                    ? UserAvatar(
                        name: holders[i].name,
                        avatarUrl: holders[i].avatarUrl,
                        radius: _radius,
                        // `CircleAvatar` sizes its letter for a 40dp avatar
                        // whatever the radius, so the fallback needs telling.
                        textStyle: theme.textTheme.labelSmall,
                      )
                    : _MoreCircle(
                        label: l10n.libraryHoldersMore(hidden),
                        radius: _radius,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// How many circles the width handed down will take.
  static int _slotsIn(double width) {
    if (!width.isFinite) return _maxFaces + 1;
    var slots = 0;
    while (slots < _maxFaces + 1 && _widthFor(slots + 1) <= width) {
      slots++;
    }
    return slots;
  }
}

/// The `+2` at the end of the row: the children who did not fit.
///
/// A circle rather than a chip so it overlaps into the row like everything
/// else, and so its width is the same known quantity — a text-sized chip would
/// make the fit arithmetic an estimate.
class _MoreCircle extends StatelessWidget {
  const _MoreCircle({required this.label, required this.radius});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        // Two digits at a large text scale would otherwise spill out of the
        // circle: a household of twelve is unusual, not impossible.
        child: FittedBox(
          child: Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item, required this.serverUrl});

  final LibraryItem item;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          item.isCollection ? Icons.collections_outlined : Icons.movie_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final tag = item.primaryImageTag;
    if (tag == null) return placeholder;

    final base =
        serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;

    return CachedNetworkImage(
      // The tag is what makes the URL change when the artwork does; without it
      // a cached poster would outlive the picture it shows.
      imageUrl: '$base/Items/${item.id}/Images/Primary?tag=$tag',
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
