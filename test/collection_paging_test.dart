// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';

import 'support/fake_jellyfin_server.dart';

/// A collection's members, and the collections themselves, are read whole.
///
/// **The reported failure.** Both listings asked for 500 and dropped
/// `TotalRecordCount`. A set of 600 read as 500, a collection write labelled
/// those 500, saw no failures and marked the container — a half-labelled set
/// recorded as complete, made by the read path with nothing to say so.
///
/// The fake answers by `StartIndex`, which is what the real server pages by:
/// measured on 10.11.11 and 12.1, pages of 2 over five members answered 2, 2,
/// 1, then 0, with `TotalRecordCount` 5 on every page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  late FakeJellyfinServer server;
  late JellyfinApi api;

  setUp(() {
    server = FakeJellyfinServer();
    api = JellyfinApiFactory(identity: identity, adapter: server)
        .create(baseUrl: 'http://host:8096', readToken: () => 'token');
  });

  /// [total] items in all, served [pageSize] at a time from `StartIndex`,
  /// for the requests [matching] picks out. [stopAt] makes every page from
  /// there on come back empty, as a listing that changed under the read.
  void serve(
    bool Function(Map<String, dynamic> query) matching, {
    required int total,
    required String type,
    int pageSize = 500,
    int? stopAt,
  }) {
    for (var start = 0; start <= total; start += pageSize) {
      final from = start;
      final end = stopAt != null && from >= stopAt
          ? from
          : (from + pageSize > total ? total : from + pageSize);
      server.onQuery(
        '/Items',
        (q) => matching(q) && q['StartIndex'] == from,
        json: <String, dynamic>{
          'Items': [
            for (var i = from; i < end; i++)
              <String, dynamic>{'Id': '$type-$i', 'Name': '$type $i', 'Type': type},
          ],
          'TotalRecordCount': total,
        },
      );
    }
  }

  bool members(Map<String, dynamic> q) => q['parentId'] == 'set-1';
  bool sets(Map<String, dynamic> q) => q['IncludeItemTypes'] == 'BoxSet';

  List<int> starts() => [
        for (final r in server.requests)
          if (r.path == '/Items') r.queryParameters['StartIndex'] as int,
      ];

  test('a set of 600 is read whole, a page at a time', () async {
    serve(members, total: 600, type: 'Movie');

    final got =
        await api.collectionMembers(userId: 'admin-1', collectionId: 'set-1');

    expect(got, hasLength(600));
    expect(got.map((m) => m.id).toSet(), hasLength(600),
        reason: 'each member once, none twice');
    expect(starts(), [0, 500]);
  });

  test('a set that fits one page is one request', () async {
    serve(members, total: 3, type: 'Movie');

    final got =
        await api.collectionMembers(userId: 'admin-1', collectionId: 'set-1');

    expect(got, hasLength(3));
    expect(starts(), [0], reason: 'no empty page asked for after the last');
  });

  test('a listing that stops short throws rather than returning a part',
      () async {
    serve(members, total: 600, type: 'Movie', stopAt: 500);

    await expectLater(
      api.collectionMembers(userId: 'admin-1', collectionId: 'set-1'),
      throwsA(isA<JellyfinException>()
          .having((e) => e.kind, 'kind', JellyfinErrorKind.server)),
    );
  });

  test('a listing that ignores StartIndex throws rather than repeating',
      () async {
    // The same first page whatever is asked for. Read naively, the repeats
    // would pile up to the total and hand over 600 "members" that are 500
    // films, some twice.
    server.onQuery(
      '/Items',
      members,
      json: <String, dynamic>{
        'Items': [
          for (var i = 0; i < 500; i++)
            <String, dynamic>{'Id': 'Movie-$i', 'Name': 'Movie $i', 'Type': 'Movie'},
        ],
        'TotalRecordCount': 600,
      },
    );

    await expectLater(
      api.collectionMembers(userId: 'admin-1', collectionId: 'set-1'),
      throwsA(isA<JellyfinException>()),
    );
    expect(starts(), [0, 500], reason: 'it stops at the first page that adds nothing');
  });

  test('a member removed between pages: refused, not read one short',
      () async {
    // Page one sees 600. Before page two, one of the first 500 is removed:
    // the rest shift left, so the page starting at 500 begins with what was
    // member 501, and the total says 599. Counting alone, 500 + 99 reaches
    // 599 and member 500 — still in the set — is never read.
    server
      ..onQuery(
        '/Items',
        (q) => members(q) && q['StartIndex'] == 0,
        json: <String, dynamic>{
          'Items': [
            for (var i = 0; i < 500; i++)
              <String, dynamic>{'Id': 'Movie-$i', 'Name': 'Movie $i', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 600,
        },
      )
      ..onQuery(
        '/Items',
        (q) => members(q) && q['StartIndex'] == 500,
        json: <String, dynamic>{
          'Items': [
            for (var i = 501; i < 600; i++)
              <String, dynamic>{'Id': 'Movie-$i', 'Name': 'Movie $i', 'Type': 'Movie'},
          ],
          'TotalRecordCount': 599,
        },
      );

    await expectLater(
      api.collectionMembers(userId: 'admin-1', collectionId: 'set-1'),
      throwsA(isA<JellyfinException>()
          .having((e) => e.kind, 'kind', JellyfinErrorKind.server)),
    );
  });

  test('pages are 500 items', () async {
    serve(members, total: 600, type: 'Movie');

    await api.collectionMembers(userId: 'admin-1', collectionId: 'set-1');

    expect(
      [
        for (final r in server.requests)
          if (r.path == '/Items') r.queryParameters['Limit'],
      ],
      [500, 500],
    );
  });

  test('600 collections are read whole too', () async {
    serve(sets, total: 600, type: 'BoxSet');

    final got = await api.collections(userId: 'admin-1');

    expect(got, hasLength(600));
    expect(starts(), [0, 500]);
  });
}
