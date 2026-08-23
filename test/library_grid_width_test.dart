// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/app_settings_store.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/widgets/library_grid.dart';
import 'package:garfin/widgets/library_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How wide a poster actually comes out, at widths nobody had run (#95).
///
/// The old rule mapped the setting to a fixed column count with no upper bound,
/// so the same three columns were used at 412dp and at 1280dp and the tiles
/// simply inflated — measured on paper at 408dp wide and ~703dp tall, against a
/// viewport of ~800dp, so not one complete row fitted. Nothing errored, which is
/// why arithmetic alone never caught it.
///
/// So these **measure the rendered tile** rather than re-deriving Flutter's
/// delegate arithmetic in the test. A test that recomputed
/// `ceil(extent / (max + spacing))` would agree with a broken delegate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  /// Enough tiles that the first row is always full at every width tested.
  final entries = [
    for (var i = 0; i < 40; i++)
      LibraryEntry(
        item: LibraryItem(id: 'i$i', name: 'Film $i', type: 'Movie', tags: const []),
        state: LibraryItemState.notGiven,
      ),
  ];

  /// The rendered width of one poster tile, and how many share the top row.
  Future<(double, int)> render(
    WidgetTester tester, {
    required double width,
    required PosterSize size,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    // Written through the store rather than by guessing its key: the plugin
    // prefixes keys, and a wrong guess reads as "the default", which is a
    // *plausible* answer rather than an error — every size would silently
    // render as regular and three assertions would fail for one reason.
    await AppSettingsStore(prefs).setPosterSize(size);

    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kidsOverviewProvider(session).overrideWith(
            (ref) async => const KidsOverview(
              shortlisted: [],
              withoutShortlist: <UnshortlistedUser>[],
            ),
          ),
          parentalRatingLadderProvider(session)
              .overrideWith((ref) async => const ParentalRatingLadder.empty()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LibraryGrid(
              session: session,
              entries: entries,
              child: null,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tiles = find.byType(LibraryTile);
    final first = tester.getRect(tiles.first);
    // Everything sharing the first tile's top edge is its row.
    final columns = tester
        .widgetList<LibraryTile>(tiles)
        .indexed
        .where((e) => tester.getRect(tiles.at(e.$1)).top == first.top)
        .length;
    return (first.width, columns);
  }

  group('the phone is unchanged', () {
    testWidgets('412dp keeps 2/3/4 columns and the same tile width',
        (tester) async {
      // Destructured, not compared as a record: a matcher inside a record
      // literal is compared as an object, so `(closeTo(184), 2)` passes only if
      // the value literally *is* that matcher — it never asserts the width.
      final (largeW, largeC) =
          await render(tester, width: 412, size: PosterSize.large);
      expect(largeW, closeTo(184, 0.5));
      expect(largeC, 2);

      final (regularW, regularC) =
          await render(tester, width: 412, size: PosterSize.regular);
      expect(regularW, closeTo(118.7, 0.5));
      expect(regularC, 3);

      final (smallW, smallC) =
          await render(tester, width: 412, size: PosterSize.small);
      expect(smallW, closeTo(86, 0.5));
      expect(smallC, 4);
    });

    /// **393dp is a Pixel 4a / 5 / 5a**, and it sits inside the band the first
    /// draft of these targets got wrong: 360 and 412 agreed with the old
    /// mapping, so both sample points passed while everything between them had
    /// changed. At the default setting that draft gave three columns of 112dp
    /// here instead of two of 174.5 — 36% smaller posters, on hardware people
    /// hold, which is the exact thing the deleted below-400dp rule existed to
    /// prevent. Caught in review; this is what keeps it caught.
    testWidgets('393dp — a real phone inside the old rule\'s band',
        (tester) async {
      final (smallW, smallC) =
          await render(tester, width: 393, size: PosterSize.small);
      expect(smallC, 3);
      expect(smallW, closeTo(112.3, 0.5));

      final (regularW, regularC) =
          await render(tester, width: 393, size: PosterSize.regular);
      expect(regularC, 2);
      expect(regularW, closeTo(174.5, 0.5));

      final (largeW, largeC) =
          await render(tester, width: 393, size: PosterSize.large);
      expect(largeC, 1);
      expect(largeW, closeTo(361, 0.5));
    });

    /// The band that *did* move, pinned deliberately rather than left to be
    /// discovered. The old cliff was at exactly 400dp; the continuous rule
    /// crosses over at ~406, so 400–406 now gets one column fewer than the old
    /// mapping gave it. Posters get bigger, which is the safe direction — but
    /// it is a change, and `docs/UI-SPEC.md` says so.
    testWidgets('400dp now behaves as narrow, where it used to not',
        (tester) async {
      expect((await render(tester, width: 400, size: PosterSize.regular)).$2, 2);
      expect((await render(tester, width: 406, size: PosterSize.regular)).$2, 2);
      // ...and the crossover has happened by the phone the app was designed on.
      expect((await render(tester, width: 412, size: PosterSize.regular)).$2, 3);
    });

    /// The old below-400dp rule dropped a column because three posters across a
    /// small phone are stamps. It is no longer written down anywhere — a narrow
    /// window simply fits fewer targets — so this is what keeps it true.
    testWidgets('360dp still loses a column at every size', (tester) async {
      expect((await render(tester, width: 360, size: PosterSize.large)).$2, 1);
      expect((await render(tester, width: 360, size: PosterSize.regular)).$2, 2);
      expect((await render(tester, width: 360, size: PosterSize.small)).$2, 3);
    });
  });

  group('the tablet stops inflating', () {
    /// The regression this issue is about. Before #95 this tile was **408dp**
    /// wide — 3.4x the phone it was designed for.
    testWidgets('1280dp never draws a poster wider than its target',
        (tester) async {
      for (final size in PosterSize.values) {
        final (tileWidth, columns) =
            await render(tester, width: 1280, size: size);
        expect(
          tileWidth,
          lessThanOrEqualTo(posterTargetWidth(size)),
          reason: '$size inflated past its target at 1280dp',
        );
        expect(columns, greaterThan(2), reason: '$size wasted a wide window');
      }
    });

    /// The point of a target rather than a count: a poster is about the same
    /// size on a phone and on a tablet, and the tablet simply shows more of
    /// them. Pinned as a ratio so it survives the numbers being retuned.
    testWidgets('a poster is close to phone-sized at 1280dp', (tester) async {
      final (phone, _) = await render(tester, width: 412, size: PosterSize.regular);
      final (tablet, columns) =
          await render(tester, width: 1280, size: PosterSize.regular);

      expect(tablet / phone, lessThan(1.5));
      // At least double the phone's three, rather than a fitted count: the
      // claim is "a tablet shows more of them", and a number tuned to one
      // target silently becomes wrong the moment the target is retuned — which
      // is exactly what happened to this line in review.
      expect(columns, greaterThanOrEqualTo(6));
    });

    /// Split-screen and folded foldables arrive as a narrow *window*, and the
    /// grid reads the space it is given rather than the display — so a wide
    /// window handed a narrow parent must still be right.
    testWidgets('a narrow parent inside a wide window is respected',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            kidsOverviewProvider(session).overrideWith(
              (ref) async => const KidsOverview(
                shortlisted: [],
                withoutShortlist: <UnshortlistedUser>[],
              ),
            ),
            parentalRatingLadderProvider(session)
                .overrideWith((ref) async => const ParentalRatingLadder.empty()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 412,
                  child: LibraryGrid(
                    session: session,
                    entries: entries,
                    child: null,
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The phone answer, from a 1280dp window — which the old code could not
      // give, because it read `MediaQuery` rather than its own constraints.
      expect(
        tester.getRect(find.byType(LibraryTile).first).width,
        closeTo(118.7, 0.5),
      );
    });
  });
}
