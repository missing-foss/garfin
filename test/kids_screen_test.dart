// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/widgets/kid_card.dart';
import 'package:garfin/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Kids screen actually puts on screen.
///
/// `docs/UI-SPEC.md` § Kids makes two claims a reader cannot check by reading
/// the widget tree in their head: that a conflicting account is *stated* rather
/// than resolved, and that the accounts with no shortlist are **not tappable**.
///
/// This comment said "both are asserted here" from the day it was written, and
/// only the first one was — every test below it drove `KidCard`, and nothing
/// touched the unmanaged list at all. Found while fixing #79, which is a bug in
/// exactly that list. The second half is asserted now, along with the avatars
/// that were missing from it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  KidSummary kid({
    List<String> allowed = const ['kids-emma'],
    List<String> blocked = const [],
    int? cap = 7,
    int? subCap,
    String? capName = 'PG',
    int? birthYear,
  }) =>
      KidSummary(
        user: JellyfinUser(
          id: 'k1',
          name: 'Emma',
          policy: UserPolicy(
            isAdministrator: false,
            isDisabled: false,
            allowedTags: allowed,
            blockedTags: blocked,
            maxParentalRating: cap,
            maxParentalSubRating: subCap,
          ),
        ),
        ratingCapName: capName,
        birthYear: birthYear,
      );

  /// Pumps a card **and opens it.**
  ///
  /// The resting card is now the picture, the name, the age and the way in;
  /// the cap, the hours, the mode and the tags are reference and wait behind
  /// the chevron. Every test below is about *what the card says* about one of
  /// those facts rather than about where it says it, so they all start from
  /// the open card.
  ///
  /// That they are hidden at rest is asserted once, in
  /// `kid_card_at_rest_test.dart`, rather than sixteen times here — a property
  /// worth one sharp test, not a precondition restated everywhere.
  Future<void> pumpCard(WidgetTester tester, KidSummary summary) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: KidCard(kid: summary, session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Only if it is closed. A second `pumpCard` in the same test reuses the
    // card's `State` — same type, same position — so `_expanded` survives the
    // rebuild and an unconditional tap would shut the card the caller just
    // asked for.
    if (find.byIcon(Icons.expand_more).evaluate().isNotEmpty) {
      await tester.tap(find.text(summary.user.name));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a card shows the name, cap, mode and tags', (tester) async {
    await pumpCard(tester, kid(birthYear: 2015));
    await tester.pumpAndSettle();

    expect(find.text('Emma'), findsOneWidget);
    // The headline "N of M things visible" is gone: the per-library card
    // answers the same question with more resolution, and two answers to one
    // question can disagree.
    expect(find.textContaining('things visible'), findsNothing);
    expect(find.text('Up to PG'), findsOneWidget);
    expect(find.text('Shortlist based on these labels:'), findsOneWidget);
    expect(find.text('kids-emma'), findsOneWidget);
    expect(find.textContaining('years old'), findsOneWidget);
  });

  group('whose settings these are (#74, #76)', () {
    // The test that stood here checked the mode was not drawn as a `Chip`,
    // after it was reported from use as "a 'select' button — it doesn't seem
    // to work". There is no mode pill any more: the labels now carry a
    // sentence that says which list they are, so the pill it guarded against
    // cannot come back in that shape. What replaced its intent is
    // 'a block-list account says so', below — the mode still has to be
    // readable, and it still must not claim to be a control.

    testWidgets('the tags below it are still chips, which is correct',
        (tester) async {
      // A control: the fix is about one widget, not about banning `Chip` from
      // the card. Without this the test above passes for a change that
      // stripped every pill off the screen.
      await pumpCard(tester, kid());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'kids-emma'), findsOneWidget);
    });

    testWidgets('the server-owned lines are labelled as the server\'s',
        (tester) async {
      // The three lines come from three places — the age from this phone, the
      // cap and the hours from Jellyfin — and stacked in one column they read
      // as one list of Garfin's.
      await pumpCard(tester, kid(birthYear: 2015));
      await tester.pumpAndSettle();

      expect(find.text('Parental controls for Emma'), findsOneWidget);

      final heading = tester.getRect(find.text('Parental controls for Emma'));
      final age = tester.getRect(find.textContaining('years old'));
      final cap = tester.getRect(find.text('Up to PG'));
      expect(age.top, lessThan(heading.top),
          reason: 'the age is this phone\'s and belongs above the heading');
      expect(cap.top, greaterThan(heading.top),
          reason: 'the cap is the server\'s and belongs under it');
    });

    // **One test per case, not one loop over six.** The first version looped
    // inside a single test and reported that English overflowed while French —
    // the longer string — did not. That asymmetry ran against the mechanism,
    // was queried in review, and was a harness artifact: `takeException()` is
    // per-test state, and a pump that overflows *two* rows leaves accounting
    // the next iteration inherits.
    //
    // Measured properly, one case per test, with each row unflexed in turn:
    // **French overflows at 1.0x — the default text scale — on both rows**,
    // and English from 1.5x. So this was never an accessibility edge case in
    // French; it was a 296dp phone with no settings changed.
    //
    // The lesson is the general one this repo keeps relearning: a loop of
    // pumps in one test cannot say which pump failed.
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        testWidgets(
            'the card fits 296dp at ${scale}x in ${locale.languageCode}',
            (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    // Scrollable, as the Kids screen itself is: at 2x the card
                    // is taller than a test viewport, and a vertical overflow
                    // here would be the harness rather than the card. The
                    // claim under test is horizontal.
                    body: SingleChildScrollView(
                      child: SizedBox(
                        width: 296,
                        child: KidCard(kid: kid(), session: session),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull,
              reason: 'the card overflowed at 296dp, '
                  '${locale.languageCode} ${scale}x');
        });
      }
    }

    testWidgets('the help button is big enough to hit', (tester) async {
      // 48dp is the Material and Android interactive minimum. It measured
      // 40x40 with `visualDensity: compact` — on the one control that
      // explains the card to a parent who could not read it.
      await pumpCard(tester, kid());
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('and the explanation says who owns them and where they live',
        (tester) async {
      await pumpCard(tester, kid());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();

      // Reads them, never writes them — ground rule 8, said plainly, because
      // a limit nobody explains reads as a missing feature.
      expect(find.textContaining('never writes them'), findsOneWidget);
      // The path, in Jellyfin's own menu names.
      expect(find.textContaining('Dashboard'), findsOneWidget);
      expect(find.textContaining('Parental Control'), findsOneWidget);
      // The question the mode label used to provoke and never answer.
      expect(find.textContaining('adds and removes titles'), findsOneWidget);
      // And the birth year, which sounds like it should drive the cap.
      expect(find.textContaining('Jellyfin stores no birth year'),
          findsOneWidget);
    });
  });

  testWidgets('in French the status reads as a state, not an action (#76)',
      (tester) async {
    // The other half of the report, and the reason it was read as a button:
    // "Sélection" is both a noun and what a select button does. The pill is
    // gone, but the requirement outlived it — whatever carries the mode has to
    // read as a state rather than as something to press, and it now does that
    // inside the sentence introducing the labels.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: KidCard(kid: kid(), session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Its own scope rather than `pumpCard`, for the locale — so it opens the
    // card itself.
    await tester.tap(find.text('Emma'));
    await tester.pumpAndSettle();

    expect(
      find.text('Liste de sélection basée sur les étiquettes suivantes :'),
      findsOneWidget,
    );
    expect(find.text('Sélection'), findsNothing);
    expect(find.widgetWithText(InkWell, 'Sélection'), findsNothing,
        reason: 'it reports, it does not act');
  });

  testWidgets('a block-list account says so, and never says Shortlist',
      (tester) async {
    // Ground rule 3: opposite verbs. Labelling a blocklist as a shortlist
    // would invert what the parent thinks every later action does.
    await pumpCard(tester, kid(allowed: const [], blocked: const ['horror']));
    await tester.pumpAndSettle();

    expect(find.text('Blocklist based on these labels:'), findsOneWidget);
    expect(find.text('Shortlist based on these labels:'), findsNothing,
        reason: 'ground rule 3: for this account the labels mean the opposite');
    expect(find.text('horror'), findsOneWidget);
  });

  testWidgets('a conflicting account is stated, not resolved', (tester) async {
    await pumpCard(
      tester,
      kid(allowed: const ['ok'], blocked: const ['nope']),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Garfin can't tell which one you meant"),
        findsOneWidget);
    // Neither sentence, because neither verb is Garfin's to pick here.
    expect(find.textContaining('based on these labels:'), findsNothing,
        reason: 'ground rule 3 forbids choosing a verb for this account');
    // Neither list is shown as "the" tags — offering one would be the guess
    // the whole state exists to avoid.
    expect(find.text('ok'), findsNothing);
    expect(find.text('nope'), findsNothing);
  });

  testWidgets('an uncapped child is not given a rating it does not have',
      (tester) async {
    await pumpCard(tester, kid(cap: null, capName: null));
    await tester.pumpAndSettle();

    expect(find.text('No rating limit'), findsOneWidget);
  });

  testWidgets('a cap the ladder cannot name shows the number, not a guess',
      (tester) async {
    await pumpCard(tester, kid(cap: 99, capName: null));
    await tester.pumpAndSettle();

    expect(find.text('Rating limit 99'), findsOneWidget);
  });

  group('an unnameable cap shows its sub-level only when it means something',
      () {
    // The cap is a pair and the server enforces both halves, so a fallback
    // printing the score alone renders two different caps identically. It is
    // the fallback that had to change: the named case was already correct.

    testWidgets('an absent sub-level is not printed, because it behaves as 0',
        (tester) async {
      await pumpCard(tester, kid(cap: 99, capName: null));
      await tester.pumpAndSettle();

      expect(find.text('Rating limit 99'), findsOneWidget);
      expect(find.textContaining('99/'), findsNothing);
    });

    testWidgets('an explicit 0 is not printed either, for the same reason',
        (tester) async {
      await pumpCard(tester, kid(cap: 99, subCap: 0, capName: null));
      await tester.pumpAndSettle();

      expect(find.text('Rating limit 99'), findsOneWidget);
      expect(find.textContaining('99/'), findsNothing);
    });

    testWidgets('a non-zero sub-level is printed, because it changes the cap',
        (tester) async {
      await pumpCard(tester, kid(cap: 99, subCap: 1, capName: null));
      await tester.pumpAndSettle();

      expect(find.text('Rating limit 99/1'), findsOneWidget);
    });

    testWidgets('the regression this exists for: 99/0 and 99/1 do not read '
        'the same', (tester) async {
      await pumpCard(tester, kid(cap: 99, subCap: 0, capName: null));
      await tester.pumpAndSettle();
      final strict = find.text('Rating limit 99').evaluate().length;

      await pumpCard(tester, kid(cap: 99, subCap: 1, capName: null));
      await tester.pumpAndSettle();
      final loose = find.text('Rating limit 99').evaluate().length;

      expect(strict, 1);
      expect(loose, 0, reason: 'a looser cap must not render as the stricter one');
      expect(find.text('Rating limit 99/1'), findsOneWidget);
    });

    testWidgets('a named cap is unaffected by the sub-level', (tester) async {
      await pumpCard(tester, kid(cap: 10, subCap: 1, capName: 'TV-PG-D'));
      await tester.pumpAndSettle();

      expect(find.text('Up to TV-PG-D'), findsOneWidget);
      expect(find.textContaining('Rating limit'), findsNothing);
    });
  });

  testWidgets('a child with no birth year is invited to have one',
      (tester) async {
    // Jellyfin has no DateOfBirth, so the absence is normal rather than an
    // error, and the card asks rather than showing a blank or a zero.
    await pumpCard(tester, kid());
    await tester.pumpAndSettle();

    expect(find.text('Add a birth year'), findsOneWidget);
    expect(find.textContaining('years old'), findsNothing);
  });

  // The section that listed accounts Garfin cannot manage is gone, and its
  // four tests with it: they asserted that those rows drew a picture, an
  // initial, three distinguishable entries, and no tap target. There are no
  // rows now, so each of them was asserting about a widget that is not built.
  //
  // What replaced them is `kids_only_managed_test.dart`, which asserts the
  // opposite property — that such an account is never named on this screen —
  // and fails on the old code by finding "Dad" on it. The coverage moved
  // rather than went.

  group('UserAvatar, the widget both lists now share', () {
    testWidgets('a name starting outside the BMP is not cut in half',
        (tester) async {
      // `name[0]` would take half a surrogate pair and render a replacement
      // box. Emoji display names are ordinary on a family server.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(name: '🐟 Fishy', avatarUrl: null),
          ),
        ),
      );

      expect(find.text('🐟'), findsOneWidget);
    });

    testWidgets('a blank name falls back to a question mark, not a crash',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: UserAvatar(name: '   ', avatarUrl: null)),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });
  });
}
