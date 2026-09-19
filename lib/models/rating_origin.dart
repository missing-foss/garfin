// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// Which certification system an `OfficialRating` names, when it names one.
///
/// **Nothing on an item says which country's system its rating belongs to.**
/// The ladder is the server's own — one list, from its `MetadataCountryCode` —
/// so it describes the server rather than the film. Some rating strings do name
/// a system as a prefix (`FR-12`, `SE-BTL`); most do not (`PG-13`, `12`, `R`).
///
/// **Reading any `XX-` as a country is wrong twice**, measured 2026-09-17 on
/// 12.1.0 and recorded in `docs/JELLYFIN-API.md`:
///
/// - 48 of the US ladder's 56 rungs are hyphenated — `TV-G`, `TV-Y7-FV`,
///   `TV-PG-D`, and `PG-13` itself — so that rule answers Tuvalu and Papua New
///   Guinea for ordinary US ratings;
/// - `NR-17` is not a rung, and `NR` is Nauru.
///
/// What separates them is the server's own country list, which contains `FR`,
/// `SE`, `PT`, `US` and `DE` and contains none of `TV`, `PG` or `NR`. So a
/// rating names a country only when **both** hold: the whole string is not a
/// rung on the server's ladder, and its two-letter prefix is a country the
/// server knows.
///
/// The default is to say nothing. Showing the server's configured country
/// beside a rating would assert something about the film that the data does not
/// say — the same mistake as the age hint treating *unknown* as *fine*.
String? ratingCountryCode(
  String? officialRating, {
  required Set<String> ladderNames,
  required Set<String> countryCodes,
}) {
  final rating = officialRating?.trim();
  if (rating == null || rating.length < 4) return null;

  // A rung of the configured system, whatever it looks like. `PG-13` and
  // `TV-PG` land here, which is the half that matters.
  if (ladderNames.any((name) => name.toLowerCase() == rating.toLowerCase())) {
    return null;
  }

  if (rating[2] != '-') return null;
  final prefix = rating.substring(0, 2).toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(prefix)) return null;
  if (!countryCodes.contains(prefix)) return null;

  return prefix;
}
