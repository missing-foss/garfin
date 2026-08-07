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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:garfin/models/active_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/screens/kids_screen.dart';
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
          ),
        ),
        visibleCount: 12,
        libraryTotal: 40,
        ratingCapName: capName,
        birthYear: birthYear,
      );

  Future<void> pumpCard(WidgetTester tester, KidSummary summary) =>
      tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: KidCard(kid: summary, session: session)),
          ),
        ),
      );

  testWidgets('a card shows the name, count, cap, mode and tags',
      (tester) async {
    await pumpCard(tester, kid(birthYear: 2015));
    await tester.pumpAndSettle();

    expect(find.text('Emma'), findsOneWidget);
    // Both numbers came from the server. Ground rule 4.
    expect(find.text('12 of 40 things visible'), findsOneWidget);
    expect(find.text('Up to PG'), findsOneWidget);
    expect(find.text('Shortlist'), findsOneWidget);
    expect(find.text('kids-emma'), findsOneWidget);
    expect(find.textContaining('years old'), findsOneWidget);
  });

  group('whose settings these are (#74, #76)', () {
    testWidgets('the status is not drawn as something you can press',
        (tester) async {
      // Reported from use as "a 'select' button — it doesn't seem to work".
      // It never did: `_ModeChip` had no `onPressed`. The problem was that a
      // `Chip` is what this app uses for the library filter bar's *tappable*
      // `FilterChip`s and `ChoiceChip`s, so a pill taught the parent it was a
      // button and then ignored them.
      await pumpCard(tester, kid());
      await tester.pumpAndSettle();

      expect(find.text('Shortlist'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Shortlist'), findsNothing,
          reason: 'the status is drawn as a chip again');
      expect(find.widgetWithText(InkWell, 'Shortlist'), findsNothing,
          reason: 'and it must not be tappable either — it reports, it does '
              'not act');
    });

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

      expect(find.text('Set in Jellyfin'), findsOneWidget);

      final heading = tester.getRect(find.text('Set in Jellyfin'));
      final age = tester.getRect(find.textContaining('years old'));
      final cap = tester.getRect(find.text('Up to PG'));
      expect(age.top, lessThan(heading.top),
          reason: 'the age is this phone\'s and belongs above the heading');
      expect(cap.top, greaterThan(heading.top),
          reason: 'the cap is the server\'s and belongs under it');
    });

    testWidgets('the card survives a 296dp width at 200% text scale',
        (tester) async {
      // Raised in review as arithmetic that probably held. Measured, it did
      // not: two rows overflowed — the heading added here, and the header
      // row, which has had an inflexible status label beside an `Expanded`
      // since long before this change.
      //
      // Both locales, because the strings differ in length and the one that
      // overflowed first was the *shorter* one.
      for (final locale in const [Locale('en'), Locale('fr')]) {
        for (final scale in const [1.0, 1.5, 2.0]) {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    // Scrollable, as the Kids screen itself is: at 200% the
                    // card is simply taller than a test viewport, and a
                    // vertical overflow here would be the harness rather than
                    // the card. The claim under test is horizontal.
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
              reason: 'the card overflowed at ${locale.languageCode} '
                  '${scale}x on a 296dp width');
        }
      }
    });

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
    // "Sélection" is both a noun and what a select button does. The pair was
    // asymmetric too — a bare noun beside a named list — so the two did not
    // read as two values of one setting.
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

    expect(find.text('Liste de sélection'), findsOneWidget);
    expect(find.text('Sélection'), findsNothing);
  });

  testWidgets('a block-list account says so, and never says Shortlist',
      (tester) async {
    // Ground rule 3: opposite verbs. Labelling a blocklist as a shortlist
    // would invert what the parent thinks every later action does.
    await pumpCard(tester, kid(allowed: const [], blocked: const ['horror']));
    await tester.pumpAndSettle();

    expect(find.text('Blocklist'), findsOneWidget);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('horror'), findsOneWidget);
  });

  testWidgets('a conflicting account is stated, not resolved', (tester) async {
    await pumpCard(
      tester,
      kid(allowed: const ['ok'], blocked: const ['nope']),
    );
    await tester.pumpAndSettle();

    expect(find.text('Both lists are set'), findsOneWidget);
    expect(find.textContaining("Garfin can't tell which one you meant"),
        findsOneWidget);
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

  testWidgets('a child with no birth year is invited to have one',
      (tester) async {
    // Jellyfin has no DateOfBirth, so the absence is normal rather than an
    // error, and the card asks rather than showing a blank or a zero.
    await pumpCard(tester, kid());
    await tester.pumpAndSettle();

    expect(find.text('Add a birth year'), findsOneWidget);
    expect(find.textContaining('years old'), findsNothing);
  });

  group('the accounts Garfin does not manage (#79)', () {
    JellyfinUser parent(String name, {String? tag}) => JellyfinUser(
          id: 'p-$name',
          name: name,
          primaryImageTag: tag,
          policy: const UserPolicy(
            isAdministrator: true,
            isDisabled: false,
            allowedTags: <String>[],
            blockedTags: <String>[],
            maxParentalRating: null,
          ),
        );

    Future<void> pumpScreen(
      WidgetTester tester,
      List<UnshortlistedUser> unmanaged,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceIdentityProvider.overrideWithValue(
              const DeviceIdentity(deviceId: 'device-1', deviceName: 'Test'),
            ),
            kidsOverviewProvider(session).overrideWith(
              (ref) async => KidsOverview(
                shortlisted: const <KidSummary>[],
                withoutShortlist: unmanaged,
              ),
            ),
            // The screen also lists active sessions; this test is not about
            // those, and an unscripted request would leave a timer pending.
            childSessionsProvider(session)
                .overrideWith((ref) async => <ActiveSession>[]),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: KidsScreen(session: session)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a parent with a picture gets their picture', (tester) async {
      // The bug: this list built a bare CircleAvatar with a letter — not as a
      // fallback, as the only branch — so an account with an avatar set in
      // Jellyfin showed a grey circle while the children above it showed
      // faces.
      await pumpScreen(tester, [
        UnshortlistedUser(
          user: parent('Mum', tag: 'abc123'),
          avatarUrl: 'http://host:8096/Users/p-Mum/Images/Primary?tag=abc123',
        ),
      ]);

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, contains('/Users/p-Mum/Images/Primary'));
      expect(image.imageUrl, contains('tag=abc123'));
    });

    testWidgets('a parent with no picture still gets their initial',
        (tester) async {
      await pumpScreen(tester, [
        UnshortlistedUser(user: parent('Dad'), avatarUrl: null),
      ]);

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('D'), findsOneWidget);
    });

    testWidgets('three unmanaged accounts are three distinguishable rows',
        (tester) async {
      // Why this is worth a screen test rather than a widget one: the whole
      // point of the fix is telling accounts apart, and that only shows up
      // with more than one of them on screen at once.
      await pumpScreen(tester, [
        UnshortlistedUser(
          user: parent('Mum', tag: 't1'),
          avatarUrl: 'http://host:8096/Users/p-Mum/Images/Primary?tag=t1',
        ),
        UnshortlistedUser(
          user: parent('Dad', tag: 't2'),
          avatarUrl: 'http://host:8096/Users/p-Dad/Images/Primary?tag=t2',
        ),
        UnshortlistedUser(user: parent('Guest'), avatarUrl: null),
      ]);

      expect(find.byType(CachedNetworkImage), findsNWidgets(2));
      expect(find.text('G'), findsOneWidget);
    });

    testWidgets('the rows are still not tappable', (tester) async {
      // The assertion this file's header has always claimed to make. Ground
      // rule 8 is why: Garfin cannot give a child their first label, so a row
      // that looked tappable would be a dead end. Showing a picture must not
      // quietly turn a boundary into a control.
      await pumpScreen(tester, [
        UnshortlistedUser(
          user: parent('Mum', tag: 'abc'),
          avatarUrl: 'http://host:8096/Users/p-Mum/Images/Primary?tag=abc',
        ),
      ]);

      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Mum'), matching: find.byType(ListTile)),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    });
  });

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
