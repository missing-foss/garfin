// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../models/tag_diff.dart';
import '../repositories/assign_repository.dart';
import 'app_providers.dart';
import 'kids_providers.dart';

/// Identifies one sheet: which server, which item.
class AssignRequest {
  const AssignRequest({required this.session, required this.itemId});

  final AuthSession session;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is AssignRequest &&
      other.session == session &&
      other.itemId == itemId;

  @override
  int get hashCode => Object.hash(session, itemId);
}

final assignRepositoryProvider =
    Provider.family<AssignRepository, AuthSession>((ref, session) {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  return AssignRepository(api: api, adminUserId: session.userId);
});

/// One row per child who has a shortlist Garfin can interpret.
///
/// Children with no shortlist are absent because Garfin cannot give them their
/// first label (ground rule 8), and a child with **both** lists set is absent
/// because ground rule 3 refuses to pick a verb for them — a row offering a
/// toggle would have to guess which direction it meant.
final assignRowsProvider =
    FutureProvider.family<List<AssignRow>, AssignRequest>((ref, request) async {
  final overview = await ref.watch(kidsOverviewProvider(request.session).future);
  final children = overview.shortlisted
      .map((KidSummary k) => k.user)
      .where((u) => AssignRepository.labelFor(u) != null)
      .toList(growable: false);

  return ref
      .watch(assignRepositoryProvider(request.session))
      .rowsFor(itemId: request.itemId, children: children);
});
