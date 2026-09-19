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
import 'package:garfin/widgets/kid_card.dart';
import 'package:garfin/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The landing screen's two answers to "how does this look".
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

  Future<void> pump(
    WidgetTester tester, {
    required List<KidSummary> shortlisted,
    List<UnshortlistedUser> withoutShortlist = const [],
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
              withoutShortlist: withoutShortlist,
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

  group('nobody to look after yet', () {
    /// The ordinary first run: a server with accounts, none of them managed.
    /// Distinct from "no accounts at all", which is the only case the screen
    /// used to say anything about.
    testWidgets('invites the parent to set one up in Jellyfin',
        (tester) async {
      await pump(
        tester,
        shortlisted: const [],
        withoutShortlist: [
          UnshortlistedUser(user: user('u1', 'Dad'), avatarUrl: null),
        ],
      );

      expect(find.text('Nobody to look after yet'), findsOneWidget);
      expect(find.textContaining('already have a shortlist'), findsOneWidget);
      expect(find.text('How parental controls work in Jellyfin'),
          findsOneWidget);
    });

    testWidgets('and is gone the moment there is a child', (tester) async {
      await pump(tester, shortlisted: [kid('kid-1', 'Emma')]);

      expect(find.text('Nobody to look after yet'), findsNothing,
          reason: 'an invitation that outstays its case is clutter');
      expect(find.text('Emma'), findsOneWidget);
    });
  });

  group('the faces are sized to how many there are', () {
    test('fewer children, bigger faces — and a ceiling', () {
      expect(kidAvatarRadius(1), 36);
      expect(kidAvatarRadius(2), 36);
      expect(kidAvatarRadius(3), 30);
      expect(kidAvatarRadius(5), 24);
      // The ceiling is the point: an avatar arrives at whatever size it was
      // uploaded and Jellyfin ignores every request to resize it, so the app
      // cannot know a picture is small until it has drawn it too large.
      expect(kidAvatarRadius(1), lessThanOrEqualTo(36));
    });

    testWidgets('and the card actually uses it', (tester) async {
      await pump(tester, shortlisted: [kid('kid-1', 'Emma')]);

      final avatar =
          tester.widget<UserAvatar>(find.byType(UserAvatar).first);
      expect(avatar.radius, kidAvatarRadius(1),
          reason: 'the rule is only worth having if the card reads it');
    });
  });
}
