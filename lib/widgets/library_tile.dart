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
    this.givenBadge,
    this.note,
  });

  final LibraryEntry entry;

  /// One line under the title, for a tile that needs to explain why it is here.
  /// Used by the search results for a collection found through a member (#147).
  final String? note;

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

  /// How much of a set is theirs, for a collection tile.
  ///
  /// Supplied by the grid rather than fetched here: the count needs this set's
  /// membership, which is a request, and a tile that fetches is a tile that
  /// fetches once per rebuild. Null for a film, and for a collection when
  /// nobody is picked — there is no verb without a child.
  final Widget? givenBadge;

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
                // **A collection is outlined**, and that is the whole of how
                // it is told apart from a film.
                //
                // Two earlier answers did not survive a phone. A rounder
                // poster separates nothing — every poster already clips at 8,
                // so collections would need a *different* radius, and a few
                // pixels of curvature is a difference a parent has to look
                // for. A stack of two dimmer sheets behind the top-right
                // corner replaced it and reads clearly on a bench; reported
                // from a phone, it does not. Both failed the same way: a
                // difference in an unsaturated grey, in one corner, on a tile
                // that is ~83dp wide at four columns.
                //
                // The line is the whole silhouette rather than a corner, so
                // there is no size at which it is only in the part of the tile
                // the eye is not on, and it competes for no space — nothing
                // else here draws an outline, so it means one thing. Colour
                // does most of the work: the theme's tertiary tone is
                // already this screen's "worth a second look" colour, the one
                // the above-their-age hint uses. Gold was the other suggestion
                // and was set aside — the palette has none, and a colour
                // outside it for one marker is the kind of thing that spreads.
                //
                // **Foreground, not background.** The artwork fills the whole
                // rect, so a border painted behind it is a border nobody can
                // see — and it would look exactly like a colour that was too
                // faint.
                //
                // It does not replace the "{count} titles" badge: the line
                // says *a set*, the badge says *how big*. It says nothing a
                // screen reader is not already told either — `_collectionKind`
                // puts "Collection, 7 titles" second in the label — so this
                // adds no semantic node of its own.
                if (item.isCollection)
                  DecoratedBox(
                    key: const ValueKey('collection-outline'),
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.tertiary,
                        width: _collectionOutline,
                      ),
                    ),
                    child: _clippedPoster(item),
                  )
                else
                  _clippedPoster(item),
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
                  // Pinned to the tile again. These carried an offset while a
                  // collection's poster was inset for the sheets behind it;
                  // with the line drawn *on* the poster there is no inset, and
                  // the corners are the tile's own at every width.
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
                      // **The set's badge, and the child's share inside it.**
                      // With a child picked this reads "3/6" beside a ring;
                      // without one it reads "6 titles" as before.
                      //
                      // One badge rather than two because all four corners of
                      // this poster are already spoken for — state top-left,
                      // faces top-right, age hint bottom-left, this one
                      // bottom-right — and the share is the same subject as
                      // the count. It replaced a 14dp ring under the title,
                      // which was sized to *fit* at 83dp and was reported
                      // unnoticeable on a phone: fitting was the wrong target.
                      //
                      // **`??` is not enough to fall back on, and the count's
                      // guard is not this one's.** [givenBadge] is a widget
                      // that decides at build time whether it has anything to
                      // say, so it is non-null on paths where it draws
                      // nothing; and the share needs a child, not a
                      // `ChildCount`. Both mistakes were made here at once —
                      // see [collectionCountBadge] for where the fallback
                      // actually lives now.
                      if (item.isCollection)
                        ?(givenBadge ?? collectionCountBadge(context, item)),
                      // **A series says how many episodes it holds**, in the
                      // same corner and for the same reason a collection says
                      // how many titles — asked for directly, on the strength
                      // of the collection badge.
                      //
                      // A separate branch rather than a shared one, because
                      // the number is a different field and the noun is not
                      // interchangeable. `ChildCount` on a series is the
                      // **seasons** — measured, a two-season five-episode show
                      // reports 2 — so reusing the collection badge would put
                      // "2 titles" on a show that holds five of neither.
                      //
                      // No share badge here. A series is one item to give and
                      // its label reaches every episode inside, so there is no
                      // partial state for a ring to describe; the collection's
                      // `3/6` exists because a set can be half given.
                      ?(item.isSeries ? episodeCountBadge(context, item) : null),
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
          // **Why a row a parent did not search for is on the grid** (#147).
          // A set whose *member* matched is added to the results, and without
          // this line it reads as the app answering a different question.
          if (note != null)
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  /// The plain size of a set — "6 titles" — for the corner the child's share
  /// otherwise owns.
  ///
  /// **Static because the fallback has to be handed to the widget that knows
  /// whether it drew.** The share is a `ConsumerWidget` watching one
  /// membership request, so "has it anything to say" is not answerable until
  /// its own build: `givenBadge ?? count` asks whether the *widget* is null,
  /// which it is not, and the corner came out blank for every collection tile
  /// between first paint and its membership arriving — permanently, if that
  /// request failed. The grid passes this in as the share's silent form, and
  /// the same widget then owns the corner in every state.
  ///
  /// Null when the server sent no `ChildCount`. That is not zero — it means
  /// the field was not asked for — and those collections stay on the grid
  /// (#110), so the caller decides what an unknown size looks like rather than
  /// this inventing a number. It must not gate the *share*, which needs a
  /// child and no count at all.
  static Widget? collectionCountBadge(BuildContext context, LibraryItem item) {
    final count = item.childCount;
    if (count == null) return null;
    return _Badge(
      label: AppLocalizations.of(context).libraryCollectionCount(count),
      tone: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }

  /// How many episodes a show holds — "5 episodes".
  ///
  /// **[LibraryItem.recursiveItemCount], not [LibraryItem.childCount].** The
  /// second counts one level down, which for a series is its seasons; the badge
  /// wants what is inside, which is what a label on the series reaches.
  ///
  /// Null when the server sent no recursive count, on the same reasoning as
  /// [collectionCountBadge]: absent means it was not asked for, and a corner
  /// left empty is better than a number invented for it. Measured on 10.11.11,
  /// a `Movie` reports the field absent even when it is requested, so this can
  /// never put an episode count on a film.
  static Widget? episodeCountBadge(BuildContext context, LibraryItem item) {
    final count = item.recursiveItemCount;
    if (count == null) return null;
    return _Badge(
      label: AppLocalizations.of(context).libraryEpisodeCount(count),
      tone: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }

  /// The artwork, clipped. Identical for a film and for a collection — the
  /// line is drawn over it, not around a smaller poster.
  Widget _clippedPoster(LibraryItem item) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _Poster(item: item, serverUrl: serverUrl),
      );

  /// The age hint, or null when there is nothing useful to say.
  ///
  /// **The hint speaks only when a title is above the selected child's age.**
  /// Silent with no child selected — there is no age to compare against —
  /// silent when the title suits, and silent when nothing can be said.
  String? _ageHint(AppLocalizations l10n) {
    if (childName == null) return null;
    return switch (suitability) {
      AgeSuitability.aboveAge => l10n.libraryHintAboveAge(childName!),
      // **Nothing for unknown**, on the same argument that already silences
      // `suitsAge`: the hint is for the titles worth a second look, and a
      // badge on most of the grid is something the eye has to skip past to
      // find the ones that mean anything. Asked for directly — "if there are
      // no classifications then it shouldn't show anything, we are only
      // interested by classifications".
      //
      // This is the grid badge only. The same string is a *value* in a list on
      // the collection prompt and the assign sheet — "this member's rating:
      // none" — where blanking it would leave an empty cell rather than remove
      // noise, so those keep it.
      AgeSuitability.unknown => null,
      AgeSuitability.suitsAge => null,
    };
  }

  String? _badge(AppLocalizations l10n) => switch (entry.state) {
        // **Nothing for a plain share: the child's own face says it.** They
        // are a holder of this item, so their picture is already on the poster
        // — first in the row — and a badge beside it was the same fact twice.
        //
        // The two that stay are the two a face cannot express.
        // `givenButHidden` is the opposite of what a face implies: the label
        // is there and the server is still not showing the title, which is
        // the one state on this screen a parent most needs told. `blocked` is
        // a block-list child, and `holdersOf` only ever collects allow-list
        // children — they have no face here at any width, so the badge is the
        // only thing that could say it.
        LibraryItemState.given => null,
        LibraryItemState.givenButHidden => l10n.libraryBadgeHeldBack,
        LibraryItemState.blocked => l10n.libraryBadgeBlocked,
        // Not-given is the default state of the grid, and badging it would
        // put a marker on almost every tile — noise rather than signal. The
        // same argument now covers `given`, one state along.
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
    final kind = _collectionKind(l10n);
    if (entry.state == LibraryItemState.givenButHidden && childName != null) {
      return <String>[
        name,
        ?kind,
        l10n.libraryHeldBackExplanation(childName!),
        ?shared,
      ].join('. ');
    }
    final parts = <String>[
      name,
      ?kind,
      ?_badge(l10n),
      ?_ageHint(l10n),
      ?shared,
    ];
    return parts.join('. ');
  }

  /// That this tile is a set, and how big (#99).
  ///
  /// Second, right after the name, because it is what the thing *is* — every
  /// part after it describes what has been done with it.
  ///
  /// **Spoken whatever the selection is**, unlike the badge and the held-back
  /// sentence. Those are claims about a child and wait for the feed to be that
  /// child's (#96); this describes the item, and is as true with nobody picked.
  ///
  /// **Says the noun, not just the number.** The bare count is what the visual
  /// badge already is, and "seven titles" leaves a screen reader user to infer
  /// the kind from whether the title happens to contain the word "Collection" —
  /// which is the library's metadata, not this app's.
  ///
  /// Degrades to the noun alone when the server sent no `ChildCount`: the field
  /// is absent unless `Fields=ChildCount` is asked for, and the badge is
  /// suppressed in that state too, so "0 titles" would be this label inventing
  /// a number nobody sent.
  String? _collectionKind(AppLocalizations l10n) {
    if (entry.item.isSeries) {
      // The same shape one step along: a show is as much "not a film" as a set
      // is, and the badge that says so visually is not spoken.
      final episodes = entry.item.recursiveItemCount;
      return episodes == null
          ? l10n.librarySemanticSeriesAlone
          : l10n.librarySemanticSeries(episodes);
    }
    if (!entry.item.isCollection) return null;
    final count = entry.item.childCount;
    return count == null
        ? l10n.librarySemanticCollectionAlone
        : l10n.librarySemanticCollection(count);
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
    // **The selected child is dropped only when the badge speaks about them.**
    // That was always the rule — `DECISIONS.md` states it — and it used to be
    // unconditional because the badge always did. It no longer does: a plain
    // share says so with a face, and a face is not spoken.
    //
    // Left unconditional, a tile with Emma selected and Léo also holding it
    // said "Given to Léo" and nothing about Emma, which reads as *not given to
    // Emma* — a confident wrong statement about a named child, which is the
    // shape ground rule 4 exists to prevent.
    final spokenFor = _badge(l10n) != null;
    final named = spokenFor
        ? holders.where((h) => h.userId != childId)
        : holders;
    if (named.isEmpty) return null;
    return l10n.libraryHolders(named.map((h) => h.name).join(', '));
  }
}

