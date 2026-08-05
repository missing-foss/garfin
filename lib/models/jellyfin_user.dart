// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// How a user's shortlist is expressed, if they have one.
///
/// Ground rule 3: allow-list and block-list are **opposite verbs**. Sharing
/// means *adding* a tag in [allow] and *removing* one in [block], so every
/// action inverts. Nothing may treat this as a boolean.
enum ShortlistMode {
  /// `AllowedTags` non-empty. The child sees *only* what is tagged.
  allow,

  /// `BlockedTags` non-empty. The child sees everything *except* what is tagged.
  block,

  /// Neither list has anything in it, so the account is not under shortlist
  /// control. Garfin cannot change that — giving a child their first label is a
  /// policy write, which ground rule 8 forbids. See `docs/UI-SPEC.md` § Kids.
  none,

  /// **Both lists are non-empty.** Ground rule 3 says this must never happen,
  /// but the server does not prevent it, so it can arrive from a library
  /// configured elsewhere. Two opposite verbs are live at once and there is no
  /// correct inversion to pick, so Garfin surfaces it and refuses to guess.
  conflicting,
}

/// The slice of Jellyfin's user DTO Garfin reads.
///
/// These models are **read-only**. Garfin never writes a user policy
/// (ground rule 8), so no `toJson` exists for them and none should be added:
/// `POST /Users/{id}/Policy` is a full-object replace over a child's whole
/// permission set, and a typed model is exactly how fields go missing from one.
class UserPolicy {
  const UserPolicy({
    required this.isAdministrator,
    required this.isDisabled,
    this.allowedTags = const [],
    this.blockedTags = const [],
    this.maxParentalRating,
    this.enableAllFolders = false,
    this.enabledFolders = const [],
  });

  /// Ground rule 7, and the field the whole of sign-in turns on.
  ///
  /// Measured on 10.11.11: a non-admin token does **not** fail later. It reads
  /// every user's policy with a 200. So nothing downstream will catch a wrong
  /// account — see `AuthRepository` and `docs/JELLYFIN-API.md` § Measured.
  final bool isAdministrator;

  final bool isDisabled;

  /// The child sees *only* items carrying one of these. Ground rule 3.
  final List<String> allowedTags;

  /// The child sees everything *except* items carrying one of these.
  final List<String> blockedTags;

  /// The rating cap, or null for uncapped.
  ///
  /// Measured on 10.11.11: an **integer**, not a string and not a rating name —
  /// `7` for a capped fixture child, `null` for an unrestricted one. It joins
  /// to `Value` in `/Localization/ParentalRatings`.
  ///
  /// This is the actual safety control, and it silently overrides tags: a
  /// correctly tagged title stays invisible to a child whose cap excludes it.
  /// That is why ground rule 4 forbids computing visibility here.
  final int? maxParentalRating;

  final bool enableAllFolders;

  final List<String> enabledFolders;

  /// Which verb applies to this user, or that no single one does.
  ///
  /// Derived rather than stored, so there is one place the question is answered
  /// and no way for a caller to reach the raw lists and reinvent it wrongly.
  ShortlistMode get shortlistMode {
    final allows = allowedTags.isNotEmpty;
    final blocks = blockedTags.isNotEmpty;
    if (allows && blocks) return ShortlistMode.conflicting;
    if (allows) return ShortlistMode.allow;
    if (blocks) return ShortlistMode.block;
    return ShortlistMode.none;
  }

  /// The tags that define this user's shortlist, whichever verb is in force.
  ///
  /// Empty for [ShortlistMode.none], and deliberately empty for
  /// [ShortlistMode.conflicting] too: with both lists live there is no single
  /// set of tags that means anything, and returning one of them would be a
  /// guess wearing the clothes of an answer.
  List<String> get shortlistTags => switch (shortlistMode) {
        ShortlistMode.allow => allowedTags,
        ShortlistMode.block => blockedTags,
        ShortlistMode.none || ShortlistMode.conflicting => const [],
      };

  factory UserPolicy.fromJson(Map<String, dynamic> json) => UserPolicy(
        // Absent means false. A server version that stops sending the field is
        // not a reason to assume administrator.
        isAdministrator: readBool(json, 'IsAdministrator'),
        isDisabled: readBool(json, 'IsDisabled'),
        allowedTags: readStringList(json, 'AllowedTags'),
        blockedTags: readStringList(json, 'BlockedTags'),
        maxParentalRating: readInt(json, 'MaxParentalRating'),
        enableAllFolders: readBool(json, 'EnableAllFolders'),
        enabledFolders: readStringList(json, 'EnabledFolders'),
      );
}

class JellyfinUser {
  const JellyfinUser({
    required this.id,
    required this.name,
    required this.policy,
    this.primaryImageTag,
  });

  final String id;
  final String name;
  final UserPolicy policy;

  /// The avatar's cache key, or null when the user has no avatar.
  ///
  /// Measured on 10.11.11: when no avatar is set the key is **absent from the
  /// JSON entirely** — not null, missing. With one it is a hash, which is
  /// exactly what `cached_network_image` wants as a cache key, because it
  /// changes when the picture does.
  ///
  /// Key-absence is the cheap check. `GET /Users/{id}/Images/Primary` on a user
  /// without one is a 404, so that is the backstop rather than the test.
  final String? primaryImageTag;

  factory JellyfinUser.fromJson(Map<String, dynamic> json) {
    final policy = readMap(json, 'Policy');
    return JellyfinUser(
      id: readString(json, 'Id') ?? '',
      name: readString(json, 'Name') ?? '',
      primaryImageTag: readString(json, 'PrimaryImageTag'),
      policy: policy == null
          // No policy in the response means nothing can be asserted about
          // administrator rights, so assert the restrictive one.
          ? const UserPolicy(isAdministrator: false, isDisabled: false)
          : UserPolicy.fromJson(policy),
    );
  }
}
