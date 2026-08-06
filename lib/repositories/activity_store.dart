// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logging.dart';
import '../models/activity_entry.dart';

/// Garfin's own record of what it wrote, on this device.
///
/// **`shared_preferences`, and that is the rule rather than a shortcut**: none
/// of this is a credential, and `SECURITY.md` puts only the access token in
/// secure storage. It does not survive an uninstall and does not leave the
/// phone — backup and device-to-device transfer are off (#39) — which is the
/// honest scope of a log that lives beside an admin token on a phone handed to
/// children by design.
class ActivityStore {
  const ActivityStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'activity_log';

  /// How many actions are kept.
  ///
  /// A bound rather than a growing list, because this is written on **every**
  /// write for the life of the install and `shared_preferences` is read whole
  /// into memory at startup. Two hundred actions is far more than the screen
  /// can be scrolled through with any purpose, and the oldest fall off the end
  /// — which is also the only way anything is ever deleted from here.
  static const maxEntries = 200;

  /// Newest first, which is the order the screen renders and the order the
  /// list is stored in — so reading it is not a sort.
  List<ActivityEntry> read() {
    final raw = _prefs.getStringList(_key) ?? const <String>[];
    final entries = <ActivityEntry>[];
    for (final line in raw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) continue;
        final entry = ActivityEntry.fromJson(decoded);
        if (entry != null) entries.add(entry);
      } on FormatException {
        // One unreadable line must not cost the whole history.
        log.info('skipping an unreadable activity entry');
      }
    }
    return entries;
  }

  Future<void> add(ActivityEntry entry) async {
    final raw = _prefs.getStringList(_key) ?? const <String>[];
    final next = <String>[
      jsonEncode(entry.toJson()),
      ...raw.take(maxEntries - 1),
    ];
    await _prefs.setStringList(_key, next);
  }

  Future<void> clear() => _prefs.remove(_key);
}
