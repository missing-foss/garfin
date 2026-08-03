// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';

/// The slice of Jellyfin's user DTO that sign-in needs.
///
/// Deliberately not the whole policy. The shortlist fields — `AllowedTags`,
/// `BlockedTags`, `MaxParentalRating`, `EnabledFolders` — belong to the Kids
/// screen (build order step 3) and modelling them here would invite a caller to
/// use them before the allow/block inversion exists to interpret them.
///
/// These models are **read-only**. Garfin never writes a user policy
/// (ground rule 8), so no `toJson` exists for them and none should be added:
/// `POST /Users/{id}/Policy` is a full-object replace over a child's whole
/// permission set, and a typed model is exactly how fields go missing from one.
class UserPolicy {
  const UserPolicy({
    required this.isAdministrator,
    required this.isDisabled,
  });

  /// Ground rule 7. Garfin needs this to read every user's policy and to write
  /// item metadata; a non-admin token fails later with a 403 that reads like a
  /// bug, so sign-in refuses it at the door instead.
  final bool isAdministrator;

  final bool isDisabled;

  factory UserPolicy.fromJson(Map<String, dynamic> json) => UserPolicy(
        // Absent means false. A server version that stops sending the field is
        // not a reason to assume administrator.
        isAdministrator: readBool(json, 'IsAdministrator'),
        isDisabled: readBool(json, 'IsDisabled'),
      );
}

class JellyfinUser {
  const JellyfinUser({
    required this.id,
    required this.name,
    required this.policy,
  });

  final String id;
  final String name;
  final UserPolicy policy;

  factory JellyfinUser.fromJson(Map<String, dynamic> json) {
    final policy = readMap(json, 'Policy');
    return JellyfinUser(
      id: readString(json, 'Id') ?? '',
      name: readString(json, 'Name') ?? '',
      policy: policy == null
          // No policy in the response means nothing can be asserted about
          // administrator rights, so assert the restrictive one.
          ? const UserPolicy(isAdministrator: false, isDisabled: false)
          : UserPolicy.fromJson(policy),
    );
  }
}
