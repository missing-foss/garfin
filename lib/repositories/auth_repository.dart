// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import '../logging.dart';
import '../models/auth_session.dart';
import '../models/authentication_result.dart';
import '../models/jellyfin_user.dart';
import '../models/server_version.dart';
import 'birth_year_store.dart';
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
    required this._birthYears,
  });

  final JellyfinApiFactory _apiFactory;

  /// `flutter_secure_storage`. The only thing that writes the access token.
  final TokenStore _tokenStore;

  /// `shared_preferences`. Server address and account name — nothing secret.
  final ServerSettingsStore _settings;

  /// Birth years the parent typed. Account-scoped, so sign-out forgets them.
  final BirthYearStore _birthYears;

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

    // **The token last.** It is what `restore` takes as "signed in", so it is
    // written only once the address and account it belongs to are: an
    // interruption between the two used to leave a token that restored with
    // an empty user id, and every request then went to `/Users//Items/…`.
    await _settings.setServerUrl(serverUrl);
    await _settings.setUser(id: result.user.id, name: result.user.name);
    await _tokenStore.write(result.accessToken);

    // Not awaited and not a gate: a sign-in to a version nobody measured
    // still signs in. It only puts that fact at the top of the log.
    unawaited(_noteServerVersion(serverUrl));

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
  /// (`docs/ENGINEERING.md` § Definition of done). Whether the token still works is
  /// [verify]'s question, asked afterwards and allowed to fail.
  Future<AuthSession?> restore() async {
    final serverUrl = _settings.serverUrl;
    if (serverUrl == null) return null;

    final token = await _tokenStore.read();
    if (token == null) return null;

    // No account id is no session: every request is keyed on it. A token
    // without one is what an interrupted sign-in used to leave behind, and it
    // is treated as signed out rather than restored into `/Users//…`. A
    // stored empty id reads as null already: the store maps it.
    final userId = _settings.userId;
    if (userId == null) return null;

    return AuthSession(
      serverUrl: serverUrl,
      accessToken: token,
      userId: userId,
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
  ///
  /// **And revokes the token on the server first**, when [revoke] is true.
  /// Clearing it here only forgets it on this phone: a Jellyfin token does not
  /// expire, the default address is plain `http://`, and the token rides in a
  /// header on every request — so one that was ever observed kept working
  /// after the parent signed out, until they found the device in the
  /// dashboard.
  ///
  /// Best effort, and bounded: signing out must work with no network, so a
  /// failure is logged and the local sign-out goes ahead. [revoke] is false
  /// when the server has just refused the token (401) — there is nothing left
  /// to revoke, and asking again would only wait on a request that cannot
  /// help.
  Future<void> signOut({bool revoke = true}) async {
    if (revoke) await _revoke();
    await _tokenStore.clear();
    await _settings.clearUser();
    // Birth years are keyed by Jellyfin user id, and ids are per-server.
    // Leaving them would at best be dead keys and at worst attach one
    // household's ages to another's accounts after a server change.
    await _birthYears.clearAll();
  }

  Future<void> _revoke() async {
    final session = await restore();
    if (session == null) return;
    try {
      await _apiFactory
          .create(
            baseUrl: session.serverUrl,
            readToken: () => session.accessToken,
          )
          .logout()
          .timeout(revokeTimeout);
    } on Object catch (error) {
      log.info('sign-out could not revoke the token: '
          '${error is JellyfinException ? error.kind.name : error.runtimeType}');
    }
  }

  /// How long sign-out waits for the server before going ahead locally.
  ///
  /// Short on purpose: the parent pressed *Sign out* and is waiting on it,
  /// and the client's own timeouts are sized for a library page.
  static const revokeTimeout = Duration(seconds: 3);

  /// Logs a warning when the server is outside what Garfin was measured
  /// against. Never throws: a version that cannot be read is no reason to
  /// interrupt anything, and is not logged as untested.
  Future<void> _noteServerVersion(String serverUrl) async {
    try {
      final version = await _anonymous(serverUrl)
          .serverVersion()
          .timeout(const Duration(seconds: 5));
      if (isTestedServerVersion(version) == false) {
        log.warning('server version $version is outside the tested '
            '10.11.x / 12.x; reports from it should say so');
      }
    } on Object {
      // Unknown, not untested.
    }
  }

  JellyfinApi _anonymous(String serverUrl) =>
      _apiFactory.create(baseUrl: serverUrl);
}
