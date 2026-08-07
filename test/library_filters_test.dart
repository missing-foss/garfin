// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';

import 'support/fake_jellyfin_server.dart';

/// The filter query, and the delimiters that are not a house style.
///
/// Measured on 10.11.11, on one server, in one query string:
///
///     genres=Family|Comedy   -> 4      genres=Family,Comedy  -> 0
///     years=1985,1989        -> 2      years=1985|1989       -> HTTP 400
///     IncludeItemTypes=Movie,Series    -> works
///
/// One wrong delimiter fails **loudly** and the other **silently**, and the
/// silent one is a filter that quietly matches nothing — an empty grid a parent
/// would read as "there is nothing here". So each is pinned rather than
/// remembered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJellyfinServer server;
  late JellyfinApi api;

  setUp(() {
    server = FakeJellyfinServer();
    api = JellyfinApiFactory(
      identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      adapter: server,
    ).create(baseUrl: 'http://host:8096');
  });

  Future<Map<String, dynamic>> queryFor(
    LibraryFilters filters, {
    int? cap,
  }) async {
    server.fallback(json: <String, dynamic>{
      'Items': <dynamic>[],
      'TotalRecordCount': 0,
    });
    await api.libraryPage(
      userId: 'admin-1',
      startIndex: 0,
      limit: 24,
      filters: filters,
      maxParentalRating: cap,
    );
    return server.requests.last.queryParameters;
  }

  group('the delimiters', () {
    test('a decade goes out as its ten years, comma-delimited', () async {
      final query = await queryFor(const LibraryFilters(decade: 1990));

      expect(query['years'],
          '1990,1991,1992,1993,1994,1995,1996,1997,1998,1999');
      expect(query['years'], isNot(contains('|')),
          reason: 'a pipe here answers HTTP 400');
    });

    test('the type list stays comma-delimited', () async {
      final query = await queryFor(const LibraryFilters());
      expect(query['IncludeItemTypes'], 'Movie,Series,BoxSet');
    });

    test('a genre goes out on its own, never joined with a comma', () async {
      // One genre at a time by design — but if this ever takes several, the
      // separator is `|`. A comma would make the query match nothing at all
      // and the grid would look empty rather than broken.
      final query = await queryFor(const LibraryFilters(genre: 'Family'));
      expect(query['genres'], 'Family');
      expect(query['genres'], isNot(contains(',')));
    });
  });

  group('what each filter sends', () {
    test('nothing set sends no filter parameters', () async {
      final query = await queryFor(const LibraryFilters());

      expect(query.containsKey('genres'), isFalse);
      expect(query.containsKey('years'), isFalse);
      expect(query.containsKey('maxOfficialRating'), isFalse);
    });

    test('a type replaces the default list rather than adding to it', () async {
      final query = await queryFor(const LibraryFilters(type: 'Series'));
      expect(query['IncludeItemTypes'], 'Series');
    });

    test('the cap goes out as the number from the policy', () async {
      // Measured: `maxOfficialRating` accepts the numeric value, and this
      // locale's ladder has five names sharing value 0 — so a name would mean
      // picking one arbitrarily.
      final query =
          await queryFor(const LibraryFilters(withinCap: true), cap: 8);
      expect(query['maxOfficialRating'], 8);
    });

    test('the cap is not sent when the toggle is off', () async {
      final query = await queryFor(const LibraryFilters(), cap: 8);
      expect(query.containsKey('maxOfficialRating'), isFalse);
    });

    test('a cap of zero is a cap, and is sent', () async {
      // Zero is a real value on the measured ladder — `G`, `U`, `E`, `All` and
      // `0+` all share it — so it belongs to the youngest and most restricted
      // children. Dart has no truthiness, so the code is right today; the
      // reason this is pinned is that the plausible edit is
      // `maxParentalRating != null && maxParentalRating > 0`, or a port that
      // reads 0 as absent. Every other test in this file survives that
      // mutation, and the failure direction is the bad one: the filter
      // silently stops applying for exactly the children it matters most for.
      final query =
          await queryFor(const LibraryFilters(withinCap: true), cap: 0);
      expect(query['maxOfficialRating'], 0);
    });

    test('the cap is not sent when the child has none', () async {
      // A child with no cap and the toggle somehow on must not send a null,
      // which measured filters *nothing* — silently, so it would look like the
      // toggle simply did not work.
      final query =
          await queryFor(const LibraryFilters(withinCap: true), cap: null);
      expect(query.containsKey('maxOfficialRating'), isFalse);
    });

    test('filters combine, and paging survives them', () async {
      final query = await queryFor(const LibraryFilters(
        type: 'Movie',
        genre: 'Comedy',
        decade: 2010,
        withinCap: true,
      ), cap: 8);

      expect(query['IncludeItemTypes'], 'Movie');
      expect(query['genres'], 'Comedy');
      expect(query['years'], startsWith('2010,'));
      expect(query['maxOfficialRating'], 8);
      expect(query['StartIndex'], 0);
      expect(query['Limit'], 24);
      expect(query['Fields'], 'Tags,ChildCount');
    });
  });

  group('search (#73), pinned to what the server actually does', () {
    test('the parameter is searchTerm, and it is trimmed', () async {
      // Measured on 10.11.11 before any of this was written. The name is not a
      // guess and neither is the behaviour: title only — not the overview, the
      // cast, tags or genres — matching any substring, case- and
      // accent-insensitively.
      final query =
          await queryFor(const LibraryFilters(searchTerm: '  paddington  '));

      expect(query['searchTerm'], 'paddington');
    });

    test('whitespace is not a search, and is not sent', () async {
      // The server returns the **whole library** for `searchTerm=%20`
      // (measured), so sending it would be a filter that filters nothing while
      // the UI claims one is active.
      expect(
        (await queryFor(const LibraryFilters(searchTerm: '   ')))
            .containsKey('searchTerm'),
        isFalse,
      );
      expect(
        (await queryFor(const LibraryFilters(searchTerm: '')))
            .containsKey('searchTerm'),
        isFalse,
      );
      expect(
        (await queryFor(const LibraryFilters())).containsKey('searchTerm'),
        isFalse,
      );
    });

    test('it goes out WITH the other filters, not instead of them', () async {
      // Measured both directions on a real server: searchTerm + genres=Family
      // returns the match, searchTerm + genres=Drama returns nothing. It ANDs.
      // If Garfin dropped a filter when searching, the grid would quietly widen
      // at the moment a parent is trying to narrow it.
      final query = await queryFor(
        const LibraryFilters(
          searchTerm: 'bear',
          type: 'Movie',
          genre: 'Family',
          decade: 2010,
          withinCap: true,
        ),
        cap: 8,
      );

      expect(query['searchTerm'], 'bear');
      expect(query['IncludeItemTypes'], 'Movie');
      expect(query['genres'], 'Family');
      expect(query['years'], startsWith('2010,'));
      expect(query['maxOfficialRating'], 8);
    });

    test('Recursive is still true when searching', () async {
      // Load-bearing, and measured: without `Recursive`, the same query answers
      // with folders — `Movies`, `Playlists` — instead of films. A search that
      // returns two folders reads as "no results" to everyone.
      final query = await queryFor(const LibraryFilters(searchTerm: 'bear'));

      expect(query['Recursive'], isTrue);
    });
  });

  group('the model', () {
    test('a decade is ten years, starting at the decade', () {
      expect(const LibraryFilters(decade: 1980).decadeYears.first, 1980);
      expect(const LibraryFilters(decade: 1980).decadeYears.last, 1989);
      expect(const LibraryFilters(decade: 1980).decadeYears, hasLength(10));
      expect(const LibraryFilters().decadeYears, isEmpty);
    });

    test('a search counts as an active filter, but whitespace does not', () {
      // The badge over the tune button reads `activeCount`, and `isEmpty`
      // decides whether the button looks engaged. A whitespace "search" that
      // counted would put a 1 on an unfiltered grid.
      expect(const LibraryFilters(searchTerm: 'bear').activeCount, 1);
      expect(const LibraryFilters(searchTerm: 'bear').isEmpty, isFalse);
      expect(const LibraryFilters(searchTerm: '   ').activeCount, 0);
      expect(const LibraryFilters(searchTerm: '   ').isEmpty, isTrue);
      expect(const LibraryFilters(searchTerm: '').isEmpty, isTrue);
      expect(
        const LibraryFilters(searchTerm: 'bear', genre: 'Family').activeCount,
        2,
      );
    });

    test('a search can be cleared like any other filter', () {
      const set = LibraryFilters(searchTerm: 'bear', genre: 'Family');

      expect(set.copyWith(searchTerm: null).searchTerm, isNull);
      expect(set.copyWith(searchTerm: null).genre, 'Family',
          reason: 'clearing the search must not clear the others');
      expect(set.copyWith(genre: null).searchTerm, 'bear',
          reason: 'and clearing another must not clear the search');
    });

    test('a filter can be cleared, not only changed', () {
      // The usual copyWith cannot express this: with null meaning "keep",
      // "no genre" and "leave the genre alone" would be the same call and
      // clearing a chip would be unreachable.
      const set = LibraryFilters(genre: 'Family', decade: 1990, type: 'Movie');

      expect(set.copyWith(genre: null).genre, isNull);
      expect(set.copyWith(genre: null).decade, 1990,
          reason: 'clearing one filter must not clear the others');
      expect(set.copyWith(decade: null).decade, isNull);
      expect(set.copyWith(type: null).type, isNull);
      expect(set.copyWith(genre: 'Comedy').genre, 'Comedy');
    });

    test('activeCount is what the badge shows', () {
      expect(const LibraryFilters().activeCount, 0);
      expect(const LibraryFilters().isEmpty, isTrue);
      expect(
        const LibraryFilters(type: 'Movie', genre: 'Comedy', withinCap: true)
            .activeCount,
        3,
      );
      expect(const LibraryFilters(withinCap: true).isEmpty, isFalse);
    });

    test('equality is by value, so an unchanged filter does not refetch', () {
      // The grid rebuilds — and repages — when this changes. Identity equality
      // would restart paging on every rebuild.
      expect(const LibraryFilters(genre: 'Family'),
          const LibraryFilters(genre: 'Family'));
      expect(const LibraryFilters(genre: 'Family'),
          isNot(const LibraryFilters(genre: 'Comedy')));
    });

    test('and every field is in it — one line per field, on purpose', () {
      // **This test used to cover `genre` alone**, and while it did,
      // `searchTerm` was missing from `==` from the commit that introduced it:
      // the grid never re-queried, and #73 filtered nothing until #90. The
      // reason nothing caught it is visible above — one field of five pinned,
      // and the omitted one was not that field.
      //
      // A field outside `==` cannot change anything. `libraryFiltersProvider`
      // is a `Notifier`, and Riverpod compares old state with new to decide
      // whether to notify (`defaultUpdateShouldNotify` is a plain `!=`), so the
      // sixth field someone adds will be exactly as unprotected as `searchTerm`
      // was, and will fail in exactly the same shape: state set correctly, and
      // a feature that does nothing.
      //
      // So: one line per field, and add one when you add one.
      const base = LibraryFilters();
      expect(base, const LibraryFilters(), reason: 'sanity: base equals base');

      expect(base, isNot(const LibraryFilters(type: 'Movie')));
      expect(base, isNot(const LibraryFilters(genre: 'Family')));
      expect(base, isNot(const LibraryFilters(decade: 1990)));
      expect(base, isNot(const LibraryFilters(withinCap: true)));
      expect(base, isNot(const LibraryFilters(searchTerm: 'bear')));

      // And each field distinguishes *values*, not merely presence — the
      // failure `hasSearch`-style equality would still have: a changed search
      // that reads as "there is still a search, nothing to do".
      expect(const LibraryFilters(type: 'Movie'),
          isNot(const LibraryFilters(type: 'Series')));
      expect(const LibraryFilters(genre: 'Family'),
          isNot(const LibraryFilters(genre: 'Comedy')));
      expect(const LibraryFilters(decade: 1990),
          isNot(const LibraryFilters(decade: 2000)));
      expect(const LibraryFilters(searchTerm: 'bear'),
          isNot(const LibraryFilters(searchTerm: 'paddington')));
    });
  });
}
