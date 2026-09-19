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

/// The Kids screen is the children under a rule, and nothing else.
///
/// Accounts Garfin cannot manage are not listed, not counted and not named.
/// They are still *known* — the roster carries them, because "no accounts at
/// all" and "accounts, none of them managed" want different screens — so the
/// thing worth testing is that knowing them does not put them on screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  JellyfinUser user(String id, String name, {List<String> allowed = const []}) =>
      JellyfinUser(
        id: id,
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: allowed,
          blockedTags: const [],
        ),
      );

  KidSummary kid(String id, String name) => KidSummary(
        user: user(id, name, allowed: const ['t']),
      );

  /// The household this screen is about: one managed child, and the adults.
  final unmanaged = <UnshortlistedUser>[
    UnshortlistedUser(user: user('u1', 'Dad'), avatarUrl: null),
    UnshortlistedUser(user: user('u2', 'Mum'), avatarUrl: null),
    UnshortlistedUser(user: user('u3', 'Guest'), avatarUrl: null),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required List<KidSummary> shortlisted,
  }) async {
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
              shortlisted: shortlisted,
              withoutShortlist: unmanaged,
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

  testWidgets('accounts with no rule are not named beside the children',
      (tester) async {
    await pump(tester, shortlisted: [kid('kid-1', 'Emma')]);

    expect(find.text('Emma'), findsOneWidget,
        reason: 'the managed child is the subject of the screen');
    for (final name in const ['Dad', 'Mum', 'Guest']) {
      expect(find.text(name), findsNothing,
          reason: '$name is not under a rule, so the screen says nothing of them');
    }
    // Not "no rows" but "no trace": the section that used to introduce them is
    // gone with them, and a heading left behind would be worse than the rows.
    expect(find.text('No shortlist yet'), findsNothing);
    expect(
      find.textContaining('Set their shortlist up in Jellyfin'),
      findsNothing,
    );
  });

  testWidgets('and the invitation still fires when none of them is managed',
      (tester) async {
    // The case that keeps the roster carrying accounts it will not draw. With
    // the data dropped rather than merely hidden, this is indistinguishable
    // from an empty server and the invitation is the wrong one.
    await pump(tester, shortlisted: const []);

    expect(find.text('Nobody to look after yet'), findsOneWidget);
    for (final name in const ['Dad', 'Mum', 'Guest']) {
      expect(find.text(name), findsNothing);
    }
  });
}
