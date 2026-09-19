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
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/screens/home_screen.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which screen the app opens on, and that the navigation agrees with it.
///
/// **Three index-aligned lists decide this**: the destination icons, the
/// labels, and the `switch` on the selected tab. Reordering means moving all
/// three, and getting two of them right leaves an app whose second destination
/// opens the first screen — which looks like a mis-tap rather than a bug and
/// would survive review easily.
///
/// So this asserts the pairing rather than the number: Kids opens, and
/// selecting the *second* destination gives the Library. A test that only
/// checked "index 0 is Kids" would pass on a shell whose labels had drifted out
/// of step with its body.
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

  Future<void> pumpShell(WidgetTester tester) async {
    // A phone, so the destinations are a NavigationBar. The default 800dp
    // surface is past the rail breakpoint and would give a NavigationRail —
    // the same four destinations, but not the widget this asserts on.
    await tester.binding.setSurfaceSize(const Size(412, 900));
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
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            state: const AuthSignedIn(session: session, verified: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the app opens on Kids, not the Library', (tester) async {
    await pumpShell(tester);

    expect(find.byType(KidsScreen), findsOneWidget);
    // The negative half is the one that catches a half-done reorder.
    expect(find.byType(LibraryScreen), findsNothing);
  });

  testWidgets('the second destination is the Library', (tester) async {
    await pumpShell(tester);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0, reason: 'the opened tab is the selected one');

    bar.onDestinationSelected!(1);
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(KidsScreen), findsNothing);
  });
}
