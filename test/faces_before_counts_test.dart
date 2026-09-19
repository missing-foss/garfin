// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

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

/// The children are drawn before their counts arrive.
///
/// **Why this is worth a screen state of its own.** Listing the users is one
/// cheap request. The counts beside them are the most expensive thing the app
/// does — measured, a child's count is 19 ms when they can see one title and
/// 8.7 s at six thousand, and the administrator's total is 7.6 s on the same
/// library. Waiting for all of it before drawing anything meant a spinner for
/// as long as the slowest child took, on the first screen anyone sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  const emma = JellyfinUser(
    id: 'kid-1',
    name: 'Emma',
    policy: UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-emma'],
      blockedTags: [],
    ),
  );

  testWidgets('the faces are on screen while the counts are still in flight',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    // Never completes: this is the window the test is about.
    final counts = Completer<KidsOverview>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kidsRosterProvider(session).overrideWith(
            (ref) async => const KidsRoster(
              shortlisted: [KidFace(user: emma, avatarUrl: null)],
              withoutShortlist: <UnshortlistedUser>[],
            ),
          ),
          kidsOverviewProvider(session).overrideWith((ref) => counts.future),
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

    expect(counts.isCompleted, isFalse);
    expect(find.text('Emma'), findsOneWidget,
        reason: 'the child is known, so she is drawn');
    // The number is genuinely not known yet, and nothing pretends otherwise —
    // no sentence, and no placeholder shaped like one.
    expect(find.textContaining('things visible'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'a spinner over names we already have is the bug this fixes');
  });
}
