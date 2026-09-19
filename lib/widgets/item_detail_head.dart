// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/country_lookup.dart';
import '../models/library_item.dart';
import '../models/rating_origin.dart';
import '../repositories/app_settings_store.dart';
import 'phosphor_glyphs.dart';

/// The head of the assign sheet: the poster the parent just tapped, its title,
/// the year and running time on one line under it, the country as flags on the
/// next, and a card of the other facts that help them decide.
///
/// **Icons and a badge, not labels** (#166): the rating is an outlined badge,
/// the genres are chips, and the scores and studios carry Phosphor icons. The
/// words are not gone — each one is the tooltip on long-press and the label a
/// screen reader announces.
///
/// **Films and series** (#160). A `BoxSet` stays out, as ruled on #145.
///
/// **An absent value does not appear at all** — not as *Unknown*, not as a
/// blank row. Ruled on #160 for everything on the item sheet, replacing the
/// #145 rule. A series with no running time shows its year alone; an item with
/// nothing for the card has no card.
class ItemDetailHead extends StatelessWidget {
  const ItemDetailHead({
    super.key,
    required this.session,
    required this.item,
    required this.posterSize,
    this.title,
    this.ladderNames = const {},
    this.countries = const CountryLookup.empty(),
  });

  final AuthSession session;
  final LibraryItem item;
  final PosterSize posterSize;

  /// Drawn centred between the poster and the facts (#155). The sheet used to
  /// own this and drew it *below* the whole block, left-aligned, because the
  /// block was added above an existing title.
  final Widget? title;

  /// The rungs of the server's own ladder, for [ratingCountryCode].
  final Set<String> ladderNames;

  /// The server's country list: its codes for [ratingCountryCode], and the
  /// code behind each country name for the flags.
  final CountryLookup countries;

  /// Wider than the grid's poster, and bounded twice.
  ///
  /// Ruled: *"slightly larger than the poster on the library grid … shouldn't
  /// take the whole screen"*, with a Pixel 9 as the reference — about 412 x
  /// 923dp. The grid's target is the parent's own poster-size setting, so this
  /// follows it rather than hard-coding a number: at the default, 175 → 210dp.
  ///
  /// **The height bound is the one that matters, and it was not obvious.** The
  /// sheet holds this block, the title, a row per child and the Apply button,
  /// and it is the button that pays for anything added above it. At 210dp wide
  /// the poster is 315dp tall, which pushed Apply off a 600dp-tall viewport
  /// entirely — caught by `assign_apply_feedback_test`, which tapped a button
  /// that was no longer on screen. So the poster also takes at most 35% of the
  /// window's height: 323dp on a Pixel 9, which still leaves it larger than the
  /// grid's, and on a short window it shrinks rather than burying the button.
  static double posterWidthFor(
    PosterSize size,
    double available, {
    double? windowHeight,
  }) {
    final target = posterTargetWidth(size) * 1.2;
    final widthCap = available * 0.5;
    // 2:3 artwork, so a height budget is two-thirds of it in width.
    final heightCap = windowHeight == null
        ? double.infinity
        : windowHeight * 0.35 * 2 / 3;
    return [target, widthCap, heightCap].reduce((a, b) => a < b ? a : b);
  }

  /// Hours and minutes from the server's 100-nanosecond units: `1h 39m`,
  /// `39m`, `2h`.
  ///
  /// **The same in every language, so not a translation** (#161, ruled). It
  /// used to be two localised strings that read `1 h 39 min` in both.
  ///
  /// Null when the server has no duration for the item, which is what a file
  /// with no media streams answers — see `LibraryItem.runTimeTicks`.
  static String? durationLabel(int? ticks) {
    if (ticks == null || ticks <= 0) return null;
    final minutes = Duration(microseconds: ticks ~/ 10).inMinutes;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// The line under the title: `1991 – 1h 39m`, or whichever half exists, or
  /// null when neither does and the line is not drawn (#161).
  ///
  /// An en dash with a space either side, as ruled.
  static String? yearAndDuration(LibraryItem item) {
    final parts = [
      if (item.productionYear case final year?) '$year',
      ?durationLabel(item.runTimeTicks),
    ];
    return parts.isEmpty ? null : parts.join(' \u2013 ');
  }

  /// The country line: a flag for each name the lookup can place, and the
  /// name itself for any it cannot (#166).
  ///
  /// **Unmatched is text, never a wrong flag and never a blank.** Measured on
  /// 12.1.0 with TMDB: seven names of eight matched the server's list; the
  /// eighth needed an alias. A historical country has no flag at all.
  static List<CountryMark> countryMarks(
    LibraryItem item,
    CountryLookup countries,
  ) => [
    for (final name in item.productionLocations)
      if (name.trim().isNotEmpty)
        CountryMark(
          name: name,
          flag: switch (countries.codeFor(name)) {
            final code? => CountryLookup.flagEmoji(code),
            null => null,
          },
        ),
  ];

  /// The rating, and whose it is **only when the rating itself says so**.
  ///
  /// Ruled on #142, option 2. A rating that is a rung on the server's ladder
  /// says nothing about a country — the ladder is the server's setting, not a
  /// property of the film — so `PG-13` shows alone. `FR-12` shows as
  /// `12 (FR)`, because that string names its system.
  ///
  /// The code rather than a flag, here: the flag belongs to where a film was
  /// made, on the line above, and a flag inside the badge would read as the
  /// same fact twice.
  static String? _rating(
    AppLocalizations l10n,
    String? rating,
    Set<String> ladderNames,
    Set<String> countryCodes,
  ) {
    if (rating == null || rating.trim().isEmpty) return null;
    final code = ratingCountryCode(
      rating,
      ladderNames: ladderNames,
      countryCodes: countryCodes,
    );
    if (code == null) return rating;
    return l10n.detailRatingWithCountry(rating.substring(3), code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final rating = _rating(
      l10n,
      item.officialRating,
      ladderNames,
      countries.codes,
    );
    final marks = countryMarks(item, countries);
    final card = _FactCard(item: item, rating: rating, theme: theme, l10n: l10n);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = posterWidthFor(
          posterSize,
          constraints.maxWidth,
          windowHeight: MediaQuery.sizeOf(context).height,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SizedBox(
                width: width,
                // The grid's own ratio, so the same artwork is not a different
                // shape in the two places it appears.
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _Poster(session: session, item: item),
                ),
              ),
            ),
            if (title != null) ...[
              const SizedBox(height: 12),
              Center(child: title),
            ],
            // The card's own value style, so moving these two out of it (#161)
            // changed where they sit and nothing about how they read.
            if (yearAndDuration(item) case final line?) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  line,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
            if (marks.isNotEmpty) ...[
              const SizedBox(height: 6),
              _CountryLine(marks: marks, theme: theme),
            ],
            if (card.hasContent) ...[
              const SizedBox(height: 12),
              card,
            ],
          ],
        );
      },
    );
  }
}

