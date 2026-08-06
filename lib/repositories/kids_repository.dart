// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/jellyfin_user.dart';
import '../models/kid_summary.dart';
import '../models/parental_rating.dart';
import 'birth_year_store.dart';
import 'jellyfin_api.dart';

/// Assembles the Kids screen.
///
/// Widgets never call HTTP (`CLAUDE.md` § Stack), and the arithmetic that would
/// break ground rule 4 is not here either — every count comes back from the
/// server.
class KidsRepository {
  const KidsRepository({
    required this._api,
    required this._birthYears,
    required this._serverUrl,
    required this._adminUserId,
  });

  final JellyfinApi _api;

  final BirthYearStore _birthYears;

  /// The address the session is signed in to, for building avatar URLs.
  final String _serverUrl;

  /// Whose view is the "of M" in "N of M things visible".
  final String _adminUserId;

  Future<KidsOverview> load() async {
    final users = await _api.users();

    // One ladder for everyone, not one fetch per child. It is a property of the
    // server, and 56 entries on a default install is not something to re-ask
    // for once per card.
    //
    // A ladder that fails to load must not take the screen down with it: the
    // caps still exist and are still enforced, and a card that shows the number
    // without the name is far better than an error page. `nameFor` on an empty
    // ladder simply answers null, which is the same path as a rung that is not
    // in the list.
    ParentalRatingLadder ladder;
    try {
      ladder = await _api.parentalRatings();
    } on Object {
      ladder = const ParentalRatingLadder.empty();
    }

    // Ground rule 4, the admin half: the denominator is what the *server* says
    // the administrator can see, not a number this app added up.
    final libraryTotal = await _api.visibleItemCount(userId: _adminUserId);

    final shortlisted = <KidSummary>[];
    final withoutShortlist = <UnshortlistedUser>[];

    for (final user in users) {
      if (user.policy.shortlistMode == ShortlistMode.none) {
        // The picture is resolved here too (#79). It used to be built only for
        // shortlisted kids, so the unmanaged half of the same screen showed a
        // letter for people who had an avatar set.
        withoutShortlist.add(
          UnshortlistedUser(user: user, avatarUrl: avatarUrlFor(user)),
        );
        continue;
      }

      // Ground rule 4, the child half. Asked as the administrator but *for*
      // this user, so the server applies their policy — tags and the rating cap
      // together, which is the combination no client-side sum can reproduce.
      final visible = await _api.visibleItemCount(userId: user.id);

      shortlisted.add(
        KidSummary(
          user: user,
          visibleCount: visible,
          libraryTotal: libraryTotal,
          ratingCapName: ladder.nameFor(user.policy.maxParentalRating),
          birthYear: _birthYears.read(user.id),
          avatarUrl: avatarUrlFor(user),
        ),
      );
    }

    return KidsOverview(
      shortlisted: shortlisted,
      withoutShortlist: withoutShortlist,
    );
  }

  /// The avatar URL, or null when the user has no picture.
  ///
  /// Null rather than a URL that 404s: key-absence is the documented signal and
  /// asking anyway would put a failed request behind every initial-avatar.
  ///
  /// The tag rides along as a query parameter because it is what makes the URL
  /// change when the picture does — without it a cached avatar would outlive
  /// the one it shows.
  String? avatarUrlFor(JellyfinUser user) {
    final tag = user.primaryImageTag;
    if (tag == null || tag.isEmpty) return null;
    final base = _serverUrl.endsWith('/')
        ? _serverUrl.substring(0, _serverUrl.length - 1)
        : _serverUrl;
    return '$base/Users/${user.id}/Images/Primary?tag=$tag';
  }
}
