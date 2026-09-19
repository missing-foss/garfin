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
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/home_tab_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/screens/home_screen.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:garfin/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tapping a child's picture means *pick this child*.
///
/// It sets the **same** selection the Library's "Picking for" row sets, then
/// goes there — one meaning for a face across the app, and one path rather than
/// a lookalike that would have to be kept in step.
///
/// **The near-miss half is the point of the second test.** This is the one
/// place on the landing screen where a mistap takes a parent somewhere they did
/// not ask to go, so the picture's target has to be the picture, not the row it
/// sits in. A test that only checked the tap *works* would pass just as well on
/// a card that navigated from anywhere on it.
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

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
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
          childSessionsProvider(session)
              .overrideWith((ref) async => <ActiveSession>[]),
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
    return ProviderScope.containerOf(tester.element(find.byType(KidsScreen)));
  }

  testWidgets('tapping the picture picks that child and opens the library',
      (tester) async {
    final container = await pumpShell(tester);
    expect(container.read(pickingForProvider), isNull);
    expect(container.read(homeTabProvider), HomeTab.kids);

    await tester.tap(find.byType(UserAvatar).first);
    // Bounded pumps, not `pumpAndSettle`: arriving at a narrowed grid for a
    // child whose feed has not been fetched shows an indeterminate progress
    // indicator, and nothing ever settles against one.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The Library's own selection, not a second one built for this screen —
    // so the grid, the cap chip and the assign sheet all arrive filtered.
    expect(container.read(pickingForProvider), 'kid-1');
    expect(container.read(homeTabProvider), HomeTab.library);
  });

  testWidgets('and lands on what that child can already see', (tester) async {
    final container = await pumpShell(tester);
    // The default the grid opens in otherwise, so the assertion below is about
    // the tap rather than about however the state happened to start.
    expect(container.read(libraryViewProvider), isNot(LibraryView.given));

    await tester.tap(find.byType(UserAvatar).first);
    // Bounded pumps, not `pumpAndSettle`: arriving at a narrowed grid for a
    // child whose feed has not been fetched shows an indeterminate progress
    // indicator, and nothing ever settles against one.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(libraryViewProvider), LibraryView.given);
    // **Both halves of "has access to".** A label is what Garfin gives; the
    // rating cap silently overrides it, so the labels alone would show a child
    // titles their own account refuses them.
    expect(container.read(libraryFiltersProvider).withinCap, isTrue,
        reason: 'the cap is the other half of what the child can see');
  });

  testWidgets('the giving grid is one tap away from there', (tester) async {
    final container = await pumpShell(tester);
    await tester.tap(find.byType(UserAvatar).first);
    // Bounded pumps, not `pumpAndSettle`: arriving at a narrowed grid for a
    // child whose feed has not been fetched shows an indeterminate progress
    // indicator, and nothing ever settles against one.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The whole reason this is a state and not a new grid: the administrator's
    // view is what "not given yet" is computed against, and it is still there.
    container.read(libraryViewProvider.notifier).set(LibraryView.toGive);

    expect(container.read(libraryViewProvider), LibraryView.toGive);
  });

  testWidgets('tapping the row beside the picture does not navigate',
      (tester) async {
    final container = await pumpShell(tester);

    // The child's name sits next to the picture, inside the same card.
    await tester.tap(find.text('Emma'));
    await tester.pumpAndSettle();

    expect(container.read(homeTabProvider), HomeTab.kids,
        reason: 'only the picture navigates; the rest of the row is not a '
            'near-miss on it');
    expect(container.read(pickingForProvider), isNull);
  });

  testWidgets('but arriving from the navigation shows Everyone', (tester) async {
    // The other half of #100, and the half a face tap must not break: coming
    // from a child's face means *this child*; coming from the navigation means
    // *the library*. Carrying the last child over would answer a question the
    // parent did not ask.
    final container = await pumpShell(tester);
    await tester.tap(find.byType(UserAvatar).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(pickingForProvider), 'kid-1');

    // Back to Kids, then into the Library from the bar rather than the face.
    container.read(homeTabProvider.notifier).go(HomeTab.kids);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(pickingForProvider), isNull);
    expect(container.read(homeTabProvider), HomeTab.library);
  });
}