/// One country on the flag line: its name, and its flag when there is one.
class CountryMark {
  const CountryMark({required this.name, this.flag});

  final String name;

  /// Null when the name could not be placed; the name is shown instead.
  final String? flag;
}

class _CountryLine extends StatelessWidget {
  const _CountryLine({required this.marks, required this.theme});

  final List<CountryMark> marks;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final mark in marks)
          // The name is the tooltip and what a screen reader says: a flag alone
          // is ambiguous to many readers, and to every screen reader.
          Tooltip(
            message: mark.name,
            child: switch (mark.flag) {
              final flag? => Text(
                flag,
                semanticsLabel: mark.name,
                style: theme.textTheme.titleLarge,
              ),
              null => Text(mark.name, style: theme.textTheme.bodyMedium),
            },
          ),
      ],
    );
  }
}

/// The card: the rating as a badge, the genres as chips, and the scores and
/// studios each behind an icon. **Every part is left out when the server has
/// no value for it** (#160), and with nothing left there is no card.
class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.item,
    required this.rating,
    required this.theme,
    required this.l10n,
  });

  final LibraryItem item;
  final String? rating;
  final ThemeData theme;
  final AppLocalizations l10n;

  bool get hasContent =>
      rating != null ||
      item.genres.isNotEmpty ||
      item.communityRating != null ||
      item.criticRating != null ||
      item.studios.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final audience = item.communityRating;
    final critics = item.criticRating;
    final value = theme.textTheme.bodyMedium;

    final rows = <Widget>[
      if (rating case final rating?)
        Align(
          alignment: AlignmentDirectional.centerStart,
          // One node per fact, read as "Rating, PG-13": without the merge, every
          // label in the card collapses into a single announcement.
          child: MergeSemantics(
            child: Tooltip(
            message: l10n.detailRating,
            child: Semantics(
              label: l10n.detailRating,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.onSurface, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(rating, style: theme.textTheme.labelLarge),
              ),
            ),
          ),
          ),
        ),
      // Every one, never cut (#160).
      if (item.genres.isNotEmpty)
        Semantics(
          container: true,
          label: l10n.detailGenres(item.genres.length),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final genre in item.genres)
                Chip(
                  label: Text(genre),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  labelStyle: theme.textTheme.labelMedium,
                ),
            ],
          ),
        ),
      // Out of ten with one decimal, and out of a hundred as a percentage: two
      // scales, so two formats (#160).
      if (audience != null)
        _IconFact(
          glyph: PhosphorGlyphs.usersThree,
          label: l10n.detailAudience,
          value: '${audience.toStringAsFixed(1)}/10',
          theme: theme,
          style: value,
        ),
      if (critics != null)
        _IconFact(
          glyph: PhosphorGlyphs.newspaper,
          label: l10n.detailCritics,
          value: '${critics.round()}%',
          theme: theme,
          style: value,
        ),
      if (item.studios.isNotEmpty)
        _IconFact(
          glyph: PhosphorGlyphs.buildings,
          label: l10n.detailStudios(item.studios.length),
          value: item.studios.join(', '),
          theme: theme,
          style: value,
        ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: rows,
        ),
      ),
    );
  }
}

/// An icon and its value. The icon's word is its tooltip and its semantics
/// label, so nothing a label said is lost to a parent who needs it.
class _IconFact extends StatelessWidget {
  const _IconFact({
    required this.glyph,
    required this.label,
    required this.value,
    required this.theme,
    required this.style,
  });

  final IconData glyph;
  final String label;
  final String value;
  final ThemeData theme;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // Merged so a screen reader says "Audience, 8.3/10" as one fact.
    return MergeSemantics(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: label,
          child: Icon(
            glyph,
            size: 20,
            semanticLabel: label,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        // Expanded, so a long list of studios wraps under itself rather than
        // running off the card.
        Expanded(child: Text(value, style: style)),
      ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.session, required this.item});

  final AuthSession session;
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tag = item.primaryImageTag;
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, color: theme.colorScheme.outline),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: tag == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl:
                  '${session.serverUrl}/Items/${item.id}/Images/Primary?tag=$tag',
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}
