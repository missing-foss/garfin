// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/kids_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Ground-rule tests for the Kids screen's data.
///
/// `CLAUDE.md` § Conventions names the allow/block inversion as one of the two
/// places bugs hide here, so most of this is about which verb applies and what
/// happens when the answer is not a single one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const serverUrl = 'http://host:8096';

  Map<String, dynamic> user(
    String id,
    String name, {
    List<String> allowed = const [],
    List<String> blocked = const [],
    Object? maxParentalRating,
    bool admin = false,
    String? primaryImageTag,
  }) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'PrimaryImageTag': ?primaryImageTag,
        'Policy': <String, dynamic>{
          'IsAdministrator': admin,
          'IsDisabled': false,
          'AllowedTags': allowed,
          'BlockedTags': blocked,
          'MaxParentalRating': maxParentalRating,
        },
      };

  late FakeJellyfinServer server;
  late KidsRepository repository;

  Future<void> build({
    List<Map<String, dynamic>> users = const [],
    bool ratingsFail = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    server = FakeJellyfinServer();
    server
      ..on('/Users', json: users)
      ..on(
        '/Localization/ParentalRatings',
        status: ratingsFail ? 500 : 200,
        // Measured on 10.11.11: the FIRST entry carries no `Value` key at
        // all. A parser that assumes one crashes before reaching any real
        // rung, so this fixture leads with it deliberately.
        json: ratingsFail
            ? null
            : <Object>[
                <String, dynamic>{'Name': 'Unrated'},
                <String, dynamic>{'Name': 'PG', 'Value': 7},
                <String, dynamic>{'Name': 'PG-13', 'Value': 13},
              ],
      )
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

    repository = KidsRepository(
      api: JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: serverUrl),
      birthYears: BirthYearStore(prefs),
      serverUrl: serverUrl,
      adminUserId: 'admin-1',
    );
  }

  group('the allow/block inversion', () {
    test('AllowedTags means allow mode, and those are the tags', () async {
      await build(users: [user('k1', 'Emma', allowed: ['kids-emma'])]);
      final overview = await repository.load();

      final kid = overview.shortlisted.single;
      expect(kid.mode, ShortlistMode.allow);
      expect(kid.tags, ['kids-emma']);
    });

    test('BlockedTags means block mode, and those are the tags', () async {
      await build(users: [user('k2', 'Sam', blocked: ['horror'])]);
      final overview = await repository.load();

      final kid = overview.shortlisted.single;
      expect(kid.mode, ShortlistMode.block);
      expect(kid.tags, ['horror']);
    });

    test('both lists populated is surfaced, not resolved', () async {
      // Ground rule 3 says this never happens. The server permits it anyway,
      // so it can arrive from a library configured elsewhere — and there is no
      // correct verb to pick, because the two are opposites.
      await build(
        users: [user('k3', 'Alex', allowed: ['ok'], blocked: ['nope'])],
      );
      final overview = await repository.load();

      final kid = overview.shortlisted.single;
      expect(kid.mode, ShortlistMode.conflicting);
      // Neither list is offered as "the" tags. Returning one would be a guess
      // that silently reverses every later action.
      expect(kid.tags, isEmpty);
      // And it stays a card rather than being filed under "no shortlist",
      // which is the one thing definitely untrue about it.
      expect(overview.withoutShortlist, isEmpty);
    });

    test('no tags at all is a boundary, not a card', () async {
      await build(users: [user('a1', 'Parent', admin: true)]);
      final overview = await repository.load();

      expect(overview.shortlisted, isEmpty);
      expect(overview.withoutShortlist.single.name, 'Parent');
    });
  });

  group('the rating cap', () {
    test('resolves through the ladder, tolerating a valueless first entry',
        () async {
      await build(
        users: [user('k1', 'Emma', allowed: ['t'], maxParentalRating: 7)],
      );
      final overview = await repository.load();

      expect(overview.shortlisted.single.ratingCapName, 'PG');
    });

    test('an uncapped child has no rating name to show', () async {
      await build(users: [user('k1', 'Emma', allowed: ['t'])]);
      final overview = await repository.load();

      expect(overview.shortlisted.single.user.policy.maxParentalRating, isNull);
      expect(overview.shortlisted.single.ratingCapName, isNull);
    });

    test('a cap with no rung in the ladder is not rounded to a neighbour',
        () async {
      // The screen shows the raw number instead. Guessing which way to round a
      // safety control is the wrong place to be helpful.
      await build(
        users: [user('k1', 'Emma', allowed: ['t'], maxParentalRating: 99)],
      );
      final overview = await repository.load();

      expect(overview.shortlisted.single.ratingCapName, isNull);
      expect(overview.shortlisted.single.user.policy.maxParentalRating, 99);
    });

    test('a ladder that fails to load does not take the screen down',
        () async {
      await build(
        users: [user('k1', 'Emma', allowed: ['t'], maxParentalRating: 7)],
        ratingsFail: true,
      );

      final overview = await repository.load();

      // The cap still exists and is still enforced by the server; only its
      // name is missing.
      expect(overview.shortlisted.single.ratingCapName, isNull);
      expect(overview.shortlisted.single.user.policy.maxParentalRating, 7);
    });
  });

  group('counts come from the server', () {
    test('asked once as the admin and once per child, never computed',
        () async {
      await build(
        users: [
          user('a1', 'Parent', admin: true),
          user('k1', 'Emma', allowed: ['kids-emma']),
        ],
      );
      await repository.load();

      final itemQueries = server.requests
          .where((r) => r.path == '/Items')
          .toList(growable: false);

      // Ground rule 4: two calls, one per user id, not one call and some
      // arithmetic.
      expect(itemQueries.length, 2);
      expect(
        itemQueries.map((r) => r.queryParameters['userId']),
        containsAll(<String>['admin-1', 'k1']),
      );
      // Limit=0 asks for the count without the items, and Recursive=true is
      // required or it counts only top-level entries.
      for (final query in itemQueries) {
        expect(query.queryParameters['Limit'], 0);
        expect(query.queryParameters['Recursive'], true);
      }
    });
  });

  group('avatars', () {
    test('a user with no PrimaryImageTag gets no URL to request', () async {
      // Measured: the key is absent, not null, when there is no avatar. A 404
      // behind every initial would be the cost of asking anyway.
      await build(users: [user('k1', 'Emma', allowed: ['t'])]);
      final overview = await repository.load();

      expect(overview.shortlisted.single.avatarUrl, isNull);
    });

    test('the tag rides along, so a changed picture busts the cache', () async {
      await build(
        users: [user('k1', 'Emma', allowed: ['t'], primaryImageTag: 'abc123')],
      );
      final overview = await repository.load();

      expect(
        overview.shortlisted.single.avatarUrl,
        '$serverUrl/Users/k1/Images/Primary?tag=abc123',
      );
    });
  });

  group('the ladder parser directly', () {
    test('an entry with no Value is skipped rather than read as zero', () {
      final ladder = ParentalRatingLadder.fromJson(<Object>[
        <String, dynamic>{'Name': 'Unrated'},
        <String, dynamic>{'Name': 'PG', 'Value': 7},
      ]);

      expect(ladder.ratings.first.value, isNull);
      // A rung with no score is not a rung at score nothing.
      expect(ladder.nameFor(0), isNull);
      expect(ladder.nameFor(7), 'PG');
    });

    test('null in, null out — an uncapped child has nothing to name', () {
      expect(const ParentalRatingLadder.empty().nameFor(null), isNull);
    });
  });
}
