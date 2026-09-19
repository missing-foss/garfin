// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/rating_origin.dart';

/// Which certification system a rating names (#142, option 2).
///
/// The cases are the ones measured on 12.1.0 — see `docs/JELLYFIN-API.md`
/// § Which certification system a rating names. Two of them are the reason
/// this function exists rather than a prefix match: `TV-PG` and `PG-13` are
/// ordinary US rungs whose first two letters are real country codes.
void main() {
  // The US ladder, abbreviated to the rungs that matter here.
  const usLadder = {'G', 'PG', 'PG-13', 'R', 'NC-17', 'TV-PG', 'TV-Y7-FV'};

  // What `GET /Localization/Countries` answered: 140 entries, and not one of
  // TV, PG or NR.
  const countries = {'FR', 'SE', 'PT', 'US', 'DE', 'GB', 'ES', 'IN'};

  String? origin(String? rating) => ratingCountryCode(
        rating,
        ladderNames: usLadder,
        countryCodes: countries,
      );

  group('says nothing', () {
    test('for a rung of the server ladder, even a hyphenated one', () {
      expect(origin('PG-13'), isNull, reason: 'PG is Papua New Guinea');
      expect(origin('TV-PG'), isNull, reason: 'TV is Tuvalu');
      expect(origin('TV-Y7-FV'), isNull);
      expect(origin('R'), isNull);
    });

    test('for a prefix the server does not know as a country', () {
      expect(origin('NR-17'), isNull, reason: 'NR is Nauru, and not a rung');
    });

    test('for a rating with no prefix at all', () {
      expect(origin('12'), isNull);
      expect(origin('Rated PG'), isNull);
    });

    test('for nothing, empty, or too short to carry a prefix', () {
      expect(origin(null), isNull);
      expect(origin(''), isNull);
      expect(origin('FR-'), isNull);
    });

    test('when the server answered no countries at all', () {
      expect(
        ratingCountryCode('FR-12', ladderNames: usLadder, countryCodes: const {}),
        isNull,
        reason: 'a failed lookup must show the rating alone, never a guess',
      );
    });
  });

  group('the rung check, which the US fixtures above cannot exercise', () {
    // On a US server every rung that looks prefixed (`PG-13`, `TV-PG`) has a
    // prefix the server does not know as a country, so the country-list check
    // alone answers null and the rung check never decides anything. Review
    // measured that: deleting it left all sixteen cases green.
    //
    // A server configured to its own country is where the two halves come
    // apart: `DE-16` is a rung on the German ladder *and* `DE` is a country.
    const germanLadder = {'DE-0', 'DE-6', 'DE-12', 'DE-16', 'DE-18'};
    const countriesKnown = {'DE', 'FR', 'US'};

    test('a domestic rung is not a country label', () {
      expect(
        ratingCountryCode(
          'DE-16',
          ladderNames: germanLadder,
          countryCodes: countriesKnown,
        ),
        isNull,
        reason: 'DE-16 on a German server is an ordinary rating, not "16 (DE)"',
      );
    });

    test('the rung comparison ignores case, as the server does', () {
      expect(
        ratingCountryCode(
          'fr-12',
          ladderNames: const {'FR-12'},
          countryCodes: const {'FR'},
        ),
        isNull,
        reason: 'the server matches ratings case-insensitively; so must this',
      );
    });
  });

  group('names the country', () {
    test('when the rating carries a code the server knows', () {
      expect(origin('FR-12'), 'FR');
      expect(origin('SE-BTL'), 'SE');
      expect(origin('PT-M/12'), 'PT');
    });

    test('case-insensitively, since the server matches ratings that way', () {
      expect(origin('fr-12'), 'FR');
    });

    test('for a string that is a rung on another ladder but not this one', () {
      // `12` alone is a rung on GB, DE and FR and not on US — measured. With a
      // prefix it is the same item on a US-configured server.
      expect(origin('DE-12'), 'DE');
    });
  });
}
