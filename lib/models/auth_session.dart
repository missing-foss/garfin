// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// A signed-in session: which server, which admin account, and the token that
/// proves it.
///
/// [accessToken] is held in memory here and persisted only by `TokenStore`
/// (`flutter_secure_storage`). [toString] omits it — this object ends up inside
/// Riverpod state, and Riverpod's own observers print state transitions.
class AuthSession {
  const AuthSession({
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
    required this.userName,
  });

  final String serverUrl;
  final String accessToken;
  final String userId;
  final String userName;

  @override
  String toString() =>
      'AuthSession(server: $serverUrl, user: $userName)';
}
