// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'assign_providers.dart';
import 'auth_providers.dart';
import 'collection_providers.dart';
import 'kids_providers.dart';
import 'library_providers.dart';
import 'session_providers.dart';

/// Every provider family keyed on an `AuthSession`, directly or through a
/// request object that carries one.
///
/// **Each is `autoDispose` and keeps itself alive**, so while a session is
/// signed in nothing changes: a tab that unmounts and comes back finds what it
/// had, and a child's per-library counts are asked once. What `autoDispose`
/// adds is that an entry can be *removed*, rather than only marked stale:
/// measured, invalidating a whole family removes every kept-alive entry no
/// screen is watching, and rebuilds none of them. A plain family keeps the
/// element either way.
///
/// `test/session_release_test.dart` reads `lib/providers/` and fails if a
/// family exists that is missing here, or is not `autoDispose`, or does not
/// keep itself alive, so the list cannot fall behind the code.
final List<ProviderOrFamily> perSessionFamilies = [
  assignRepositoryProvider,
  assignRowsProvider,
  collectionRepositoryProvider,
  collectionIndexProvider,
  collectionSetProvider,
  collectionMembersProvider,
  setsContainingProvider,
  kidsRepositoryProvider,
  kidsOverviewProvider,
  kidsRosterProvider,
  childLibrariesProvider,
  childLibraryCountsProvider,
  pickedChildProvider,
  parentalRatingLadderProvider,
  countriesProvider,
  libraryApiProvider,
  libraryRepositoryProvider,
  taggedItemCountProvider,
  resolvedLibraryFiltersProvider,
  libraryGenresProvider,
  libraryDecadesProvider,
  libraryControllerProvider,
  childSessionsProvider,
];

/// Releases what a session cached once that session has ended.
///
/// A sign-out, or a sign-in that produces a different session (a new token is
/// a new session), leaves every entry keyed on the old one behind: nothing
/// will read those keys again. This invalidates the families above as whole
/// families at that moment. A change that keeps the same session, such as the
/// server confirming it, releases nothing.
///
/// Watched by the app root, so it lives as long as the app does.
final sessionReleaseProvider = Provider<void>((ref) {
  ref.listen(authControllerProvider, (previous, next) {
    final before = previous?.value;
    final after = next.value;
    if (before is! AuthSignedIn) return;
    if (after is AuthSignedIn && after.session == before.session) return;
    for (final family in perSessionFamilies) {
      ref.invalidate(family);
    }
  });
});
