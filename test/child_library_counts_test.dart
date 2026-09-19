// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';

import 'support/fake_jellyfin_server.dart';

/// The per-library counts, against what the server actually answers.
///
/// **Measured 2026-09-05 on 10.11.11**, five libraries and a child enabled on
/// one of them, and both halves of this were wrong:
///
///   * `/UserViews` returned five libraries for the administrator and one for
///     the child, while the app listed the administrator's and counted in them
///     as the child;
///   * `/Items` was asked for `Movie,Series` in every one of them, which
///     answers **0** for a music, book or home-video library that is not empty.
///
/// And the two compounded: a `parentId` the child cannot open answers **401**,
/// not zero, so a single inaccessible library rejected the whole batch and the
/// section rendered nothing at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  const identity = DeviceIdentity(deviceId: 'd', deviceName: 't');
  const request = ChildLibrariesRequest(session: session, childId: 'kid-1');

  Map<String, dynamic> view(String id, String name, String? type) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'CollectionType': ?type,
      };

  late FakeJellyfinServer server;

  /// The server as measured: the child's views are a subset, and each library
  /// answers only for the types it can actually hold.
  ProviderContainer containerWith({required List<String> childCanOpen}) {
    server = FakeJellyfinServer();
    const all = [
      ('lib-films', 'Films', 'movies', 'Movie', 5),
      ('lib-shows', 'Shows', 'tvshows', 'Series', 1),
      ('lib-music', 'Music', 'music', 'Audio', 2),
      ('lib-books', 'Books', 'books', 'Book', 1),
    ];

    server.onQuery(
      '/UserViews',
      (q) => q['userId'] == 'admin-1',
      json: <String, dynamic>{
        'Items': [for (final l in all) view(l.$1, l.$2, l.$3)],
      },
    );
    server.onQuery(
      '/UserViews',
      (q) => q['userId'] == 'kid-1',
      json: <String, dynamic>{
        'Items': [
          for (final l in all)
            if (childCanOpen.contains(l.$1)) view(l.$1, l.$2, l.$3),
        ],
      },
    );

    // Registered widest-first: matchers are checked **newest first**, so the
    // narrow "asked for the type it holds" rule has to go in last or the catch
    // -all shadows it and every library answers zero. That mistake reads as the
    // production code being wrong.
    for (final (id, _, _, _, _) in all) {
      server.onQuery(
        '/Items',
        (q) => q['parentId'] == id,
        json: <String, dynamic>{'TotalRecordCount': 0},
      );
    }
    for (final (id, _, _, holds, count) in all) {
      // Only the type the library really holds returns anything. Asking a music
      // library for `Movie,Series` answers zero, exactly as measured.
      server.onQuery(
        '/Items',
        (q) => q['parentId'] == id && q['IncludeItemTypes'] == holds,
        json: <String, dynamic>{'TotalRecordCount': count},
      );
    }
    server.fallback(json: <String, dynamic>{'TotalRecordCount': 0});

    return ProviderContainer(
      overrides: [
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: server),
        ),
      ],
    );
  }

  test('a library the child cannot open is never asked about', () async {
    final c = containerWith(childCanOpen: ['lib-films']);
    addTearDown(c.dispose);

    final counts = await c.read(childLibraryCountsProvider(request).future);

    expect(counts.map((l) => l.library.name), ['Films']);
    // The half that matters most: the request is not made at all, so the 401
    // the real server answers here has nowhere to happen.
    expect(
      server.requests.where((r) => r.queryParameters['parentId'] == 'lib-books'),
      isEmpty,
      reason: 'asking about a library the child cannot open answers 401, and '
          'one of those rejected the whole batch',
    );
  });

  test('each library is asked for what it can actually hold', () async {
    final c = containerWith(
      childCanOpen: ['lib-films', 'lib-shows', 'lib-music', 'lib-books'],
    );
    addTearDown(c.dispose);

    final counts = await c.read(childLibraryCountsProvider(request).future);
    final byName = {for (final l in counts) l.library.name: l.visible};

    expect(byName['Films'], 5);
    expect(byName['Shows'], 1, reason: 'a tvshows library is counted in series');
  });

  test('a library holding nothing Garfin can give is left off', () async {
    final c = containerWith(
      childCanOpen: ['lib-films', 'lib-shows', 'lib-music', 'lib-books'],
    );
    addTearDown(c.dispose);

    final counts = await c.read(childLibraryCountsProvider(request).future);

    expect(counts.map((l) => l.library.name), ['Films', 'Shows']);
    // Not "shown as zero". A music library that the child can open and that has
    // two tracks in it would have read "0", which is indistinguishable from
    // "nothing here to give" and is the wrong one of the two.
    expect(counts.any((l) => l.library.name == 'Music'), isFalse);
    expect(counts.any((l) => l.library.name == 'Books'), isFalse);
  });
}