/// How thick the line around a collection's poster is.
///
/// 2 rather than 1: this is the third attempt at telling a set from a film and
/// the first two were each lost to a phone screen, so the number is chosen to
/// be seen at 83dp — a hairline is what "too subtle" already looked like.
/// Thicker starts eating the artwork it is framing.
const double _collectionOutline = 2;

/// The faces along the top edge of a poster.
///
/// Discreet by design: 22dp circles, overlapped, three at most, plus a `+N`
/// circle for the rest. The tile's job is the title; this is a glance-level
/// answer to "who already has this", which is the question a parent has
/// *before* picking a child
///
/// **The count adapts to width; above 200dp the size does too.** Tile width is
/// the grid's `maxCrossAxisExtent`, so it is capped by the poster-size setting
/// at 112, 175 or 360 -- small and regular never cross 200 at any window size,
/// and only "large" scales, on a phone as much as on a tablet. Holding 22dp
/// there left the faces at a sixteenth of the poster they annotate.
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

  /// Below this the row is exactly the size it has always been.
  ///
  /// The trigger is the poster-size setting, not the device: tile width is
  /// `maxCrossAxisExtent`, so it is capped at the target the setting picks --
  /// 112, 175 or 360. Small and regular never reach 200 and are untouched at
  /// any window size. Only "large" posters scale, and they do so on a phone
  /// too, which is where a 22dp face in a 360dp poster looks least considered.
  static const _scaleFrom = 200.0;

  /// 1.6 lands a large poster's faces at ~35dp. Past that the row starts
  /// competing with the title rather than annotating it.
  static const _maxScale = 1.6;

  /// Unbounded width means an unconstrained parent, not a huge tile, so it
  /// scales by nothing -- the same reading [_slotsIn] gives it.
  static double _scaleFor(double width) =>
      width.isFinite ? (width / _scaleFrom).clamp(1.0, _maxScale) : 1.0;

  /// The width [count] circles need: each costs the uncovered part, and the
  /// last one shows whole.
  static double _widthFor(int count, [double scale = 1.0]) => count <= 0
      ? 0
      : (count - 1) * (_diameter * scale - _overlap * scale) +
            _diameter * scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (holders.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // How many circles fit, one more than the faces because the `+N` is
        // one too.
        final scale = _scaleFor(constraints.maxWidth);
        final slots = _slotsIn(constraints.maxWidth, scale);
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
          scale: scale,
        );
      },
    );
  }

  Widget _circles(
    ThemeData theme,
    AppLocalizations l10n, {
    required int faces,
    required double scale,
  }) {
    final hidden = holders.length - faces;
    final circles = faces + (hidden > 0 ? 1 : 0);

    return SizedBox(
      width: _widthFor(circles, scale),
      height: _diameter * scale,
      child: Stack(
        children: [
          for (var i = 0; i < circles; i++)
            Positioned(
              left: i * (_diameter * scale - _overlap * scale),
              child: Container(
                // A ring in the surface colour, because a dark avatar over a
                // dark poster is one shape rather than two — and posters are
                // arbitrary images, so there is no colour to design against.
                padding: EdgeInsets.all(_ring * scale),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                ),
                child: i < faces
                    ? UserAvatar(
                        name: holders[i].name,
                        avatarUrl: holders[i].avatarUrl,
                        radius: _radius * scale,
                        // `CircleAvatar` sizes its letter for a 40dp avatar
                        // whatever the radius, so the fallback needs telling.
                        textStyle: theme.textTheme.labelSmall,
                      )
                    : _MoreCircle(
                        label: l10n.libraryHoldersMore(hidden),
                        radius: _radius * scale,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// How many circles the width handed down will take.
  static int _slotsIn(double width, [double scale = 1.0]) {
    if (!width.isFinite) return _maxFaces + 1;
    var slots = 0;
    while (slots < _maxFaces + 1 && _widthFor(slots + 1, scale) <= width) {
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
