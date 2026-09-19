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
    int? recursiveItemCount,
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
                    recursiveItemCount: recursiveItemCount,
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

  testWidgets('held back and blocked badge; a plain share does not',
      (tester) async {
    // **Inverted from what this asserted, deliberately.** It required a
    // "Given" badge. A shared title now says so with the child's own face —
    // asked for directly: "when an item has been shared it says so on the
    // poster on top of the kids profile picture. I think the kids profile
    // picture is enough."
    //
    // The two that stay are the two a face cannot express. Held-back is the
    // opposite of what a face implies — the label is there and the server is
    // still not showing the title — and a block-list child is never collected
    // as a holder at all, so nothing else could carry `blocked`.
    // The holder inline rather than through the group's helper: that lives in
    // the faces group, and this test is above it.
    await pump(tester, LibraryItemState.given,
        holders: const [ItemHolder(userId: 'id-Emma', name: 'Emma')]);
    await tester.pumpAndSettle();
    expect(find.text('Given'), findsNothing);
    expect(find.text('E'), findsOneWidget, reason: 'the face is the badge now');

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

    testWidgets('not-known is silent, like suitable', (tester) async {
      // **This assertion is inverted from what it was, deliberately.** It used
      // to require the badge, on the argument that an unrated title is where a
      // parent most needs telling Garfin cannot say. Overruled from use: "if
      // there are no classifications then it shouldn't show anything, we are
      // only interested by classifications". The badge was on a large share of
      // the grid, and a marker that common is one the eye learns to skip —
      // taking the ones that mean something with it.
      await pump(tester, LibraryItemState.notGiven,
          suitability: AgeSuitability.unknown);
      await tester.pumpAndSettle();
      expect(find.text('No age rating'), findsNothing);

      await pump(tester, LibraryItemState.notGiven,
          suitability: AgeSuitability.suitsAge, rating: 'G');
      await tester.pumpAndSettle();
      expect(find.text('No age rating'), findsNothing);

      // The control, and the reason this is a change of copy rather than the
      // hint being switched off: the one state that is worth a second look
      // still speaks.
      await pump(tester, LibraryItemState.notGiven,
          suitability: AgeSuitability.aboveAge, rating: '15');
      await tester.pumpAndSettle();
      expect(find.text("Above Emma's age"), findsOneWidget);
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
        // 240 and 360 are past the point where the circles start growing,
        // and a badge that stays put while the row beside it gets bigger is
        // exactly how a scaling change would reintroduce the overlap this
        // pins. 360 is the widest a tile can be: the grid sizes by
        // `maxCrossAxisExtent`, and the largest poster target is 360.
        for (final width in <double>[83, 110, 118, 178, 240, 360]) {
          await pump(
            tester,
            LibraryItemState.givenButHidden,
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

          final badge = tester.getRect(find.text('Held back'));
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

      testWidgets('a large poster gets larger faces, a small one does not',
          (tester) async {
        Future<double> faceWidthAt(double width) async {
          await pump(
            tester,
            LibraryItemState.given,
            width: width,
            holders: [holder('Emma')],
          );
          await tester.pumpAndSettle();
          return tester.getRect(find.byType(UserAvatar).first).width;
        }

        // Every width these tests already pinned is below the threshold, and
        // stays byte-identical: the 22dp circle was measured against a real
        // phone tile and there was never anything wrong with it there. 83 is
        // not among them because at 83 the row gives way to the badge and
        // draws nothing at all -- the rule the test above this one pins.
        final at118 = await faceWidthAt(118);
        expect(await faceWidthAt(178), at118);

        // Above it the row grows with the poster instead of sitting in the
        // corner of one several times its size.
        expect(await faceWidthAt(360), greaterThan(at118));
      });

      testWidgets('the faces stop growing before they compete with the title',
          (tester) async {
        // Unbounded would be the easy mistake: a poster is capped at 360, but
        // the row is handed a width, not a promise, and a clamp is cheaper to
        // keep than an assumption about who calls it.
        //
        // Neither width is a real tile. A real one does not reach the ceiling:
        // the row gets the tile minus the badge, so even the widest poster
        // scales by about 1.4 rather than the full 1.6. This is the clamp
        // doing nothing in production and everything if the row is ever reused
        // somewhere wider.
        //
        // **400 and 2000 rather than two large widths.** Past about 800dp the
        // face stops growing on its own -- the top edge runs out of height --
        // so a pair chosen from up there matches whether the clamp is applied
        // or not, and the test passes with the ceiling removed. Verified by
        // raising it and watching all 39 still pass. The pair has to straddle
        // that saturation, not sit above it.
        Future<double> faceWidthAt(double width) async {
          await pump(
            tester,
            LibraryItemState.given,
            width: width,
            holders: [holder('Emma')],
          );
          await tester.pumpAndSettle();
          return tester.getRect(find.byType(UserAvatar).first).width;
        }

        // `closeTo` because the two arrive at the same size by different
        // arithmetic and land a 14th decimal place apart.
        expect(await faceWidthAt(2000), closeTo(await faceWidthAt(400), 0.001));
      });

      testWidgets('room for more means more of them', (tester) async {
        // The other half of the same rule: giving way is a response to the
        // width, not a permanent retreat. Counting circles rather than naming
        // them keeps this independent of the test font too.
        //
        // `givenButHidden` for the same reason as the test above — with no
        // badge to give way to, the row has the whole edge at every width and
        // there is nothing for this to measure.
        Future<int> circlesAt(double width) async {
          await pump(
            tester,
            LibraryItemState.givenButHidden,
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
      // given-versus-visible split. The badge has already spoken about the
      // selected child; the sentence adds who *else*.
      //
      // **Held back rather than a plain share**, which is where this rule now
      // applies: the exclusion was always conditional on the badge speaking,
      // and for a plain share it no longer does.
      // Wide enough for the faces to survive beside the badge: at the default
      // width the row gives way to "Held back", which is a different rule and
      // is pinned by its own group.
      await pump(
        tester,
        LibraryItemState.givenButHidden,
        childId: 'id-Emma',
        width: 240,
        holders: [holder('Emma'), holder('Léo')],
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(LibraryTile));
      expect(semantics.label, contains('Given to Léo'));
      expect(semantics.label, isNot(contains('Given to Emma')));
      // Her face is still on the poster. The row says who has it; the sentence
      // says who else — dropping her from both would lose a fact.
      expect(find.text('E'), findsOneWidget);
    });

    testWidgets('but she is named when no badge speaks for her',
        (tester) async {
      // **The regression this closes.** With the plain-share badge gone,
      // dropping her unconditionally left the tile saying "Given to Léo" and
      // nothing about Emma — which reads as *not given to Emma*, a confident
      // wrong statement about a named child.
      await pump(
        tester,
        LibraryItemState.given,
        childId: 'id-Emma',
        holders: [holder('Emma'), holder('Léo')],
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(LibraryTile));
      expect(semantics.label, contains('Emma'),
          reason: 'nothing else on this tile says it out loud any more');
      expect(semantics.label, contains('Léo'));
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
      // **Inverted, and it is the same rule rather than a new one.** #84
      // guarded against saying it twice — "Given. Given to Emma." — and with
      // the plain-share badge gone there is only one place left to say it, so
      // the sentence is where it belongs.
      expect(semantics.label, contains('Given to Emma'));
      expect('Given to'.allMatches(semantics.label).length, 1,
          reason: 'once, which was always the point');
    });

    testWidgets('the row keeps the front of the list when it cannot keep all',
        (tester) async {
      // **This replaces "the row never replaces the state badge", whose
      // premise is now the opposite of the behaviour**: for a plain share the
      // row *is* the badge.
      //
      // Which makes list order load-bearing rather than tidy — the row draws
      // holders in order and collapses the rest, so whoever is first is
      // whoever survives a narrow tile. *Who* ends up first is
      // `holdersOf`'s job and is tested there; this pins the half the row
      // owns, which is what makes that sort worth doing.
      // Five, because three fit: dropping the badge gave the row the whole
      // edge back, so overflow now needs more holders than it used to. That is
      // a good consequence of the change and a trap for a test written against
      // the old widths.
      await pump(
        tester,
        LibraryItemState.given,
        width: 83,
        holders: [
          holder('Emma'),
          holder('Ana'),
          holder('Leo'),
          holder('Sam'),
          holder('Zoe'),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('E'), findsOneWidget,
          reason: 'the first holder is the one that fits');
      expect(find.text('Z'), findsNothing);
      expect(find.textContaining('+'), findsOneWidget,
          reason: 'the rest collapse rather than disappearing silently');
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
          // `aboveAge` rather than `unknown`: this group is about two badges
          // colliding, not about which badge, and `unknown` no longer draws
          // one at all.
          suitability: AgeSuitability.aboveAge,
          rating: '15',
        );

    testWidgets('at every width, the two never share a pixel', (tester) async {
      for (final width in <double>[83, 110, 118, 178]) {
        await pumpBottom(tester, width);
        await tester.pumpAndSettle();

        final hint = tester.getRect(find.text("Above Emma's age"));
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

        expect(find.text("Above Emma's age"), findsOneWidget,
            reason: 'the hint went missing at ${width}dp');
        expect(find.text('7 titles'), findsOneWidget,
            reason: 'the count went missing at ${width}dp');
      }
    });

    testWidgets('side by side when there is room, stacked when there is not',
        (tester) async {
      // 400dp rather than a real tile width, deliberately: how much fits
      // depends on how wide the badge text measures, and the font in a widget
      // test is not the font on the phone — rendered with the shipped fonts
      // these sit side by side at 178dp, and in here they do not. The claim
      // worth pinning is that *enough* room keeps them on one line, not the
      // exact width at which that starts being true.
      //
      // It was 300 while the hint read "No age rating"; the badge this group
      // now uses is longer, and the number moved with it — which is the whole
      // reason the comment above says the exact width is not the claim.
      await pumpBottom(tester, 400);
      await tester.pumpAndSettle();
      final wideHint = tester.getRect(find.text("Above Emma's age"));
      final wideCount = tester.getRect(find.text('7 titles'));
      expect(wideHint.center.dy, closeTo(wideCount.center.dy, 1),
          reason: 'a wide tile should keep them on one line');
      expect(wideHint.left, lessThan(wideCount.left),
          reason: 'the hint keeps the left corner it has always had');

      await pumpBottom(tester, 83);
      await tester.pumpAndSettle();
      final narrowHint = tester.getRect(find.text("Above Emma's age"));
      final narrowCount = tester.getRect(find.text('7 titles'));
      expect(narrowCount.center.dy, greaterThan(narrowHint.center.dy),
          reason: 'a narrow tile should stack them, count below');
    });

    testWidgets('a lone count keeps the corner it has always had',
        (tester) async {
      // With no child selected there is no age hint, so the count is alone in
      // the row — and that is the state the app opens in. Raised in review and
      // unverified there; this is the check.
      await pump(tester, LibraryItemState.unknown,
          width: 178, childName: null, type: 'BoxSet', childCount: 7);
      await tester.pumpAndSettle();

      // Relative rather than to the pixel: `find.text` measures the label
      // inside the badge's own padding, so an exact edge assertion is really
      // an assertion about that padding.
      final tile = tester.getRect(find.byType(LibraryTile));
      final count = tester.getRect(find.text('7 titles'));
      expect(count.center.dx, greaterThan(tile.center.dx),
          reason: 'the count moved off the right-hand corner');
    });

    testWidgets('a film with no collection count is unaffected',
        (tester) async {
      await pump(tester, LibraryItemState.notGiven,
          width: 83, suitability: AgeSuitability.aboveAge, rating: '15');
      await tester.pumpAndSettle();

      expect(find.text("Above Emma's age"), findsOneWidget);
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

  /// #99. The badge is a picture; a screen reader was told nothing by it, on
  /// the one tile whose tap does something different from every other tile.
  group('a collection says so out loud (#99)', () {
    testWidgets('names the kind as well as the number', (tester) async {
      await pump(
        tester,
        LibraryItemState.notGiven,
        type: 'BoxSet',
        childCount: 7,
      );
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(LibraryTile)).label;
      expect(label, contains('Collection, 7 titles'));
      // Right after the name: what the thing *is* comes before what has been
      // done with it.
      expect(label.indexOf('Collection, 7 titles'),
          greaterThan(label.indexOf('Paddington')));
    });

    testWidgets('a film says neither', (tester) async {
      await pump(tester, LibraryItemState.notGiven, childCount: 7);
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(LibraryTile)).label;
      expect(label, isNot(contains('Collection')));
      expect(label, isNot(contains('titles')));
    });

    /// `ChildCount` is absent unless `Fields=ChildCount` is asked for — the
    /// trap #51 already hit. The tile draws no badge in that state, and the
    /// spoken label must not invent a number the server never sent.
    testWidgets('degrades to the noun alone with no count', (tester) async {
      await pump(tester, LibraryItemState.notGiven, type: 'BoxSet');
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(LibraryTile)).label;
      expect(label, contains('Collection'));
      expect(label, isNot(contains('0 titles')));
      expect(label, isNot(contains('titles')));
    });

    /// Not a claim about a child, unlike the badge and the held-back sentence
    /// — so it does not wait for a selection the way those do (#96).
    testWidgets('is spoken with nobody picked', (tester) async {
      await pump(
        tester,
        LibraryItemState.unknown,
        type: 'BoxSet',
        childCount: 7,
        childName: null,
      );
      await tester.pumpAndSettle();

      expect(tester.getSemantics(find.byType(LibraryTile)).label,
          contains('Collection, 7 titles'));
    });

    /// The held-back branch returns early and composes its own sentence, so it
    /// is the one place the new part could silently go missing.
    testWidgets('survives the held-back sentence', (tester) async {
      await pump(
        tester,
        LibraryItemState.givenButHidden,
        type: 'BoxSet',
        childCount: 7,
      );
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(LibraryTile)).label;
      expect(label, contains('Collection, 7 titles'));
      expect(label, contains('Emma'));
    });
  });

  group('a collection is outlined (#107)', () {
    /// The line by its own key. Reading the decoration is the point: a
    /// `DecoratedBox` in the right place with the wrong colour, the wrong
    /// width or the wrong paint order looks identical to the finder.
    Finder outline() => find.byKey(const ValueKey('collection-outline'));

    BoxDecoration decorationOf(WidgetTester tester) =>
        tester.widget<DecoratedBox>(outline()).decoration as BoxDecoration;

    testWidgets('a film has none', (tester) async {
      // The control, and the half that would be easy to lose: this is a change
      // to collections, and an ordinary tile must look exactly as it did.
      await pump(tester, LibraryItemState.notGiven);
      await tester.pumpAndSettle();

      expect(outline(), findsNothing);
    });

    testWidgets('a collection has one, in the tertiary tone', (tester) async {
      await pump(tester, LibraryItemState.notGiven,
          type: 'BoxSet', childCount: 7);
      await tester.pumpAndSettle();

      expect(outline(), findsOneWidget);

      final border = decorationOf(tester).border! as Border;
      // The scheme the tile was actually handed, rather than one rebuilt here
      // — but named: asking for `tertiary` and comparing against `tertiary`
      // still fails on a line drawn in `primary`, which is the mistake this
      // catches. What it must not do is re-derive the colour by the same
      // expression the widget uses, which accepts whatever that returns.
      final scheme = Theme.of(tester.element(find.byType(LibraryTile)))
          .colorScheme;
      expect(border.top.color, scheme.tertiary,
          reason: 'the palette has no gold; tertiary is the tone this screen '
              'already uses for "worth a second look"');
      expect(border.top.width, 2,
          reason: 'a hairline is what "too subtle" already looked like');
      expect(border.isUniform, isTrue,
          reason: 'the whole silhouette, which is what a corner marker was not');
    });

    testWidgets('painted over the artwork, not under it', (tester) async {
      // **The failure this catches is invisible rather than wrong.** The
      // poster fills the whole rect, so a border in the background position is
      // painted and then covered — the widget is in the tree, the colour and
      // the width are exactly right, and there is no line on the screen. It
      // would look like a colour that was too faint, which is the report this
      // change came from.
      await pump(tester, LibraryItemState.notGiven,
          type: 'BoxSet', childCount: 7);
      await tester.pumpAndSettle();

      expect(tester.widget<DecoratedBox>(outline()).position,
          DecorationPosition.foreground);
    });

    testWidgets('and around the whole poster, not inside it', (tester) async {
      // The stack cost the poster its top-right corner, and the line does not.
      // Same rect, so the artwork is the size it is on a film.
      await pump(tester, LibraryItemState.notGiven,
          type: 'BoxSet', childCount: 7, width: 178);
      await tester.pumpAndSettle();

      final poster = tester.getRect(find.byType(ClipRRect).first);
      expect(tester.getRect(outline()), poster);
    });

    testWidgets('the badge and the faces are back in the tile\'s own corners',
        (tester) async {
      // They carried an offset for as long as a collection's poster was inset
      // for the sheets behind it. With the inset gone the offset would push
      // them *into* the artwork, so this is not a leftover that costs nothing.
      //
      // `givenButHidden`, because a plain share has no badge to place any
      // more; and holders, because `_HolderRow` renders a `SizedBox.shrink()`
      // for an empty list — an earlier version of this assertion measured a
      // row that was not in the tree.
      await pump(tester, LibraryItemState.givenButHidden,
          type: 'BoxSet',
          childCount: 7,
          width: 178,
          holders: const [
            ItemHolder(userId: 'kid-2', name: 'Leo'),
            ItemHolder(userId: 'kid-3', name: 'Ana'),
          ]);
      await tester.pumpAndSettle();

      final tile = tester.getRect(find.byType(LibraryTile));
      final badge = tester.getRect(find.text('Held back'));
      expect(badge.top - tile.top, lessThan(8),
          reason: 'the badge sits on the tile inset, not below a sheet edge');

      // The **rightmost** face: the left end of a row does not move when the
      // right inset does, which is how an earlier attempt at this passed on
      // the mutant it was written to catch.
      final rowRight = find
          .byType(UserAvatar)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)).right)
          .reduce((a, b) => a > b ? a : b);
      expect(tile.right - rowRight, lessThan(8),
          reason: 'and the faces reach the tile edge, not a sheet edge');
    });
  });

  group('a series says how many episodes it holds (#119)', () {
    testWidgets('the count is the episodes, not the seasons', (tester) async {
      // **The whole of this change is in this assertion.** Measured on
      // 10.11.11: a two-season, five-episode show reports `ChildCount: 2` and
      // `RecursiveItemCount: 5`. Reusing the collection badge would read the
      // first and print "2 titles" for a show holding five of neither, so the
      // fixture carries both numbers and they are deliberately different.
      await pump(tester, LibraryItemState.notGiven,
          type: 'Series', childCount: 2, recursiveItemCount: 5);
      await tester.pumpAndSettle();

      expect(find.text('5 episodes'), findsOneWidget);
      expect(find.text('2 episodes'), findsNothing,
          reason: 'two is the seasons, and the seasons are not the answer');
      expect(find.textContaining(RegExp(r'\d+ titles')), findsNothing,
          reason: 'a series holds episodes; titles is the collection noun');
    });

    testWidgets('a film has no episode badge', (tester) async {
      // The control. Measured: a `Movie` reports neither count field even when
      // both are requested, so this is the server's own shape rather than a
      // type check — but the tile must still be seen not to badge it.
      await pump(tester, LibraryItemState.notGiven);
      await tester.pumpAndSettle();

      expect(find.text('Paddington'), findsOneWidget,
          reason: 'the tile is drawn; it is the badge that is absent');
      expect(find.textContaining(RegExp(r'\d+ episodes')), findsNothing);
    });

    testWidgets('and neither does a show whose size was not asked for',
        (tester) async {
      // `RecursiveItemCount` is absent unless `Fields` names it. Absent is not
      // zero, so nothing is invented for the corner — the same rule the
      // collection badge follows.
      await pump(tester, LibraryItemState.notGiven, type: 'Series');
      await tester.pumpAndSettle();

      expect(find.text('Paddington'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ episodes')), findsNothing);
    });

    testWidgets('a screen reader is told what it is, and how big',
        (tester) async {
      await pump(tester, LibraryItemState.notGiven,
          type: 'Series', childCount: 2, recursiveItemCount: 5);
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(LibraryTile)).label;
      expect(label, contains('Series, 5 episodes'));
    });

    testWidgets('degrading to the noun alone when the count is missing',
        (tester) async {
      await pump(tester, LibraryItemState.notGiven, type: 'Series');
      await tester.pumpAndSettle();

      final label = tester.getSemantics(find.byType(LibraryTile)).label;
      expect(label, contains('Series'));
      expect(label, isNot(contains('episodes')),
          reason: 'no count was sent, so none is spoken');
    });
  });
}
