// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

/// Whether the one-time support card has been shown.
///
/// **Once, ever, on this install.** The flag is set the moment the card
/// appears rather than when it is dismissed, so a parent who leaves the screen
/// without answering it is not asked again either — and an update keeps the
/// key, so it does not come back with a new version. Only an uninstall clears
/// it, along with everything else.
class SupportCardStore {
  const SupportCardStore(this._prefs);

  final SharedPreferences _prefs;

  /// The actions recorded before the card is due, counted by
  /// `ActivityStore.total`.
  static const milestone = 50;

  static const _shownKey = 'support_card_shown';

  bool get shown => _prefs.getBool(_shownKey) ?? false;

  Future<void> markShown() => _prefs.setBool(_shownKey, true);
}
