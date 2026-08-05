// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// One rung of the server's parental rating ladder.
///
/// `UserPolicy.maxParentalRating` is an integer; this is what turns it back
/// into something a parent recognises.
class ParentalRating {
  const ParentalRating({required this.name, required this.value});

  final String name;

  /// The score this rung sits at, or null for a rung that carries no score.
  final int? value;

  factory ParentalRating.fromJson(Map<String, dynamic> json) => ParentalRating(
        name: readString(json, 'Name') ?? '',
        value: readInt(json, 'Value'),
      );
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
/// anywhere else. See `docs/JELLYFIN-API.md` § Gotchas.
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
  /// ## The ladder is not injective, and this returns the first match
  ///
  /// Measured on 10.11.11's default US ladder, 2026-08-05: 56 entries, and
  /// **six scores carry more than one name**.
  ///
  /// | Score | Names |
  /// |---|---|
  /// | 0 | Approved, G, TV-G, TV-Y |
  /// | 7 | TV-Y7, TV-Y7-FV |
  /// | 10 | PG, TV-PG, and 15 TV-PG-\* variants |
  /// | 14 | TV-14 and 15 variants |
  /// | 17 | R, NC-17, TV-MA and 7 more |
  /// | 18 | TV-X, TV-AO |
  ///
  /// Jellyfin stores only the integer, so **which name the parent clicked is
  /// not recoverable** — the information is gone server-side, not lost here.
  /// A child capped at 10 shows "PG" whether the parent picked PG or TV-PG.
  ///
  /// That is deliberate, and it is *not* the same as the missing-rung case
  /// above, which this refuses. Every name at a given score is the **same
  /// cap**: score 10 admits exactly the same items whichever of those 17
  /// labels was clicked. So a first-match name is accurate about the policy
  /// while merely being an unfaithful echo of the click. A neighbouring rung
  /// would be inaccurate about the policy, which is why that one returns null.
  ///
  /// First in the server's own order, so the answer is stable across calls and
  /// across installs with the same ladder rather than incidental.
  ///
  /// If this ever needs revisiting, the honest alternatives are to show the
  /// number alongside the name, or to fall back to the number whenever the
  /// score is shared. Both were considered; both cost every common cap its
  /// name, because on a US ladder the colliding scores are the usual ones.
  String? nameFor(int? value) {
    if (value == null) return null;
    for (final rating in ratings) {
      if (rating.value == value) return rating.name;
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
