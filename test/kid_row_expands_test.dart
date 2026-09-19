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
import 'package:garfin/models/media_library.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The per-library breakdown, and when it is allowed to cost anything.
///
/// **The rule this pins is about requests, not pixels.** The counts query
/// tracks the result set — 19 ms at one title, 8.7 s at six thousand — so a
/// landing screen that asked it per child per library on every open would be
/// the slowest screen in the app. It is fetched when a row is opened, for that
/// child, and not before.
///
/// A test that only checked "the numbers appear after a tap" would pass just as
/// well on a screen that had fetched them all at startup and hidden them, which
/// is the version that is actually expensive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  KidSummary kid(String id, String name) => KidSummary(
        user: JellyfinUser(
          id: id,
          name: name,
          policy: const UserPolicy(
            isAdministrator: false,
            isDisabled: false,
            allowedTags: ['t'],
            blockedTags: [],
          ),
        ),
      );

  final emma = kid('kid-1', 'Emma');
  final liam = kid('kid-2', 'Liam');

  late Map<String, int> fetches;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fetches = <String, int>{};
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kidsOverviewProvider(session).overrideWith(
            (ref) async => KidsOverview(
              shortlisted: [emma, liam],
              withoutShortlist: const <UnshortlistedUser>[],
            ),
          ),
          childSessionsProvider(session)
              .overrideWith((ref) async => <ActiveSession>[]),
          // Counted per child, so "opened Emma" and "fetched for Liam" are
          // distinguishable rather than one number.
          for (final childId in const ['kid-1', 'kid-2'])
            childLibraryCountsProvider(
              ChildLibrariesRequest(session: session, childId: childId),
            ).overrideWith((ref) async {
              fetches[childId] = (fetches[childId] ?? 0) + 1;
              return [
                const LibraryVisibleCount(
                  library: MediaLibrary(
                    id: 'lib-films',
                    name: 'Films',
                    collectionType: 'movies',
                  ),
                  visible: 12,
                ),
              ];
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
  }

  testWidgets('nothing per-library is fetched until a row is opened',
      (tester) async {
    await pumpScreen(tester);

    expect(fetches, isEmpty,
        reason: 'two children on screen and not one count requested');
    expect(find.text('Films'), findsNothing);
  });

  testWidgets('opening one row fetches for that child alone', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Emma'));
    await tester.pumpAndSettle();

    expect(find.text('Films'), findsOneWidget);
    expect(fetches['kid-1'], 1);
    // The half worth having: the other child's counts are still unasked.
    expect(fetches.containsKey('kid-2'), isFalse,
        reason: 'opening Emma must not fetch for Liam');
  });

  testWidgets('closing and reopening does not fetch twice', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Emma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emma'));
    await tester.pumpAndSettle();
    expect(find.text('Films'), findsNothing);

    await tester.tap(find.text('Emma'));
    await tester.pumpAndSettle();

    expect(find.text('Films'), findsOneWidget);
    expect(fetches['kid-1'], 1,
        reason: 'the answer is cached for the child, not re-asked per tap');
  });
}
