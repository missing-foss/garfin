// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/collection_set.dart';
import '../models/library_item.dart';
import '../repositories/collection_repository.dart';
import 'app_providers.dart';

final collectionRepositoryProvider =
    Provider.family<CollectionRepository, AuthSession>((ref, session) {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  return CollectionRepository(api: api, adminUserId: session.userId);
});

/// Every collection and its membership, built once and kept.
///
/// **This costs 1 + N requests**, one per BoxSet, because Jellyfin has no way
/// to ask which collections contain a given film — see `CollectionRepository`
/// for the four routes that look like they answer that and do not. Keeping it
/// is what stops that price being paid every time a sheet opens; nothing Garfin
/// does changes membership, so nothing it does invalidates this.
final collectionIndexProvider =
    FutureProvider.family<CollectionIndex, AuthSession>(
  (ref, session) => ref.watch(collectionRepositoryProvider(session)).index(),
);

/// One collection's membership, for a sheet opened on the collection itself.
///
/// Identifies the set directly, so it does not wait on the whole index.
final collectionSetProvider =
    FutureProvider.family<CollectionSet, CollectionRequest>(
  (ref, request) => ref
      .watch(collectionRepositoryProvider(request.session))
      .setFor(request.collection),
);

/// Which collections a film belongs to — **possibly several**.
///
/// Empty when the index has not resolved or could not be built. That is the
/// conservative answer: with no sets known, no cascade is offered, and a
/// single-film write happens exactly as it did before this feature existed.
final setsContainingProvider =
    Provider.family<List<CollectionSet>, CollectionRequest>((ref, request) {
  final index = ref.watch(collectionIndexProvider(request.session));
  return index.asData?.value.setsContaining(request.collection.id) ?? const [];
});

/// Identifies one collection lookup: which server, which item.
class CollectionRequest {
  const CollectionRequest({required this.session, required this.collection});

  final AuthSession session;
  final LibraryItem collection;

  @override
  bool operator ==(Object other) =>
      other is CollectionRequest &&
      other.session == session &&
      other.collection.id == collection.id;

  @override
  int get hashCode => Object.hash(session, collection.id);
}
