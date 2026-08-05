// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../models/library_item.dart';
import '../models/tag_diff.dart';
import '../repositories/assign_repository.dart';
import 'app_providers.dart';
import 'collection_providers.dart';
import 'kids_providers.dart';

/// Identifies one sheet: which server, which item.
///
/// Carries the tile itself, for its name, its type and the copy the sheet
/// writes from it. **The write path still takes ids** — `AssignRepository`
/// accepts no item object at all, which is what makes ground rule 2 structural
/// rather than a habit.
class AssignRequest {
  const AssignRequest({required this.session, required this.item});

  final AuthSession session;
  final LibraryItem item;

  String get itemId => item.id;

  @override
  bool operator ==(Object other) =>
      other is AssignRequest &&
      other.session == session &&
      other.item.id == item.id;

  @override
  int get hashCode => Object.hash(session, item.id);
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

  // For a collection, "does the child have this" is a question about the films
  // inside it as well as the box — see `AssignRepository.rowsFor`.
  final set = request.item.isCollection
      ? await ref.watch(collectionSetProvider(
          CollectionRequest(
            session: request.session,
            collection: request.item,
          ),
        ).future)
      : null;

  return ref.watch(assignRepositoryProvider(request.session)).rowsFor(
        itemId: request.itemId,
        children: children,
        members: set?.members,
      );
});
