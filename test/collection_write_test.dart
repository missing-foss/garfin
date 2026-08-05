// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/repositories/assign_repository.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';

import 'support/fake_jellyfin_server.dart';

/// Collection writes — build order step 6, and the only place ground rule 5's
/// pre-flight and fix-forward machinery runs.
///
/// The assertions here are mostly about **what did not happen**: no write
/// before the pre-flight passed, no compensating write after one failed, no
/// container marker over a half-tagged set, no cascade on a removal. Those are
/// the ones a plausible-looking implementation gets wrong.
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

  final give = TagDiff([
    TagChange(child: emma, label: 'kids-emma', adding: true),
  ]);
  final take = TagDiff([
    TagChange(child: emma, label: 'kids-emma', adding: false),
  ]);

  /// A full item as the single-item `GET` returns it.
  Map<String, dynamic> fullItem(String id, {List<String>? tags}) =>
      <String, dynamic>{
        'Id': id,
        'Name': id,
        'Overview': 'Something the write must not drop.',
        'ProviderIds': <String, dynamic>{'Tmdb': '1'},
        'Etag': 'etag-$id',
        'Tags': tags ?? <String>['scraper-tag'],
      };

  late FakeJellyfinServer server;
  late AssignRepository repository;

  const members = <String>['film-1', 'film-2', 'film-3'];

  void build() {
    server = FakeJellyfinServer();
    repository = AssignRepository(
      api: JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: serverUrl),
      adminUserId: 'admin-1',
    );
  }

  /// A three-film set, every item readable, every write accepted.
  ///
  /// [unreadable] answers 404 for a member's single-item `GET` — the item that
  /// has gone away. It is scripted here rather than queued afterwards because
  /// the fake replays queued replies **in order**, so a later `on()` for the
  /// same path is the *second* answer, not a replacement: the pre-flight would
  /// read the item happily and only the write would fail, which is the opposite
  /// of what these tests are about.
  void scriptSet({List<String>? tags, Set<String> unreadable = const {}}) {
    server.on('/Users/admin-1/Items/set-1', json: fullItem('set-1', tags: tags));
    for (final id in members) {
      if (unreadable.contains(id)) {
        server.on('/Users/admin-1/Items/$id', status: 404);
      } else {
        server.on('/Users/admin-1/Items/$id', json: fullItem(id, tags: tags));
      }
    }
    server.fallback(json: <String, dynamic>{'TotalRecordCount': 10});
  }

  List<String> postedTo() => server.requests
      .where((r) => r.method == 'POST' && r.path.startsWith('/Items/'))
      .map((r) => r.path.substring('/Items/'.length))
      .toList(growable: false);

  Map<String, dynamic> bodyOf(String itemId) {
    final post = server.requests.lastWhere(
      (r) => r.method == 'POST' && r.path == '/Items/$itemId',
    );
    final data = post.data;
    return data is String
        ? jsonDecode(data) as Map<String, dynamic>
        : Map<String, dynamic>.from(data as Map);
  }

  setUp(build);

  group('ground rule 5 — pre-flight, before anything is written', () {
    test('one unreadable member cancels the whole batch', () async {
      // film-2 has gone: the id is well formed and the server has no such item.
      scriptSet(unreadable: const {'film-2'});

      await expectLater(
        () => repository.applyToCollection(
          collectionId: 'set-1',
          memberIds: members,
          diff: give,
        ),
        throwsA(isA<CollectionPreflightException>()),
      );

      expect(postedTo(), isEmpty,
          reason: 'not one write may go out once a member is unreadable');
    });

    test('it reads the container as well as the members', () async {
      scriptSet();

      await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      // Four items read before the writes started: the container and three
      // films. The container is written too, so leaving it out of the
      // pre-flight would be checking three quarters of the batch.
      final firstPost = server.requests
          .indexWhere((r) => r.method == 'POST' && r.path.startsWith('/Items/'));
      final readsBeforeWriting = server.requests
          .take(firstPost)
          .where((r) => r.path.startsWith('/Users/admin-1/Items/'))
          .map((r) => r.path)
          .toSet();
      expect(readsBeforeWriting, hasLength(4));
    });

    test('the body read in pre-flight is never the body posted', () async {
      // Ground rule 2 and the Undo rule are the same rule: every write starts
      // with its own fresh GET. Here the item changes underneath — a metadata
      // refresh, another admin — between the pre-flight and the write, and the
      // posted body has to be the later one.
      server
        ..on('/Users/admin-1/Items/set-1', json: fullItem('set-1'))
        ..on('/Users/admin-1/Items/set-1', json: fullItem('set-1'))
        ..on('/Users/admin-1/Items/film-1',
            json: fullItem('film-1', tags: <String>['stale']))
        ..on('/Users/admin-1/Items/film-1',
            json: fullItem('film-1', tags: <String>['fresh']))
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: const ['film-1'],
        diff: give,
      );

      final tags = (bodyOf('film-1')['Tags'] as List).cast<String>();
      expect(tags, contains('fresh'));
      expect(tags, isNot(contains('stale')),
          reason: 'a pre-flight body reused for the write would be stale');
    });
  });

  group('ground rule 5 — fix forward, never roll back', () {
    test('a failed member does not undo the ones that landed', () async {
      scriptSet();
      server.on('/Items/film-2', status: 400);

      final outcome = await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      expect(outcome.written, <String>['film-1', 'film-3']);
      expect(outcome.failed, <String>['film-2']);
      expect(outcome.isComplete, isFalse);
      // The exact state ground rule 5 asks to be surfaced.
      expect(outcome.total, 3);

      // The compensating writes a roll-back would need. Each successful member
      // is written exactly once, and never a second time to take it back.
      expect(postedTo().where((id) => id == 'film-1'), hasLength(1));
      expect(postedTo().where((id) => id == 'film-3'), hasLength(1));
    });

    test('the container is not marked over a half-tagged set', () async {
      scriptSet();
      server.on('/Items/film-2', status: 400);

      final outcome = await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      expect(outcome.setMarked, isFalse);
      expect(postedTo(), isNot(contains('set-1')),
          reason: 'the container label means the whole set is there');
    });

    test('a retry finishes the rest, and is safe over the ones already done',
        () async {
      scriptSet();
      server.on('/Items/film-2', status: 400);
      await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      // The server recovers; the same write goes out again.
      build();
      scriptSet(tags: <String>['scraper-tag', 'kids-emma']);
      server.on('/Users/admin-1/Items/film-2', json: fullItem('film-2'));

      final second = await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      expect(second.isComplete, isTrue);
      expect(second.failed, isEmpty);
      // Idempotent: the films that already carried the label still carry it
      // exactly once.
      expect(
        (bodyOf('film-1')['Tags'] as List).where((t) => t == 'kids-emma'),
        hasLength(1),
      );
    });
  });

  group('the write order, which is what the container label means', () {
    test('an addition writes every member first and the container last',
        () async {
      scriptSet();

      final outcome = await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      expect(outcome.isComplete, isTrue);
      expect(outcome.setMarked, isTrue);
      expect(postedTo().toSet(), {...members, 'set-1'});
      // Once, and after all of them. Asserting only that the *last* write is
      // the container is not enough: a container written first and then again
      // at the end satisfies that and still marks the set before its films
      // exist. Mutation-tested — that is exactly what slipped through.
      expect(postedTo().where((id) => id == 'set-1'), hasLength(1));
      expect(postedTo().indexOf('set-1'), postedTo().length - 1,
          reason: 'the marker lands only after everything it claims');
    });

    test('a removal takes the container first', () async {
      scriptSet(tags: <String>['scraper-tag', 'kids-emma']);

      await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: take,
      );

      expect(postedTo().where((id) => id == 'set-1'), hasLength(1));
      expect(postedTo().indexOf('set-1'), 0,
          reason: 'the set must stop claiming films it is about to lose');
    });

    test('undo across a set flips the order with the direction', () async {
      scriptSet(tags: <String>['scraper-tag', 'kids-emma']);

      await repository.undoCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      expect(postedTo().indexOf('set-1'), 0);
      expect(postedTo().where((id) => id == 'set-1'), hasLength(1));
      // A forward write, not a restore: the label comes off what is there now.
      expect((bodyOf('film-1')['Tags'] as List), <String>['scraper-tag']);
    });

    test('every member keeps the fields ground rule 2 protects', () async {
      scriptSet();

      await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: give,
      );

      for (final id in members) {
        final posted = bodyOf(id);
        expect(posted.keys.toSet(), fullItem(id).keys.toSet());
        expect(posted['Overview'], 'Something the write must not drop.');
        expect(posted['ProviderIds'], <String, dynamic>{'Tmdb': '1'});
        expect(posted['Tags'], containsAll(<String>['scraper-tag', 'kids-emma']));
      }
    });
  });

  group('what "the child has this set" means', () {
    LibraryItem member(String id, {List<String> tags = const []}) =>
        LibraryItem(id: id, name: id, type: 'Movie', tags: tags);

    Future<bool> hasSet({
      required List<String> containerTags,
      required List<LibraryItem> setMembers,
    }) async {
      build();
      server
        ..on('/Users/admin-1/Items/set-1',
            json: fullItem('set-1', tags: containerTags))
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});
      final rows = await repository.rowsFor(
        itemId: 'set-1',
        children: [emma],
        members: setMembers,
      );
      return rows.single.hasLabel;
    }

    test('every member labelled but not the container is not given', () async {
      // Measured on 10.11.11: the child gets all three films and the set itself
      // is absent from their library — browsing it answers 401. Calling that
      // "given" would file a half-shared set under done.
      expect(
        await hasSet(
          containerTags: const ['scraper-tag'],
          setMembers: [
            member('a', tags: const ['kids-emma']),
            member('b', tags: const ['kids-emma']),
          ],
        ),
        isFalse,
      );
    });

    test('the container labelled but not every member is not given', () async {
      // The other half: measured, the child sees the collection and it is empty.
      expect(
        await hasSet(
          containerTags: const ['kids-emma'],
          setMembers: [
            member('a', tags: const ['kids-emma']),
            member('b'),
          ],
        ),
        isFalse,
      );
    });

    test('both halves is given', () async {
      expect(
        await hasSet(
          containerTags: const ['kids-emma'],
          setMembers: [
            member('a', tags: const ['kids-emma']),
            member('b', tags: const ['KIDS-EMMA']),
          ],
        ),
        isTrue,
      );
    });

    test('an empty set is not given, however the container is tagged', () async {
      expect(
        await hasSet(containerTags: const ['kids-emma'], setMembers: const []),
        isFalse,
      );
    });
  });

  group('ground rule 6 — a removal never cascades', () {
    final set = CollectionSet(
      collection: LibraryItem(
          id: 'set-1', name: 'Back to the Future', type: 'BoxSet', tags: const []),
      members: [
        LibraryItem(id: 'film-1', name: 'One', type: 'Movie', tags: const []),
        LibraryItem(id: 'film-2', name: 'Two', type: 'Movie', tags: const []),
      ],
    );

    test('taking a label off one film asks about nothing', () {
      expect(cascadeAsks(take), isFalse);
    });

    test('giving one film asks about the set it belongs to', () {
      expect(cascadeAsks(give), isTrue);
    });

    test('a diff that both gives and takes still asks', () {
      expect(cascadeAsks(TagDiff([...give.changes, ...take.changes])), isTrue);
    });

    test('the dialog lists the other members, not this one', () {
      expect(set.othersThan('film-1').map((m) => m.id), <String>['film-2']);
    });
  });

  group('a film can belong to more than one set', () {
    LibraryItem film(String id) =>
        LibraryItem(id: id, name: id, type: 'Movie', tags: const []);
    CollectionSet setOf(String id, List<String> ids) => CollectionSet(
          collection:
              LibraryItem(id: id, name: id, type: 'BoxSet', tags: const []),
          members: ids.map(film).toList(),
        );

    final index = CollectionIndex([
      setOf('paddington', const ['p1', 'p2']),
      setOf('bears', const ['p2', 'other']),
      setOf('bttf', const ['b1']),
    ]);

    test('both of its sets come back, not the first one found', () {
      expect(
        index.setsContaining('p2').map((s) => s.collection.id),
        <String>['paddington', 'bears'],
      );
    });

    test('a film in no set gets no cascade question', () {
      expect(index.setsContaining('b1'), hasLength(1));
      expect(index.setsContaining('nowhere'), isEmpty);
    });
  });

  group('the item that comes back must be the item asked for', () {
    test('a different id refuses the write', () async {
      // Measured on 10.11.11: `GET /Users/{uid}/Items/00000000000000000000000000000000`
      // answers **200 with the root "Media Folders" object**. Trusting the
      // status would post that body — the root of the library — to
      // `/Items/000…`.
      server
        ..on('/Users/admin-1/Items/00000000000000000000000000000000',
            json: fullItem('e9d5075a555c1cbc394eec4cef295274'))
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await expectLater(
        () => repository.apply(
          itemId: '00000000000000000000000000000000',
          diff: give,
        ),
        throwsA(isA<JellyfinException>()),
      );
      expect(postedTo(), isEmpty);
    });

    test('and it is checked in the pre-flight too', () async {
      server
        ..on('/Users/admin-1/Items/set-1', json: fullItem('set-1'))
        ..on('/Users/admin-1/Items/film-1', json: fullItem('film-1'))
        // The one that answers 200 with a different item — the shape the
        // all-zero GUID takes on a real server.
        ..on('/Users/admin-1/Items/film-2',
            json: fullItem('somebody-elses-item'))
        ..on('/Users/admin-1/Items/film-3', json: fullItem('film-3'))
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await expectLater(
        () => repository.applyToCollection(
          collectionId: 'set-1',
          memberIds: members,
          diff: give,
        ),
        throwsA(isA<CollectionPreflightException>()),
      );
      expect(postedTo(), isEmpty);
    });
  });
}
