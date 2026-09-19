// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/parental_rating.dart';

/// The cap is two numbers, and the second one is enforced.
///
/// Measured on 10.11.11, 2026-08-26: at cap 10/0 a `TV-PG` item is visible and
/// a `TV-PG-D` item is hidden. Same score, different cap. Everything here
/// follows from that one fact.
void main() {
  // Shaped exactly as the server sends it: the first rung carries no Value and
  // no RatingScore at all, and the scored ones carry both.
  ParentalRatingLadder ladder() => ParentalRatingLadder.fromJson([
        {'Name': 'Unrated'},
        {'Name': 'Approved', 'Value': 0, 'RatingScore': {'score': 0, 'subScore': 0}},
        {'Name': 'G', 'Value': 0, 'RatingScore': {'score': 0, 'subScore': 0}},
        {'Name': 'TV-Y7', 'Value': 7, 'RatingScore': {'score': 7, 'subScore': 0}},
        {'Name': 'TV-Y7-FV', 'Value': 7, 'RatingScore': {'score': 7, 'subScore': 1}},
        {'Name': 'PG', 'Value': 10, 'RatingScore': {'score': 10, 'subScore': 0}},
        {'Name': 'TV-PG', 'Value': 10, 'RatingScore': {'score': 10, 'subScore': 0}},
        {'Name': 'TV-PG-D', 'Value': 10, 'RatingScore': {'score': 10, 'subScore': 1}},
        {'Name': 'R', 'Value': 17, 'RatingScore': {'score': 17, 'subScore': 0}},
        {'Name': 'TV-MA', 'Value': 17, 'RatingScore': {'score': 17, 'subScore': 1}},
      ]);

  group('parsing the pair', () {
    test('score and subScore come from RatingScore', () {
      final r = ParentalRating.fromJson(
          {'Name': 'TV-PG-D', 'Value': 10, 'RatingScore': {'score': 10, 'subScore': 1}});
      expect(r.value, 10);
      expect(r.subScore, 1);
    });

    test('Value is the fallback when RatingScore is absent', () {
      // An older server, or the shape a pre-RatingScore install sends.
      final r = ParentalRating.fromJson({'Name': 'PG', 'Value': 10});
      expect(r.value, 10);
      expect(r.subScore, isNull);
    });

    test('the valueless first rung still parses rather than throwing', () {
      final r = ParentalRating.fromJson({'Name': 'Unrated'});
      expect(r.value, isNull);
      expect(r.subScore, isNull);
    });
  });

  // The FR ladder as the server actually sends it, measured 2026-09-02 on
  // 10.11.11 with MetadataCountryCode=FR. Note the shape: `RatingScore` is
  // present but carries **no `subScore` key at all**, which is not how the US
  // ladder above is built and is what these tests exist to pin.
  ParentalRatingLadder frLadder() => ParentalRatingLadder.fromJson([
        {'Name': 'Unrated'},
        {'Name': '0+', 'Value': 0, 'RatingScore': {'score': 0}},
        {'Name': 'Public Averti', 'Value': 0, 'RatingScore': {'score': 0}},
        {'Name': 'Tous Publics', 'Value': 0, 'RatingScore': {'score': 0}},
        {'Name': 'TP', 'Value': 0, 'RatingScore': {'score': 0}},
        {'Name': 'U', 'Value': 0, 'RatingScore': {'score': 0}},
        {'Name': '6+', 'Value': 6, 'RatingScore': {'score': 6}},
        {'Name': '12', 'Value': 12, 'RatingScore': {'score': 12}},
      ]);

  // The US ladder's real collision shape at 10/1, measured 2026-09-02: fifteen
  // names share that one pair. The fixture above stops at TV-PG-D, which made
  // 10/1 look like a clean two-way split; it is not.
  ParentalRatingLadder usSubVariants() => ParentalRatingLadder.fromJson([
        {'Name': 'PG', 'Value': 10, 'RatingScore': {'score': 10, 'subScore': 0}},
        {'Name': 'TV-PG', 'Value': 10, 'RatingScore': {'score': 10, 'subScore': 0}},
        for (final v in [
          'TV-PG-D', 'TV-PG-L', 'TV-PG-S', 'TV-PG-V',
          'TV-PG-DL', 'TV-PG-DS', 'TV-PG-DV', 'TV-PG-LS',
          'TV-PG-LV', 'TV-PG-SV', 'TV-PG-DLS', 'TV-PG-DLV',
          'TV-PG-DSV', 'TV-PG-LSV', 'TV-PG-DLSV',
        ])
          {'Name': v, 'Value': 10, 'RatingScore': {'score': 10, 'subScore': 1}},
      ]);

  group('the sub-score narrows collisions without ending them', () {
    test('fifteen US names share the single pair 10/1', () {
      // The correction this group exists for. `nameFor(10, 1)` is a first
      // match out of fifteen, not a clean answer -- so the US ladder is the
      // WORST measured case for faithfulness, not the reference one.
      expect(usSubVariants().namesFor(10).length, 17);
      expect(usSubVariants().nameFor(10, 1), 'TV-PG-D');
    });

    test('the clean 10/0 answer is the best case, not the typical one', () {
      // PG and TV-PG really do name cleanly -- two names, same cap. Kept as
      // the control: the lookup is lossy at 10/1 and exact-ish at 10/0 on the
      // same ladder, so a test showing only one of those would mislead.
      expect(usSubVariants().nameFor(10, 0), 'PG');
    });
  });

  group('a ladder that carries no sub-scores at all', () {
    test('a missing subScore key parses to null, not to 0', () {
      // The distinction matters: null means the server said nothing, and it is
      // only [nameFor] that then reads it as 0 to match the server's own
      // behaviour. A parser that wrote 0 here would lose that.
      final r = ParentalRating.fromJson(
          {'Name': 'Tous Publics', 'Value': 0, 'RatingScore': {'score': 0}});
      expect(r.value, 0);
      expect(r.subScore, isNull);
    });

    test('the sub-score cannot split a collision it does not have', () {
      // Five FR names sit on the one pair 0/0, so the "sub-score dissolves the
      // collision" argument -- true on the US ladder -- buys nothing here.
      expect(frLadder().namesFor(0),
          containsAll(['0+', 'Public Averti', 'Tous Publics', 'TP', 'U']));
      expect(frLadder().nameFor(0, 0), '0+');
      // And asking with the sub-score the server never sent changes nothing.
      expect(frLadder().nameFor(0), '0+');
    });

    test('a sub-cap of 1 finds no rung rather than falling back to 0', () {
      // Nothing on this ladder is at 0/1. Answering '0+' here would report a
      // cap the child is not under, which is the failure this pair-matching
      // was introduced to stop.
      expect(frLadder().nameFor(0, 1), isNull);
    });

    test('the rungs that do not collide still name exactly', () {
      // The control: this ladder can name things. A test that only showed
      // collisions would not distinguish a lossy lookup from a broken one.
      expect(frLadder().nameFor(6, 0), '6+');
      expect(frLadder().nameFor(12, 0), '12');
      // And the bare numeric certificate resolves by name, which it cannot do
      // on the US ladder -- there is no rung named '12' there.
      expect(frLadder().valueFor('12'), 12);
      expect(ladder().valueFor('12'), isNull);
    });
  });

  group('naming a cap now uses both numbers', () {
    test('the regression this exists for: R is not TV-MA', () {
      // Both sit at score 17. A score-only lookup answers "R" for a child
      // capped at TV-MA -- and R is the more permissive-looking of the two.
      expect(ladder().nameFor(17, 0), 'R');
      expect(ladder().nameFor(17, 1), 'TV-MA');
    });

    test('and the same at 10 and at 7', () {
      expect(ladder().nameFor(10, 0), 'PG');
      expect(ladder().nameFor(10, 1), 'TV-PG-D');
      expect(ladder().nameFor(7, 0), 'TV-Y7');
      expect(ladder().nameFor(7, 1), 'TV-Y7-FV');
    });

    test('names sharing one PAIR still first-match, and that is correct', () {
      // PG and TV-PG are both 10/0. They admit the same items, so they are the
      // same cap -- the old first-match argument, now correctly scoped to the
      // pair instead of to the score.
      expect(ladder().namesFor(10), containsAll(['PG', 'TV-PG', 'TV-PG-D']));
      expect(ladder().nameFor(10, 0), 'PG');
    });

    test('a null sub-cap is the STRICT reading, not the loose one', () {
      // Measured: cap 10 with no sub-rating behaves exactly as sub 0 --
      // TV-PG-D stays hidden. So an absent sub-cap must name the 0 rung.
      expect(ladder().nameFor(10, null), 'PG');
      expect(ladder().nameFor(10), 'PG');
      expect(ladder().nameFor(10, null), isNot('TV-PG-D'));
    });

    test('a pair with no rung falls through to the number, as before', () {
      // The missing-rung case is unchanged: better a bare number than a
      // neighbouring name. Score 10 exists, sub-level 7 does not.
      expect(ladder().nameFor(10, 7), isNull);
      expect(ladder().nameFor(99, 0), isNull);
    });

    test('null in, null out -- an uncapped child has no rating to name', () {
      expect(ladder().nameFor(null), isNull);
      expect(ladder().nameFor(null, 1), isNull);
    });

    test('a ladder with no RatingScore at all still names by score', () {
      // Older server: every subScore is null, so every rung reads as 0 and a
      // cap with no sub-rating still finds its name.
      final old = ParentalRatingLadder.fromJson([
        {'Name': 'PG', 'Value': 10},
        {'Name': 'R', 'Value': 17},
      ]);
      expect(old.nameFor(10), 'PG');
      expect(old.nameFor(17, 0), 'R');
    });
  });

  group('the policy carries the second number', () {
    UserPolicy parse(Map<String, dynamic> extra) => UserPolicy.fromJson({
          'IsAdministrator': false,
          'IsDisabled': false,
          'AllowedTags': <String>[],
          'BlockedTags': <String>[],
          ...extra,
        });

    test('MaxParentalSubRating is read', () {
      expect(parse({'MaxParentalRating': 10, 'MaxParentalSubRating': 1})
          .maxParentalSubRating, 1);
    });

    test('absent stays null rather than being defaulted to 0', () {
      // Nullable on purpose: "the server said 0" and "the server said nothing"
      // are different facts, even though they behave alike. Flattening them
      // here would lose the distinction for every future consumer.
      final p = parse({'MaxParentalRating': 10});
      expect(p.maxParentalSubRating, isNull);
      expect(p.maxParentalRating, 10);
    });

    test('an uncapped child is null in both, which is not the same as 0', () {
      final p = parse({});
      expect(p.maxParentalRating, isNull);
      expect(p.maxParentalSubRating, isNull);
    });
  });
}
