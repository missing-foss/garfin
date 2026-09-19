// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/widgets/collection_given_line.dart';

/// How much of a set is a child's, as a ring.
///
/// The sentence it replaced named a child the app bar already names and was the
/// longest thing on a tile. It is not lost: the collection screen shows it in
/// full, and it is the ring's spoken label.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The painter the widget actually built.
  Future<GivenRingPainter> painterFor(
    WidgetTester tester,
    CollectionGiven given,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: GivenRing(given: given))),
      ),
    );
    await tester.pumpAndSettle();
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(GivenRing),
        matching: find.byType(CustomPaint),
      ),
    );
    return paint.painter! as GivenRingPainter;
  }

  /// The tone the widget **painted**, read off its painter.
  ///
  /// Recomputing it from the theme was the first version of this, and it was a
  /// tautology: `allow != block` is true of the two theme colours whatever the
  /// ring does with them. It passed against a ring hard-coded to one tone.
  Future<Color> toneOf(WidgetTester tester, CollectionGiven given) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: GivenRing(given: given))),
      ),
    );
    await tester.pumpAndSettle();
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(GivenRing),
        matching: find.byType(CustomPaint),
      ),
    );
    return (paint.painter! as GivenRingPainter).tone;
  }

  testWidgets('it draws at a size that fits under a title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: GivenRing(
              given: CollectionGiven(
                labelled: 3,
                total: 5,
                mode: ShortlistMode.allow,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The ring's own box, not `find.byType(CustomPaint).first` — the app
    // scaffold paints too, and that finder returns an 800dp one.
    expect(tester.getSize(find.byType(GivenRing)).width, GivenRing.diameter);
  });

  testWidgets('the two directions do not share a tone', (tester) async {
    // Ground rule 3: the same proportion means the opposite for a block-list
    // child, and the ring cannot say which in its shape. Tone is what carries
    // it on screen — a deliberate trade, with the sentence one tap away on the
    // collection screen and in this ring's own spoken label.
    final allow = await toneOf(
      tester,
      const CollectionGiven(labelled: 3, total: 5, mode: ShortlistMode.allow),
    );
    final block = await toneOf(
      tester,
      const CollectionGiven(labelled: 3, total: 5, mode: ShortlistMode.block),
    );

    expect(allow, isNot(block));
  });

  testWidgets('the arc is the share of the set that is theirs',
      (tester) async {
    // **The whole content of this widget, and nothing was reading it.**
    // Hard-coded to `fraction: 1` — every collection drawn as fully given, for
    // every child — the entire suite passed. That is a confident wrong
    // statement about what a child has, which is the shape ground rule 4
    // exists to prevent.
    final some = await painterFor(
      tester,
      const CollectionGiven(labelled: 3, total: 5, mode: ShortlistMode.allow),
    );
    expect(some.fraction, closeTo(0.6, 0.0001));

    final all = await painterFor(
      tester,
      const CollectionGiven(labelled: 5, total: 5, mode: ShortlistMode.allow),
    );
    expect(all.fraction, 1);

    final none = await painterFor(
      tester,
      const CollectionGiven(labelled: 0, total: 5, mode: ShortlistMode.allow),
    );
    expect(none.fraction, 0);
  });

  testWidgets('an empty set is an empty ring, not a NaN', (tester) async {
    // **This asserted the absence of an exception and could not fail.** `0 / 0`
    // on Dart doubles is `NaN`, not a throw, so removing the guard left the
    // test green while the painter was handed a NaN. The guard is right; the
    // instrument in front of it was not evidence for it.
    //
    // `total` is the server's and a set can be empty, so this is a case that
    // happens rather than a defensive one.
    final painter = await painterFor(
      tester,
      const CollectionGiven(labelled: 0, total: 0, mode: ShortlistMode.allow),
    );

    expect(painter.fraction, 0);
    expect(painter.fraction.isNaN, isFalse);
  });
}
