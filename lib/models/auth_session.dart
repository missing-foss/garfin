// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// A signed-in session: which server, which admin account, and the token that
/// proves it.
///
/// [accessToken] is held in memory here and persisted only by `TokenStore`
/// (`flutter_secure_storage`). [toString] omits it — this object ends up inside
/// Riverpod state, and Riverpod's own observers print state transitions.
///
/// **Compared by value, every field.** Every per-session provider family is
/// keyed on this, directly or through a request object, so identity equality
/// made each provider's cache depend on one instance being passed around: a
/// second, equal session would have forked every family into a duplicate
/// client and cache, and an invalidation through one would miss the screen
/// watching the other. The token is part of the key, deliberately — the
/// clients these families build read it, so a session with a new token must
/// not be handed one built for the old.
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
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.serverUrl == serverUrl &&
      other.accessToken == accessToken &&
      other.userId == userId &&
      other.userName == userName;

  @override
  int get hashCode => Object.hash(serverUrl, accessToken, userId, userName);

  @override
  String toString() =>
      'AuthSession(server: $serverUrl, user: $userName)';
}
