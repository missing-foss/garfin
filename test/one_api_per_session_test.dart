// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/assign_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/media_browser_auth.dart' show TokenReader;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Counts the APIs it makes. Each one owns a `Dio`, and each `Dio` its own
/// connection pool to the server.
class _CountingFactory extends JellyfinApiFactory {
  _CountingFactory({required super.identity, super.adapter});

  int made = 0;

  @override
  JellyfinApi create({required String baseUrl, TokenReader? readToken}) {
    made++;
    return super.create(baseUrl: baseUrl, readToken: readToken);
  }
}

/// One session, one API: every repository and lookup for a session goes
/// through `libraryApiProvider`, so the app holds one connection pool to the
/// server rather than one per caller, and one per child.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  test("every repository and lookup of a session shares one API", () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final server = FakeJellyfinServer()..fallback(json: <String, dynamic>{'Items': <Object>[]});
    final factory = _CountingFactory(
      identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      adapter: server,
    );
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      deviceIdentityProvider.overrideWithValue(const DeviceIdentity(deviceId: 'd', deviceName: 't')),
      jellyfinApiFactoryProvider.overrideWithValue(factory),
    ]);
    addTearDown(container.dispose);

    container.read(libraryApiProvider(session));
    container.read(libraryRepositoryProvider(session));
    container.read(collectionRepositoryProvider(session));
    container.read(assignRepositoryProvider(session));
    container.read(kidsRepositoryProvider(session));
    // The lookups and the per-child lists: these used to make one each, and
    // the child lists one per child.
    final subs = [
      container.listen(parentalRatingLadderProvider(session), (_, _) {}),
      container.listen(countriesProvider(session), (_, _) {}),
      for (final child in ['kid-1', 'kid-2']) ...[
        container.listen(childLibrariesProvider(ChildLibrariesRequest(session: session, childId: child)), (_, _) {}),
        // The counts too: the other per-child provider, which also made one each.
        container.listen(childLibraryCountsProvider(ChildLibrariesRequest(session: session, childId: child)), (_, _) {}),
      ],
    ];
    addTearDown(() {
      for (final sub in subs) {
        sub.close();
      }
    });
    // The counts wait for the lists before they make their requests.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(factory.made, 1);
  });
}
