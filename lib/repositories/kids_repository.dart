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
/// Widgets never call HTTP (`docs/ENGINEERING.md` § Stack), and the arithmetic
/// that would break ground rule 4 is not here either — no count is computed
/// here. The counts that remain on this screen are the per-library ones, asked
/// when a card is opened, and each of those is a `TotalRecordCount` the server
/// answered with the child's own policy applied.
class KidsRepository {
  const KidsRepository({
    required this._api,
    required this._birthYears,
    required this._serverUrl,
  });

  final JellyfinApi _api;

  final BirthYearStore _birthYears;

  /// The address the session is signed in to, for building avatar URLs.
  final String _serverUrl;

  /// Who the children are, and their pictures. One request.
  ///
  /// The cheap half of what this screen needs, separated so the faces can be
  /// drawn while the counts are still being asked for — see [KidsRoster].
  Future<KidsRoster> roster() async {
    final users = await _api.users();
    return KidsRoster(
      shortlisted: <KidFace>[
        for (final user in users)
          if (user.policy.shortlistMode != ShortlistMode.none)
            KidFace(user: user, avatarUrl: avatarUrlFor(user)),
      ],
      // The picture is resolved here too (#79). It used to be built only for
      // shortlisted kids, so the unmanaged half of the same screen showed a
      // letter for people who had an avatar set.
      withoutShortlist: <UnshortlistedUser>[
        for (final user in users)
          if (user.policy.shortlistMode == ShortlistMode.none)
            UnshortlistedUser(user: user, avatarUrl: avatarUrlFor(user)),
      ],
    );
  }

  /// The counts, on top of a roster that has already arrived.
  ///
  /// Takes the roster rather than re-listing the users, so the split costs no
  /// extra request.
  Future<KidsOverview> load(KidsRoster roster) async {

    // One ladder for everyone, not one fetch per child. It is a property of the
    // server, and 56 entries on a default install is not something to re-ask
    // for once per card.
    //
    // A ladder that fails to load must not take the screen down with it: the
    // caps still exist and are still enforced, and a card that shows the number
    // without the name is far better than an error page. `nameFor` on an empty
    // ladder simply answers null, which is the same path as a rung that is not
    // in the list.
    //
    // **One request now, and this method used to make one per child plus one.**
    // The administrator's total and each child's visible count were the whole
    // of the expense here — measured on 10.11.11, a child's count costs 19 ms
    // when they can see 1 title, 538 ms at 2000 and 8.7 s at 6000, and the
    // administrator's own total 7.6 s on that same library. A household of four
    // well-supplied children paid five of those on the first screen that opens,
    // again on every invalidation after a write.
    //
    // They are gone because nothing draws them. The card's "N of M things
    // visible" line and the bar above it were both removed in favour of the
    // per-library breakdown, which is fetched only when a row is opened and
    // asks each library its own question. Keeping the fetch for fields no
    // widget reads would be paying the app's largest cost for a value that
    // cannot appear.
    //
    // What is left is the ladder, which is a property of the *server* rather
    // than of a child: 56 entries on a default install, fetched once for
    // everyone rather than once per card.
    //
    // A ladder that fails to load must not take the screen down with it: the
    // caps still exist and are still enforced, and a card that shows the number
    // without the name is far better than an error page. `nameFor` on an empty
    // ladder simply answers null, which is the same path as a rung that is not
    // in the list.
    final ladder = await _api.parentalRatings().then<ParentalRatingLadder>(
          (value) => value,
          onError: (_, _) => const ParentalRatingLadder.empty(),
        );

    final shortlisted = <KidSummary>[
      for (final face in roster.shortlisted)
        KidSummary(
          user: face.user,
          ratingCapName: ladder.nameFor(
            face.user.policy.maxParentalRating,
            face.user.policy.maxParentalSubRating,
          ),
          birthYear: _birthYears.read(face.user.id),
          avatarUrl: avatarUrlFor(face.user),
        ),
    ];

    return KidsOverview(
      shortlisted: shortlisted,
      withoutShortlist: roster.withoutShortlist,
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
