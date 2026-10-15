// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

/// The access token's only home.
///
/// `docs/ENGINEERING.md` § Stack: settings go in `shared_preferences`, the access token
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

/// Logs whether what the store held survived a major upgrade of the plugin.
///
/// `flutter_secure_storage` 11 can no longer read data written with the
/// algorithms it removed, and a loss would otherwise look like nothing more
/// than a parent who has to sign in again. This makes it a log line instead of
/// a mystery. Garfin has only ever written with v10's defaults (RSA-OAEP key,
/// AES-GCM storage), which v11 kept, so the expected answer is `ok`.
///
/// Read-only, and called from `main` before anything reads the store, which is
/// what the plugin asks for. A loss is logged at WARNING so it survives the
/// release log level; an intact store is INFO. The platform's `details` text
/// goes through the logger's `redactSecrets` like every other record.
///
/// Never throws: a check that could stop the app starting would be worse than
/// the loss it reports.
Future<SecureStorageUpgradeStatus?> logSecureStorageUpgradeStatus(
  FlutterSecureStorage storage,
  Logger log,
) async {
  try {
    final status = await storage.checkUpgradeStatus();
    if (status.hasDataLoss) {
      log.warning('Secure storage lost data in an upgrade: $status');
    } else {
      log.info('Secure storage upgrade check: $status');
    }
    return status;
  } on Object catch (e) {
    // The type, never the message: as at every other log site, an
    // exception's text is not something this app vouches for.
    log.warning('Secure storage upgrade check failed: ${e.runtimeType}');
    return null;
  }
}
