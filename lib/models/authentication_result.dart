// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

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

  factory AuthenticationResult.fromJson(Map<String, dynamic> json) {
    final user = json['User'];
    return AuthenticationResult(
      accessToken: json['AccessToken'] as String? ?? '',
      serverId: json['ServerId'] as String? ?? '',
      user: user is Map<String, dynamic>
          ? JellyfinUser.fromJson(user)
          : const JellyfinUser(
              id: '',
              name: '',
              policy: UserPolicy(isAdministrator: false, isDisabled: false),
            ),
    );
  }

  @override
  String toString() => 'AuthenticationResult(user: ${user.name})';
}
