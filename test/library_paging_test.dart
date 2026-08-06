// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Infinite scroll, and the three ways it goes wrong.
///
/// A scroll listener fires far more often than a page arrives, pages can
/// overlap when the library changes underneath, and the network fails on page
/// four as readily as on page one. None of those is visible in a screenshot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  /// A full screenful, because `LibraryRepository.fetch` keeps asking until it
  /// has one — a short page is a *refill* to it, not a page. Pages of three
  /// would make one `loadMore` fire six requests, which is the repository
  /// working as designed and a test measuring the wrong thing.
  List<int> ids(int from, [int count = 24]) =>
      [for (var i = 0; i < count; i++) from + i];

  Map<String, dynamic> page(List<int> ids, int total) => <String, dynamic>{
        'TotalRecordCount': total,
        'Items': [
          for (final id in ids)
            <String, dynamic>{
              'Id': 'item-$id',
              'Name': 'Item $id',
              'Type': 'Movie',
              'Tags': <String>[],
            },
        ],
      };

  late FakeJellyfinServer server;

  Future<ProviderContainer> build() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return ProviderContainer(
      overrides: [
        // Resolved here for the same reason `main` resolves it: the provider
        // throws rather than building its own, so a test cannot accidentally
        // assert against a second store the app never used.
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        deviceIdentityProvider.overrideWithValue(
          const DeviceIdentity(deviceId: 'd', deviceName: 't'),
        ),
        // The real factory with a scripted transport, so the query building,
        // the interceptor and the parsing are all exercised — stubbing the API
        // would leave the layer under test unrun.
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(
            identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
            adapter: server,
          ),
        ),
      ],
    );
  }

  setUp(() => server = FakeJellyfinServer());

  test('the first page is what the grid starts with', () async {
    server.fallback(json: page(ids(1), 90));
    final container = await build();
    addTearDown(container.dispose);

    final feed =
        await container.read(libraryControllerProvider(session).future);

    expect(feed.entries, hasLength(24));
    expect(feed.totalRecordCount, 90);
    expect(feed.hasMore, isTrue);
  });

  test('loadMore appends rather than replacing', () async {
    server
      ..on('/Items', json: page(ids(1), 90))
      ..on('/Items', json: page(ids(25), 90));
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();

    final feed = container.read(libraryControllerProvider(session)).value!;
    expect(feed.entries, hasLength(48));
    expect(feed.entries.first.item.id, 'item-1');
    expect(feed.entries.last.item.id, 'item-48');
  });

  test('an overlapping page does not duplicate a tile', () async {
    // Pages can overlap for real: an item written to between two requests
    // moves in the sort order. A duplicate key in a grid is a crash, not a
    // cosmetic problem.
    server
      ..on('/Items', json: page(ids(1), 90))
      // The second page starts one early: an item written to between the two
      // requests moves in the sort order and comes back twice.
      ..on('/Items', json: page(ids(24), 90));
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();

    final seen = container
        .read(libraryControllerProvider(session))
        .value!
        .entries
        .map((e) => e.item.id)
        .toList();
    expect(seen, hasLength(47), reason: 'item-24 arrived twice, listed once');
    expect(seen.toSet(), hasLength(seen.length));
  });

  test('a failed page keeps what is already on screen', () async {
    server
      ..on('/Items', json: page(ids(1), 90))
      ..on('/Items', status: 500);
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();

    final feed = container.read(libraryControllerProvider(session)).value!;
    expect(feed.entries, hasLength(24), reason: 'the tiles must survive');
    expect(feed.moreFailed, isTrue);
    expect(feed.loadingMore, isFalse);
  });

  test('an empty page ends the feed rather than looping forever', () async {
    // `hasMore` from the server plus an empty result is the state that spins:
    // the scroll listener asks again, gets nothing, and asks again.
    server
      ..on('/Items', json: page(ids(1), 90))
      ..on('/Items', json: page(const [], 90));
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();

    expect(
        container.read(libraryControllerProvider(session)).value!.hasMore,
        isFalse);
  });

  test('the feed stops asking once the server has run out', () async {
    server.fallback(json: page(ids(1, 2), 2));
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    final before = server.callsTo('/Items');
    await container.read(libraryControllerProvider(session).notifier).loadMore();

    expect(server.callsTo('/Items'), before,
        reason: 'nothing left to fetch, so nothing should be asked');
  });

  test('changing a filter starts the grid again from the top', () async {
    server.fallback(json: page(ids(1), 90));
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();
    expect(container.read(libraryControllerProvider(session)).value!.entries,
        hasLength(24),
        reason: 'the same fallback page again, deduplicated');

    container
        .read(libraryFiltersProvider.notifier)
        .set(const LibraryFilters(genre: 'Comedy'));
    final feed =
        await container.read(libraryControllerProvider(session).future);

    expect(feed.entries, hasLength(24),
        reason: 'a new filter means a new first page, not an appended one');
  });
}
