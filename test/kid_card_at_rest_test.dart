// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/active_session.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a kid's card says before anyone taps it.
///
/// A face, a name, an age and a way in. Everything else is reference — read
/// when a question is asked — and the card has to *say* the rest is there, or
/// the tap is a thing only whoever built it knows about.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  final emma = KidSummary(
    user: const JellyfinUser(
      id: 'kid-1',
      name: 'Emma',
      policy: UserPolicy(
        isAdministrator: false,
        isDisabled: false,
        allowedTags: ['kids-emma'],
        blockedTags: [],
        maxParentalRating: 10,
      ),
    ),
    birthYear: 2016,
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kidsOverviewProvider(session).overrideWith(
            (ref) async => KidsOverview(
              shortlisted: [emma],
              withoutShortlist: const <UnshortlistedUser>[],
            ),
          ),
          childSessionsProvider(session)
              .overrideWith((ref) async => <ActiveSession>[]),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: KidsScreen(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The card's age, which is [KidSummary.ageIn] — the nominal
  /// `year - birthYear`.
  ///
  /// Deliberately *not* `guaranteedAge` from `age_suitability.dart`, which
  /// subtracts one more because only the year is stored. That one is the
  /// conservative age the Library reasons with when deciding whether to hint
  /// that something may be too old; this one is the age a parent would say out
  /// loud. Different questions, and the card is answering the second.
  String ageOf(int birthYear) => '${DateTime.now().year - birthYear} years old';

  group('at rest', () {
    testWidgets('the card is a face, a name, an age and a way in',
        (tester) async {
      await pump(tester);

      expect(find.text('Emma'), findsOneWidget);
      expect(find.text(ageOf(2016)), findsOneWidget);
      expect(find.text('Sign in on a device'), findsOneWidget);
    });

    testWidgets('and says nothing else', (tester) async {
      await pump(tester);

      // The bar the parent asked to lose. Its own type, so this cannot pass by
      // the text merely being absent.
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: 'the progress bar is the thing that was asked to go');
      expect(find.textContaining('things visible'), findsNothing);
      expect(find.text('Parental controls for Emma'), findsNothing);
      expect(find.byIcon(Icons.help_outline), findsNothing);
      expect(find.text('kids-emma'), findsNothing,
          reason: 'the tags are reference, not identity');
    });

    testWidgets('but shows that there is more', (tester) async {
      await pump(tester);

      expect(find.byIcon(Icons.expand_more), findsOneWidget,
          reason: 'hidden detail behind an unmarked tap is hidden twice');
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });
  });

  group('after the tap', () {
    testWidgets('the detail arrives', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Emma'));
      await tester.pumpAndSettle();

      expect(find.text('Parental controls for Emma'), findsOneWidget);
      expect(find.text('kids-emma'), findsOneWidget);
      // The headline count that used to be revealed here is gone entirely now,
      // replaced by the per-library card — same question, more resolution.
      expect(find.textContaining('things visible'), findsNothing);
      // The bar stays gone too — it was the rendering, not the fact.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.expand_less), findsOneWidget,
          reason: 'the affordance reports the state it put the card in');
    });

    testWidgets('the face is still its own target, not the expander',
        (tester) async {
      await pump(tester);
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();

      expect(find.text('Parental controls for Emma'), findsNothing,
          reason: 'tapping the picture picks the child; it does not reveal');
    });
  });
}
