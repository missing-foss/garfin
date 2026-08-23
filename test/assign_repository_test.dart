// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/repositories/assign_repository.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';

import 'support/fake_jellyfin_server.dart';

/// The write path, which is the first thing in Garfin that can damage
/// somebody's library rather than just their screen.
///
/// Ground rule 2 is the one these are mostly about: `POST /Items/{id}` replaces
/// the whole item, so the assertion that matters is not "the tag changed" but
/// **"nothing else did"**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const serverUrl = 'http://host:8096';

  JellyfinUser child(
    String id,
    String name, {
    List<String> allowed = const [],
    List<String> blocked = const [],
  }) =>
      JellyfinUser(
        id: id,
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: allowed,
          blockedTags: blocked,
        ),
      );

  final emma = child('kid-1', 'Emma', allowed: const ['kids-emma']);
  final sam = child('kid-2', 'Sam', blocked: const ['block-sam']);

  /// A full item as `GET /Users/{uid}/Items/{id}` returns it: many fields, and
  /// `Tags` already holding the scraper's own.
  Map<String, dynamic> fullItem({List<String>? tags}) => <String, dynamic>{
        'Id': 'item-1',
        'Name': 'Paddington',
        'Overview': 'A bear arrives in London.',
        'ProviderIds': <String, dynamic>{'Tmdb': '116149'},
        'Genres': <String>['Family', 'Comedy'],
        'People': <Map<String, dynamic>>[
          <String, dynamic>{'Name': 'Ben Whishaw'}
        ],
        'Studios': <Map<String, dynamic>>[
          <String, dynamic>{'Name': 'StudioCanal'}
        ],
        'Path': '/media/Movies/Paddington (2014).mp4',
        'SortName': 'paddington',
        'OfficialRating': 'PG',
        'ProductionYear': 2014,
        'RunTimeTicks': 5000000000,
        'Etag': 'abc123',
        'Tags': tags ??
            <String>['bear', 'london, england', 'family', 'taxidermist'],
      };

  late FakeJellyfinServer server;
  late AssignRepository repository;

  void build() {
    server = FakeJellyfinServer();
    repository = AssignRepository(
      api: JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: serverUrl),
      adminUserId: 'admin-1',
    );
  }

  setUp(build);

  /// The body of the one POST that went out.
  Map<String, dynamic> postedBody() {
    final posts = server.requests
        .where((r) => r.method == 'POST' && r.path.startsWith('/Items/'))
        .toList(growable: false);
    expect(posts, hasLength(1), reason: 'expected exactly one write');
    final data = posts.single.data;
    return data is String
        ? jsonDecode(data) as Map<String, dynamic>
        : Map<String, dynamic>.from(data as Map);
  }

  group('ground rule 2 — the whole object goes back', () {
    test('every field survives the round-trip, not just Tags', () async {
      // The assertion that matters. A write that changed the tag correctly and
      // dropped `Overview` would pass a naive test and corrupt the library.
      final before = fullItem();
      server
        ..on('/Users/admin-1/Items/item-1', json: before)
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      final posted = postedBody();
      expect(posted.keys.toSet(), before.keys.toSet(),
          reason: 'the posted object must have the same fields');
      for (final key in before.keys) {
        if (key == 'Tags') continue;
        expect(posted[key], before[key], reason: '$key was altered');
      }
    });

    test('the scraper\'s tags ride along untouched', () async {
      // Measured: a film arrived carrying eighteen provider tags before Garfin
      // added the nineteenth. A replacement rather than a surgical add would
      // wipe the lot.
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      expect(
        postedBody()['Tags'],
        containsAll(<String>['bear', 'london, england', 'family', 'taxidermist']),
      );
      expect(postedBody()['Tags'], contains('kids-emma'));
    });

    test('the item is read singly, never taken from the caller', () async {
      // `apply` takes an id, so a list result cannot reach it — a list query
      // returns 19 of 52 fields and posting that back is the wipe.
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      expect(
        server.requests.any((r) => r.path == '/Users/admin-1/Items/item-1'),
        isTrue,
      );
    });

    test('an empty diff writes nothing at all', () async {
      server.fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.apply(itemId: 'item-1', diff: const TagDiff.empty());

      expect(
        server.requests.where((r) => r.method == 'POST'),
        isEmpty,
        reason: 'no write on an empty diff',
      );
    });
  });

  group('ground rule 3 — the inversion, and the casing', () {
    test('adding a label gives access in allow mode and removes it in block',
        () {
      expect(
        TagChange(child: emma, label: 'kids-emma', adding: true).givesAccess,
        isTrue,
      );
      // Same act, opposite meaning. This is the whole of ground rule 3.
      expect(
        TagChange(child: sam, label: 'block-sam', adding: true).givesAccess,
        isFalse,
      );
      expect(
        TagChange(child: sam, label: 'block-sam', adding: false).givesAccess,
        isTrue,
      );
    });

    test('the label is written in the policy\'s casing', () async {
      // Measured: the server stores casing verbatim and does not fold it. The
      // filter forgives a mismatch, so this is about not leaving KIDS-EMMA
      // beside kids-emma in the parent's own tag list.
      final odd = child('kid-3', 'Ada', allowed: const ['Kids-Ada']);
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(
            child: odd,
            label: AssignRepository.labelFor(odd)!,
            adding: true,
          ),
        ]),
      );

      expect(postedBody()['Tags'], contains('Kids-Ada'));
    });

    test('removal matches whatever casing is stored', () async {
      // A label written wrongly in the past still has to come off cleanly.
      server
        ..on('/Users/admin-1/Items/item-1',
            json: fullItem(tags: <String>['bear', 'KIDS-EMMA']))
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: false),
        ]),
      );

      expect(postedBody()['Tags'], <String>['bear']);
    });

    test('a second shortlist tag counts as already given, but is not written',
        () async {
      // Read against all of them — the server matches any — and write the
      // first, because adding a label is a choice rather than a match.
      final multi = child('kid-5', 'Mia',
          allowed: const ['kids-mia', 'family-films']);
      server
        ..on('/Users/admin-1/Items/item-1',
            json: fullItem(tags: <String>['bear', 'family-films']))
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      final rows =
          await repository.rowsFor(itemId: 'item-1', children: [multi]);

      // Already reachable via the second label — the toggle must show it on.
      expect(rows.single.hasLabel, isTrue);
      expect(rows.single.hasAccess, isTrue);
      // And the label the sheet would write is still the first.
      expect(rows.single.label, 'kids-mia');
    });

    test('a child with both lists set gets no label, so no row', () {
      final conflicted =
          child('kid-4', 'Alex', allowed: const ['a'], blocked: const ['b']);
      expect(AssignRepository.labelFor(conflicted), isNull);
    });
  });

  group('ground rule 1 — the last-item warning', () {
    test('fires when the removal would strip the final tagged item', () async {
      server.fallback(json: <String, dynamic>{'TotalRecordCount': 1});

      final warnings = await repository.lastItemWarningsFor(
        TagDiff([TagChange(child: emma, label: 'kids-emma', adding: false)]),
      );

      expect(warnings, hasLength(1));
      expect(warnings.single.child.name, 'Emma');
    });

    test('stays quiet when others still carry the label', () async {
      server.fallback(json: <String, dynamic>{'TotalRecordCount': 7});

      final warnings = await repository.lastItemWarningsFor(
        TagDiff([TagChange(child: emma, label: 'kids-emma', adding: false)]),
      );

      expect(warnings, isEmpty);
    });

    test('never fires on an addition', () async {
      server.fallback(json: <String, dynamic>{'TotalRecordCount': 1});

      final warnings = await repository.lastItemWarningsFor(
        TagDiff([TagChange(child: emma, label: 'kids-emma', adding: true)]),
      );

      expect(warnings, isEmpty);
    });

    test('never fires for a block-list child', () async {
      // Removing a block label *grants* access. It cannot leave anyone seeing
      // nothing, so the warning would be nonsense.
      server.fallback(json: <String, dynamic>{'TotalRecordCount': 1});

      final warnings = await repository.lastItemWarningsFor(
        TagDiff([TagChange(child: sam, label: 'block-sam', adding: false)]),
      );

      expect(warnings, isEmpty);
    });
  });

  group('ground rule 1 — the count reported afterwards is the server\'s', () {
    test('it is re-fetched after the write, not predicted', () async {
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 25});

      final outcome = await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      // Awaited here because this test is about the number. The app does not
      // await it before closing the sheet (#68) — the write is done when
      // `apply` returns, and the verification lands in the toast afterwards.
      expect((await outcome.counts)['kid-1'], 25);
      // Asked *after* the POST. A count read before it would report the old
      // number and look like the write did nothing.
      final order = server.requests.map((r) => '${r.method} ${r.path}').toList();
      expect(
        order.indexOf('POST /Items/item-1') < order.lastIndexOf('GET /Items'),
        isTrue,
        reason: 'the verifying count must come after the write',
      );
    });
  });

  group('ground rule 5 — Undo is a forward write', () {
    test('it re-reads the item rather than re-posting a captured body',
        () async {
      // The rule that reads as a contradiction until you see that both are
      // idempotent forward writes. A restore would clobber a concurrent edit;
      // this inverts against whatever is on the server now.
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      // Someone else edits the item in between — a new tag Garfin never saw.
      build();
      server
        ..on('/Users/admin-1/Items/item-1',
            json: fullItem(
                tags: <String>['bear', 'kids-emma', 'added-by-someone-else']))
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.undo(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      final tags = (postedBody()['Tags'] as List).cast<String>();
      expect(tags, isNot(contains('kids-emma')), reason: 'the label came off');
      expect(tags, contains('added-by-someone-else'),
          reason: "a stale snapshot would have wiped someone else's edit");
    });

    test('Undo asks for no counts at all (#68)', () async {
      // Undo used to go through `apply`, which verifies. Nothing read those
      // numbers — the sheet's Undo takes a `Future<void>` and the toast after
      // it names none — and the call is the expensive one in the whole path:
      // measured at 538 ms against a child who can see 2000 titles. Half a
      // second of the server's time, asked for and discarded, after every Undo.
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.undo(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      expect(server.callsTo('/Items/item-1'), 1, reason: 'control: it wrote');
      expect(server.callsTo('/Items'), 0,
          reason: 'a verifying count nobody reads is a request not to make');
    });
  });

  group('the wait, and who does it (#68)', () {
    test('apply returns as soon as the write is done', () async {
      // The reported symptom: the sheet sat on a spinner long after the film
      // was shared. Measured on 10.11.11 — the write is ~18 ms and flat, while
      // the verifying count runs from 19 ms to 538 ms depending on how much the
      // child can already see. So the write returns; the number follows.
      final counting = Completer<void>();
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        // The write must be scripted *separately* from the fallback, or the
        // delay lands on the POST and the test measures the write being slow —
        // which is the one thing it is not. Cost me a confident red.
        ..on('/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 25},
            delay: const Duration(seconds: 30));

      final outcome = await repository
          .apply(
            itemId: 'item-1',
            diff: TagDiff([
              TagChange(child: emma, label: 'kids-emma', adding: true),
            ]),
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError(
                'apply waited for the verification; #68 is back'),
          );

      // The write happened...
      expect(server.callsTo('/Items/item-1'), 1);
      // ...and the number is still in flight, which is the whole point.
      unawaited(outcome.counts.then((_) => counting.complete()));
      expect(counting.isCompleted, isFalse);
    });

    test('a verification that fails does not become an unhandled error',
        () async {
      // This future is handed to the UI unawaited. If it could throw, a failed
      // *verification* would surface as a crash for a write that succeeded.
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..on('/Items/item-1', json: fullItem())
        ..fallback(failWith: DioExceptionType.connectionError);

      final outcome = await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
        ]),
      );

      expect(await outcome.counts, isEmpty,
          reason: 'empty is "asked, could not verify" — the toast then keeps '
              'the sentence that is still true');
    });

    test('two children are counted together, not one after the other',
        () async {
      // `mapBounded` rather than a `for` loop with an `await` in it. Both make
      // the same requests in the same order and differ only in *when*, so the
      // only way to tell them apart is to make each call take measurable time.
      server
        ..on('/Users/admin-1/Items/item-1', json: fullItem())
        ..on('/Items/item-1', json: fullItem())
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 25},
            delay: const Duration(milliseconds: 300));

      final outcome = await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
          TagChange(child: sam, label: 'block-sam', adding: false),
        ]),
      );

      final started = DateTime.now();
      await outcome.counts;
      final elapsed = DateTime.now().difference(started);

      expect(elapsed, lessThan(const Duration(milliseconds: 500)),
          reason: 'serial would be two 300ms calls end to end; '
              'took ${elapsed.inMilliseconds}ms');
    });
  });
}
