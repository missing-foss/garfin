// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/age_suitability.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/widgets/library_tile.dart';

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
    String type = 'Movie',
    int? childCount,
    AgeSuitability suitability = AgeSuitability.unknown,
    String? rating,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 160,
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
