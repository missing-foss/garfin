// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// What `GET /QuickConnect/Initiate` hands back: the six digits the user types
/// into Jellyfin, and the secret Garfin trades for an access token.
///
/// **The secret is never written to disk** — not to `flutter_secure_storage`,
/// not to `shared_preferences`, nowhere (`docs/JELLYFIN-API.md`, and settled in
/// `docs/DECISIONS.md`). It is a credential for the length of one exchange and
/// is inert once traded, so persisting it would buy nothing and add a
/// stale-credential-after-crash case that memory-only cannot have.
///
/// [toString] prints the code and not the secret, for the same reason
/// `AuthenticationResult` hides its token: an object interpolated into a log
/// line is how credentials get written down.
class QuickConnectInitiation {
  const QuickConnectInitiation({required this.code, required this.secret});

  /// Six digits, shown to the user. Not a credential — it is useless without
  /// the secret, and the whole point is that it appears on screen.
  final String code;

  /// The credential half. In memory only, for one exchange.
  final String secret;

  factory QuickConnectInitiation.fromJson(Map<String, dynamic> json) =>
      QuickConnectInitiation(
        code: json['Code'] as String? ?? '',
        secret: json['Secret'] as String? ?? '',
      );

  @override
  String toString() => 'QuickConnectInitiation(code: $code)';
}

/// What `GET /QuickConnect/Connect?secret=…` reports while polling.
class QuickConnectStatus {
  const QuickConnectStatus({required this.authenticated});

  final bool authenticated;

  factory QuickConnectStatus.fromJson(Map<String, dynamic> json) =>
      QuickConnectStatus(authenticated: json['Authenticated'] == true);
}
