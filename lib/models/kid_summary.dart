// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'jellyfin_user.dart';

/// One card on the Kids screen: a user under shortlist control, plus the
/// server-computed facts about what they can see.
class KidSummary {
  const KidSummary({
    required this.user,
    required this.visibleCount,
    required this.libraryTotal,
    this.ratingCapName,
    this.birthYear,
    this.avatarUrl,
  });

  final JellyfinUser user;

  /// What the **server** says this child can see. Never computed here.
  ///
  /// Ground rule 4. The rating cap silently overrides tags, so a count derived
  /// from the tag list would be confidently wrong for exactly the children who
  /// matter most.
  final int visibleCount;

  /// The same query asked as the administrator, for the "N of M" denominator.
  final int libraryTotal;

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

  /// How much of the library this child can reach, for the progress bar.
  ///
  /// Zero when the library is empty rather than a division by zero, and clamped
  /// because the child's count can exceed the admin's denominator when the
  /// admin's own view is itself restricted.
  double get progress => libraryTotal <= 0
      ? 0
      : (visibleCount / libraryTotal).clamp(0.0, 1.0).toDouble();
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
  final List<JellyfinUser> withoutShortlist;

  bool get isEmpty => shortlisted.isEmpty && withoutShortlist.isEmpty;
}
