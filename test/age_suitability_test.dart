// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/age_suitability.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';

/// The whole truth table for the age hint.
///
/// Most of this is about [AgeSuitability.unknown]. Four different situations
/// land there, and a helper that read any of them as "fine" would be wrong
/// exactly where a parent is trusting it — so each gets its own test rather
/// than being covered by one.
void main() {
  /// The measured US ladder, values as the server reports them.
  final ladder = ParentalRatingLadder.fromJson(<Object>[
    <String, dynamic>{'Name': 'Unrated'},
    <String, dynamic>{'Name': 'Approved', 'Value': 0},
    <String, dynamic>{'Name': 'G', 'Value': 0},
    <String, dynamic>{'Name': 'TV-Y7', 'Value': 7},
    <String, dynamic>{'Name': 'PG', 'Value': 10},
    <String, dynamic>{'Name': 'PG-13', 'Value': 13},
    <String, dynamic>{'Name': 'R', 'Value': 17},
    <String, dynamic>{'Name': '21', 'Value': 21},
    <String, dynamic>{'Name': 'XXX', 'Value': 1000},
    <String, dynamic>{'Name': 'Banned', 'Value': 1001},
  ]);

  LibraryItem film({String? rating}) => LibraryItem(
        id: 'a',
        name: 'Paddington',
        type: 'Movie',
        tags: const [],
        officialRating: rating,
      );

  AgeSuitability check({String? rating, int? age}) => suitabilityFor(
        item: film(rating: rating),
        ladder: ladder,
        childAge: age,
      );

  group('the comparison itself', () {
    test('a rating at or below the age suits', () {
      expect(check(rating: 'G', age: 7), AgeSuitability.suitsAge);
      expect(check(rating: 'TV-Y7', age: 7), AgeSuitability.suitsAge);
      expect(check(rating: 'PG', age: 12), AgeSuitability.suitsAge);
    });

    test('a rating above the age does not', () {
      expect(check(rating: 'PG-13', age: 7), AgeSuitability.aboveAge);
      expect(check(rating: 'R', age: 13), AgeSuitability.aboveAge);
    });

    test('the boundary is inclusive — 13 suits a thirteen-year-old', () {
      expect(check(rating: 'PG-13', age: 13), AgeSuitability.suitsAge);
      expect(check(rating: 'PG-13', age: 12), AgeSuitability.aboveAge);
    });

    test('a rating name is matched case-insensitively', () {
      // `OfficialRating` is written by whichever provider scraped the file and
      // does not reliably match the ladder's capitalisation.
      expect(check(rating: 'pg-13', age: 13), AgeSuitability.suitsAge);
      expect(check(rating: '  R  ', age: 20), AgeSuitability.suitsAge);
    });
  });

  group('the four ways it must answer "not known"', () {
    test('the item has no OfficialRating at all', () {
      // Arguably the majority case in a self-hosted library. Reading absence as
      // suitability is the failure this whole enum exists to prevent.
      expect(check(rating: null, age: 7), AgeSuitability.unknown);
      expect(check(rating: '', age: 7), AgeSuitability.unknown);
    });

    test('the rating is not on the server\'s ladder', () {
      expect(check(rating: 'Rated PG', age: 7), AgeSuitability.unknown);
      expect(check(rating: 'Tous publics', age: 7), AgeSuitability.unknown);
    });

    test('no birth year has been entered for the child', () {
      expect(check(rating: 'R', age: null), AgeSuitability.unknown);
    });

    test('the ladder value is a sentinel rather than an age', () {
      // 1000 and 1001 are ordering values. Comparing an age against them would
      // answer "above their age" for the right reason by accident, and the same
      // arithmetic would mis-handle whatever a different locale introduces.
      expect(check(rating: 'XXX', age: 7), AgeSuitability.unknown);
      expect(check(rating: 'Banned', age: 40), AgeSuitability.unknown);
      // The last real rung still works, so the cut-off is not swallowing them.
      expect(check(rating: '21', age: 21), AgeSuitability.suitsAge);
    });
  });

  group('unknown is never quietly suitable', () {
    test('an unrated item is not treated as safe for a young child', () {
      // The sharpest statement of the rule: same child, same answer expected,
      // and the two must not collapse into one.
      expect(check(rating: null, age: 4), isNot(AgeSuitability.suitsAge));
      expect(check(rating: 'G', age: 4), AgeSuitability.suitsAge);
    });

    test('an empty ladder answers unknown rather than suiting everything', () {
      // The ladder is fetched, so it can fail to load. When it does, every
      // rating becomes unrecognisable — which is a don't-know, not a pass.
      expect(
        suitabilityFor(
          item: film(rating: 'R'),
          ladder: const ParentalRatingLadder.empty(),
          childAge: 4,
        ),
        AgeSuitability.unknown,
      );
    });
  });

  group('the age the hint compares against', () {
    test('it is the age the child is guaranteed to have reached', () {
      // Born 2013. On 2026-08-05 they are 13 only if their birthday has
      // passed; with a November one they are 12. Only the year is stored, so
      // the hint takes the lower.
      expect(
        guaranteedAge(birthYear: 2013, today: DateTime(2026, 8, 5)),
        12,
      );
    });

    test('erring low points the residual error at aboveAge, not suitsAge', () {
      // The asymmetry this whole feature runs on, applied to its own
      // arithmetic. Taking the higher age would have read a 13-rated title as
      // suiting a child who is still 12 — systematic, invisible, and pointed
      // the wrong way for roughly half of children at any moment.
      final age = guaranteedAge(birthYear: 2013, today: DateTime(2026, 8, 5));

      expect(check(rating: 'PG-13', age: age), AgeSuitability.aboveAge);
      // And the naive arithmetic would have said the opposite.
      expect(check(rating: 'PG-13', age: age + 1), AgeSuitability.suitsAge);
    });

    test('it does not depend on the month, only the year', () {
      // The whole point of storing a year: the answer must not lurch on
      // 1 January for a child born in December.
      expect(
        guaranteedAge(birthYear: 2013, today: DateTime(2026, 1, 1)),
        guaranteedAge(birthYear: 2013, today: DateTime(2026, 12, 31)),
      );
    });
  });

  group('the ladder\'s inverse lookup', () {
    test('a name has one value even though a value has many names', () {
      expect(ladder.valueFor('PG'), 10);
      expect(ladder.valueFor('G'), 0);
      // The forward direction is the ambiguous one — three names at 0 here.
      expect(ladder.namesFor(0), ['Approved', 'G']);
    });

    test('a valueless rung is not findable by name', () {
      // `Unrated` carries no `Value`, so there is no score to return for it.
      expect(ladder.valueFor('Unrated'), isNull);
    });

    test('an unknown name is null, not zero', () {
      expect(ladder.valueFor('Rated PG'), isNull);
      expect(ladder.valueFor(null), isNull);
    });
  });
}
