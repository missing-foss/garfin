// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/collection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// How much of a set is theirs, said on screen (#107).
///
/// The state this answers — *some* given, not all — was invisible to the parent
/// as well as to the child: the set's own tile says "not given", which is true
/// of the container and misleading about the eight titles inside it.
///
/// Two things are easy to get wrong here and both are asserted below: the count
/// is of **labels** rather than of what the child can see (ground rule 4), and
/// the **verb inverts** with the shortlist mode (ground rule 3) — the same
/// label gives to one child and withholds from another.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  JellyfinUser child({
    List<String> allowed = const ['kids-emma'],
    List<String> blocked = const [],
    String name = 'Emma',
  }) =>
      JellyfinUser(
        id: 'kid-1',
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: allowed,
          blockedTags: blocked,
        ),
      );

  group('the count itself', () {
    test('refuses to answer where there is no verb', () {
      // Nobody picked.
      expect(CollectionGiven.of(labelled: 3, total: 8, child: null), isNull);
      // Ground rule 3: both lists live, so no direction is correct.
      expect(
        CollectionGiven.of(
          labelled: 3,
          total: 8,
          child: child(allowed: ['a'], blocked: ['b']),
        ),
        isNull,
      );
      // No shortlist at all — Garfin cannot give them a first label either.
      expect(
        CollectionGiven.of(
          labelled: 0,
          total: 8,
          child: child(allowed: [], blocked: []),
        ),
        isNull,
      );
    });

    test('an empty set has nothing to say', () {
      expect(CollectionGiven.of(labelled: 0, total: 0, child: child()), isNull);
    });

    test('none, some and all are distinguishable', () {
      final none = CollectionGiven.of(labelled: 0, total: 8, child: child())!;
      expect((none.none, none.all), (true, false));

      final some = CollectionGiven.of(labelled: 3, total: 8, child: child())!;
      expect((some.none, some.all), (false, false));

      final all = CollectionGiven.of(labelled: 8, total: 8, child: child())!;
      expect((all.none, all.all), (false, true));
    });
  });

  group('on the collection screen', () {
    const session = AuthSession(
      serverUrl: 'http://host:8096',
      accessToken: 'token',
      userId: 'admin-1',
      userName: 'Parent',
    );

    late FakeJellyfinServer server;
    setUp(() {
      server = FakeJellyfinServer();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Map<String, dynamic> item(String id, String name,
            {String type = 'Movie', List<String> tags = const []}) =>
        <String, dynamic>{
          'Id': id,
          'Name': name,
          'Type': type,
          'Tags': tags,
        };

    /// Four of the six members carry the label, so "some" is the state under
    /// test and neither boundary can pass by accident.
    Future<void> pump(WidgetTester tester, JellyfinUser kid) async {
      final prefs = await SharedPreferences.getInstance();
      final label = kid.policy.shortlistTags.first;

      server.onQuery(
        '/Items',
        (q) => q['parentId'] == 'coll-1',
        json: <String, dynamic>{
          'TotalRecordCount': 6,
          'Items': [
            for (var i = 0; i < 6; i++)
              item('film-$i', 'Film $i', tags: i < 4 ? [label] : const []),
          ],
        },
      );
      server.fallback(json: <String, dynamic>{
        'TotalRecordCount': 0,
        'Items': <dynamic>[],
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
                shortlisted: [
                  KidSummary(user: kid, visibleCount: 4, libraryTotal: 40),
                ],
                withoutShortlist: const <UnshortlistedUser>[],
              ),
            ),
            parentalRatingLadderProvider(session)
                .overrideWith((ref) async => const ParentalRatingLadder.empty()),
            // Picked, so the screen has a child to answer about.
            pickingForProvider.overrideWith(() => _Picked(kid.id)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CollectionScreen(
              session: session,
              collection: const LibraryItem(
                id: 'coll-1',
                name: 'Phase One',
                type: 'BoxSet',
                tags: [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says how much of the set is theirs', (tester) async {
      await pump(tester, child());

      // The set's own count is unchanged — it is a fact about the library.
      expect(find.text('6 titles in this collection'), findsOneWidget);
      // And the state #107 is about, which nothing said before.
      expect(find.text('4 of 6 given to Emma'), findsOneWidget);
    });

    /// **The same four labels, the opposite sentence.** A block-list child is
    /// not a child with fewer things given to them; the label withholds. One
    /// count with one verb would be exactly backwards for every child in this
    /// mode, and nothing on screen would look wrong.
    testWidgets('inverts for a block-list child', (tester) async {
      await pump(
        tester,
        child(allowed: const [], blocked: const ['block-sam'], name: 'Sam'),
      );

      expect(find.text('4 of 6 kept from Sam'), findsOneWidget);
      expect(find.text('4 of 6 given to Sam'), findsNothing);
    });

    testWidgets('says nothing at all with nobody picked', (tester) async {
      final kid = child();
      final prefs = await SharedPreferences.getInstance();
      server.onQuery(
        '/Items',
        (q) => q['parentId'] == 'coll-1',
        json: <String, dynamic>{
          'TotalRecordCount': 2,
          'Items': [item('film-0', 'Film 0', tags: const ['kids-emma'])],
        },
      );
      server.fallback(
          json: <String, dynamic>{'TotalRecordCount': 0, 'Items': <dynamic>[]});

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
                shortlisted: [
                  KidSummary(user: kid, visibleCount: 1, libraryTotal: 40),
                ],
                withoutShortlist: const <UnshortlistedUser>[],
              ),
            ),
            parentalRatingLadderProvider(session)
                .overrideWith((ref) async => const ParentalRatingLadder.empty()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CollectionScreen(
              session: session,
              collection: const LibraryItem(
                id: 'coll-1',
                name: 'Phase One',
                type: 'BoxSet',
                tags: [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Everyone is selected, so there is no child to answer about and the
      // screen says nothing rather than guessing a direction.
      expect(find.textContaining('given to'), findsNothing);
      expect(find.textContaining('kept from'), findsNothing);
    });
  });
}

/// A `pickingForProvider` that starts on a given child rather than on Settings.
class _Picked extends PickingFor {
  _Picked(this._id);

  final String _id;

  @override
  String? build() => _id;
}
