// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../models/media_library.dart';
import '../repositories/bounded_batch.dart';
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
  );
});

/// The Kids screen's data.
///
/// A `FutureProvider` so the screen gets loading, data and error as one value
/// and cannot forget the third — the definition of done requires a clear error
/// rather than a blank screen.
final kidsOverviewProvider =
    FutureProvider.family<KidsOverview, AuthSession>((ref, session) async {
  // Built on the roster rather than beside it, so listing the users happens
  // once and this provider's wait is the counts alone.
  final roster = await ref.watch(kidsRosterProvider(session).future);
  return ref.watch(kidsRepositoryProvider(session)).load(roster);
});

/// The children and their pictures, without any count.
///
/// **One cheap request, so the faces can be drawn while the counts are still
/// in flight.** The landing screen renders from this the moment it lands and
/// swaps to the counted cards when [kidsOverviewProvider] finishes — which on
/// a large library is seconds later, and used to be seconds of spinner on the
/// first screen anyone sees.
final kidsRosterProvider =
    FutureProvider.family<KidsRoster, AuthSession>((ref, session) {
  return ref.watch(kidsRepositoryProvider(session)).roster();
});


/// Which child's per-library breakdown is wanted.
///
/// A pair rather than two families, so the counts for one child are cached and
/// disposed as one unit — expanding a row twice does not fetch twice, and
/// collapsing every row lets the lot go.
class ChildLibrariesRequest {
  const ChildLibrariesRequest({required this.session, required this.childId});

  final AuthSession session;
  final String childId;

  @override
  bool operator ==(Object other) =>
      other is ChildLibrariesRequest &&
      other.session == session &&
      other.childId == childId;

  @override
  int get hashCode => Object.hash(session, childId);
}

/// The libraries **one child** can open.
///
/// Asked as the child, and that is the whole of the change. Measured 2026-09-05
/// on 10.11.11: `/UserViews` answers the same name and id for a library both
/// the administrator and the child can open — which was already recorded — but
/// the *set* differs, five against one for a child enabled on a single library.
/// The recorded claim was true and was being asked to support something it
/// never said.
///
/// Per child rather than shared once, therefore. The saving that bought is not
/// worth having: the alternative shows a parent libraries that are not their
/// child's, and every count in one of them fails outright.
final childLibrariesProvider =
    FutureProvider.family<List<MediaLibrary>, ChildLibrariesRequest>(
        (ref, request) {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: request.session.serverUrl,
        readToken: () => request.session.accessToken,
      );
  return api.libraries(userId: request.childId);
});

/// What one child can see in each library Garfin can act on.
///
/// **Nothing here runs until something watches it**, which is the whole design:
/// the landing screen watches it when a row is expanded and not before, so a
/// screen showing six children costs nothing extra until a parent asks about
/// one of them. The counts are the expensive question in this app — the query
/// tracks the result set, 19 ms at one title against 8.7 s at six thousand —
/// and a landing screen that asked them for every child on every open would be
/// the slowest screen in the app by a wide margin.
///
/// **Two filters, and they are not the same filter.** [childLibrariesProvider]
/// removes what the child cannot open; [MediaLibrary.manageable] removes what
/// Garfin cannot give or take. A music library the child *can* open is still
/// dropped, because a count there is a number this card cannot act on.
///
/// The first of those is also what stops this failing outright. Measured:
/// `/Items` with a `parentId` the child cannot open answers **401**, not zero,
/// and [mapBounded] does not catch — so one inaccessible library rejected the
/// whole batch and the section rendered nothing at all. Filtering makes that
/// case unreachable rather than handled.
///
/// Fanned out with [mapBounded] at the house limit of four, the same as every
/// other batch here: one library at a time would be needlessly slow, and all of
/// them at once is what the limit exists to prevent.
final childLibraryCountsProvider = FutureProvider.family<
    List<LibraryVisibleCount>, ChildLibrariesRequest>((ref, request) async {
  final libraries = await ref.watch(childLibrariesProvider(request).future);
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: request.session.serverUrl,
        readToken: () => request.session.accessToken,
      );
  return mapBounded<MediaLibrary, LibraryVisibleCount>(
    libraries.where((library) => library.manageable).toList(growable: false),
    (library) async => LibraryVisibleCount(
      library: library,
      visible: await api.visibleItemCountIn(
        userId: request.childId,
        libraryId: library.id,
        itemTypes: library.countedTypes!,
      ),
    ),
  );
});
