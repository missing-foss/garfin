// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';

/// The `Client`, `Device`, `DeviceId` and `Version` fields of the
/// `Authorization: MediaBrowser …` header.
///
/// Jellyfin keys a session on `DeviceId`, so it has to be stable across app
/// restarts or every launch registers a new device on the server's dashboard.
/// It is an identifier, not a credential — `shared_preferences` is the right
/// home for it. The access token is the credential, and it lives in
/// `flutter_secure_storage`; see `TokenStore`.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    this.client = appClientName,
    this.version = appVersion,
  });

  final String client;
  final String deviceName;
  final String deviceId;
  final String version;

  static const _deviceIdKey = 'device_id';

  /// Loads the persisted device id, generating one on first run.
  ///
  /// A reinstall *without a restore* wipes `shared_preferences` and so mints a
  /// fresh id, which is correct rather than unfortunate: the old session's
  /// token is gone with it, so reusing the id would only leave a stale device
  /// entry pointing at nothing.
  ///
  /// With a restore it is not fresh. Nothing declares `allowBackup`, so
  /// Android's default carries preferences to the user's cloud account and back
  /// — the id survives, while the token does not, because
  /// `flutter_secure_storage`'s master key lives in the Keystore and is not
  /// backed up. Harmless: Jellyfin simply sees the same device entry sign in
  /// again. Noted because this comment used to claim the opposite. See #35.
  static Future<DeviceIdentity> load(SharedPreferences prefs) async {
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = generateDeviceId();
      await prefs.setString(_deviceIdKey, id);
    }
    return DeviceIdentity(deviceId: id, deviceName: defaultDeviceName());
  }

  /// 128 bits of `Random.secure()` as hex.
  ///
  /// Not a credential, but it is the handle a server-side session hangs off, so
  /// it should not be guessable or collide between two phones in one house.
  static String generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// What the server lists this phone as.
  ///
  /// `Platform.operatingSystemVersion` is the most useful label available
  /// without pulling in `device_info_plus` — on Android it reads like
  /// "Android 14 (API 34)", which is enough to tell two devices apart in the
  /// Jellyfin dashboard. Header values are sanitised on the way out anyway
  /// (see `MediaBrowserAuthInterceptor`), but trim here too so the stored name
  /// is the one the user would recognise.
  static String defaultDeviceName() {
    final raw = Platform.operatingSystemVersion.trim();
    if (raw.isEmpty) return 'Android';
    return raw.length <= 64 ? raw : raw.substring(0, 64);
  }
}
