// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dto_json.dart';
import 'jellyfin_user.dart';

/// What `POST /Users/AuthenticateByName` and
/// `POST /Users/AuthenticateWithQuickConnect` return.
///
/// [accessToken] is a live credential from the moment it is parsed. It reaches
/// `flutter_secure_storage` and the `Authorization` header and nowhere else —
/// in particular it is deliberately absent from [toString], because an object
/// interpolated into a log message is the ordinary way a token ends up in one.
class AuthenticationResult {
  const AuthenticationResult({
    required this.accessToken,
    required this.user,
    required this.serverId,
  });

  final String accessToken;
  final JellyfinUser user;
  final String serverId;

  /// Measured on 10.11.11: the response carries exactly
  /// `AccessToken`, `ServerId`, `SessionInfo` and `User`. `SessionInfo` is not
  /// modelled — Garfin has no use for it, and an unused field is one more thing
  /// to keep true across a version bump.
  factory AuthenticationResult.fromJson(Map<String, dynamic> json) {
    final user = readMap(json, 'User');
    return AuthenticationResult(
      accessToken: readString(json, 'AccessToken') ?? '',
      serverId: readString(json, 'ServerId') ?? '',
      user: user == null
          ? const JellyfinUser(
              id: '',
              name: '',
              policy: UserPolicy(isAdministrator: false, isDisabled: false),
            )
          : JellyfinUser.fromJson(user),
    );
  }

  @override
  String toString() => 'AuthenticationResult(user: ${user.name})';
}
