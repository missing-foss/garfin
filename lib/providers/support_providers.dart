// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/support_card_store.dart';
import 'activity_providers.dart';
import 'app_providers.dart';

final supportCardStoreProvider = Provider<SupportCardStore>(
  (ref) => SupportCardStore(ref.watch(sharedPreferencesProvider)),
);

/// Whether the support card should appear now: the milestone is reached and
/// the card has never been shown.
///
/// Watches the log so that the 50th action is noticed without a relaunch;
/// the count itself is the store's lifetime total, not the log's length.
/// Auto-disposed, so that leaving Kids reads the shown flag afresh.
final supportCardDueProvider = Provider.autoDispose<bool>((ref) {
  ref.watch(activityLogProvider);
  final cards = ref.watch(supportCardStoreProvider);
  return !cards.shown &&
      ref.watch(activityStoreProvider).total >= SupportCardStore.milestone;
});
