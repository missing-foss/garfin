// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/active_session.dart';
import 'package:garfin/models/activity_entry.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/providers/activity_providers.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one-time thank-you card on Kids.
///
/// Once, after the 50th action, and never again: not on the next visit, not
/// after an update. Every case here is on the real Kids screen, because where
/// the card sits — past the unlock — is half of what it promises.
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

  const body =
      "Garfin has saved 50 tag changes for you. If it's useful, a coffee helps.";

  Future<ProviderContainer> pump(
    WidgetTester tester,
    SharedPreferences prefs, {
    Key? key,
    Widget home = const Scaffold(body: KidsScreen(session: session)),
  }) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        key: key,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kidsOverviewProvider(session).overrideWith(
            (ref) async => KidsOverview(
              shortlisted: [emma],
              withoutShortlist: const <UnshortlistedUser>[],
            ),
          ),
          childSessionsProvider(
            session,
          ).overrideWith((ref) async => <ActiveSession>[]),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  testWidgets('not before the 50th action', (tester) async {
    await pump(tester, await prefsWith({'activity_total': 49}));

    expect(find.text('Emma'), findsOneWidget, reason: 'the screen is up');
    expect(find.text(body), findsNothing);
  });

  testWidgets('at 50 it appears once, and not on the next visit', (
    tester,
  ) async {
    final prefs = await prefsWith({'activity_total': 50});
    await pump(tester, prefs);

    expect(find.text(body), findsOneWidget);
    expect(find.text('Support on Ko-fi'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      prefs.getBool('support_card_shown'),
      isTrue,
      reason: 'marked as soon as it is drawn, answered or not',
    );

    // Leave Kids and come back, in the same run of the app.
    await pump(tester, prefs, home: const Scaffold(body: Text('Library')));
    expect(find.text(body), findsNothing);
    await pump(tester, prefs);
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text(body), findsNothing, reason: 'not on the next visit');

    // And after a relaunch.
    await pump(tester, prefs, key: UniqueKey());
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text(body), findsNothing, reason: 'not after a relaunch');
  });

  testWidgets('Not now closes it', (tester) async {
    await pump(tester, await prefsWith({'activity_total': 50}));

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text(body), findsNothing);
  });

  testWidgets('shown once already: never again, however many actions', (
    tester,
  ) async {
    await pump(
      tester,
      await prefsWith({'activity_total': 500, 'support_card_shown': true}),
    );

    expect(find.text(body), findsNothing);
  });

  testWidgets('the 50th action is noticed without a relaunch', (tester) async {
    final prefs = await prefsWith({'activity_total': 49});
    final container = await pump(tester, prefs);
    expect(find.text(body), findsNothing);

    await tester.runAsync(
      () => container
          .read(activityStoreProvider)
          .add(
            ActivityEntry(
              itemId: 'item-50',
              itemName: 'Paddington',
              childId: 'kid-1',
              childName: 'Emma',
              label: 'kids-emma',
              gaveAccess: true,
              at: DateTime(2026, 10, 24),
            ),
          ),
    );
    await tester.pumpAndSettle();

    expect(find.text(body), findsOneWidget);
  });
}
