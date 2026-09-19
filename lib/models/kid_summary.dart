// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'jellyfin_user.dart';

/// One card on the Kids screen: a user under shortlist control, and what
/// Garfin knows about them beyond their Jellyfin account.
///
/// **No totals here any more.** This used to carry the child's visible count
/// and the administrator's, for a "N of M things visible" line and the bar
/// above it. Both are gone from the card — the per-library breakdown answers
/// the same question with more resolution — and the fields went with them
/// rather than staying as fields nothing reads. The fetch behind them was the
/// most expensive call the app makes: one for the administrator plus one per
/// child, 19 ms at a single title and 8.7 s at six thousand, on the screen a
/// parent opens first.
class KidSummary {
  const KidSummary({
    required this.user,
    this.ratingCapName,
    this.birthYear,
    this.avatarUrl,
  });

  final JellyfinUser user;

  /// The cap as a parent would recognise it, or null when uncapped *or* when
  /// the ladder has no rung at that score. The screen distinguishes the two by
  /// looking at [UserPolicy.maxParentalRating], which stays authoritative.
  final String? ratingCapName;

  /// Set by the parent inside Garfin, because Jellyfin has no `DateOfBirth`.
  final int? birthYear;

  final String? avatarUrl;

  ShortlistMode get mode => user.policy.shortlistMode;

  List<String> get tags => user.policy.shortlistTags;

  /// Whole years, or null when no birth year has been set.
  ///
  /// Deliberately approximate. Only the year is stored (see
  /// `BirthYearStore`), so this is right to within a birthday, which is all a
  /// rating cap is ever used at.
  int? ageIn(int currentYear) =>
      birthYear == null ? null : currentYear - birthYear!;
}

/// The children and their pictures, before a single count has been asked for.
///
/// **Split out of [KidsOverview] so the faces can arrive first.** Listing the
/// users is one cheap request; the counts beside them are the most expensive
/// thing this app does — measured, a child's count is 19 ms when they can see
/// one title and **8.7 s at six thousand**, and the administrator's total is
/// 7.6 s on the same library. A landing screen that waited for all of that
/// before drawing anything showed a spinner for as long as the slowest child
/// took, on the first screen anyone sees.
///
/// [KidsOverview] is built on top of this rather than beside it, so the users
/// are fetched once and the counts are what the second wait is for.
class KidsRoster {
  const KidsRoster({required this.shortlisted, required this.withoutShortlist});

  /// Label-controlled users, in the order the server gave them.
  final List<KidFace> shortlisted;

  final List<UnshortlistedUser> withoutShortlist;

  bool get isEmpty => shortlisted.isEmpty && withoutShortlist.isEmpty;
}

/// One child and their picture, with nothing counted yet.
///
/// Deliberately not [UnshortlistedUser] despite the identical shape: that type
/// means *an account Garfin does not manage*, and reusing it for the managed
/// half would make the one place that distinction is drawn depend on reading
/// which field it was assigned to.
class KidFace {
  const KidFace({required this.user, required this.avatarUrl});

  final JellyfinUser user;

  /// Null when the user has no picture. Same rule as [KidSummary.avatarUrl].
  final String? avatarUrl;
}

/// The Kids screen's whole payload.
class KidsOverview {
  const KidsOverview({
    required this.shortlisted,
    required this.withoutShortlist,
  });

  /// Users with a shortlist, in either verb — and the conflicting ones too.
  ///
  /// A user with both lists populated is still label-controlled; what is
  /// missing is a single correct interpretation. Hiding them in the section
  /// below would read as "no shortlist set", which is the one thing that is
  /// definitely untrue about them.
  final List<KidSummary> shortlisted;

  /// Users with no shortlist at all, the administrator included.
  ///
  /// A boundary, not a to-do list: Garfin cannot give a child their first
  /// label, because that is a policy write and ground rule 8 forbids it. The
  /// rows are non-interactive on purpose — see `docs/UI-SPEC.md` § Kids.
  final List<UnshortlistedUser> withoutShortlist;

  bool get isEmpty => shortlisted.isEmpty && withoutShortlist.isEmpty;
}

/// One account Garfin does not manage, and its picture (#79).
///
/// A pair rather than a bare [JellyfinUser] so that the *repository* builds the
/// avatar URL, exactly as it already does for [KidSummary]. The alternative was
/// to have the screen reach into `KidsRepository.avatarUrlFor`, which puts the
/// server address in the widget layer for the sake of one string — and the
/// screen is the layer that must not know how to talk to Jellyfin.
class UnshortlistedUser {
  const UnshortlistedUser({required this.user, required this.avatarUrl});

  final JellyfinUser user;

  /// Null when the user has no picture. Same rule as [KidSummary.avatarUrl].
  final String? avatarUrl;
}
