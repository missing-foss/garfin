// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
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
/// The age on a child's card can be changed by tapping it, so it is sized
/// and announced as the control it is (#219).
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
          localizationsDelegates: appLocalizationsDelegates,
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

  Finder ageTarget() => find.ancestor(of: find.text(ageOf(2016)), matching: find.byType(InkWell)).first;

  testWidgets('the age line is a full-size tap target of its own', (tester) async {
    await pump(tester);

    expect(tester.getSize(ageTarget()).height, greaterThanOrEqualTo(kMinInteractiveDimension));
  });

  testWidgets('a screen reader hears a button that changes the birth year', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(
      tester.getSemantics(find.text(ageOf(2016))),
      isSemantics(isButton: true, hint: 'Change the birth year', hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('tapping the age opens the birth-year dialog, not the card', (tester) async {
    await pump(tester);

    await tester.tap(find.text(ageOf(2016)));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Birth year')), findsWidgets);
  });
}
