// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// The server's own country list, turned into what the item sheet needs: the
/// ISO code for a country **name**, and the set of codes a rating prefix can
/// name.
///
/// **The server's list settles it, and a table here only fills measured gaps.**
/// `GET /Localization/Countries` answers 140 rows of `Name`, `DisplayName` and
/// two- and three-letter codes. An item's `ProductionLocations` are English
/// names from its metadata provider, and they usually match a `DisplayName`,
/// but not always. [aliases] holds the ones measured not to.
class CountryLookup {
  const CountryLookup._(this.codes, this._byName);

  const CountryLookup.empty() : codes = const {}, _byName = const {};

  /// Built from the rows `/Localization/Countries` answers.
  ///
  /// Every name a row carries is a key, case-folded: `Name` (which is the code
  /// on 12.1), `DisplayName`, and both codes. So `France`, `FR` and `FRA` all
  /// find `FR`, and a provider writing `USA` finds `US` without an alias.
  factory CountryLookup.fromRows(Iterable<Map<String, dynamic>> rows) {
    final codes = <String>{};
    final byName = <String, String>{};
    for (final row in rows) {
      final code = readString(row, 'TwoLetterISORegionName')?.toUpperCase();
      if (code == null || code.length != 2) continue;
      codes.add(code);
      for (final field in const [
        'Name',
        'DisplayName',
        'TwoLetterISORegionName',
        'ThreeLetterISORegionName',
      ]) {
        final name = readString(row, field);
        if (name != null && name.trim().isNotEmpty) {
          byName.putIfAbsent(_key(name), () => code);
        }
      }
    }
    return CountryLookup._(codes, byName);
  }

  /// The two-letter codes the server knows. What `ratingCountryCode` reads.
  final Set<String> codes;

  final Map<String, String> _byName;

  /// Names a metadata provider writes that the server's list spells otherwise.
  ///
  /// **Every entry is measured, never guessed.** 2026-09-19 on 12.1.0 with TMDB
  /// on, eight films: seven country names matched a `DisplayName`, and TMDB's
  /// `United States of America` did not — the server's is `United States`. A
  /// name that matches nothing is shown as text, so a missing alias costs a
  /// flag, never a wrong one.
  static const aliases = <String, String>{
    'united states of america': 'US',
  };

  /// The code for [name], or null when neither the server's list nor
  /// [aliases] knows it.
  ///
  /// An alias only applies when the server knows the code it points at, so
  /// this never answers a code the server's own list does not contain.
  String? codeFor(String name) {
    final key = _key(name);
    final direct = _byName[key];
    if (direct != null) return direct;
    final alias = aliases[key];
    return alias != null && codes.contains(alias) ? alias : null;
  }

  static String _key(String name) => name.trim().toLowerCase();

  /// The flag emoji for a two-letter [code]: a pair of regional indicator
  /// symbols, which the phone's emoji font draws as the flag.
  ///
  /// Measured 2026-09-19 in Flutter on Android 14: `FR US DE AU JP GB BE CH`
  /// all rendered as colour flags. Null for anything that is not two ASCII
  /// letters, so nothing malformed reaches the screen as a stray symbol.
  static String? flagEmoji(String code) {
    final upper = code.toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(upper)) return null;
    return String.fromCharCodes(
      upper.codeUnits.map((unit) => 0x1F1E6 + unit - 0x41),
    );
  }
}
