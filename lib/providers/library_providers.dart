// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/parental_rating.dart';
import '../repositories/library_repository.dart';
import 'app_providers.dart';

/// Which child the parent is picking for, or null for Everyone.
///
/// Held here rather than in the screen so the assign sheet (step 5) inherits
/// it: `docs/UI-SPEC.md` says the selection "carries into the assign sheet",
/// and a selection owned by a widget would not survive the sheet being opened.
class PickingFor extends Notifier<JellyfinUser?> {
  @override
  JellyfinUser? build() => null;

  void select(JellyfinUser? user) => state = user;
}

final pickingForProvider =
    NotifierProvider<PickingFor, JellyfinUser?>(PickingFor.new);

/// Whether already-shared items are hidden. On by default.
///
/// `docs/DECISIONS.md` § Product shape: hiding turns the grid into a to-do list
/// rather than an inventory.
class HideShared extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final hideSharedProvider = NotifierProvider<HideShared, bool>(HideShared.new);

/// The server's rating ladder, for the age hint (#43).
///
/// Separate from the Kids screen's copy on purpose: a failure here must cost
/// the hint and nothing else. An empty ladder answers "not known" for every
/// rating, which is the honest degradation — see `suitabilityFor`.
final parentalRatingLadderProvider =
    FutureProvider.family<ParentalRatingLadder, AuthSession>((ref, session) async {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  try {
    return await api.parentalRatings();
  } on Object {
    return const ParentalRatingLadder.empty();
  }
});

final libraryRepositoryProvider =
    Provider.family<LibraryRepository, AuthSession>((ref, session) {
  final api = ref.watch(jellyfinApiFactoryProvider).create(
        baseUrl: session.serverUrl,
        readToken: () => session.accessToken,
      );
  return LibraryRepository(api: api, adminUserId: session.userId);
});

/// The first screenful of the grid.
///
/// Deliberately not a paging controller yet. Infinite scroll needs the assign
/// sheet to exist before it is worth building — there is nothing to do with a
/// tile beyond look at it — and a `FutureProvider` keeps loading, data and
/// error as one value that the screen cannot forget to handle.
final librarySliceProvider =
    FutureProvider.family<LibrarySlice, AuthSession>((ref, session) {
  final child = ref.watch(pickingForProvider);
  final hideShared = ref.watch(hideSharedProvider);
  return ref.watch(libraryRepositoryProvider(session)).fetch(
        startIndex: 0,
        child: child,
        hideShared: hideShared,
      );
});
