// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

/// The Unlock section of Settings (`docs/UI-SPEC.md`), persisted.
///
/// Both values are preferences, not credentials, so `shared_preferences` is
/// right. Someone with the device unlocked could flip them — but someone with
/// the device unlocked is already past the gate, which is the honest scope of
/// what this feature buys (`SECURITY.md`).
class UnlockSettingsStore {
  const UnlockSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _requiredKey = 'unlock_required';
  static const _idleTimeoutKey = 'unlock_idle_timeout_seconds';

  /// Two minutes, and the number is the whole point of the setting.
  ///
  /// Long enough not to nag a parent who is picking something and glancing at a
  /// message, short enough that handing the phone over expires the session in
  /// practice. Issue #18 and `docs/UI-SPEC.md` both name it.
  static const defaultIdleTimeout = Duration(minutes: 2);

  /// The choices offered in Settings.
  ///
  /// Zero is included because "ask every single time" is a legitimate answer
  /// for a phone that gets handed over constantly, and because leaving it out
  /// would make the strictest setting the one you cannot pick.
  static const idleTimeoutChoices = <Duration>[
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// On by default. Ground rule 9 is the app's own rule about itself, so the
  /// default is the rule and switching it off is the deliberate act.
  bool get required => _prefs.getBool(_requiredKey) ?? true;

  Future<void> setRequired(bool value) => _prefs.setBool(_requiredKey, value);

  Duration get idleTimeout {
    final seconds = _prefs.getInt(_idleTimeoutKey);
    if (seconds == null || seconds < 0) return defaultIdleTimeout;
    return Duration(seconds: seconds);
  }

  Future<void> setIdleTimeout(Duration value) =>
      _prefs.setInt(_idleTimeoutKey, value.inSeconds);
}
