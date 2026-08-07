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
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:garfin/widgets/library_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// What a tile says while a new child's query is in flight (#96).
///
/// #94 stopped the grid blanking to a spinner on every refresh, which is right
/// — a write, a pull-to-refresh and an Undo all happen constantly and all used
/// to throw away the tiles the parent was looking at. It applies to *every*
/// dependency change though, and choosing a different child is one, so the
/// previous child's feed now stays on screen for as long as the new query
/// takes: up to half a second, measured in #68.
///
/// Every per-child marker on those tiles was computed for somebody else.
/// Measured on this branch, one frame after selecting Léo:
///
///     before the fix:  Paddington. Leo has this, but the server isn't
///                      showing it to them. Their age limit is the usual
///                      reason.
///     after:           Paddington. Given to Emma
///
/// He had never been given it. That is the one shape of claim this app is most
/// careful about — ground rule 4 exists to stop it — and it was being said in
/// a sentence naming a specific child.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  JellyfinUser kid(String name, String tag) => JellyfinUser(
        id: 'id-$name',
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: [tag],
          blockedTags: const [],
        ),
      );

  testWidgets('a tile says nothing about a child it was not computed for',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final emma = kid('Emma', 'kids-emma');
    final leo = kid('Leo', 'kids-leo');

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeJellyfinServer()
      // One film, tagged for Emma. The visibility lookup says the server does
      // NOT show it to her, so it classifies as given-but-hidden for Emma.
      ..onQuery('/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] == 0,
          json: {
            'TotalRecordCount': 1,
            'Items': [
              <String, dynamic>{
                'Id': 'item-1',
                'Name': 'Paddington',
                'Type': 'Movie',
                'Tags': ['kids-emma'],
              },
            ],
          })
      ..onQuery('/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] != 0,
          json: {'TotalRecordCount': 1, 'Items': <Object>[]})
      ..onQuery('/Items', (q) => q.containsKey('ids'),
          json: {'TotalRecordCount': 0, 'Items': <Object>[]})
      ..fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      deviceIdentityProvider.overrideWithValue(
        const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      ),
      jellyfinApiFactoryProvider.overrideWithValue(
        JellyfinApiFactory(
          identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
          adapter: server,
        ),
      ),
      kidsOverviewProvider(session).overrideWith(
        (ref) async => KidsOverview(
          shortlisted: [
            KidSummary(user: emma, visibleCount: 0, libraryTotal: 0),
            KidSummary(user: leo, visibleCount: 0, libraryTotal: 0),
          ],
          withoutShortlist: const [],
        ),
      ),
      parentalRatingLadderProvider(session)
          .overrideWith((ref) async => const ParentalRatingLadder.empty()),
    ]);
    addTearDown(container.dispose);
    await container.read(kidsOverviewProvider(session).future);
    container.read(pickingForProvider.notifier).select(emma.id);
    if (container.read(hideSharedProvider)) {
      container.read(hideSharedProvider.notifier).toggle();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // The control: with Emma selected, the tile does say Emma's sentence.
    // Without this the test would pass over a grid that never classified
    // anything at all.
    expect(tester.getSemantics(find.byType(LibraryTile)).label,
        contains("Emma has this, but the server isn't showing it to them"));
    expect(find.text('Held back'), findsOneWidget);

    // Switch to Léo and look at the very next frame.
    container.read(pickingForProvider.notifier).select(leo.id);
    await tester.pump();

    // The tiles stay — that is #94 working, and throwing them away is the
    // cure that is worse than the disease.
    expect(find.byType(LibraryTile), findsOneWidget);
    expect(find.text('Paddington'), findsOneWidget);

    final mid = tester.getSemantics(find.byType(LibraryTile)).label;
    expect(mid, isNot(contains('Leo has this')),
        reason: 'the tile made a claim about a child it was not computed for');
    expect(mid, isNot(contains("isn't showing it to them")));
    expect(find.text('Held back'), findsNothing,
        reason: 'the badge is a per-child claim too');

    // The avatar row is untouched, because it is not relative to the
    // selection: it says who *has* the title, which is as true mid-flight as
    // after. (The issue expected this to need suppressing; it does not.)
    expect(mid, contains('Given to Emma'));

    // And neither is the age hint, which is the other half of the same
    // distinction: it is computed on this screen from the *current* child's
    // age against the item's own rating, so it already describes Léo.
    // Suppressing everything per-child would have removed a true statement
    // and made the hint flicker on every switch.
    expect(find.text('No age rating'), findsOneWidget,
        reason: 'the fresh age hint was suppressed along with the stale ones');

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // And once the new feed lands, the tile speaks about Léo again: he has not
    // been given it, so there is no badge and no held-back sentence.
    final after = tester.getSemantics(find.byType(LibraryTile)).label;
    expect(after, isNot(contains('Leo has this')));
    expect(after, contains('Given to Emma'));
  });
}
