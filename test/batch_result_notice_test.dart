// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/repositories/assign_repository.dart';
import 'package:garfin/widgets/batch_result_notice.dart';

/// What a half-finished collection write actually says to the parent.
///
/// Ground rule 5's job is to "surface the exact state", and this is the panel
/// that does it — so being wrong here is not cosmetic. The failure this suite
/// exists for: copy written for an addition, shown after a **removal**, which
/// describes the opposite situation and labels the button with the opposite
/// act. Review of #51 found exactly that; these are the cases it walked.
void main() {
  final emma = JellyfinUser(
    id: 'kid-1',
    name: 'Emma',
    policy: const UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-emma'],
    ),
  );
  final sam = JellyfinUser(
    id: 'kid-2',
    name: 'Sam',
    policy: const UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-sam'],
    ),
  );

  final added = TagDiff([
    TagChange(child: emma, label: 'kids-emma', adding: true),
  ]);
  final removed = TagDiff([
    TagChange(child: emma, label: 'kids-emma', adding: false),
  ]);
  final mixed = TagDiff([
    TagChange(child: emma, label: 'kids-emma', adding: true),
    TagChange(child: sam, label: 'kids-sam', adding: false),
  ]);

  BatchOutcome outcome({
    int written = 12,
    List<String> failed = const [],
    bool setMarked = false,
  }) =>
      BatchOutcome(
        written: List.generate(written, (i) => 'film-$i'),
        failed: failed,
        setMarked: setMarked,
        counts: const {},
        applied: const TagDiff.empty(),
      );

  Future<void> pump(
    WidgetTester tester, {
    required BatchOutcome result,
    required TagDiff diff,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BatchResultNotice(
              outcome: result,
              diff: diff,
              onFinish: () {},
              onReverse: () {},
            ),
          ),
        ),
      );

  group('the container was left unmarked, and which way the change went', () {
    testWidgets('labels went on: the films are there and the set is not',
        (tester) async {
      await pump(tester, result: outcome(written: 12), diff: added);

      expect(find.textContaining('All 12 titles are labelled'), findsOneWidget);
      expect(find.textContaining('The films are there'), findsOneWidget);
    });

    testWidgets('labels came off: the set is there and it will look empty',
        (tester) async {
      // The state is reachable — `applyToCollection` writes the container's
      // removals first, so a failure there with every member succeeding lands
      // exactly here. Told in the addition's words it would send a parent
      // looking for a missing collection that is in fact still on screen.
      await pump(tester, result: outcome(written: 12), diff: removed);

      expect(
          find.textContaining('All 12 titles are unlabelled'), findsOneWidget);
      expect(find.textContaining('will look empty'), findsOneWidget);
      expect(find.textContaining('The films are there'), findsNothing);
    });

    testWidgets('both at once: nothing directional is claimed', (tester) async {
      await pump(tester, result: outcome(written: 12), diff: mixed);

      expect(
        find.text("All 12 titles changed, but the collection itself didn't."),
        findsOneWidget,
      );
    });
  });

  group('the reversing button names what it will do', () {
    testWidgets('after labels went on, it removes them', (tester) async {
      await pump(tester, result: outcome(), diff: added);
      expect(find.text('Remove all'), findsOneWidget);
      expect(find.text('Put it all back'), findsNothing);
    });

    testWidgets('after labels came off, it puts them back', (tester) async {
      // "Remove all" here would name the opposite of what pressing it does.
      await pump(tester, result: outcome(), diff: removed);
      expect(find.text('Put it all back'), findsOneWidget);
      expect(find.text('Remove all'), findsNothing);
    });

    testWidgets('a mixed change is put back, not removed', (tester) async {
      await pump(tester, result: outcome(), diff: mixed);
      expect(find.text('Put it all back'), findsOneWidget);
    });

    testWidgets('finishing the rest is offered whichever way it went',
        (tester) async {
      for (final diff in [added, removed, mixed]) {
        await pump(tester, result: outcome(), diff: diff);
        expect(find.text('Finish the rest'), findsOneWidget);
      }
    });
  });

  group('some titles failed', () {
    testWidgets('the count is reported, in words that fit either direction',
        (tester) async {
      for (final diff in [added, removed, mixed]) {
        await pump(
          tester,
          result: outcome(written: 7, failed: const ['a', 'b', 'c', 'd', 'e']),
          diff: diff,
        );
        // Ground rule 5's own example, and the change preview above the panel
        // has already said who gained and who lost.
        expect(find.text('7 of 12 titles changed.'), findsOneWidget);
      }
    });
  });

  group('the direction rule itself', () {
    test('additions only, removals only, and both', () {
      expect(added.direction, DiffDirection.added);
      expect(removed.direction, DiffDirection.removed);
      expect(mixed.direction, DiffDirection.mixed);
    });

    test('an empty diff claims nothing', () {
      // It is never written, so it must never assert a direction either.
      expect(const TagDiff.empty().direction, DiffDirection.mixed);
    });

    test('the direction is about the labels, not about access', () {
      // Ground rule 3: for a block-list child, adding a label takes access
      // away. The panel describes what happened to the *item*, so a block-list
      // addition is still `added` — and `givesAccess` stays the thing that
      // speaks for the child.
      final blocked = JellyfinUser(
        id: 'kid-3',
        name: 'Ada',
        policy: const UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          blockedTags: ['block-ada'],
        ),
      );
      final diff = TagDiff([
        TagChange(child: blocked, label: 'block-ada', adding: true),
      ]);

      expect(diff.direction, DiffDirection.added);
      expect(diff.changes.single.givesAccess, isFalse);
    });
  });
}
