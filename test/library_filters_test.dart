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

  group('the model', () {
    test('a decade is ten years, starting at the decade', () {
      expect(const LibraryFilters(decade: 1980).decadeYears.first, 1980);
      expect(const LibraryFilters(decade: 1980).decadeYears.last, 1989);
      expect(const LibraryFilters(decade: 1980).decadeYears, hasLength(10));
      expect(const LibraryFilters().decadeYears, isEmpty);
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
  });
}
