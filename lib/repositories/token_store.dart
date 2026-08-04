// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The access token's only home.
///
/// `CLAUDE.md` § Stack: settings go in `shared_preferences`, the access token
/// **never** does — it goes in `flutter_secure_storage`, which on Android is
/// backed by the AndroidKeyStore. This class exists so there is exactly one
/// place the token is written and exactly one thing to audit.
///
/// The Quick Connect secret is not here on purpose, and must not be added: it
/// lives in memory for one exchange and is never written to disk at all
/// (`docs/DECISIONS.md`, `docs/JELLYFIN-API.md`). "Secure storage" is still
/// storage.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  /// The key. Bare, because the store is app-private.
  static const _key = 'jellyfin_access_token';

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
