// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/kid_summary.dart';
import '../models/parental_rating.dart';
import '../repositories/library_repository.dart';
import 'app_providers.dart';
import 'kids_providers.dart';
import 'settings_providers.dart';

/// Which child the parent is picking for, as an **id**, or null for Everyone.
///
/// Held here rather than in the screen so the assign sheet (step 5) inherits
/// it: `docs/UI-SPEC.md` says the selection "carries into the assign sheet",
/// and a selection owned by a widget would not survive the sheet being opened.
///
/// An id rather than the user, because the starting value comes from Settings
/// and a stored name would be the wrong key: names repeat on a Jellyfin server
/// and can be changed without the account changing. [pickedChildProvider]
/// resolves it against the accounts that actually exist, which is also what
/// makes a stored id for a deleted account degrade to Everyone rather than to
/// an error.
class PickingFor extends Notifier<String?> {
  @override
  String? build() => ref.watch(settingsProvider).startingChildId;

  /// The choice for this session. Deliberately **not** written back to
  /// Settings: `docs/UI-SPEC.md` § Settings calls the stored one the *starting*
  /// child, and a picker that quietly rewrote the default would make "start on
  /// Emma" impossible to keep.
  void select(String? userId) => state = userId;
}

final pickingForProvider =
    NotifierProvider<PickingFor, String?>(PickingFor.new);

/// The selected child, once the accounts are known.
///
/// Null for Everyone, and also null while the accounts are still loading or if
/// the stored id names an account that is gone — the grid then shows every
/// tile as unknown, which is exactly what Everyone means and is the safe answer
/// to render before the policies have arrived.
final pickedChildProvider =
    Provider.family<JellyfinUser?, AuthSession>((ref, session) {
  final id = ref.watch(pickingForProvider);
  if (id == null) return null;
  final overview = ref.watch(kidsOverviewProvider(session)).asData?.value;
  for (final kid in overview?.shortlisted ?? const <KidSummary>[]) {
    if (kid.user.id == id) return kid.user;
  }
  return null;
});

/// Whether already-shared items are hidden.
///
/// Starts from Settings, and the Library's own Show/Hide button moves it for
/// this session only. `docs/DECISIONS.md` § Product shape: hiding turns the
/// grid into a to-do list rather than an inventory, which is why the stored
/// default is on.
class HideShared extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsProvider).hideShared;

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
  final child = ref.watch(pickedChildProvider(session));
  final hideShared = ref.watch(hideSharedProvider);
  return ref.watch(libraryRepositoryProvider(session)).fetch(
        startIndex: 0,
        child: child,
        hideShared: hideShared,
      );
});
