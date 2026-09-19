// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/library_item.dart';

/// The two fields the detail view needs, and the distinction each one has to
/// keep (#146).
///
/// Measured on 12.1.0 and recorded in `docs/JELLYFIN-API.md` § Duration and
/// country of origin: `RunTimeTicks` arrives unasked when the item has media
/// and is **absent** when it has none, and `ProductionLocations` is absent
/// until it is asked for. Neither absence may read as a value.
void main() {
  group('duration', () {
    test('is read when the server sends it', () {
      final item = LibraryItem.fromJson(const {
        'Id': 'a',
        'Name': 'Rated US',
        'Type': 'Movie',
        // the 7 s fixture, verbatim from the measurement
        'RunTimeTicks': 70030000,
      });

      expect(item.runTimeTicks, 70030000);
      expect(
        Duration(microseconds: item.runTimeTicks! ~/ 10).inSeconds,
        7,
        reason: 'ticks are 100ns units, not milliseconds',
      );
    });

    test('is null when the key is absent, which is what a file with no media '
        'answers', () {
      final item = LibraryItem.fromJson(const {
        'Id': 'b',
        'Name': 'No media',
        'Type': 'Movie',
      });

      expect(item.runTimeTicks, isNull);
    });

    test('is null for a BoxSet, which never carries one', () {
      final item = LibraryItem.fromJson(const {
        'Id': 'c',
        'Name': 'Ctl Set',
        'Type': 'BoxSet',
        'ChildCount': 2,
      });

      expect(item.runTimeTicks, isNull);
    });
  });

  group('country of origin', () {
    test('reads the list the server sends, in order', () {
      final item = LibraryItem.fromJson(const {
        'Id': 'd',
        'Name': 'Rated bare',
        'Type': 'Movie',
        'ProductionLocations': ['Germany', 'France'],
      });

      expect(item.productionLocations, ['Germany', 'France'],
          reason: 'names, not codes, and more than one is normal');
    });

    test('is empty — never null — whether the server sent none or was not '
        'asked', () {
      final sentEmpty = LibraryItem.fromJson(const {
        'Id': 'e',
        'Name': 'No country',
        'Type': 'Movie',
        'ProductionLocations': <String>[],
      });
      final notAsked = LibraryItem.fromJson(const {
        'Id': 'f',
        'Name': 'No country',
        'Type': 'Movie',
      });

      expect(sentEmpty.productionLocations, isEmpty);
      expect(notAsked.productionLocations, isEmpty);
    });
  });

  test('an item with neither field still parses', () {
    final item = LibraryItem.fromJson(const {
      'Id': 'g',
      'Name': 'Plain',
      'Type': 'Movie',
    });

    expect(item.name, 'Plain');
    expect(item.runTimeTicks, isNull);
    expect(item.productionLocations, isEmpty);
  });

  group('scores, genres and studios (#160)', () {
    // The shapes are verbatim from the 2026-09-18 measurement on 12.1.0.
    final film = LibraryItem.fromJson(const {
      'Id': 'e',
      'Name': 'Amelie',
      'Type': 'Movie',
      'CommunityRating': 8.3,
      'CriticRating': 89,
      'Genres': ['Comedy', 'Romance'],
      'Studios': [
        {'Name': 'StudioOne', 'Id': 'bafaf9bb11eedcf00d1369c6057e4feb'},
      ],
    });

    test('both scores are read, the integer one too', () {
      expect(film.communityRating, 8.3);
      expect(film.criticRating, 89.0,
          reason: 'JSON sent 89, an int, which must not read as absent');
    });

    test('genres are the names, in order', () {
      expect(film.genres, ['Comedy', 'Romance']);
    });

    test('studios are objects on the wire and names here', () {
      expect(film.studios, ['StudioOne']);
    });

    test('all four absent read as absent, not as zero', () {
      final bare = LibraryItem.fromJson(const {
        'Id': 'f',
        'Name': 'Bare',
        'Type': 'Series',
      });

      expect(bare.communityRating, isNull);
      expect(bare.criticRating, isNull);
      expect(bare.genres, isEmpty);
      expect(bare.studios, isEmpty);
    });

    test('a studio without a name is skipped, not shown blank', () {
      final item = LibraryItem.fromJson(const {
        'Id': 'g',
        'Name': 'x',
        'Type': 'Movie',
        'Studios': [
          {'Id': 'no-name'},
          {'Name': ''},
          {'Name': 'Kept'},
        ],
      });

      expect(item.studios, ['Kept']);
    });
  });
}
