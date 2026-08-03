// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../logging.dart';
import '../models/auth_session.dart';
import '../models/authentication_result.dart';
import '../models/jellyfin_user.dart';
import 'jellyfin_api.dart';
import 'jellyfin_exception.dart';
import 'quick_connect_session.dart';
import 'server_settings_store.dart';
import 'token_store.dart';

/// Sign-in, sign-out, and the one rule that governs both.
///
/// **Ground rule 7 lives here.** An account that is not a Jellyfin
/// administrator is refused at sign-in, and its token is never written down.
///
/// The usual justification for that rule is "otherwise it fails later with a
/// 403". Measured against 10.11.11 (2026-08-03), that is not what happens, and
/// the truth is a stronger argument for the rule rather than a weaker one: a
/// non-admin account is issued a perfectly good token, and `GET /Users` with it
/// answers **200 with every user's `Policy` populated**. So Garfin would sail
/// through sign-in, build the whole Kids screen, and only discover the problem
/// at the first write. There is no 403 to catch — which is exactly why the
/// check has to be here, at the door, rather than left to surface on its own.
class AuthRepository {
  /// Collaborators are private: nothing outside this class should be able to
  /// reach the token store directly and write a token that has not been through
  /// the admin check in [completeSignIn].
  AuthRepository({
    required this._apiFactory,
    required this._tokenStore,
    required this._settings,
  });

  final JellyfinApiFactory _apiFactory;

  /// `flutter_secure_storage`. The only thing that writes the access token.
  final TokenStore _tokenStore;

  /// `shared_preferences`. Server address and account name — nothing secret.
  final ServerSettingsStore _settings;

  /// The last address the user signed in against, if any.
  String? get rememberedServerUrl => _settings.serverUrl;

  /// Whether this server offers Quick Connect.
  ///
  /// Doubles as the reachability probe for a freshly typed address: it is the
  /// cheapest anonymous endpoint Garfin already needs, so checking the URL
  /// costs no extra request.
  Future<bool> quickConnectEnabled(String serverUrl) =>
      _anonymous(serverUrl).quickConnectEnabled();

  /// A fresh pairing against [serverUrl]. The caller owns it and must
  /// [QuickConnectSession.dispose] it.
  QuickConnectSession beginQuickConnect(String serverUrl) =>
      QuickConnectSession(api: _anonymous(serverUrl));

  /// The password fallback.
  Future<AuthSession> signInWithPassword({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final result = await _anonymous(serverUrl).authenticateByName(
      username: username,
      password: password,
    );
    return completeSignIn(serverUrl: serverUrl, result: result);
  }

  /// Turns a successful authentication into a stored session — but only after
  /// the admin check passes.
  ///
  /// The order is the point. Nothing is persisted until
  /// `Policy.IsAdministrator` has been read and found true, so a refused
  /// sign-in leaves no token on the device to be picked up by the next launch.
  Future<AuthSession> completeSignIn({
    required String serverUrl,
    required AuthenticationResult result,
  }) async {
    if (result.accessToken.isEmpty) {
      throw const JellyfinException(
        JellyfinErrorKind.server,
        message: 'authentication succeeded without an access token',
      );
    }

    if (!result.user.policy.isAdministrator) {
      log.info('refusing sign-in: account is not an administrator');
      throw JellyfinException(
        JellyfinErrorKind.notAdministrator,
        detail: result.user.name,
      );
    }

    await _tokenStore.write(result.accessToken);
    await _settings.setServerUrl(serverUrl);
    await _settings.setUser(id: result.user.id, name: result.user.name);

    return AuthSession(
      serverUrl: serverUrl,
      accessToken: result.accessToken,
      userId: result.user.id,
      userName: result.user.name,
    );
  }

  /// Rebuilds the last session from storage without touching the network.
  ///
  /// Deliberately offline: a cold start with no route to the server still knows
  /// who is signed in and against which address, so the app can show that plus
  /// a clear error rather than a blank screen or a spurious sign-out
  /// (`CLAUDE.md` § Definition of done). Whether the token still works is
  /// [verify]'s question, asked afterwards and allowed to fail.
  Future<AuthSession?> restore() async {
    final serverUrl = _settings.serverUrl;
    if (serverUrl == null) return null;

    final token = await _tokenStore.read();
    if (token == null) return null;

    return AuthSession(
      serverUrl: serverUrl,
      accessToken: token,
      userId: _settings.userId ?? '',
      userName: _settings.userName ?? '',
    );
  }

  /// Re-reads the signed-in account from the server.
  ///
  /// Rights can be withdrawn between two launches, so ground rule 7 is checked
  /// again here and not only at the door. Throws
  /// [JellyfinErrorKind.notAdministrator] if the account has been demoted, and
  /// a network error if the server cannot be reached — the caller decides which
  /// of those is worth signing out over.
  Future<JellyfinUser> verify(AuthSession session) async {
    final api = _apiFactory.create(
      baseUrl: session.serverUrl,
      readToken: () => session.accessToken,
    );
    final user = await api.currentUser();
    if (!user.policy.isAdministrator) {
      throw JellyfinException(
        JellyfinErrorKind.notAdministrator,
        detail: user.name,
      );
    }
    return user;
  }

  /// Forgets the account and the token. Keeps the server address, which the
  /// next sign-in will want and which is not a secret.
  Future<void> signOut() async {
    await _tokenStore.clear();
    await _settings.clearUser();
  }

  JellyfinApi _anonymous(String serverUrl) =>
      _apiFactory.create(baseUrl: serverUrl);
}
