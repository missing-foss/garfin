// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// One rung of the server's parental rating ladder.
///
/// `UserPolicy.maxParentalRating` is an integer; this is what turns it back
/// into something a parent recognises.
class ParentalRating {
  const ParentalRating({
    required this.name,
    required this.value,
    this.subScore,
  });

  final String name;

  /// The score this rung sits at, or null for a rung that carries no score.
  ///
  /// Read from `RatingScore.score` where the server sends it, falling back to
  /// the deprecated top-level `Value`. The server's own source marks `Value`
  /// deprecated and populates it from the score, so the two agree today —
  /// reading the score first is what stops that becoming a silent divergence.
  final int? value;

  /// The second half of the cap, and the reason [value] alone is not it.
  ///
  /// **Measured on 10.11.11, 2026-08-26: this is enforced.** Two rungs at the
  /// same score and different sub-scores are different caps — a child capped at
  /// `TV-PG` (10/0) is shown `TV-PG` and *not* `TV-PG-D` (10/1). 40 of the 56
  /// default rungs carry a non-zero sub-score, so this is the majority of the
  /// ladder rather than a curiosity.
  ///
  /// Null for a rung the server sends without a `RatingScore` — the `Unrated`
  /// entry, and anything from a server predating the field.
  final int? subScore;

  factory ParentalRating.fromJson(Map<String, dynamic> json) {
    final score = readMap(json, 'RatingScore');
    return ParentalRating(
      name: readString(json, 'Name') ?? '',
      // `RatingScore.score` first, `Value` as the fallback for older servers.
      value: score == null
          ? readInt(json, 'Value')
          : readInt(score, 'score') ?? readInt(json, 'Value'),
      subScore: score == null ? null : readInt(score, 'subScore'),
    );
  }
}

/// The rating ladder as fetched from `/Localization/ParentalRatings`.
///
/// **Two things measured on 10.11.11 that a naive parser gets wrong.**
///
/// The entries do **not** have a uniform shape. A default install returns 56 of
/// them, and the very first one is:
///
/// ```json
/// {"Name": "Unrated"}
/// ```
///
/// with no `Value` key at all, while the rest carry `Name`, `Value` and
/// `RatingScore`. Anything assuming `Value` exists crashes on entry zero, which
/// is why [ParentalRating.value] is nullable and why [nameFor] skips valueless
/// rungs instead of treating them as zero — a rung with no score is not a rung
/// at score nothing.
///
/// And the ladder is **locale-dependent**, so it must be fetched rather than
/// hardcoded. A US ladder baked in would mislabel every cap on a server set to
/// anywhere else. Measured rather than assumed: four `MetadataCountryCode`
/// values give four different ladders — 56 rungs for `US`, 26 for `GB`, 24 for
/// `DE`, 16 for `FR` — and the non-US ones carry the bare numeric certificates
/// the US ladder has no rung for. See `docs/JELLYFIN-API.md` § The ladder
/// really is per-country.
class ParentalRatingLadder {
  const ParentalRatingLadder(this.ratings);

  const ParentalRatingLadder.empty() : ratings = const [];

  final List<ParentalRating> ratings;

  factory ParentalRatingLadder.fromJson(List<dynamic> json) =>
      ParentalRatingLadder(
        json
            .whereType<Map<String, dynamic>>()
            .map(ParentalRating.fromJson)
            .toList(growable: false),
      );

