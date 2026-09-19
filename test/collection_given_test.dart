// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/widgets/collection_given_line.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/screens/library_screen.dart';
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
                  KidSummary(user: kid),
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
                  KidSummary(user: kid),
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

  group('on the library grid tile', () {
    const session = AuthSession(
      serverUrl: 'http://host:8096',
      accessToken: 'token',
      userId: 'admin-1',
      userName: 'Parent',
    );
    late FakeJellyfinServer gridServer;
    setUp(() {
      gridServer = FakeJellyfinServer();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Map<String, dynamic> gitem(String id, String name,
            {String type = 'Movie',
            List<String> tags = const [],
            int? childCount}) =>
        <String, dynamic>{
          'Id': id,
          'Name': name,
          'Type': type,
          'Tags': tags,
          'ChildCount': ?childCount,
        };

    /// The grid does not build the collection index -- `index()` is 1 + N
    /// requests and nothing on this path pays it. Each collection tile asks
    /// for its own membership instead, so this scripts one members query
    /// alongside the grid page.
    Future<void> pumpGrid(
      WidgetTester tester,
      JellyfinUser? kid, {
      // The server's `ChildCount` for the drawn set. Absent is a real state:
      // the field only arrives when `Fields` asks for it, and #110 keeps those
      // collections on the grid rather than dropping them.
      int? childCount = 6,
      // Whether the membership request answers at all. A 500 rather than a
      // transport error, because that is what a Jellyfin server does.
      bool membershipFails = false,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      const label = 'kids-emma';

      if (membershipFails) {
        gridServer.onQuery(
          '/Items',
          (q) => q['parentId'] == 'coll-1',
          status: 500,
          json: <String, dynamic>{},
        );
      } else {
        gridServer.onQuery(
          '/Items',
          (q) => q['parentId'] == 'coll-1',
          json: <String, dynamic>{
            'TotalRecordCount': 6,
            'Items': [
              for (var i = 0; i < 6; i++)
                gitem('film-$i', 'Film $i',
                    tags: i < 4 ? const [label] : const []),
            ],
          },
        );
      }
      gridServer.onQuery(
        '/Items',
        (q) => q['parentId'] == null,
        json: <String, dynamic>{
          'TotalRecordCount': 2,
          'Items': [
            gitem('coll-1', 'Phase One',
                type: 'BoxSet', childCount: childCount),
            // An empty set beside it (#109). The grid must neither draw it nor
            // ask about it, and this harness is where the asking happens —
            // `LibraryRepository.fetch` never requests a membership.
            gitem('coll-2', 'Nothing Here', type: 'BoxSet', childCount: 0),
          ],
        },
      );
      gridServer.fallback(
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
                adapter: gridServer,
              ),
            ),
            kidsOverviewProvider(session).overrideWith(
              (ref) async => KidsOverview(
                shortlisted: [
                  if (kid != null)
                    KidSummary(user: kid),
                ],
                withoutShortlist: const <UnshortlistedUser>[],
              ),
            ),
            parentalRatingLadderProvider(session)
                .overrideWith((ref) async => const ParentalRatingLadder.empty()),
            if (kid != null)
              pickingForProvider.overrideWith(() => _Picked(kid.id)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: LibraryScreen(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a collection tile shows how much of the set is theirs',
        (tester) async {
      // **The sentence became a ring**, chosen over numerals by the owner on
      // the reasoning that a set whose ring is ambiguous is one tap from the
      // sentence in full. So the tile is asserted through the ring and the
      // sentence through the label it still carries — the fact did not move,
      // only its rendering.
      await pumpGrid(tester, child());
      expect(find.text('Phase One'), findsOneWidget);
      expect(find.byType(GivenRing), findsOneWidget);
      expect(find.text('4 of 6 given to Emma'), findsNothing);

      final ring = tester.getSemantics(find.byType(GivenRing));
      expect(ring.label, '4 of 6 given to Emma');
    });

    testWidgets('and shows nothing with nobody picked', (tester) async {
      // The control. Without it the assertion above could pass on a ring that
      // is simply always drawn -- and the proportion is a child's, so there is
      // no neutral form for it to fall back to.
      await pumpGrid(tester, null);
      expect(find.text('Phase One'), findsOneWidget);
      expect(find.byType(GivenRing), findsNothing);
    });

    testWidgets('the share reads as numerals beside the ring (#108)',
        (tester) async {
      // The ring alone was reported unnoticeable on a phone. A proportion you
      // have to interpret becomes one you read, and the count it stands in for
      // is not lost — it is the denominator.
      await pumpGrid(tester, child());

      expect(find.text('4/6'), findsOneWidget);
      expect(find.byType(GivenRing), findsOneWidget);
      // The count badge it replaced, gone rather than doubled up.
      expect(find.text('6 titles'), findsNothing);
    });

    testWidgets('and it sits on the poster, not under the title',
        (tester) async {
      // Where it was is the whole of why it was missed: the tile's smallest
      // text zone, below the artwork. The badge row is on the poster.
      await pumpGrid(tester, child());

      final ring = tester.getRect(find.byType(GivenRing));
      final title = tester.getRect(find.text('Phase One'));
      final poster = tester.getRect(find.byType(ClipRRect).first);

      // **Inside the poster**, not merely above the title. "Above the title"
      // is also true of anything placed earlier in the column, so it does not
      // separate the artwork from the space around it — the first version of
      // this assertion said only that and passed on a badge moved back into
      // the column.
      expect(poster.contains(ring.center), isTrue,
          reason: 'the badge is on the artwork');
      expect(ring.bottom, lessThan(title.top));
    });

    testWidgets('with nobody picked the badge is the plain count',
        (tester) async {
      // The control: there is no child to have a share, so the badge falls
      // back rather than disappearing — and the tile still says how big the
      // set is.
      await pumpGrid(tester, null);

      expect(find.text('6 titles'), findsOneWidget);
      expect(find.byType(GivenRing), findsNothing);
      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('a share that cannot be worked out leaves the count standing',
        (tester) async {
      // **The corner must not go blank while the share is unknown.** The share
      // is one membership request per visible collection tile, so between
      // first paint and its answer there is nothing to say — and if the
      // request fails there never will be. Before this, the tile lost the
      // "{count} titles" badge along with the ring, because the fallback was
      // written as `givenBadge ?? count` and the share widget is not null on
      // the paths where it draws nothing.
      //
      // A 500 rather than a slow reply: it is the same state as loading, held
      // still, and it is the half that is permanent.
      await pumpGrid(tester, child(), membershipFails: true);

      expect(find.text('Phase One'), findsOneWidget);
      expect(find.byType(GivenRing), findsNothing,
          reason: 'there is no share to draw');
      expect(find.text('6 titles'), findsOneWidget,
          reason: 'but the set is still six titles, and the tile still says so');
    });

    testWidgets('a set of unknown size can still show a share', (tester) async {
      // The other half of the same mistake: the share sat inside the count's
      // `childCount != null` guard, and it does not need one. The size comes
      // from the membership this widget already has — `set.size` — not from
      // the field the server may not have sent.
      //
      // These collections are on the grid deliberately (#110): a missing
      // `ChildCount` means the field was not asked for, not that the set is
      // empty. They were the tiles left with no badge and no share at all.
      await pumpGrid(tester, child(), childCount: null);

      expect(find.text('Phase One'), findsOneWidget);
      expect(find.text('4/6'), findsOneWidget,
          reason: 'four of six labelled, counted from the membership');
      expect(find.byType(GivenRing), findsOneWidget);
      // The badge's own shape rather than the bare word: the library screen's
      // search field says "Search titles", so a plain `textContaining` here
      // matches a widget that has nothing to do with this.
      expect(find.textContaining(RegExp(r'\d+ titles')), findsNothing,
          reason: 'nothing invents a size the server never sent');
    });

    testWidgets('and with neither, the corner is simply empty', (tester) async {
      // The fourth state of that corner, and the only one where nothing is
      // drawn: no `ChildCount` to fall back on and no share to put there.
      //
      // Worth asserting rather than reasoning about, because `UI-SPEC.md` now
      // states all four and three of them were the ones with tests. The
      // control is that the tile itself is on screen — an empty corner and an
      // absent tile look the same to every expectation below.
      await pumpGrid(tester, child(),
          childCount: null, membershipFails: true);

      expect(find.text('Phase One'), findsOneWidget,
          reason: 'the tile is drawn; it is the badge that has nothing to say');
      expect(find.byType(GivenRing), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ titles')), findsNothing);
    });

    testWidgets('an empty set costs no membership request (#109)',
        (tester) async {
      // **The half that is a saving rather than a tidy.** The grid asks for one
      // membership per visible collection tile, through `collectionSetProvider`
      // — so a set that is never drawn must leave no trace in the requests, not
      // merely none on screen.
      //
      // Asserted on the query rather than the path: a membership is
      // `GET /Items?parentId=<id>`, so the id never appears in a path. The
      // first version of this assertion looked for `/Items/coll-2` and could
      // not fail.
      await pumpGrid(tester, child());

      expect(find.text('Phase One'), findsOneWidget);
      expect(find.text('Nothing Here'), findsNothing);

      expect(
        gridServer.requests
            .where((r) => r.queryParameters['parentId'] == 'coll-2'),
        isEmpty,
        reason: 'a row that is never drawn never asks',
      );
      // The control: the set that *is* drawn does ask, so the absence above is
      // the filter working rather than the grid asking about nothing at all.
      expect(
        gridServer.requests
            .where((r) => r.queryParameters['parentId'] == 'coll-1'),
        isNotEmpty,
      );
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
