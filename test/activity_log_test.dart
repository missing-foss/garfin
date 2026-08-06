// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/activity_entry.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/repositories/activity_store.dart';
import 'package:garfin/repositories/assign_repository.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The Activity log — Garfin's own record, because the server keeps none.
///
/// Measured for #57: `POST /Items/{id}` adds nothing to Jellyfin's
/// `/System/ActivityLog/Entries`, so this is the only history there is, and the
/// guarantee worth testing is that **a write cannot happen without being
/// recorded** — the log is written in the repository rather than by the caller
/// for exactly that reason.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Map<String, dynamic> fullItem(String id, {String name = 'Paddington'}) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'Overview': 'A bear arrives in London.',
        'Tags': <String>['scraper-tag'],
      };

  late FakeJellyfinServer server;
  late ActivityStore store;
  late AssignRepository repository;

  Future<void> build() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = ActivityStore(await SharedPreferences.getInstance());
    server = FakeJellyfinServer();
    repository = AssignRepository(
      api: JellyfinApiFactory(
        identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
        adapter: server,
      ).create(baseUrl: 'http://host:8096'),
      adminUserId: 'admin-1',
      activity: store,
    );
  }

  setUp(build);

  void scriptItem(String id, {String name = 'Paddington'}) {
    server
      ..on('/Users/admin-1/Items/$id', json: fullItem(id, name: name))
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});
  }

  group('a write cannot happen without being recorded', () {
    test('one item, one entry, carrying the server\'s own name', () async {
      scriptItem('item-1');

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([TagChange(child: emma, label: 'kids-emma', adding: true)]),
      );

      final entries = store.read();
      expect(entries, hasLength(1));
      expect(entries.single.itemId, 'item-1');
      // Taken from the fetched object rather than passed in by a caller: one
      // source of truth for what an item is called.
      expect(entries.single.itemName, 'Paddington');
      expect(entries.single.childName, 'Emma');
      expect(entries.single.gaveAccess, isTrue);
    });

    test('an entry per child, because one Apply can do two things', () async {
      scriptItem('item-1');

      await repository.apply(
        itemId: 'item-1',
        diff: TagDiff([
          TagChange(child: emma, label: 'kids-emma', adding: true),
          TagChange(child: sam, label: 'block-sam', adding: true),
        ]),
      );

      final entries = store.read();
      expect(entries, hasLength(2));
      // Ground rule 3: the same act — adding a label — gave to one child and
      // took from the other, and the log says what happened to each of them.
      expect(
        {for (final e in entries) e.childName: e.gaveAccess},
        {'Emma': true, 'Sam': false},
      );
    });

    test('a collection is one entry, not one per title', () async {
      const members = ['film-1', 'film-2', 'film-3'];
      server.on('/Users/admin-1/Items/set-1',
          json: fullItem('set-1', name: 'Back to the Future'));
      for (final id in members) {
        server.on('/Users/admin-1/Items/$id', json: fullItem(id, name: id));
      }
      server.fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: TagDiff([TagChange(child: emma, label: 'kids-emma', adding: true)]),
      );

      final entries = store.read();
      expect(entries, hasLength(1));
      expect(entries.single.itemName, 'Back to the Future');
      expect(entries.single.collectionSize, 3);
      expect(entries.single.isCollection, isTrue);
    });

    test('an empty diff writes nothing and records nothing', () async {
      scriptItem('item-1');
      await repository.apply(itemId: 'item-1', diff: const TagDiff.empty());
      expect(store.read(), isEmpty);
    });
  });

  group('a half-finished collection is not an action', () {
    test('a partly-written set records nothing', () async {
      // The sheet keeps that state on screen with *finish the rest* / *put it
      // all back*. Logging it as done would put an Undo behind a claim that is
      // not true yet.
      const members = ['film-1', 'film-2'];
      server.on('/Users/admin-1/Items/set-1', json: fullItem('set-1'));
      for (final id in members) {
        server.on('/Users/admin-1/Items/$id', json: fullItem(id));
      }
      server
        ..on('/Items/film-2', status: 400)
        ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      final outcome = await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: TagDiff([TagChange(child: emma, label: 'kids-emma', adding: true)]),
      );

      expect(outcome.isComplete, isFalse);
      expect(store.read(), isEmpty);
    });

    test('the retry that completes it does record', () async {
      const members = ['film-1', 'film-2'];
      server.on('/Users/admin-1/Items/set-1', json: fullItem('set-1'));
      for (final id in members) {
        server.on('/Users/admin-1/Items/$id', json: fullItem(id));
      }
      server.fallback(json: <String, dynamic>{'TotalRecordCount': 10});

      final outcome = await repository.applyToCollection(
        collectionId: 'set-1',
        memberIds: members,
        diff: TagDiff([TagChange(child: emma, label: 'kids-emma', adding: true)]),
      );

      expect(outcome.isComplete, isTrue);
      expect(store.read(), hasLength(1));
    });
  });

  group('the log itself', () {
    test('newest first', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = ActivityStore(await SharedPreferences.getInstance());

      for (var i = 0; i < 3; i++) {
        await store.add(ActivityEntry(
          itemId: 'item-$i',
          itemName: 'Item $i',
          childId: 'kid-1',
          childName: 'Emma',
          label: 'kids-emma',
          gaveAccess: true,
          at: DateTime(2026, 8, 6, 10 + i),
        ));
      }

      expect(store.read().map((e) => e.itemId), ['item-2', 'item-1', 'item-0']);
    });

    test('it is bounded, and the oldest fall off the end', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = ActivityStore(prefs);

      for (var i = 0; i < ActivityStore.maxEntries + 20; i++) {
        await store.add(ActivityEntry(
          itemId: 'item-$i',
          itemName: 'Item $i',
          childId: 'kid-1',
          childName: 'Emma',
          label: 'kids-emma',
          gaveAccess: true,
          at: DateTime(2026, 8, 6),
        ));
      }

      final entries = store.read();
      expect(entries, hasLength(ActivityStore.maxEntries));
      expect(entries.first.itemId, 'item-219', reason: 'the newest is kept');
      expect(entries.map((e) => e.itemId), isNot(contains('item-0')));
    });

    test('one unreadable line does not cost the whole history', () async {
      // A half-written value, or one from a later version. Losing the log
      // because of a single bad row would be a worse answer than losing the row.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'activity_log': <String>[
          'not json at all',
          jsonEncode(<String, dynamic>{'itemId': 'item-1'}), // no date
          jsonEncode(ActivityEntry(
            itemId: 'item-2',
            itemName: 'Paddington',
            childId: 'kid-1',
            childName: 'Emma',
            label: 'kids-emma',
            gaveAccess: true,
            at: DateTime(2026, 8, 6),
          ).toJson()),
        ],
      });
      final store = ActivityStore(await SharedPreferences.getInstance());

      final entries = store.read();
      expect(entries, hasLength(1));
      expect(entries.single.itemId, 'item-2');
    });

    test('an entry survives being written and read back', () async {
      final entry = ActivityEntry(
        itemId: 'set-1',
        itemName: 'Back to the Future',
        childId: 'kid-2',
        childName: 'Sam',
        label: 'block-sam',
        gaveAccess: false,
        at: DateTime(2026, 8, 6, 9, 30),
        collectionSize: 3,
      );

      final back = ActivityEntry.fromJson(
          jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>)!;

      expect(back.itemId, entry.itemId);
      expect(back.childName, 'Sam');
      expect(back.gaveAccess, isFalse);
      expect(back.collectionSize, 3);
      expect(back.at.toUtc(), entry.at.toUtc(),
          reason: 'stored as UTC, shown in local time');
    });

    test('the membership of a collection is never stored', () async {
      // Undo re-resolves it: a set can gain or lose titles between the write
      // and the undo, and replaying a captured list is the same mistake as
      // replaying a captured item body.
      final json = ActivityEntry(
        itemId: 'set-1',
        itemName: 'Back to the Future',
        childId: 'kid-1',
        childName: 'Emma',
        label: 'kids-emma',
        gaveAccess: true,
        at: DateTime(2026, 8, 6),
        collectionSize: 3,
      ).toJson();

      expect(json.keys, isNot(contains('memberIds')));
      expect(jsonEncode(json), isNot(contains('film-')));
    });
  });

  group('a failure to record is not a failure to write', () {
    test('the write still succeeds when the log cannot be written', () async {
      scriptItem('item-1');
      final broken = AssignRepository(
        api: JellyfinApiFactory(
          identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
          adapter: server,
        ).create(baseUrl: 'http://host:8096'),
        adminUserId: 'admin-1',
        activity: _FailingActivityStore(await SharedPreferences.getInstance()),
      );

      // No throw: the library write happened, and surfacing a preferences
      // problem as a failed write would be a lie in the alarming direction.
      final outcome = await broken.apply(
        itemId: 'item-1',
        diff: TagDiff([TagChange(child: emma, label: 'kids-emma', adding: true)]),
      );

      expect(outcome.applied.changes, hasLength(1));
    });
  });
}

class _FailingActivityStore extends ActivityStore {
  const _FailingActivityStore(super.prefs);

  @override
  Future<void> add(ActivityEntry entry) async => throw StateError('disk full');
}
