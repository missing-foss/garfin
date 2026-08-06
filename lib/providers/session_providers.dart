// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/active_session.dart';
import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import 'app_providers.dart';
import 'kids_providers.dart';
import 'library_providers.dart';

/// The signed-in devices belonging to children Garfin manages.
///
/// **Filtered here, not by the server.** Measured for #41: `/Sessions` accepts
/// `userId` and ignores it, answering with every session including the admin's
/// — so a screen that trusted the parameter would put somebody else's device
/// under a child's name.
///
/// Garfin's own device is excluded outright rather than shown and disabled:
/// ending it is a 204 followed by an immediate 401 on the next request, which
/// is signing the parent out of the app from inside the app. A control that
/// does that has no business being on screen at all.
final childSessionsProvider =
    FutureProvider.family<List<ActiveSession>, AuthSession>(
        (ref, session) async {
  final api = ref.watch(libraryApiProvider(session));
  final overview = await ref.watch(kidsOverviewProvider(session).future);
  final children = {
    for (final KidSummary kid in overview.shortlisted) kid.user.id: kid.user.name,
  };
  final ownDevice = ref.watch(deviceIdentityProvider).deviceId;

  final sessions = await api.sessions();
  return sessions
      .where((s) => children.containsKey(s.userId))
      .where((s) => s.deviceId != ownDevice)
      .toList(growable: false);
});