  /// The human name for a cap, or null when there is nothing honest to show.
  ///
  /// Null in for null out: an uncapped child has no rating to name, and the
  /// caller should say "no limit" rather than be handed a fabricated rung.
  ///
  /// Null is also the answer when the ladder has no rung at that score. That
  /// happens on a server whose ladder changed after the cap was set, and the
  /// number alone is more honest than the nearest neighbour — guessing which
  /// way to round a *safety* control is exactly the wrong place to be clever.
  ///
  /// ## The ladder is not injective, and the score alone is not the cap
  ///
  /// Measured on 10.11.11's default US ladder: 56 entries, and **six scores
  /// carry more than one name**. This function used to take a score alone and
  /// return the first name at it, on the argument that every name at a given
  /// score is the same cap.
  ///
  /// **That argument was wrong, and it was measured wrong on 2026-08-26.**
  /// `MaxParentalSubRating` is enforced by the server: at cap 10/0 a `TV-PG`
  /// item is visible and a `TV-PG-D` item is hidden. Of the six shared scores,
  /// **four mix sub-levels**, so 41 of 55 scored rungs could be mislabelled by
  /// a score-only first match — including reporting `R` for a child actually
  /// capped at `TV-MA`, which is the more permissive-looking of the two.
  ///
  /// So the match is on the **pair**. Within one `(score, subScore)` the old
  /// argument holds and is now correctly scoped: those names really are the
  /// same cap, admitting the same items, so a first match is accurate about
  /// the policy while being an unfaithful echo of which label was clicked —
  /// and which one was clicked is not recoverable, the server storing only the
  /// numbers.
  ///
  /// An earlier note here worried that falling back to the number whenever a
  /// score is shared "costs every common cap its name, because on a US ladder
  /// the colliding scores are the usual ones". That was true of a score-only
  /// fallback, and the sub-score dissolves it **on a ladder that carries
  /// sub-scores**: `PG` and `TV-PG` are both 10/0 and still name cleanly. Only
  /// a pair with no rung at all falls through to the number.
  ///
  /// **It reduces the collisions; it does not end them, on any ladder
  /// measured.** Counted 2026-09-02 on 10.11.11, over the distinct
  /// `(score, subScore)` pairs each ladder actually sends:
  ///
  /// ```
  /// ladder   pairs   pairs with >1 name   worst collapse
  /// US          14                    6               15
  /// GB          15                    6                5
  /// DE          11                    5                5
  /// FR          11                    1                5
  /// ```
  ///
  /// The worst case is **`US`**, not the ladders without sub-scores: 15 names
  /// share the single pair 10/1 (`TV-PG-D` through `TV-PG-DLSV`), 15 more
  /// share 14/1, and 9 share 17/1. So `nameFor(10, 1)` answers `TV-PG-D` out
  /// of fifteen. `PG` and `TV-PG` naming cleanly at 10/0 is the *best* case on
  /// that ladder, not a representative one.
  ///
  /// `FR`, `DE` and `GB` send `RatingScore` with no `subScore` key at all, so
  /// every rung reads as sub-score 0 and first-match is the only resolution
  /// available. That sounds worse and measures better: `FR` has exactly **one**
  /// colliding pair of eleven — five names at 0/0 (`0+`, `Public Averti`,
  /// `Tous Publics`, `TP`, `U`) — against six on `US`.
  ///
  /// Not a defect to fix here, on any ladder: names sharing a pair admit the
  /// same items, and which one was clicked is not recoverable because the
  /// server stores only the numbers. Recorded so neither the "dissolves"
  /// argument above nor its converse is read wider than what was counted.
  ///
  /// Null in for null out: an uncapped child has no rating to name.
  ///
  /// [subScore] null is treated as **0**, because that is what the server does
  /// — see `UserPolicy.maxParentalSubRating`, where the reasoning and the
  /// measurement live.
  String? nameFor(int? value, [int? subScore]) {
    if (value == null) return null;
    final wantedSub = subScore ?? 0;
    for (final rating in ratings) {
      if (rating.value == value && (rating.subScore ?? 0) == wantedSub) {
        return rating.name;
      }
    }
    return null;
  }

  /// The score a rating *name* sits at, or null when the ladder has no such
  /// name.
  ///
  /// The inverse of [nameFor], and unlike it this direction **is** unambiguous:
  /// many names share a score, but a name has one score.
  ///
  /// Matched case-insensitively. An item's `OfficialRating` is written by
  /// whichever metadata provider scraped it and does not reliably match the
  /// ladder's capitalisation, and the server's own `tags=` filter sets the
  /// precedent that comparisons here are case-insensitive.
  ///
  /// Null for a name that is not on the ladder at all — `Rated PG`, or a French
  /// certificate on a US-configured server. That is a *don't know*, not a low
  /// rating, and callers must keep the two apart.
  int? valueFor(String? name) {
    if (name == null) return null;
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final rating in ratings) {
      if (rating.value != null && rating.name.toLowerCase() == wanted) {
        return rating.value;
      }
    }
    return null;
  }

  /// Every name sharing a score, in the server's order.
  ///
  /// Exists so the collision above is testable as a property of the data
  /// rather than only visible in whatever [nameFor] happened to return.
  List<String> namesFor(int? value) => value == null
      ? const []
      : ratings
          .where((r) => r.value == value)
          .map((r) => r.name)
          .toList(growable: false);
}
