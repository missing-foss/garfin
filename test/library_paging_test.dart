// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/library_repository.dart';
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

  /// A full page, because `LibraryRepository.fetch` keeps asking until it has
  /// one — a short page is a *refill* to it, not a page. Pages of three would
  /// make one `loadMore` fire six requests, which is the repository working as
  /// designed and a test measuring the wrong thing.
  ///
  /// **Named rather than written out.** These tests are about paging, not about
  /// how big a page is, and the number changed from 24 to 240 once a page was
  /// sized for scrolling rather than for one screen.
  const pageSize = LibraryRepository.pageSize;

  /// A library a few pages deep. Named for the same reason [pageSize] is: the
  /// old literal 90 was "about four pages" when a page was 24 and is smaller
  /// than one page now.
  const libraryTotal = pageSize * 4;

  List<int> ids(int from, [int count = pageSize]) =>
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
    server.fallback(json: page(ids(1), libraryTotal));
    final container = await build();
    addTearDown(container.dispose);

    final feed =
        await container.read(libraryControllerProvider(session).future);

    expect(feed.entries, hasLength(pageSize));
    expect(feed.totalRecordCount, libraryTotal);
    expect(feed.hasMore, isTrue);
  });

  test('loadMore appends rather than replacing', () async {
    server
      ..on('/Items', json: page(ids(1), libraryTotal))
      ..on('/Items', json: page(ids(pageSize + 1), libraryTotal));
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();

    final feed = container.read(libraryControllerProvider(session)).value!;
    expect(feed.entries, hasLength(pageSize * 2));
    expect(feed.entries.first.item.id, 'item-1');
    expect(feed.entries.last.item.id, 'item-${pageSize * 2}');
  });

  test('an overlapping page does not duplicate a tile', () async {
    // Pages can overlap for real: an item written to between two requests
    // moves in the sort order. A duplicate key in a grid is a crash, not a
    // cosmetic problem.
    server
      ..on('/Items', json: page(ids(1), libraryTotal))
      // The second page starts one early: an item written to between the two
      // requests moves in the sort order and comes back twice.
      ..on('/Items', json: page(ids(pageSize), libraryTotal));
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
    expect(seen, hasLength(pageSize * 2 - 1),
        reason: 'item-\$pageSize arrived twice, listed once');
    expect(seen.toSet(), hasLength(seen.length));
  });

  test('a failed page keeps what is already on screen', () async {
    server
      ..on('/Items', json: page(ids(1), libraryTotal))
      ..on('/Items', status: 500);
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();

    final feed = container.read(libraryControllerProvider(session)).value!;
    expect(feed.entries, hasLength(pageSize), reason: 'the tiles must survive');
    expect(feed.moreFailed, isTrue);
    expect(feed.loadingMore, isFalse);
  });

  test('an empty page ends the feed rather than looping forever', () async {
    // `hasMore` from the server plus an empty result is the state that spins:
    // the scroll listener asks again, gets nothing, and asks again.
    server
      ..on('/Items', json: page(ids(1), libraryTotal))
      ..on('/Items', json: page(const [], libraryTotal));
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
    server.fallback(json: page(ids(1), libraryTotal));
    final container = await build();
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider(session).future);
    await container.read(libraryControllerProvider(session).notifier).loadMore();
    expect(container.read(libraryControllerProvider(session)).value!.entries,
        hasLength(pageSize),
        reason: 'the same fallback page again, deduplicated');

    container
        .read(libraryFiltersProvider.notifier)
        .set(const LibraryFilters(genre: 'Comedy'));
    final feed =
        await container.read(libraryControllerProvider(session).future);

    expect(feed.entries, hasLength(pageSize),
        reason: 'a new filter means a new first page, not an appended one');
  });

  group('applying a share keeps your place (#120)', () {
    /// Distinct pages keyed on `StartIndex`, so a window of two pages is
    /// visibly two pages rather than the same one twice. The shared fallback
    /// above deliberately returns the same 24 items every time, which is right
    /// for the tests that only count requests and wrong for these.
    /// One matcher per `StartIndex`, because the fake answers with a fixed
    /// body rather than a function of the request.
    ///
    /// **Each answer is one page**, which is what the real server does:
    /// measured on 10.11.11, `Limit` is honoured up to the size of the library
    /// and `Limit=5000` returns everything that exists rather than a slice. So
    /// a restore of ten pages is ten requests, and the budget is what decides
    /// whether it gets all ten.
    void scriptPages({int total = pageSize * 40, int pages = 24}) {
      for (var p = 0; p < pages; p++) {
        final start = p * pageSize;
        server.onQuery(
          '/Items',
          (q) => q['StartIndex'] == start,
          json: page(ids(start + 1), total),
        );
      }
    }

    test('a refresh asks for the window that was open, not the first page',
        () async {
      scriptPages();
      final container = await build();
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider(session).future);
      await container
          .read(libraryControllerProvider(session).notifier)
          .loadMore();
      expect(container.read(libraryControllerProvider(session)).value!.entries,
          hasLength(pageSize * 2),
          reason: 'two pages, which is the place the parent scrolled to');

      // Exactly what the assign sheet does after a successful Apply.
      container.read(libraryRevisionProvider.notifier).bump();
      final feed =
          await container.read(libraryControllerProvider(session).future);

      expect(feed.entries, hasLength(pageSize * 2),
          reason: 'the window is restored; before this it came back holding '
              'the first 24 and the rest could not be scrolled back to');
      // Asserted on the request, not only on the count: the entries could be
      // right for the wrong reason if something cached them.
      expect(server.requests.last.queryParameters['Limit'], pageSize * 2,
          reason: 'it asked for the window it had');
    });

    test('but a new filter still starts at the top', () async {
      // The other direction, and the one a restore is most likely to break.
      // A different filter is a different list, not the same list seen again.
      scriptPages();
      final container = await build();
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider(session).future);
      await container
          .read(libraryControllerProvider(session).notifier)
          .loadMore();
      expect(container.read(libraryControllerProvider(session)).value!.entries,
          hasLength(pageSize * 2));

      container
          .read(libraryFiltersProvider.notifier)
          .set(const LibraryFilters(genre: 'Comedy'));
      final feed =
          await container.read(libraryControllerProvider(session).future);

      expect(feed.entries, hasLength(pageSize),
          reason: 'a new list, so page one');
      expect(server.requests.last.queryParameters['Limit'], pageSize);
    });

    test('and so does switching the view', () async {
      scriptPages();
      final container = await build();
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider(session).future);
      await container
          .read(libraryControllerProvider(session).notifier)
          .loadMore();
      expect(container.read(libraryControllerProvider(session)).value!.entries,
          hasLength(pageSize * 2));

      container.read(libraryViewProvider.notifier).set(LibraryView.given);
      final feed =
          await container.read(libraryControllerProvider(session).future);

      expect(feed.entries, hasLength(pageSize));
    });

    test('a deep window is restored whole, not to the fetch budget', () async {
      // **The failure this catches reports success.** `maxFetches` is six —
      // one page plus five refills — and a server that answers a page at
      // a time needs one request per page. Held at six, a ten-page restore
      // returns 144 of 240 and looks like the bug happening less often, which
      // is worse than the bug: it is unreproducible.
      scriptPages();
      final container = await build();
      addTearDown(container.dispose);

      final repository = container.read(libraryRepositoryProvider(session));
      final slice =
          await repository.fetch(startIndex: 0, want: pageSize * 10);

      expect(slice.entries, hasLength(pageSize * 10),
          reason: 'ten pages asked for is ten pages back');
    });

    test('and an ordinary call still asks for exactly one page', () async {
      // The control for the budget change: the ordinary call must not have
      // grown a bigger appetite along with it.
      scriptPages();
      final container = await build();
      addTearDown(container.dispose);

      final slice = await container
          .read(libraryRepositoryProvider(session))
          .fetch(startIndex: 0);

      expect(slice.entries, hasLength(pageSize));
      expect(server.callsTo('/Items'), 1,
          reason: 'one page, one request — unchanged');
    });
  });

  group('a page is sized for scrolling, not for one screen (#123)', () {
    test('one page is one request, and it is 240 rows', () async {
      // **The number is the point, so it is asserted rather than derived.**
      // Everything else in this file names `pageSize` because it is about
      // paging; this one is about how big a page is, and a test that read the
      // constant would pass at any value including the old 24.
      expect(LibraryRepository.pageSize, 240);

      server.fallback(json: page(ids(1), libraryTotal));
      final container = await build();
      addTearDown(container.dispose);

      final feed =
          await container.read(libraryControllerProvider(session).future);

      expect(feed.entries, hasLength(240));
      expect(server.callsTo('/Items'), 1,
          reason: '240 rows for one round trip, where 24 took ten');
      expect(server.requests.first.queryParameters['Limit'], 240);
    });

    test('the filtering window matches it, so a full page is one request too',
        () async {
      // It was four times the page — a multiple that bought one round trip
      // when a quarter of the rows survived. At 240 that trade inverts: it
      // would fetch 960 to keep 240 on the common path, where most of a
      // library is not given to any one child, to save a refill on the rare
      // one. The refill loop handles the rare one.
      expect(LibraryRepository.filteringWindow, LibraryRepository.pageSize);
    });
  });
}
