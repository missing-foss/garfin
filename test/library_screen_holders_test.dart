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
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The join that puts a child's face on a poster, wired up (#84).
///
/// `library_holders_test.dart` pins what the join answers and
/// `library_tile_test.dart` pins what a tile does with it. Neither notices if
/// the screen stops asking — and the screen is where the two halves meet, both
/// of them already in memory. So this pumps the real one: a library page with
/// tags from the fake server, a Kids overview beside it, and a face expected on
/// the tile with **no child selected**, which is the case the issue was raised
/// about.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  KidSummary kid(
    String name, {
    List<String> allowed = const [],
    List<String> blocked = const [],
  }) =>
      KidSummary(
        user: JellyfinUser(
          id: 'id-$name',
          name: name,
          policy: UserPolicy(
            isAdministrator: false,
            isDisabled: false,
            allowedTags: allowed,
            blockedTags: blocked,
          ),
        ),
        visibleCount: 0,
        libraryTotal: 0,
      );

  late FakeJellyfinServer server;

  setUp(() => server = FakeJellyfinServer());

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<String> tags,
    required List<KidSummary> kids,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    server.fallback(json: <String, dynamic>{
      'TotalRecordCount': 1,
      'Items': [
        <String, dynamic>{
          'Id': 'item-1',
          'Name': 'Paddington',
          'Type': 'Movie',
          'Tags': tags,
        },
      ],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
              shortlisted: kids,
              withoutShortlist: const <UnshortlistedUser>[],
            ),
          ),
          // Not what this test is about, and an unscripted ladder request would
          // answer with the item page above.
          parentalRatingLadderProvider(session)
              .overrideWith((ref) async => const ParentalRatingLadder.empty()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a tile carries the face of the child who has it',
      (tester) async {
    await pumpScreen(
      tester,
      tags: const ['kidnapping', 'kids-emma'],
      kids: [kid('Emma', allowed: const ['kids-emma'])],
    );

    expect(find.text('Paddington'), findsOneWidget);
    // Emma has no picture set, so the row falls back to her initial — the
    // letter is the assertion because it cannot come from anywhere else on
    // this screen. Her *name* appears in the picker row above the grid.
    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('a child who has not been given it is not on the tile',
      (tester) async {
    await pumpScreen(
      tester,
      tags: const ['dinosaur'],
      kids: [kid('Emma', allowed: const ['kids-emma'])],
    );

    expect(find.text('Paddington'), findsOneWidget);
    expect(find.text('E'), findsNothing);
  });

  testWidgets('a block-list child never reaches the row', (tester) async {
    // End to end, because this is the reading that would be exactly backwards:
    // the tag means the title is withheld from Sam.
    await pumpScreen(
      tester,
      tags: const ['no-horror'],
      kids: [kid('Sam', blocked: const ['no-horror'])],
    );

    expect(find.text('Paddington'), findsOneWidget);
    expect(find.text('S'), findsNothing);
  });
}
