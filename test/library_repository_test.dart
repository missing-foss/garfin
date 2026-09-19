// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/library_repository.dart';

import 'support/fake_jellyfin_server.dart';

/// Ground-rule tests for the Library grid.
///
/// The two that matter most: the shared/not-shared partition must survive a
/// `Tags` list full of the scraper's own tags, and the visibility state must
/// come from the server's answer rather than from any local comparison of a
/// rating against a cap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const serverUrl = 'http://host:8096';

  JellyfinUser child({
    List<String> allowed = const ['kids-emma'],
    List<String> blocked = const [],
  }) =>
      JellyfinUser(
        id: 'kid-1',
        name: 'Emma',
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: allowed,
          blockedTags: blocked,
        ),
      );

  Map<String, dynamic> item(String id, String name, {List<String>? tags}) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'Type': 'Movie',
        'Tags': ?tags,
      };

  late FakeJellyfinServer server;
  late LibraryRepository repository;

  void build() {
    server = FakeJellyfinServer();
    repository = LibraryRepository(
      api: JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: serverUrl),
      adminUserId: 'admin-1',
    );
  }

  setUp(build);

  /// A page of items, then the `ids` reply saying which of them the child sees.
  void respondWith({
    required List<Map<String, dynamic>> items,
    required List<String> visibleIds,
    int? total,
  }) {
    server
      ..on('/Items',
          json: {'Items': items, 'TotalRecordCount': total ?? items.length})
      ..on('/Items', json: {
        'Items': [for (final id in visibleIds) <String, dynamic>{'Id': id}],
        'TotalRecordCount': visibleIds.length,
      });
  }

  group('the shared partition survives the scraper', () {
    test('Garfin\'s label is found among the metadata provider\'s tags',
        () async {
      // Measured on 10.11.11: tagging one film left it holding six tags, of
      // which one was Garfin's. Anything treating "has tags" as "shared" would
      // mark the whole library.
      respondWith(
        items: [
          item('a', 'Alpha', tags: [
            'missing person',
            'kidnapping',
            'alien abduction',
            'kids-emma',
            'secret agent',
          ]),
          item('b', 'Bravo', tags: ['dinosaur', 'island']),
        ],
        visibleIds: ['a'],
      );

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries[0].state, LibraryItemState.given);
      expect(slice.entries[1].state, LibraryItemState.notGiven);
    });

    test('matching is case-insensitive, agreeing with the server', () async {
      // The server's own `tags=` filter matched `KIDS-EMMA` against an item
      // tagged `kids-emma`. Matching case-sensitively here would disagree with
      // it about which items are shared.
      respondWith(
        items: [item('a', 'Alpha', tags: ['KIDS-EMMA'])],
        visibleIds: ['a'],
      );

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries.single.state, LibraryItemState.given);
    });

    test('an item with no Tags key at all is not given, not an error',
        () async {
      // Without `Fields=Tags` the key is absent rather than empty. The request
      // asks for it, but a server that omits it must not crash the grid.
      respondWith(items: [item('a', 'Alpha')], visibleIds: const []);

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries.single.state, LibraryItemState.notGiven);
    });
  });

  group('visibility comes from the server, not from arithmetic', () {
    test('a labelled item the server omits is given-but-hidden', () async {
      // The state that does not exist anywhere else: the parent did the thing,
      // and it still is not reaching the child.
      respondWith(
        items: [
          item('a', 'Alpha', tags: ['kids-emma']),
          item('b', 'Bravo', tags: ['kids-emma']),
        ],
        // The server returns only 'a'. Nothing here knows or asks why.
        visibleIds: ['a'],
      );

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries[0].state, LibraryItemState.given);
      expect(slice.entries[1].state, LibraryItemState.givenButHidden);
    });

    test('no rating or cap is consulted — there are none to consult', () async {
      // Deliberately no OfficialRating on the items and no MaxParentalRating on
      // the child. If the state were computed locally this could not answer,
      // and the answer would silently become "fine".
      respondWith(
        items: [item('a', 'Alpha', tags: ['kids-emma'])],
        visibleIds: const [],
      );

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries.single.item.officialRating, isNull);
      expect(slice.entries.single.state, LibraryItemState.givenButHidden);
    });

    test('unlabelled items are not asked about', () async {
      respondWith(
        items: [item('a', 'Alpha'), item('b', 'Bravo')],
        visibleIds: const [],
      );

      await repository.fetch(startIndex: 0, child: child());

      // One page request and no `ids` request: nothing was labelled, so there
      // was no question worth a round-trip.
      final idQueries = server.requests
          .where((r) => r.queryParameters.containsKey('ids'))
          .toList(growable: false);
      expect(idQueries, isEmpty);
    });

    test('a failed visibility lookup degrades to given, not to hidden',
        () async {
      // Inventing a problem is worse than losing an overlay: "hidden" would
      // send a parent looking for a cap that is not there.
      server
        ..on('/Items', json: {
          'Items': [item('a', 'Alpha', tags: ['kids-emma'])],
          'TotalRecordCount': 1,
        })
        ..on('/Items', status: 500);

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries.single.state, LibraryItemState.given);
    });
  });

  group('a child with more than one shortlist tag', () {
    test('any of their labels counts as given, because the server matches any',
        () async {
      // `AllowedTags: ["kids-emma", "family-films"]` means an item tagged
      // either one is visible to that child. Checking only the first would
      // report "not given yet" for something they can already watch.
      respondWith(
        items: [
          item('a', 'Alpha', tags: ['family-films']),
          item('b', 'Bravo', tags: ['kids-emma']),
          item('c', 'Charlie', tags: ['dinosaur']),
        ],
        visibleIds: ['a', 'b'],
      );

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(allowed: const ['kids-emma', 'family-films']),
      );

      expect(slice.entries[0].state, LibraryItemState.given);
      expect(slice.entries[1].state, LibraryItemState.given);
      expect(slice.entries[2].state, LibraryItemState.notGiven);
    });

    test('block mode reads all of them too', () async {
      server.on('/Items', json: {
        'Items': [
          item('a', 'Alpha', tags: ['no-horror']),
          item('b', 'Bravo', tags: ['nothing']),
        ],
        'TotalRecordCount': 2,
      });

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(allowed: const [], blocked: const ['block-sam', 'no-horror']),
      );

      expect(slice.entries[0].state, LibraryItemState.blocked);
      expect(slice.entries[1].state, LibraryItemState.available);
    });

    test('hide-shared hides items carrying the second label as well',
        () async {
      // The wrong answer with the most consequence: an item the child can
      // already watch reappearing on the to-do list.
      respondWith(
        items: [
          item('a', 'Alpha', tags: ['family-films']),
          item('b', 'Bravo', tags: ['dinosaur']),
        ],
        visibleIds: ['a'],
      );

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(allowed: const ['kids-emma', 'family-films']),
        view: LibraryView.toGive,
      );

      expect(slice.entries.map((e) => e.item.name), ['Bravo']);
    });
  });

  group('block mode inverts, and asks nothing', () {
    test('the label takes it away, and its absence leaves it available',
        () async {
      server.on('/Items', json: {
        'Items': [
          item('a', 'Alpha', tags: ['block-sam']),
          item('b', 'Bravo', tags: ['dinosaur']),
        ],
        'TotalRecordCount': 2,
      });

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(allowed: const [], blocked: const ['block-sam']),
      );

      expect(slice.entries[0].state, LibraryItemState.blocked);
      expect(slice.entries[1].state, LibraryItemState.available);
      // The tag *is* the answer in block mode. Asking the server what the child
      // can see would be a round-trip that changes nothing.
      expect(
        server.requests.where((r) => r.queryParameters.containsKey('ids')),
        isEmpty,
      );
    });
  });

  group('ground rule 3 — no verb, no answer', () {
    test('a child with both lists set gets no per-item state', () async {
      server.on('/Items', json: {
        'Items': [item('a', 'Alpha', tags: ['kids-emma'])],
        'TotalRecordCount': 1,
      });

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(allowed: const ['kids-emma'], blocked: const ['nope']),
      );

      expect(slice.entries.single.state, LibraryItemState.unknown);
    });

    test('Everyone — no child selected — is unknown, not not-given', () async {
      server.on('/Items', json: {
        'Items': [item('a', 'Alpha', tags: ['kids-emma'])],
        'TotalRecordCount': 1,
      });

      final slice = await repository.fetch(startIndex: 0);

      expect(slice.entries.single.state, LibraryItemState.unknown);
    });
  });

  group('hide-shared fills the page rather than returning a ragged one', () {
    test('it keeps fetching until it has a page', () async {
      // The whole reason this is client-side: there is no excludeTags, and
      // excludeItemIds would be a URL that grows with the shared set.
      //
      // First window is entirely shared, so filtering empties it. The loop must
      // go back for more rather than hand up nothing while the server still has
      // items.
      // One window of each, named rather than written out: the window is a
      // constant that moved from 96 to 240 when a page grew from one screen to
      // roughly twenty-seven, and a fixture pinned to the old number tests
      // nothing.
      const window = LibraryRepository.filteringWindow;
      final shared = [
        for (var i = 0; i < window; i++)
          item('s$i', 'Shared $i', tags: ['kids-emma'])
      ];
      final fresh = [
        for (var i = 0; i < window; i++) item('f$i', 'Fresh $i', tags: ['other'])
      ];

      server
        ..on('/Items',
            json: {'Items': shared, 'TotalRecordCount': window * 2})
        ..on('/Items', json: {
          'Items': [for (final s in shared) <String, dynamic>{'Id': s['Id']}],
          'TotalRecordCount': window,
        })
        ..on('/Items', json: {'Items': fresh, 'TotalRecordCount': window * 2})
        ..fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(),
        view: LibraryView.toGive,
      );

      // At least a full screen of not-yet-given items, out of a first window
      // that had none of them.
      //
      // At *least*: a window that yields more than a page is not trimmed.
      // Those items are already fetched and already classified, and throwing
      // them away would only mean fetching them again.
      expect(
        slice.entries.length,
        greaterThanOrEqualTo(LibraryRepository.pageSize),
      );
      expect(
        slice.entries.every((e) => e.state == LibraryItemState.notGiven),
        isTrue,
      );
      // And the denominator still describes the whole library, not the filtered
      // remainder.
      expect(slice.totalRecordCount, window * 2);
    });

    test('an empty response ends the loop instead of spinning', () async {
      server.fallback(json: {'Items': <Object>[], 'TotalRecordCount': 50});

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(),
        view: LibraryView.toGive,
      );

      expect(slice.entries, isEmpty);
    });
  });

  group('the diff decorates, it never filters', () {
    test('a given-but-hidden item stays on the grid', () async {
      // Hiding it would hide the one case the screen exists to explain.
      respondWith(
        items: [item('a', 'Alpha', tags: ['kids-emma'])],
        visibleIds: const [],
      );

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries, hasLength(1));
      expect(slice.entries.single.state, LibraryItemState.givenButHidden);
    });

    test('but hide-shared does count it as shared', () async {
      // The label is on the item; the parent has done the thing. That it is not
      // arriving is a different problem, not outstanding work.
      final entry = LibraryEntry(
        item: const LibraryItem(
            id: 'a', name: 'Alpha', type: 'Movie', tags: []),
        state: LibraryItemState.givenButHidden,
      );

      expect(entry.isShared, isTrue);
    });
  });

  group('the view a face tap lands on (#88)', () {
    test('keeps what the child has, which is the mirror of hiding it',
        () async {
      // The same page, classified the same way, kept the other way round. That
      // symmetry is the argument for this being a lens on the administrator's
      // grid rather than a second grid.
      respondWith(
        items: [
          item('a', 'Alpha', tags: ['family-films']),
          item('b', 'Bravo', tags: ['dinosaur']),
        ],
        visibleIds: ['a'],
      );
      final emma = child(allowed: const ['kids-emma', 'family-films']);

      final given = await repository.fetch(
        startIndex: 0,
        child: emma,
        view: LibraryView.given,
      );

      expect(given.entries.map((e) => e.item.name), ['Alpha'],
          reason: 'hide-shared keeps Bravo; this keeps exactly the other one');
      expect(given.entries.every((e) => e.isShared), isTrue);
    });

    test('a child with no labels is not narrowed to nothing', () async {
      // Without a label to classify by every item lands on the same side, so
      // narrowing would page through the whole library collecting an empty
      // list. The guard is shared with hide-shared; this pins it for the new
      // view too, since that is the half a future edit could miss.
      respondWith(
        items: [
          item('a', 'Alpha'),
          item('b', 'Bravo'),
        ],
        visibleIds: const [],
      );

      final slice = await repository.fetch(
        startIndex: 0,
        child: child(allowed: const []),
        view: LibraryView.given,
      );

      expect(slice.entries, isNotEmpty);
    });
  });

  group('a collection with nothing in it (#109)', () {
    test('is not drawn, and a film beside it is', () async {
      // Nothing in it to give or withhold, an assign sheet with no members to
      // write to, and the share ring already suppressed for it — the tile could
      // only ever be a row a parent cannot act on.
      respondWith(
        items: [
          item('a', 'Paddington'),
          {...item('b', 'Empty Set'), 'Type': 'BoxSet', 'ChildCount': 0},
          {...item('c', 'Full Set'), 'Type': 'BoxSet', 'ChildCount': 4},
        ],
        visibleIds: const ['a', 'b', 'c'],
      );

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries.map((e) => e.item.name), ['Paddington', 'Full Set']);
    });

    test('a set whose count the server did not send is kept', () async {
      // **`null` is not zero.** `ChildCount` is absent unless `Fields` asks for
      // it, and the tile's own code already reads a missing count as "the
      // server did not say". Dropping on absence would hide real collections
      // the moment that field stopped being requested.
      respondWith(
        items: [
          {...item('b', 'Unknown Set'), 'Type': 'BoxSet'},
        ],
        visibleIds: const ['b'],
      );

      final slice = await repository.fetch(startIndex: 0, child: child());

      expect(slice.entries.map((e) => e.item.name), ['Unknown Set']);
    });

    // "and nothing asks the server about one" stood here and could not fail.
    // It looked for a request path containing `/Items/b`; a membership is
    // fetched as `GET /Items?parentId=<id>`, so no path in this app ever
    // contains it — and `fetch` does not ask for memberships at all, which the
    // grid does through `collectionSetProvider`. It asserted the absence of
    // something this layer would not do with the filter deleted.
    //
    // The claim is worth pinning and now lives where the request happens:
    // `collection_given_test.dart`, "an empty set costs no membership request".
  });
}
