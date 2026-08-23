// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/auth_repository.dart';
import '../repositories/birth_year_store.dart';
import '../repositories/device_identity.dart';
import '../repositories/jellyfin_api.dart';
import '../repositories/server_settings_store.dart';
import '../repositories/token_store.dart';

/// The platform singletons, resolved once in `main` and injected here.
///
/// Both throw if read without an override. That is deliberate: they need async
/// setup before the first frame, and a provider that quietly built its own
/// instance would give a test a *second* `SharedPreferences` and make a
/// storage assertion pass against a store the app never used.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'override sharedPreferencesProvider in main() or in the test',
  ),
);

final deviceIdentityProvider = Provider<DeviceIdentity>(
  (ref) => throw UnimplementedError(
    'override deviceIdentityProvider in main() or in the test',
  ),
);

/// Where the access token goes. Nothing else in the app constructs a
/// `FlutterSecureStorage`.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => SecureTokenStore(ref.watch(secureStorageProvider)),
);

final birthYearStoreProvider = Provider<BirthYearStore>(
  (ref) => BirthYearStore(ref.watch(sharedPreferencesProvider)),
);

final serverSettingsStoreProvider = Provider<ServerSettingsStore>(
  (ref) => ServerSettingsStore(ref.watch(sharedPreferencesProvider)),
);

final jellyfinApiFactoryProvider = Provider<JellyfinApiFactory>(
  (ref) => JellyfinApiFactory(identity: ref.watch(deviceIdentityProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    apiFactory: ref.watch(jellyfinApiFactoryProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    settings: ref.watch(serverSettingsStoreProvider),
    birthYears: ref.watch(birthYearStoreProvider),
  ),
);
