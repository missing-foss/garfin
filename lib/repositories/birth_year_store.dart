// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

/// Birth years for children, set by the parent inside Garfin.
///
/// **Why this exists at all.** `docs/UI-SPEC.md` § Kids asks each card to show
/// an age, and Jellyfin cannot supply one: measured on 10.11.11, `GET /Users`
/// returns no `DateOfBirth` and no key containing `Date`. So the parent enters
/// it here — and the **year alone**, settled with the maintainer, because a
/// rating cap is never applied at a finer resolution than that and a full date
/// of birth for a child is more data than the job needs.
///
/// Storing less is the point rather than a shortcut. A year is not a birthday.
///
/// `shared_preferences` is right: this is a preference the parent typed, not a
/// credential, and nothing about it protects anything. It does not go to the
/// server — Garfin never writes a user policy (ground rule 8) and there is no
/// field for it there anyway. And it does not leave the device: backup and
/// device-to-device transfer are both off (#35), which is why this could be
/// added without widening what syncs.
class BirthYearStore {
  const BirthYearStore(this._prefs);

  final SharedPreferences _prefs;

  /// Keyed by Jellyfin user id, not by name.
  ///
  /// A rename in Jellyfin must not silently reattach one child's age to
  /// another's card, and ids are what survive it.
  static String _key(String userId) => 'birth_year_$userId';

  /// The bounds an entry has to fall inside to be stored or returned.
  ///
  /// Not validation theatre: a typo of three digits or five would otherwise
  /// render an age of several hundred years next to a child's name, and the
  /// screen has no sensible way to lay that out. The lower bound is generous
  /// because nothing stops a parent recording their own year on their own
  /// account.
  static const minYear = 1900;
  static const maxYear = 2200;

  static bool isPlausible(int year) => year >= minYear && year <= maxYear;

  int? read(String userId) {
    final value = _prefs.getInt(_key(userId));
    if (value == null) return null;
    // A value already on disk gets the same check as a new one. Bounds can
    // change, and a stored number that no longer passes is not worth trusting
    // just because it arrived earlier.
    return isPlausible(value) ? value : null;
  }

  /// Stores a year, or clears it when [year] is null or out of bounds.
  Future<void> write(String userId, int? year) async {
    if (year == null || !isPlausible(year)) {
      await _prefs.remove(_key(userId));
      return;
    }
    await _prefs.setInt(_key(userId), year);
  }

  /// Forgets every stored year.
  ///
  /// For sign-out and for switching servers: user ids are per-server, so
  /// carrying them across would at best be dead keys and at worst attach one
  /// household's ages to another's accounts.
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('birth_year_'));
    for (final key in keys.toList(growable: false)) {
      await _prefs.remove(key);
    }
  }
}
