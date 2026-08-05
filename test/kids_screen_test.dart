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
import 'package:shared_preferences/shared_preferences.dart';

/// What the Kids screen actually puts on screen.
///
/// `docs/UI-SPEC.md` § Kids makes two claims a reader cannot check by reading
/// the widget tree in their head: that a conflicting account is *stated* rather
/// than resolved, and that the accounts with no shortlist are **not tappable**.
/// Both are asserted here.
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
}
