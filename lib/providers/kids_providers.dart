// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../repositories/kids_repository.dart';
import 'app_providers.dart';

/// The Kids repository for a given signed-in session.
///
/// A family keyed on the session rather than a bare provider, because the
/// server address and the administrator's id both come from it, and both change
/// when the account does. Keying on the session means switching accounts cannot
/// leave a repository pointed at the previous one.
final kidsRepositoryProvider =
    Provider.family<KidsRepository, AuthSession>((ref, session) {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  return KidsRepository(
    api: api,
    birthYears: ref.watch(birthYearStoreProvider),
    serverUrl: session.serverUrl,
    adminUserId: session.userId,
  );
});

/// The Kids screen's data.
///
/// A `FutureProvider` so the screen gets loading, data and error as one value
/// and cannot forget the third — the definition of done requires a clear error
/// rather than a blank screen.
final kidsOverviewProvider =
    FutureProvider.family<KidsOverview, AuthSession>((ref, session) {
  return ref.watch(kidsRepositoryProvider(session)).load();
});
