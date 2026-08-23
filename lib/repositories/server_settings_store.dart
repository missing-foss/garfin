// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

/// The non-secret half of a session: which server, and who was signed in.
///
/// All of it is `shared_preferences`, and none of it is a credential. The
/// access token is in `TokenStore`; nothing here may be used to authenticate.
/// If a value ever needs to be, it belongs in the other file.
class ServerSettingsStore {
  const ServerSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _serverUrlKey = 'server_url';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';

  /// The address the user typed, already normalised by [normalizeServerUrl].
  ///
  /// Remembered so a returning user does not retype it — and kept even after a
  /// sign-out, because the server is a property of the household, not of the
  /// session.
  String? get serverUrl => _emptyToNull(_prefs.getString(_serverUrlKey));

  Future<void> setServerUrl(String url) =>
      _prefs.setString(_serverUrlKey, url);

  /// The signed-in account, cached so a cold start with no network can still
  /// name who it is showing rather than a blank screen (definition of done).
  String? get userId => _emptyToNull(_prefs.getString(_userIdKey));
  String? get userName => _emptyToNull(_prefs.getString(_userNameKey));

  Future<void> setUser({required String id, required String name}) async {
    await _prefs.setString(_userIdKey, id);
    await _prefs.setString(_userNameKey, name);
  }

  /// Forgets the account but keeps the server address.
  Future<void> clearUser() async {
    await _prefs.remove(_userIdKey);
    await _prefs.remove(_userNameKey);
  }

  static String? _emptyToNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}

/// Turns what a user typed into a base URL dio can use, or null if it cannot.
///
/// A scheme-less entry is resolved to `http://`. A home Jellyfin on the LAN is
/// usually plain HTTP, and guessing `https://` there fails with a TLS error
/// that reads like the server is down. The sign-in screen writes the resolved
/// URL back into the field, so the guess is visible rather than silent, and a
/// user on HTTPS can type the scheme and keep it.
///
/// Trailing slashes are stripped: dio joins `baseUrl` and a leading-slash path
/// verbatim, so `http://host:8096/` would produce `http://host:8096//Users/Me`.
String? normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;

  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
    text = 'http://$text';
  }

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  // Rebuilt field by field rather than with `Uri.replace`, which reads a null
  // argument as "keep this" and so cannot drop a query or a fragment. Neither
  // is ever part of a Jellyfin base URL, and carrying one would append it to
  // every request path.
  //
  // `userInfo` is dropped for a harder reason: it is a **password**, and this
  // string is persisted to `shared_preferences` in clear, written back into a
  // visible text field, and interpolated into on-screen error text. Every one
  // of those is somewhere a credential must never go. See
  // [addressCarriesCredentials] for what the screen does about it.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.replaceAll(RegExp(r'/+$'), ''),
  ).toString();
}

/// Whether the typed address carried `user:password@`, so the screen can say
/// the credentials were dropped instead of silently discarding them.
///
/// **Garfin cannot sign in through a reverse proxy that does HTTP basic auth,**
/// and this is why it says so rather than trying. Measured against Jellyfin
/// 10.11.11 (2026-08-03): the proxy wants `Authorization: Basic …` and Jellyfin
/// wants `Authorization: MediaBrowser …`, one header cannot be both, and every
/// alternative route for the device identity has been removed —
/// `X-Emby-Authorization` answers 400/401, the split `X-Emby-Client` /
/// `X-Emby-Device-Id` / `X-Emby-Device-Name` / `X-Emby-Client-Version` headers
/// answer 400, and sending no identity answers 400. Only `X-Emby-Token` still
/// works, and that is useless here: it carries a token you can only obtain by
/// signing in first.
///
/// So there is nothing to implement, not merely something unimplemented.
/// Details in `docs/JELLYFIN-API.md` § Measured.
bool addressCarriesCredentials(String input) {
  var text = input.trim();
  if (text.isEmpty) return false;
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
    text = 'http://$text';
  }
  return Uri.tryParse(text)?.userInfo.isNotEmpty ?? false;
}
