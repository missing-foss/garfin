// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_entry.dart';
import '../repositories/activity_store.dart';
import 'app_providers.dart';

final activityStoreProvider = Provider<ActivityStore>(
  (ref) => ActivityStore(ref.watch(sharedPreferencesProvider)),
);

/// The log, newest first.
///
/// **Re-read when the store says so.** This used to call `read()` once and
/// cache the answer, which made Activity empty for the whole life of the
/// process: nothing invalidated it after a write, and it is not auto-disposed
/// either, so dropping every listener by leaving the tab did not re-read it.
/// Only a relaunch could populate the screen. The single `invalidate` that did
/// exist was on the Undo path, unreachable with no rows to undo.
///
/// Subscribing here rather than invalidating at each write means the guarantee
/// does not have to be remembered at the next call site added.
final activityLogProvider = Provider<List<ActivityEntry>>((ref) {
  final store = ref.watch(activityStoreProvider);
  void reread() => ref.invalidateSelf();
  store.addListener(reread);
  ref.onDispose(() => store.removeListener(reread));
  return store.read();
});
