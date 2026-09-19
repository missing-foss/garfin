// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/country_lookup.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/repositories/app_settings_store.dart';
import 'package:garfin/widgets/item_detail_head.dart';

/// The detail head on the assign sheet (#145, #155, #160, #161).
///
/// Two things it must not do: show an absent value in any form — ruled on
/// #160, an absent value does not appear at all — and claim a duration or a
/// country for an item that cannot have one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  LibraryItem film({
    String type = 'Movie',
    int? year = 2019,
    int? ticks = 70030000,
    List<String> countries = const ['United States'],
    String? rating = 'PG-13',
    double? audience,
    double? critics,
    List<String> genres = const [],
    List<String> studios = const [],
  }) => LibraryItem(
    id: 'i1',
    name: 'Paddington',
    type: type,
    tags: const [],
    productionYear: year,
    runTimeTicks: ticks,
    productionLocations: countries,
    officialRating: rating,
    communityRating: audience,
    criticRating: critics,
    genres: genres,
    studios: studios,
  );

  /// Minutes, in the server's 100ns units.
  int minutes(int m) => m * 60 * 10000000;

  /// The server's list, in the shape 12.1 answers it: `Name` is the code.
  /// No Australia, deliberately, so a name the lookup cannot place exists.
  final countries = CountryLookup.fromRows([
    for (final (code, three, name) in const [
      ('FR', 'FRA', 'France'),
      ('SE', 'SWE', 'Sweden'),
      ('US', 'USA', 'United States'),
      ('DE', 'DEU', 'Germany'),
    ])
      {
        'Name': code,
        'DisplayName': name,
        'TwoLetterISORegionName': code,
        'ThreeLetterISORegionName': three,
      },
  ]);
  final fr = CountryLookup.flagEmoji('FR')!;
  final us = CountryLookup.flagEmoji('US')!;
  final de = CountryLookup.flagEmoji('DE')!;

  Future<AppLocalizations> pump(
    WidgetTester tester,
    LibraryItem item, {
    Locale locale = const Locale('en'),
  }) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
                return ItemDetailHead(
                session: session,
                item: item,
                posterSize: PosterSize.regular,
                ladderNames: const {'G', 'PG', 'PG-13', 'R', 'TV-PG'},
                countries: countries,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return l10n;
  }

  testWidgets('the year and duration are one line, the country a flag under '
      'it, outside the card', (tester) async {
    await pump(tester, film(ticks: minutes(92)));

    expect(find.text('2019 \u2013 1h 32m'), findsOneWidget);
    expect(find.text(us), findsOneWidget);
    expect(
      tester.getRect(find.text(us)).top,
      greaterThan(tester.getRect(find.text('2019 \u2013 1h 32m')).bottom),
      reason: 'below the year line (#166)',
    );
    expect(
      find.descendant(of: find.byType(Card), matching: find.text(us)),
      findsNothing,
      reason: 'the country left the card (#166)',
    );
    expect(
      find.descendant(
        of: find.byType(Card),
        matching: find.textContaining('2019'),
      ),
      findsNothing,
      reason: 'the year left the card (#161)',
    );
  });

  testWidgets('the duration reads the same in English and French', (
    tester,
  ) async {
    // Ruled on #161: `1h 39m` whatever the language. The old strings read
    // `1 h 39 min` in both, so a test pumping one locale could not tell a
    // translated format from a fixed one.
    await pump(tester, film(ticks: minutes(99)));
    expect(find.text('2019 \u2013 1h 39m'), findsOneWidget);

    await pump(tester, film(ticks: minutes(99)), locale: const Locale('fr'));
    expect(find.text('2019 \u2013 1h 39m'), findsOneWidget);
  });

  test('the duration format', () {
    // Each branch once. Dropping the hours-zero or minutes-zero test would
    // print `0h 39m` or `2h 0m`, and nothing else in this file uses a length
    // that reaches either branch.
    expect(ItemDetailHead.durationLabel(minutes(99)), '1h 39m');
    expect(ItemDetailHead.durationLabel(minutes(39)), '39m');
    expect(ItemDetailHead.durationLabel(minutes(120)), '2h');
    expect(ItemDetailHead.durationLabel(null), isNull);
    expect(ItemDetailHead.durationLabel(0), isNull);
  });

  testWidgets('with no duration the line is the year alone, no dash', (
    tester,
  ) async {
    await pump(tester, film(ticks: null));

    expect(find.text('2019'), findsOneWidget);
    expect(find.textContaining('\u2013'), findsNothing);
  });

  testWidgets('with no year the line is the duration alone', (tester) async {
    await pump(tester, film(year: null, ticks: minutes(39)));

    expect(find.text('39m'), findsOneWidget);
    expect(find.textContaining('\u2013'), findsNothing);
  });

  testWidgets('shows the rating alone when it names no system', (tester) async {
    await pump(tester, film(rating: 'PG-13'));

    expect(find.text('PG-13'), findsOneWidget,
        reason: 'a rung of the server ladder says nothing about a country');
  });

  testWidgets('names the system when the rating carries one', (tester) async {
    final l10n = await pump(tester, film(rating: 'FR-12'));

    expect(find.text(l10n.detailRatingWithCountry('12', 'FR')), findsOneWidget);
  });

  testWidgets('an absent value does not appear, and nothing left means no '
      'card and no line', (tester) async {
    final l10n = await pump(
      tester,
      film(year: null, ticks: null, countries: const [], rating: null),
    );

    // Ruled on #160, replacing #145's *Unknown*. Labels are tooltips now
    // (#166), so that is where their absence is checked: the text was never
    // drawn, and asserting it absent would pass on anything.
    expect(find.byType(Card), findsNothing);
    expect(find.byTooltip(l10n.detailRating), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(Text), findsNothing,
        reason: 'no title was given, and nothing else has a value');
  });

  testWidgets('one absent value drops its row and keeps the others', (
    tester,
  ) async {
    final l10n = await pump(tester, film(countries: const []));

    expect(find.text(us), findsNothing);
    expect(find.byTooltip(l10n.detailRating), findsOneWidget);
    expect(find.text('PG-13'), findsOneWidget);
  });

  testWidgets('the audience and critics scores, each on its own scale', (
    tester,
  ) async {
    final l10n = await pump(tester, film(audience: 8.3, critics: 89));

    expect(find.byTooltip(l10n.detailAudience), findsOneWidget);
    expect(find.text('8.3/10'), findsOneWidget);
    expect(find.byTooltip(l10n.detailCritics), findsOneWidget);
    expect(find.text('89%'), findsOneWidget);
    expect(find.text(l10n.detailAudience), findsNothing,
        reason: 'an icon, not a label (#166)');
  });

  testWidgets('a whole audience score still shows its decimal', (tester) async {
    await pump(tester, film(audience: 7));

    expect(find.text('7.0/10'), findsOneWidget);
  });

  testWidgets('every genre and studio, joined and never cut', (tester) async {
    final l10n = await pump(
      tester,
      film(
        genres: const ['Comedy', 'Romance'],
        studios: const ['One', 'Two', 'Three', 'Four', 'Five'],
      ),
    );

    // Genres are chips (#166): one each, not a joined string.
    expect(find.widgetWithText(Chip, 'Comedy'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Romance'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(l10n.detailGenres(2))), findsOneWidget);
    expect(find.byTooltip(l10n.detailStudios(5)), findsOneWidget);
    expect(find.text('One, Two, Three, Four, Five'), findsOneWidget);
  });

  testWidgets('one genre takes the singular label', (tester) async {
    final handle = tester.ensureSemantics();
    final l10n = await pump(tester, film(genres: const ['Comedy']));

    expect(l10n.detailGenres(1), isNot(l10n.detailGenres(2)),
        reason: 'otherwise this case proves nothing');
    // Anchored and followed by a non-letter: "Genre" is a prefix of "Genres".
    expect(
      find.bySemanticsLabel(RegExp('^${l10n.detailGenres(1)}(?![A-Za-z])')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a series: its country and scores show, and no duration is '
      'invented', (tester) async {
    // Measured 2026-09-18 on 12.1.0: a series carries `ProductionLocations`
    // and `CommunityRating`, and no `RunTimeTicks`.
    final l10n = await pump(
      tester,
      film(
        type: 'Series',
        year: 2018,
        ticks: null,
        countries: const ['Australia'],
        rating: 'TV-Y',
        audience: 9.3,
      ),
    );

    expect(find.text('2018'), findsOneWidget);
    // Not in this lookup, so the name, not a flag: unmatched is text.
    expect(find.text('Australia'), findsOneWidget);
    expect(find.text('9.3/10'), findsOneWidget);
    expect(find.byTooltip(l10n.detailCritics), findsNothing);
  });

  testWidgets('joins a co-production rather than picking one country', (
    tester,
  ) async {
    await pump(tester, film(countries: const ['Germany', 'France']));

    expect(find.text(de), findsOneWidget);
    expect(find.text(fr), findsOneWidget);
    expect(
      tester.getRect(find.text(de)).left,
      lessThan(tester.getRect(find.text(fr)).left),
      reason: 'in the order the server sent them',
    );
  });

  testWidgets('a name the lookup cannot place is shown as the name, beside '
      'the flags it can', (tester) async {
    await pump(tester, film(countries: const ['Soviet Union', 'France']));

    expect(find.text('Soviet Union'), findsOneWidget);
    expect(find.text(fr), findsOneWidget);
  });

  testWidgets('TMDB\'s "United States of America" finds its flag through the '
      'alias', (tester) async {
    // Measured on 12.1.0 with TMDB: the server's list says "United States".
    await pump(tester, film(countries: const ['United States of America']));

    expect(find.text(us), findsOneWidget);
    expect(find.text('United States of America'), findsNothing);
  });

  testWidgets('each flag is announced and long-pressed as its country', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, film(countries: const ['France']));

    expect(find.bySemanticsLabel('France'), findsOneWidget);
    expect(find.byTooltip('France'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('each icon is announced as its word', (tester) async {
    final handle = tester.ensureSemantics();
    final l10n = await pump(
      tester,
      film(audience: 8.3, critics: 89, studios: const ['StudioOne']),
    );

    // Anchored, so each is the *start* of its own node: merged into one, the
    // card would read as a single run of every label and only the first would
    // match. And each node carries its value with it.
    for (final (label, value) in [
      (l10n.detailRating, 'PG-13'),
      (l10n.detailAudience, '8.3/10'),
      (l10n.detailCritics, '89%'),
      (l10n.detailStudios(1), 'StudioOne'),
    ]) {
      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\\n?.*$value')),
        findsOneWidget,
        reason: '"$label" is its own fact, read with "$value"',
      );
    }
    handle.dispose();
  });

  test('the poster is bounded by the window height, not only its width', () {
    // Pixel 9: 412 x 923dp. A 600dp-tall window is the one that caught this —
    // at 210dp wide the poster is 315dp tall and Apply left the screen.
    const regular = PosterSize.regular;

    final onPixel9 = ItemDetailHead.posterWidthFor(
      regular,
      412,
      windowHeight: 923,
    );
    final onShort = ItemDetailHead.posterWidthFor(
      regular,
      412,
      windowHeight: 600,
    );

    expect(
      onPixel9,
      greaterThan(posterTargetWidth(regular)),
      reason: 'still larger than the grid poster where there is room',
    );
    expect(
      onShort,
      lessThan(onPixel9),
      reason: 'a short window shrinks the poster rather than burying Apply',
    );
    expect(
      onShort * 3 / 2,
      lessThanOrEqualTo(600 * 0.35),
      reason: 'at most 35% of the window height',
    );
  });

  group('the facts card (#155)', () {
    /// **No font is loaded here, deliberately.** An earlier version read
    /// Roboto out of the Flutter SDK by absolute path, which put one machine's
    /// home directory in the repository and made these four cases pass on that
    /// machine alone — caught in review.
    ///
    /// The default test font is a fixed-width block per glyph, so it is wider
    /// than Roboto for the same string: *Classification* is 14 glyphs, and at
    /// the old fixed 96dp column it wraps at any text size. That makes this a
    /// stricter regression test than the real font, and a portable one. The
    /// measurement that diagnosed the report — 84.3dp against 96, breaking at
    /// 1.14x — is recorded in the commit and on the issue, where a number
    /// belongs; a test only has to be able to fail.
    Future<void> pumpAt(
      WidgetTester tester, {
      required Locale locale,
      required double textScale,
    }) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: ItemDetailHead(
                session: session,
                item: film(ticks: minutes(92), audience: 8.3),
                posterSize: PosterSize.regular,
                title: const Text('Paddington'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the facts sit in a card', (tester) async {
      await pumpAt(tester, locale: const Locale('en'), textScale: 1);

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('the title, then the year and duration, both centred, '
        'between the poster and the facts', (tester) async {
      await pumpAt(tester, locale: const Locale('en'), textScale: 1);

      final title = tester.getRect(find.text('Paddington'));
      final line = tester.getRect(find.text('2019 \u2013 1h 32m'));
      final poster = tester.getRect(find.byType(AspectRatio).first);
      final card = tester.getRect(find.byType(Card));

      expect(title.top, greaterThan(poster.bottom));
      expect(line.top, greaterThanOrEqualTo(title.bottom));
      expect(line.bottom, lessThan(card.top));
      expect((title.center.dx - 412 / 2).abs(), lessThan(1),
          reason: 'title centred under the poster');
      expect((line.center.dx - 412 / 2).abs(), lessThan(1),
          reason: 'the line centred like the title (#161)');
    });

    testWidgets('the line is in the style the card uses for its values', (
      tester,
    ) async {
      await pumpAt(tester, locale: const Locale('en'), textScale: 1);

      final line = tester.widget<Text>(find.text('2019 \u2013 1h 32m'));
      // A value on an icon row: the card's values since #166, the rating
      // being a badge in the label style.
      final value = tester.widget<Text>(find.text('8.3/10'));

      expect(line.style, isNotNull);
      expect(line.style, value.style,
          reason: 'moved out of the card, same font and size (#161)');
    });

    // The French *Classification* label that wrapped at 1.14x (#155) is not
    // drawn any more: the card's labels became tooltips and semantics (#166),
    // so there is no label column left to wrap. The test for it went with it.

    testWidgets('every value is on one line at 1.3x', (tester) async {
      await pumpAt(tester, locale: const Locale('fr'), textScale: 1.3);

      for (final text in [
        '2019 \u2013 1h 32m',
        'PG-13',
        '8.3/10',
      ]) {
        final p = tester.renderObject<RenderParagraph>(find.text(text));
        expect(p.size.height, lessThan(p.preferredLineHeight * 1.5),
            reason: '"$text" wrapped');
      }
    });
  });

  testWidgets('the poster is larger than the grid poster and never half the '
      'sheet', (tester) async {
    // Pixel 9 is the reference width the ruling names.
    const pixel9 = 412.0;

    for (final size in PosterSize.values) {
      final width = ItemDetailHead.posterWidthFor(size, pixel9);
      expect(
        width,
        lessThanOrEqualTo(pixel9 / 2),
        reason: '$size must not take the screen',
      );
      if (posterTargetWidth(size) * 1.2 <= pixel9 / 2) {
        expect(
          width,
          greaterThan(posterTargetWidth(size)),
          reason: '$size should be larger than the same poster on the grid',
        );
      }
    }
  });
}
