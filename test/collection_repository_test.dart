// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/collection_repository.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/repositories/device_identity.dart';

import 'support/fake_jellyfin_server.dart';

/// The collection index is 1 + N requests: the BoxSets, then each one's
/// members, because Jellyfin cannot say which sets contain a film. These pin
/// what it asks, as whom, and what it skips.
void main() {
  const admin = 'admin-1';

  Map<String, Object?> boxSet(String id, {int? childCount}) => {
        'Id': id,
        'Name': 'Set $id',
        'Type': 'BoxSet',
        'Tags': <String>[],
        'ChildCount': ?childCount,
      };
  Map<String, Object?> film(String id) => {'Id': id, 'Name': 'Film $id', 'Type': 'Movie', 'Tags': <String>[]};
  Map<String, Object?> page(List<Map<String, Object?>> items) =>
      {'Items': items, 'TotalRecordCount': items.length};

  bool listsSets(Map<String, dynamic> q) => q['IncludeItemTypes'] == 'BoxSet';
  bool membersOf(Map<String, dynamic> q, String id) => q['parentId'] == id;

  (CollectionRepository, FakeJellyfinServer) build() {
    final server = FakeJellyfinServer()..fallback(json: page(const []));
    final api = JellyfinApiFactory(
      identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      adapter: server,
    ).create(baseUrl: 'http://host:8096');
    return (CollectionRepository(api: api, adminUserId: admin), server);
  }

  List<Map<String, dynamic>> itemsQueries(FakeJellyfinServer server) => [
        for (final r in server.requests)
          if (r.path == '/Items') r.queryParameters,
      ];

  group('index', () {
    test('lists the sets once, then asks each non-empty one for its members', () async {
      final (repo, server) = build();
      server
        ..onQuery('/Items', listsSets,
            json: page([boxSet('a', childCount: 2), boxSet('b', childCount: 1)]))
        ..onQuery('/Items', (q) => membersOf(q, 'a'), json: page([film('1'), film('2')]))
        ..onQuery('/Items', (q) => membersOf(q, 'b'), json: page([film('2')]));

      final index = await repo.index();

      final queries = itemsQueries(server);
      expect(queries.where(listsSets), hasLength(1));
      expect(queries.where((q) => q['parentId'] != null).map((q) => q['parentId']).toSet(), {'a', 'b'});
      expect(queries, hasLength(3), reason: '1 + N with N = 2');
      expect(index.setsContaining('2').map((s) => s.collection.id).toSet(), {'a', 'b'});
      expect(index.setsContaining('1').map((s) => s.collection.id), ['a']);
      expect(index.allMemberIds, {'1', '2'});
    });

    test('an empty set is never asked for its members, but an uncounted one is', () async {
      final (repo, server) = build();
      server
        ..onQuery('/Items', listsSets,
            json: page([boxSet('empty', childCount: 0), boxSet('uncounted')]))
        ..onQuery('/Items', (q) => membersOf(q, 'uncounted'), json: page([film('9')]));

      final index = await repo.index();

      final asked = itemsQueries(server).map((q) => q['parentId']).whereType<String>().toList();
      expect(asked, ['uncounted'], reason: 'null ChildCount means "not asked", not "empty"');
      expect(index.byId('empty'), isNull);
      expect(index.setsContaining('9').single.collection.id, 'uncounted');
    });

    test('reads as the administrator, so hidden members still count', () async {
      final (repo, server) = build();
      server
        ..onQuery('/Items', listsSets, json: page([boxSet('a', childCount: 1)]))
        ..onQuery('/Items', (q) => membersOf(q, 'a'), json: page([film('1')]));

      await repo.index();

      final users = itemsQueries(server).map((q) => q['userId']).toSet();
      expect(users, {admin});
    });
  });

  test("setFor asks one set's members in the grid's order", () async {
    final (repo, server) = build();
    server.onQuery('/Items', (q) => membersOf(q, 'a'), json: page([film('1')]));
    final set = await repo.setFor(
      LibraryItem.fromJson(boxSet('a', childCount: 1)),
      sortBy: 'PremiereDate',
      sortOrder: 'Descending',
    );

    final q = itemsQueries(server).single;
    expect(q['SortBy'], 'PremiereDate');
    expect(q['SortOrder'], 'Descending');
    expect(q.containsKey('IncludeItemTypes'), isFalse, reason: 'no index built');
    expect(set.members.single.id, '1');
  });

  test('setForId reads the set itself first, which also proves it still exists', () async {
    final (repo, server) = build();
    server
      ..on('/Users/$admin/Items/a', json: boxSet('a', childCount: 1))
      ..onQuery('/Items', (q) => membersOf(q, 'a'), json: page([film('1')]));

    final set = await repo.setForId('a');

    expect(server.requests.first.path, '/Users/$admin/Items/a');
    expect(set.collection.id, 'a');
    expect(set.members.single.id, '1');
  });
}
