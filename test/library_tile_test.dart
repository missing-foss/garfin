// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/age_suitability.dart';
import 'package:garfin/models/item_holder.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/widgets/library_tile.dart';
import 'package:garfin/widgets/user_avatar.dart';

/// What a tile actually says.
///
/// The claim worth pinning is the negative one: the scraper's tags are on the
/// model and must never reach the screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester,
    LibraryItemState state, {
    List<String> tags = const [],
    String? childName = 'Emma',
    String? childId,
    String type = 'Movie',
    int? childCount,
    AgeSuitability suitability = AgeSuitability.unknown,
    String? rating,
    List<ItemHolder> holders = const [],
    // A real tile: ~118dp at three columns, ~83dp at four, and 178dp at two
    // under 400dp. 160 is the historical default of these tests.
    double width = 160,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 300,
              child: LibraryTile(
                entry: LibraryEntry(
                  item: LibraryItem(
                    id: 'a',
                    name: 'Paddington',
                    type: type,
                    tags: tags,
                    childCount: childCount,
                    officialRating: rating,
                  ),
                  state: state,
                ),
                serverUrl: 'http://host:8096',
                childName: childName,
                childId: childId,
                holders: holders,
                suitability: suitability,
              ),
            ),
          ),
        ),
      );

  testWidgets('the scraper\'s tags never reach the screen', (tester) async {
    // Measured on 10.11.11: a film tagged for a child also carried
    // "kidnapping" and "alien abduction" from the metadata provider. Rendering
    // the tag list would put those under a child's face.
    await pump(
      tester,
      LibraryItemState.given,
      tags: const ['kidnapping', 'alien abduction', 'kids-emma'],
    );
    await tester.pumpAndSettle();

    expect(find.text('kidnapping'), findsNothing);
    expect(find.text('alien abduction'), findsNothing);
    expect(find.text('kids-emma'), findsNothing);
    expect(find.text('Paddington'), findsOneWidget);
  });

  testWidgets('given, held back and blocked each read differently',
      (tester) async {
    await pump(tester, LibraryItemState.given);
    await tester.pumpAndSettle();
    expect(find.text('Given'), findsOneWidget);

    await pump(tester, LibraryItemState.givenButHidden);
    await tester.pumpAndSettle();
    expect(find.text('Held back'), findsOneWidget);
    expect(find.text('Given'), findsNothing);

    await pump(tester, LibraryItemState.blocked);
    await tester.pumpAndSettle();
    expect(find.text('Blocked'), findsOneWidget);
  });

  testWidgets('not-given carries no badge, because most tiles are not-given',
      (tester) async {
    await pump(tester, LibraryItemState.notGiven);
    await tester.pumpAndSettle();

    expect(find.text('Given'), findsNothing);
    expect(find.text('Held back'), findsNothing);
    expect(find.text('Blocked'), findsNothing);
  });

  testWidgets('the held-back explanation offers a reason, never asserts one',
      (tester) async {
    // The server does not say why it hid an item — a folder permission looks
    // identical to a rating cap from here. A tile that asserted the cause would
    // send a parent to change the wrong setting.
    await pump(tester, LibraryItemState.givenButHidden);
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(find.byType(LibraryTile));
    expect(semantics.label, contains('the usual reason'));
    expect(semantics.label, isNot(contains('because')));
  });

  group('the age hint (#43)', () {
    testWidgets('above their age is said plainly, naming the child',
        (tester) async {
      await pump(tester, LibraryItemState.notGiven,
          suitability: AgeSuitability.aboveAge, rating: 'PG-13');
      await tester.pumpAndSettle();

      expect(find.text("Above Emma's age"), findsOneWidget);
    });

    testWidgets('not-known looks different from suitable, not absent',
        (tester) async {
      // The whole point of the third state. A helper that rendered "unknown"
      // as nothing would read as a pass on exactly the items — unrated ones —
      // where a parent most needs telling that Garfin cannot say.
      await pump(tester, LibraryItemState.notGiven,
          suitability: AgeSuitability.unknown);
      await tester.pumpAndSettle();
      expect(find.text('No age rating'), findsOneWidget);

      await pump(tester, LibraryItemState.notGiven,
          suitability: AgeSuitability.suitsAge, rating: 'G');
      await tester.pumpAndSettle();
      expect(find.text('No age rating'), findsNothing);
    });

    testWidgets('a suitable title is not badged — that is most of the grid',
        (tester) async {
      await pump(tester, LibraryItemState.notGiven,
          suitability: AgeSuitability.suitsAge, rating: 'G');
      await tester.pumpAndSettle();

      expect(find.textContaining('age'), findsNothing);
    });

    testWidgets('no child selected means no hint at all', (tester) async {
      // There is no age to compare against, so there is nothing to say.
      await pump(tester, LibraryItemState.unknown,
          childName: null, suitability: AgeSuitability.unknown);
      await tester.pumpAndSettle();

      expect(find.text('No age rating'), findsNothing);
    });

    testWidgets('the hint never removes the tile', (tester) async {
      // Ground rule 4's neighbour: this is advice, and advice does not filter.
      for (final s in AgeSuitability.values) {
        await pump(tester, LibraryItemState.notGiven, suitability: s);
        await tester.pumpAndSettle();
        expect(find.text('Paddington'), findsOneWidget,
            reason: 'the tile disappeared for $s');
      }
    });
  });

  group('the children who already have it (#84)', () {
    ItemHolder holder(String name, {String? avatarUrl}) =>
        ItemHolder(userId: 'id-$name', name: name, avatarUrl: avatarUrl);

    testWidgets('their pictures go on the poster', (tester) async {
      await pump(
        tester,
        LibraryItemState.unknown,
        childName: null,
        holders: [
          holder('Emma',
              avatarUrl: 'http://host:8096/Users/id-Emma/Images/Primary?tag=t1'),
          holder('Léo',
              avatarUrl: 'http://host:8096/Users/id-Leo/Images/Primary?tag=t2'),
        ],
      );
      await tester.pumpAndSettle();

      final images = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((i) => i.imageUrl)
          .toList();
      expect(images, contains(contains('/Users/id-Emma/Images/Primary')));
      expect(images, contains(contains('/Users/id-Leo/Images/Primary')));
    });

    testWidgets('with no child selected, which is the case it exists for',
        (tester) async {
      // The reason #84 was raised: a parent scanning the grid before picking
      // anyone gets nothing today. Every other marker on this tile is silent
      // without a selection, and this one must not be.
      await pump(
        tester,
        LibraryItemState.unknown,
        childName: null,
        holders: [holder('Emma')],
      );
      await tester.pumpAndSettle();

      expect(find.text('E'), findsOneWidget);
    });

    testWidgets('a child with no picture still gets their initial',
        (tester) async {
      // #79's fallback, reused rather than reimplemented.
      await pump(tester, LibraryItemState.unknown,
          childName: null, holders: [holder('Léo')]);
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('L'), findsOneWidget);
    });

    testWidgets('a title nobody has carries no row at all', (tester) async {
      await pump(tester, LibraryItemState.notGiven);
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('past three, the rest become a chip', (tester) async {
      // A poster is ~110dp wide on a 3-column grid. A fourth face leaves no
      // poster.
      await pump(
        tester,
        LibraryItemState.unknown,
        childName: null,
        holders: [
          holder('Emma'),
          holder('Léo'),
          holder('Sam'),
          holder('Ada'),
          holder('Zoé'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('E'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('exactly three faces need no chip', (tester) async {
      await pump(
        tester,
        LibraryItemState.unknown,
        childName: null,
        holders: [holder('Emma'), holder('Léo'), holder('Sam')],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('the faces fit inside the tile', (tester) async {
      // Three circles and a chip in one corner of a small poster: the row
      // overlaps to fit, and this is the assertion that catches it stopping to.
      await pump(
        tester,
        LibraryItemState.unknown,
        childName: null,
        holders: [holder('Emma'), holder('Léo'), holder('Sam'), holder('Ada')],
      );
      await tester.pumpAndSettle();

      final tile = tester.getRect(find.byType(LibraryTile));
      final chip = tester.getRect(find.text('+1'));
      expect(chip.right, lessThanOrEqualTo(tile.right));
      expect(tester.getRect(find.text('E')).left,
          greaterThanOrEqualTo(tile.left));
      expect(tester.takeException(), isNull);
    });

    group('and the badge beside them, on a tile with no room for both', () {
      // Rendered at 110dp, opposite corners collided: the faces painted
      // straight over "Held back", and nothing errored — the row simply won an
      // argument it should lose. Four columns is narrower still, ~83dp.

      testWidgets('the row gives way rather than painting over the badge',
          (tester) async {
        await pump(
          tester,
          LibraryItemState.givenButHidden,
          width: 83,
          holders: [
            holder('Emma'),
            holder('Léo'),
            holder('Sam'),
            holder('Ada'),
            holder('Zoé'),
          ],
        );
        await tester.pumpAndSettle();

        // The badge is the answer about the child the parent picked, so it
        // keeps its width. The faces are gone from the poster and still in the
        // sentence — see the semantics test below.
        expect(find.text('Held back'), findsOneWidget);
        expect(find.text('E'), findsNothing);
        // And *nothing* on the poster, not a bare count: a `+N` with no face
        // beside it would mean "N in total" where every other `+N` on the grid
        // means "N more than these". Asserting only the absent face would pass
        // for a lone `+5` too, which is the thing this pins.
        expect(find.textContaining('+'), findsNothing);
        expect(tester.takeException(), isNull);

        final semantics = tester.getSemantics(find.byType(LibraryTile));
        expect(semantics.label, contains('Given to Emma'));
      });

      testWidgets('at every width, nothing in the row lands on the badge',
          (tester) async {
        // Widths rather than one width, and an overlap check rather than a
        // count: how many circles fit depends on how wide the badge's text
        // measures, and the font in a widget test is not the font on the
        // phone. What must hold at *any* width is that the two never share a
        // pixel — which is exactly what the first attempt got wrong.
        for (final width in <double>[83, 110, 118, 178]) {
          await pump(
            tester,
            LibraryItemState.given,
            width: width,
            holders: [
              holder('Emma'),
              holder('Léo'),
              holder('Sam'),
              holder('Ada'),
              holder('Zoé'),
            ],
          );
          await tester.pumpAndSettle();

          final badge = tester.getRect(find.text('Given'));
          for (final face in find.byType(UserAvatar).evaluate()) {
            expect(
              badge.overlaps(tester.getRect(find.byWidget(face.widget))),
              isFalse,
              reason: 'a face landed on the badge at ${width}dp',
            );
          }
          for (final chip in find.textContaining('+').evaluate()) {
            expect(
              badge.overlaps(tester.getRect(find.byWidget(chip.widget))),
              isFalse,
              reason: 'the count landed on the badge at ${width}dp',
            );
          }
          // A `+N` never appears alone, at any width: without a face beside it
          // the same glyph would mean "N in total" rather than "N more".
          if (find.textContaining('+').evaluate().isNotEmpty) {
            expect(find.byType(UserAvatar), findsWidgets,
                reason: 'a bare count with no face at ${width}dp');
          }
          expect(tester.takeException(), isNull,
              reason: 'the top row overflowed at ${width}dp');
        }
      });

      testWidgets('room for more means more of them', (tester) async {
        // The other half of the same rule: giving way is a response to the
        // width, not a permanent retreat. Counting circles rather than naming
        // them keeps this independent of the test font too.
        Future<int> circlesAt(double width) async {
          await pump(
            tester,
            LibraryItemState.given,
            width: width,
            holders: [
              holder('Emma'),
              holder('Léo'),
              holder('Sam'),
              holder('Ada'),
              holder('Zoé'),
            ],
          );
          await tester.pumpAndSettle();
          return find.byType(UserAvatar).evaluate().length +
              find.textContaining('+').evaluate().length;
        }

        final narrow = await circlesAt(83);
        final wide = await circlesAt(178);
        expect(wide, greaterThan(narrow));
        expect(narrow, lessThanOrEqualTo(4));
      });

      testWidgets('no badge means the whole width is the row\'s',
          (tester) async {
        // The case #84 is about: no child selected, so no badge exists at all
        // and even an 83dp tile carries three faces and a count.
        await pump(
          tester,
          LibraryItemState.unknown,
          width: 83,
          childName: null,
          holders: [
            holder('Emma'),
            holder('Léo'),
            holder('Sam'),
            holder('Ada'),
            holder('Zoé'),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.text('E'), findsOneWidget);
        expect(find.text('S'), findsOneWidget);
        expect(find.text('+2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a screen reader is told, in words, and told "given"',
        (tester) async {
      // Ground rule 4 in a sentence: the label is on the item. Whether the
      // child can *see* it is the server's answer and depends on their age
      // limit too, so the copy must not claim it.
      await pump(
        tester,
        LibraryItemState.unknown,
        childName: null,
        holders: [holder('Emma'), holder('Léo')],
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(LibraryTile));
      expect(semantics.label, contains('Given to Emma, Léo'));
      expect(semantics.label, isNot(contains('can watch')));
      expect(semantics.label, isNot(contains('sees')));
    });

    testWidgets('and told about every one of them, not the three on screen',
        (tester) async {
      // The chip is a space constraint. A spoken label has no corner to run
      // out of, so "+2" there would lose two names for nothing.
      await pump(
        tester,
        LibraryItemState.unknown,
        childName: null,
        holders: [
          holder('Emma'),
          holder('Léo'),
          holder('Sam'),
          holder('Ada'),
          holder('Zoé'),
        ],
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(LibraryTile));
      expect(semantics.label, contains('Ada'));
      expect(semantics.label, contains('Zoé'));
      expect(semantics.label, isNot(contains('+2')));
    });

    testWidgets('the held-back explanation survives alongside the faces',
        (tester) async {
      // Two different facts about the same tile: Emma has been given it and
      // the server is not showing it to her, while Léo has it too. Losing
      // either one would be the tile telling a partial truth.
      await pump(
        tester,
        LibraryItemState.givenButHidden,
        childId: 'id-Emma',
        holders: [holder('Emma'), holder('Léo')],
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(LibraryTile));
      expect(semantics.label, contains('the usual reason'));
      expect(semantics.label, contains('Given to Léo'));
    });

    testWidgets('the selected child is not named twice in one breath',
        (tester) async {
      // "Emma has this, but the server isn't showing it to them … Given to
      // Emma" reads as a contradiction to anyone who has not internalised the
      // given-versus-visible split — and on a plain given tile it reads as a
      // stutter: "Given. Given to Emma." The badge has already spoken about
      // the selected child; the sentence adds who *else*.
      await pump(
        tester,
        LibraryItemState.given,
        childId: 'id-Emma',
        holders: [holder('Emma'), holder('Léo')],
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(LibraryTile));
      expect(semantics.label, contains('Given to Léo'));
      expect(semantics.label, isNot(contains('Given to Emma')));
      expect(semantics.label, isNot(contains('Emma')));
      // Her face is still on the poster. The row says who has it; the sentence
      // says who else — dropping her from both would lose a fact.
      expect(find.text('E'), findsOneWidget);
    });

    testWidgets('a title only the selected child has says it once',
        (tester) async {
      await pump(
        tester,
        LibraryItemState.given,
        childId: 'id-Emma',
        holders: [holder('Emma')],
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(LibraryTile));
      expect(semantics.label, contains('Given'));
      expect(semantics.label, isNot(contains('Given to')));
    });

    testWidgets('the row never replaces the state badge', (tester) async {
      await pump(tester, LibraryItemState.given, holders: [holder('Emma')]);
      await tester.pumpAndSettle();

      expect(find.text('Given'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
    });
  });

  group('the bottom edge, which had the same collision (#89)', () {
    // The age hint and the collection count were pinned to opposite corners
    // and appear together on a collection tile with a child selected.
    // Rendered at 83dp and 118dp the count painted straight over the hint and
    // spilled past the poster — inside the tile, so no assertion saw it, and
    // nothing errored. The same defect #84 fixed at the top edge.

    Future<void> pumpBottom(WidgetTester tester, double width) => pump(
          tester,
          LibraryItemState.notGiven,
          width: width,
          type: 'BoxSet',
          childCount: 7,
          suitability: AgeSuitability.unknown,
        );

    testWidgets('at every width, the two never share a pixel', (tester) async {
      for (final width in <double>[83, 110, 118, 178]) {
        await pumpBottom(tester, width);
        await tester.pumpAndSettle();

        final hint = tester.getRect(find.text('No age rating'));
        final count = tester.getRect(find.text('7 titles'));
        expect(hint.overlaps(count), isFalse,
            reason: 'they collided at ${width}dp');
        expect(tester.takeException(), isNull,
            reason: 'the bottom row overflowed at ${width}dp');
      }
    });

    testWidgets('and both survive — neither is dropped to make room',
        (tester) async {
      // The top edge drops faces when it runs out of room, because a `+N`
      // stands for them. Neither of these has anything that stands for it, so
      // the narrow answer is to stack rather than to hide.
      for (final width in <double>[83, 118, 178]) {
        await pumpBottom(tester, width);
        await tester.pumpAndSettle();

        expect(find.text('No age rating'), findsOneWidget,
            reason: 'the hint went missing at ${width}dp');
        expect(find.text('7 titles'), findsOneWidget,
            reason: 'the count went missing at ${width}dp');
      }
    });

    testWidgets('side by side when there is room, stacked when there is not',
        (tester) async {
      // 300dp rather than a real tile width, deliberately: how much fits
      // depends on how wide the badge text measures, and the font in a widget
      // test is not the font on the phone — rendered with the shipped fonts
      // these sit side by side at 178dp, and in here they do not. The claim
      // worth pinning is that *enough* room keeps them on one line, not the
      // exact width at which that starts being true.
      await pumpBottom(tester, 300);
      await tester.pumpAndSettle();
      final wideHint = tester.getRect(find.text('No age rating'));
      final wideCount = tester.getRect(find.text('7 titles'));
      expect(wideHint.center.dy, closeTo(wideCount.center.dy, 1),
          reason: 'a wide tile should keep them on one line');
      expect(wideHint.left, lessThan(wideCount.left),
          reason: 'the hint keeps the left corner it has always had');

      await pumpBottom(tester, 83);
      await tester.pumpAndSettle();
      final narrowHint = tester.getRect(find.text('No age rating'));
      final narrowCount = tester.getRect(find.text('7 titles'));
      expect(narrowCount.center.dy, greaterThan(narrowHint.center.dy),
          reason: 'a narrow tile should stack them, count below');
    });

    testWidgets('a film with no collection count is unaffected',
        (tester) async {
      await pump(tester, LibraryItemState.notGiven,
          width: 83, suitability: AgeSuitability.unknown);
      await tester.pumpAndSettle();

      expect(find.text('No age rating'), findsOneWidget);
      expect(find.textContaining('titles'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a collection says how many titles it holds', (tester) async {
    await pump(
      tester,
      LibraryItemState.notGiven,
      type: 'BoxSet',
      childCount: 7,
    );
    await tester.pumpAndSettle();

    expect(find.text('7 titles'), findsOneWidget);
  });
}
