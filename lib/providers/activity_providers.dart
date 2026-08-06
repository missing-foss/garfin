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
/// Invalidated after a write and after an undo — both of which add to it, and
/// neither of which the screen can see happen from here.
final activityLogProvider = Provider<List<ActivityEntry>>(
  (ref) => ref.watch(activityStoreProvider).read(),
);
