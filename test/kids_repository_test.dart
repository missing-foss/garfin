// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/repositories/kids_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Ground-rule tests for the Kids screen's data.
///
/// `docs/ENGINEERING.md` § Conventions names the allow/block inversion as one of the two
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
    bool disabled = false,
    String? primaryImageTag,
  }) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'PrimaryImageTag': ?primaryImageTag,
        'Policy': <String, dynamic>{
          'IsAdministrator': admin,
          'IsDisabled': disabled,
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
    Duration? countDelay,
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
                // Values are the measured ones, not invented: on 10.11.11's
                // default US ladder PG sits at 10, not 7, and score 0 is
                // shared four ways. A tidier fixture would have hidden the
                // collision the real ladder has.
                <String, dynamic>{'Name': 'Unrated'},
                <String, dynamic>{'Name': 'Approved', 'Value': 0},
                <String, dynamic>{'Name': 'G', 'Value': 0},
                <String, dynamic>{'Name': 'TV-Y7', 'Value': 7},
                <String, dynamic>{'Name': 'PG', 'Value': 10},
                <String, dynamic>{'Name': 'TV-PG', 'Value': 10},
              ],
      )
      ..fallback(
        json: <String, dynamic>{'TotalRecordCount': 10},
        delay: countDelay,
      );

    repository = KidsRepository(
      api: JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: serverUrl),
      birthYears: BirthYearStore(prefs),
      serverUrl: serverUrl,
    );
  }

  /// The production path in one call: the roster, then the counts on top of it.
  ///
  /// Kept as a helper rather than each test doing both, so a test can never
  /// accidentally exercise `load` against a roster it built itself — the split
  /// exists so the users are listed once, and that only holds if the same
  /// roster is what the counts are asked about.
  Future<KidsOverview> loadAll() async => repository.load(await repository.roster());

  group('the allow/block inversion', () {
    test('AllowedTags means allow mode, and those are the tags', () async {
      await build(users: [user('k1', 'Emma', allowed: ['kids-emma'])]);
      final overview = await loadAll();

      final kid = overview.shortlisted.single;
      expect(kid.mode, ShortlistMode.allow);
      expect(kid.tags, ['kids-emma']);
    });

    test('BlockedTags means block mode, and those are the tags', () async {
      await build(users: [user('k2', 'Sam', blocked: ['horror'])]);
      final overview = await loadAll();

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
      final overview = await loadAll();

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
      final overview = await loadAll();

      expect(overview.shortlisted, isEmpty);
      expect(overview.withoutShortlist.single.user.name, 'Parent');
    });
  });

  group('the rating cap', () {
    test('resolves through the ladder, tolerating a valueless first entry',
        () async {
      await build(
        users: [user('k1', 'Emma', allowed: ['t'], maxParentalRating: 10)],
      );
      final overview = await loadAll();

      expect(overview.shortlisted.single.ratingCapName, 'PG');
    });

    test('an uncapped child has no rating name to show', () async {
      await build(users: [user('k1', 'Emma', allowed: ['t'])]);
      final overview = await loadAll();

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
      final overview = await loadAll();

      expect(overview.shortlisted.single.ratingCapName, isNull);
      expect(overview.shortlisted.single.user.policy.maxParentalRating, 99);
    });

    test('a ladder that fails to load does not take the screen down',
        () async {
      await build(
        users: [user('k1', 'Emma', allowed: ['t'], maxParentalRating: 10)],
        ratingsFail: true,
      );

      final overview = await loadAll();

      // The cap still exists and is still enforced by the server; only its
      // name is missing.
      expect(overview.shortlisted.single.ratingCapName, isNull);
      expect(overview.shortlisted.single.user.policy.maxParentalRating, 10);
    });
  });

  group('the totals nobody displays are not fetched', () {
    test('loading the screen asks for no item count at all', () async {
      // This group used to assert the opposite — "asked once as the admin and
      // once per child, never computed" — and that was right while the card
      // showed "N of M things visible". The card does not, so the calls are
      // gone with it, and this asserts their absence instead of their shape.
      //
      // Worth a test rather than a comment: they were the most expensive calls
      // the app makes. Measured on 10.11.11, a child's count is 19 ms at one
      // visible title, 538 ms at 2000 and 8.7 s at 6000, and the administrator's
      // own total 7.6 s on that library — paid per child, on the first screen a
      // parent opens, again on every invalidation after a write. Something that
      // costly coming back by accident should break a test, not a phone.
      await build(
        users: [
          user('a1', 'Parent', admin: true),
          user('k1', 'Emma', allowed: ['kids-emma']),
          user('k2', 'Sam', allowed: ['kids-sam']),
        ],
      );
      await loadAll();

      expect(
        server.requests.where((r) => r.path == '/Items'),
        isEmpty,
        reason: 'no widget reads a total any more, so nothing should pay for '
            'one; the per-library counts are asked when a card is opened',
      );
    });

    test('and the ladder is still asked once, for everyone', () async {
      // What is left. It is a property of the server rather than of a child,
      // and it is what turns a cap of 10 into "Up to PG" on every card.
      await build(
        users: [
          user('k1', 'Emma', allowed: ['t']),
          user('k2', 'Sam', allowed: ['t']),
        ],
      );
      await loadAll();

      expect(
        server.requests.where((r) => r.path == '/Localization/ParentalRatings'),
        hasLength(1),
      );
    });
  });

  // The timing group that stood here measured that the children's counts ran
  // four at a time rather than one after another. There are no children's
  // counts now, so it measured nothing: with the fake's `countDelay` attached
  // to a request that is never made, it would have passed however the code was
  // written. A test that cannot fail is removed rather than left green.
  //
  // The parallelism itself has not been abandoned — `mapBounded` still fans the
  // per-library counts out at the house limit, and `kid_row_expands_test.dart`
  // is where that behaviour lives now, because that is where the requests are.

  group('when the server is unreachable', () {
    test('it surfaces from the roster, which is the request that is left',
        () async {
      // **This changed shape, and the change is worth stating.** `load` used to
      // make three requests and the assertion was that a failure reached the
      // screen as itself rather than as a wrapper, with nothing left unobserved.
      // Two of those three are gone, and the one that remains — the ratings
      // ladder — deliberately swallows its own error, because a cap that cannot
      // be named is not a reason to replace the screen with an error page.
      //
      // So `load` can no longer fail at all. Unreachability surfaces one step
      // earlier, from `roster`, which is the request that lists the children —
      // and `kidsOverviewProvider` awaits that first, so the screen still shows
      // the error rather than an empty list of children.
      await build(users: [user('k1', 'Emma', allowed: ['t'])]);
      // `onQuery`, not `on`: `build` has already queued a successful `/Users`
      // reply and a queued reply is **sticky**, so queueing a failure behind it
      // changes nothing and the test passes for the wrong reason. Matchers are
      // checked before the positional script.
      server.onQuery('/Users', (_) => true,
          failWith: DioExceptionType.connectionError);

      await expectLater(
        repository.roster(),
        throwsA(isA<JellyfinException>()),
        reason: 'the original error must reach the screen, not a wrapper — the '
            'Kids screen maps JellyfinException to a sentence a parent can act '
            'on and everything else to a generic one',
      );
    });

    test('a ladder that will not load does not take the screen down',
        () async {
      // The other half, and now the only failure `load` can meet. The caps are
      // still enforced by the server whether or not this app can name them.
      await build(users: [user('k1', 'Emma', allowed: ['t'], maxParentalRating: 10)]);
      final roster = await repository.roster();
      // Registered after the roster is in hand, and as a matcher for the same
      // reason as above: the ladder already has a good reply queued.
      server.onQuery('/Localization/ParentalRatings', (_) => true,
          failWith: DioExceptionType.connectionError);

      final overview = await repository.load(roster);

      expect(overview.shortlisted, hasLength(1));
      expect(overview.shortlisted.single.ratingCapName, isNull,
          reason: 'unnamed, not absent: the card falls back to the number');
    });
  });

  group('avatars', () {
    test('a user with no PrimaryImageTag gets no URL to request', () async {
      // Measured: the key is absent, not null, when there is no avatar. A 404
      // behind every initial would be the cost of asking anyway.
      await build(users: [user('k1', 'Emma', allowed: ['t'])]);
      final overview = await loadAll();

      expect(overview.shortlisted.single.avatarUrl, isNull);
    });

    test('an unmanaged account gets its picture too (#79)', () async {
      // The root of the bug: `avatarUrlFor` was only ever called while
      // assembling shortlisted kids, so the other half of the same screen had
      // no URL to show even when the user had an avatar set.
      await build(users: [user('a1', 'Mum', admin: true, primaryImageTag: 'xyz')]);
      final overview = await loadAll();

      expect(overview.shortlisted, isEmpty);
      expect(
        overview.withoutShortlist.single.avatarUrl,
        '$serverUrl/Users/a1/Images/Primary?tag=xyz',
      );
    });

    test('an unmanaged account with no picture gets no URL', () async {
      await build(users: [user('a1', 'Dad', admin: true)]);
      final overview = await loadAll();

      expect(overview.withoutShortlist.single.avatarUrl, isNull);
    });

    test('the tag rides along, so a changed picture busts the cache', () async {
      await build(
        users: [user('k1', 'Emma', allowed: ['t'], primaryImageTag: 'abc123')],
      );
      final overview = await loadAll();

      expect(
        overview.shortlisted.single.avatarUrl,
        '$serverUrl/Users/k1/Images/Primary?tag=abc123',
      );
    });
  });

  group('the ladder parser directly', () {
    test('an entry with no Value is skipped rather than read as zero', () {
      // 'Unrated' is the real valueless entry, and it is entry zero on a
      // default install. Score 0 is deliberately absent from this fixture so
      // the assertion below is about the valueless rung and nothing else — an
      // earlier version had no rung at 0 at all, which made the same
      // expectation pass for the wrong reason.
      final ladder = ParentalRatingLadder.fromJson(<Object>[
        <String, dynamic>{'Name': 'Unrated'},
        <String, dynamic>{'Name': 'PG', 'Value': 10},
      ]);

      expect(ladder.ratings.first.value, isNull);
      // A rung with no score is not a rung at score nothing.
      expect(ladder.nameFor(0), isNull);
      expect(ladder.nameFor(10), 'PG');
    });

    test('a shared score resolves to the first name, and that is documented',
        () {
      // Measured on the real ladder: six scores carry more than one name, and
      // they are the common ones — 0 is shared four ways, 10 seventeen ways,
      // 17 ten ways. Jellyfin stores only the integer, so which label the
      // parent clicked is unrecoverable.
      //
      // Every name at a score is the SAME cap, so a first-match name is
      // accurate about the policy even when it is not the label that was
      // clicked. That is what separates it from the missing-rung case, which
      // returns null.
      final ladder = ParentalRatingLadder.fromJson(<Object>[
        <String, dynamic>{'Name': 'Approved', 'Value': 0},
        <String, dynamic>{'Name': 'G', 'Value': 0},
        <String, dynamic>{'Name': 'TV-G', 'Value': 0},
      ]);

      expect(ladder.namesFor(0), ['Approved', 'G', 'TV-G']);
      // Pinned rather than incidental: server order, first match.
      expect(ladder.nameFor(0), 'Approved');
    });

    test('null in, null out — an uncapped child has nothing to name', () {
      expect(const ParentalRatingLadder.empty().nameFor(null), isNull);
    });
  });
}
