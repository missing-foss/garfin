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

/// The landing screen re-reads `/Sessions` on a timer — and only that.
///
/// Two things make this worth pinning rather than reading. The sessions and the
/// per-child counts are **one dependency chain**, so refreshing the wrong half
/// puts a query that takes 8.7 s at six thousand titles on a ten-second loop.
/// And Stop and End answer 204 whether or not the client obeyed, so both
/// commands re-read `/Sessions` a few seconds later to say what actually
/// happened — a poll landing inside that window asks the server before it can
/// reflect the command and redraws the card as though nothing had.
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
      ),
    ),
  );

  late int overviewBuilds;
  late int sessionBuilds;

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    overviewBuilds = 0;
    sessionBuilds = 0;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kidsOverviewProvider(session).overrideWith((ref) async {
            overviewBuilds++;
            return KidsOverview(
              shortlisted: [emma],
              withoutShortlist: const <UnshortlistedUser>[],
            );
          }),
          childSessionsProvider(session).overrideWith((ref) async {
            sessionBuilds++;
            return <ActiveSession>[];
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: KidsScreen(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(KidsScreen)));
  }

  /// Long enough for one tick, short enough that two cannot fit.
  final oneInterval = sessionPollInterval + const Duration(seconds: 1);

  testWidgets('the timer re-reads the sessions and never the overview',
      (tester) async {
    await pumpScreen(tester);
    expect(sessionBuilds, 1);
    expect(overviewBuilds, 1);

    await tester.pump(oneInterval);
    await tester.pumpAndSettle();

    expect(sessionBuilds, 2, reason: 'the tick must re-read /Sessions');
    // The half that matters: the counts query is the expensive one and must
    // not be on a ten-second loop.
    expect(overviewBuilds, 1,
        reason: 'the overview carries the per-child counts and must not poll');
  });

  testWidgets('a tick is skipped while a command waits on its read-back',
      (tester) async {
    final container = await pumpScreen(tester);
    expect(sessionBuilds, 1);

    container.read(sessionCommandsInFlightProvider.notifier).begin();
    await tester.pump(oneInterval);
    await tester.pumpAndSettle();

    expect(sessionBuilds, 1,
        reason: 'the verifier is about to say what happened; the poll must not '
            'redraw the card with the state the command has not reached yet');

    // Skipped, not queued: once the command settles the next tick behaves
    // normally rather than firing a backlog.
    container.read(sessionCommandsInFlightProvider.notifier).end();
    await tester.pump(oneInterval);
    await tester.pumpAndSettle();

    expect(sessionBuilds, 2);
  });

  testWidgets('leaving the screen stops the timer', (tester) async {
    await pumpScreen(tester);
    expect(sessionBuilds, 1);

    // The shell builds one destination at a time, so navigating away disposes
    // this screen. Replacing it here is that, without the shell.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    await tester.pump(oneInterval);
    await tester.pumpAndSettle();

    expect(sessionBuilds, 1, reason: 'a disposed screen must not keep polling');
  });

  testWidgets('pulling to refresh re-reads the sessions, not the counts',
      (tester) async {
    await pumpScreen(tester);
    expect(sessionBuilds, 1);
    expect(overviewBuilds, 1);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();

    expect(sessionBuilds, 2);
    expect(overviewBuilds, 1,
        reason: 'a gesture a parent can repeat freely must not re-run the '
            'per-child counts');
  });
}
