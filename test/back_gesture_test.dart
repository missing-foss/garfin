// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/active_session.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/home_tab_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/providers/unlock_providers.dart';
import 'package:garfin/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Android back gesture does.
///
/// The app is one route with an internal tab switch, so back had no meaning and
/// went straight to the system: from anywhere, it left the app. From a tab
/// other than Kids it now goes home instead — Kids is where a face tap sends
/// you, so back is the way out of where it sent you.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  /// [locked] puts the gate up, which is a state the gesture must pass through
  /// rather than be caught by.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool locked = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The store's own key, so this exercises the real lock controller rather
    // than a stubbed one — an empty preferences map leaves the gate UP.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'unlock_required': locked,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      kidsOverviewProvider(session).overrideWith(
        (ref) async => const KidsOverview(
          shortlisted: <KidSummary>[],
          withoutShortlist: <UnshortlistedUser>[],
        ),
      ),
      childSessionsProvider(session)
          .overrideWith((ref) async => <ActiveSession>[]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(
            state: AuthSignedIn(
              session: session,
              verified: true,
              justSignedIn: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The system gesture, as the framework delivers it.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('from another tab it goes back to Kids', (tester) async {
    final container = await pump(tester);
    container.read(homeTabProvider.notifier).go(HomeTab.settings);
    await tester.pumpAndSettle();

    expect(container.read(lockControllerProvider).isOpen, isTrue,
        reason: 'control: the gate is down, so the gesture reaches the tabs');

    await back(tester);

    expect(container.read(homeTabProvider), HomeTab.kids);
  });

  testWidgets('and from Kids it does not swallow the gesture',
      (tester) async {
    // The case the report was about: a `PopScope` that always intercepts
    // leaves a parent unable to leave the app from the screen it opens on.
    //
    // **Asserted on `canPop`, not on the tab.** The tab cannot tell the two
    // outcomes apart — the handler's only action is `go(HomeTab.kids)`, so an
    // interception from Kids lands on the value the test already had, and the
    // first version of this test passed whether the gesture reached the system
    // or was swallowed. Caught in review.
    //
    // `PopScope<Object>` explicitly: the type is generic and the shell's
    // infers `Object`, so a bare `find.byType(PopScope)` matches nothing and
    // hands zero widgets to the assertion — a test that passes by finding
    // nothing at all, which is the same failure in a smaller shape.
    final container = await pump(tester);
    expect(container.read(homeTabProvider), HomeTab.kids);

    expect(
      tester.widget<PopScope<Object>>(find.byType(PopScope<Object>)).canPop,
      isTrue,
      reason: 'from Kids the route must pop, which at the root means the '
          'system takes the gesture and the app closes',
    );

    await back(tester);

    expect(container.read(homeTabProvider), HomeTab.kids);
  });

  testWidgets('behind the lock it is not intercepted at all', (tester) async {
    // The lock screen is an overlay in a `Stack`, not a route, so back there
    // already means *leave the app* and cannot dismiss the gate. Catching the
    // gesture would send a parent to a tab they cannot see and leave them with
    // a back gesture that does nothing — worse than exiting.
    final container = await pump(tester, locked: true);
    expect(container.read(lockControllerProvider).isOpen, isFalse);
    container.read(homeTabProvider.notifier).go(HomeTab.settings);
    await tester.pumpAndSettle();

    await back(tester);

    expect(container.read(homeTabProvider), HomeTab.settings,
        reason: 'the gesture went to the system, not to the tab switch');
  });
}
