// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'library_item.dart';
import 'parental_rating.dart';

/// Whether a title looks suitable for a child's age.
///
/// **A hint, and never enforcement.** Jellyfin enforces `MaxParentalRating`
/// server-side — measured, a correctly tagged item goes from visible to
/// invisible under a cap — but only if the parent set one, and on a
/// self-hosted server most accounts have no cap at all. This is for that case:
/// the parent is choosing, nothing is enforcing, and a number on the item and a
/// year they typed are enough to flag the obvious mismatches.
///
/// It must never filter. See [AgeSuitability.unknown] for why the third state
/// carries most of the weight.
enum AgeSuitability {
  /// The item's rating sits at or below the child's age.
  suitsAge,

  /// The item's rating is above the child's age.
  aboveAge,

  /// **Not "fine". Not known.**
  ///
  /// Four different situations land here, and a helper that quietly read any
  /// of them as suitable would be wrong exactly where a parent is trusting it:
  ///
  /// - the item has no `OfficialRating` at all — common, arguably the majority
  ///   case in a library of ripped or side-loaded files
  /// - its rating is not on the server's ladder: `Rated PG`, or a French
  ///   certificate on a US-configured server
  /// - no birth year has been entered for the child
  /// - the ladder's value is a sentinel rather than an age
  ///
  /// This must look different on screen from [suitsAge], not merely absent.
  unknown,
}

/// The largest ladder value treated as an age.
///
/// Measured on 10.11.11's default US ladder: the real rungs are 0, 7, 10, 13,
/// 14, 17, 18 and 21, and then **1000 (`XXX`) and 1001 (`Banned`)**, which are
/// ordering sentinels rather than ages. Comparing a child's age against 1000
/// would answer "above their age" for the right reason by accident, but the
/// same arithmetic is what would silently mis-handle any other out-of-band
/// value a locale introduces.
///
/// A heuristic, and named as one: these numbers are an *ordering* that happens
/// to line up with ages in the low range, not ages. The ladder is
/// locale-dependent, so a server configured elsewhere may order differently —
/// which is also why the mapping is read from the ladder rather than hardcoded.
const maxAgeLikeRatingValue = 21;

/// Whether [item] looks suitable for a child of [childAge].
///
/// Pure, so the whole truth table is testable without a server or a widget.
///
/// Note what is *not* an input: the child's `MaxParentalRating`. This does not
/// predict what the server will show — that is the visibility diff's job, and
/// computing it here is what ground rule 4 forbids. This compares a number on
/// the item to a number the parent typed, and offers a sentence.
AgeSuitability suitabilityFor({
  required LibraryItem item,
  required ParentalRatingLadder ladder,
  required int? childAge,
}) {
  if (childAge == null) return AgeSuitability.unknown;

  final value = ladder.valueFor(item.officialRating);
  if (value == null) return AgeSuitability.unknown;

  // Out-of-band values are not ages, whichever direction they point.
  if (value < 0 || value > maxAgeLikeRatingValue) return AgeSuitability.unknown;

  return value <= childAge ? AgeSuitability.suitsAge : AgeSuitability.aboveAge;
}
