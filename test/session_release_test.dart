// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/providers/session_release.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// A session's caches are released when the session ends, and not before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serverUrl = 'http://host:8096';
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const me = '/Users/Me';
  const logout = '/Sessions/Logout';

  late FakeJellyfinServer server;

  Future<ProviderContainer> launched() async {
    FlutterSecureStorage.setMockInitialValues(
      <String, String>{'jellyfin_access_token': 'token-abc'},
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': serverUrl,
      'user_id': 'admin-1',
      'user_name': 'Alex',
    });
    final prefs = await SharedPreferences.getInstance();
    server = FakeJellyfinServer()
      ..onQuery(me, (_) => true, json: <String, dynamic>{
        'Id': 'admin-1',
        'Name': 'Alex',
        'Policy': <String, dynamic>{'IsAdministrator': true, 'IsDisabled': false},
      })
      ..onQuery(logout, (_) => true, status: 204);
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWith(
          (ref) => JellyfinApiFactory(
            identity: identity,
            adapter: server,
            signals: ref.watch(sessionSignalsProvider),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    // What the app root does: keep the release listening for the app's life.
    c.listen(sessionReleaseProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    return c;
  }

  AuthSession sessionOf(ProviderContainer c) =>
      (c.read(authControllerProvider).value! as AuthSignedIn).session;

  test('signing out removes what the session cached', () async {
    final c = await launched();
    final session = sessionOf(c);
    c.read(libraryApiProvider(session));
    c.read(kidsRepositoryProvider(session));
    expect(c.exists(libraryApiProvider(session)), isTrue);

    await c.read(authControllerProvider.notifier).signOut();
    await pumpEventQueue();

    expect(c.read(authControllerProvider).value, isA<AuthSignedOut>());
    expect(c.exists(libraryApiProvider(session)), isFalse,
        reason: 'nothing will read the old session again');
    expect(c.exists(kidsRepositoryProvider(session)), isFalse);
  });

  test('the server confirming the session releases nothing', () async {
    // The launch restores the session unverified, then confirms it: the same
    // session, so an entry read before the confirmation must survive it.
    final c = await launched();
    final session = sessionOf(c);
    expect((c.read(authControllerProvider).value! as AuthSignedIn).verified,
        isFalse,
        reason: 'the read below must come before the confirmation');
    c.read(libraryApiProvider(session));

    await pumpEventQueue();

    final state = c.read(authControllerProvider).value! as AuthSignedIn;
    expect(state.verified, isTrue, reason: 'the confirmation happened');
    expect(state.session, session);
    expect(c.exists(libraryApiProvider(session)), isTrue);
  });

  test('every session-keyed family is listed, autoDispose and kept alive', () {
    // Read from source, so a family added later cannot be forgotten here.
    final listed = File('lib/providers/session_release.dart').readAsStringSync();
    final family = RegExp(
      r'^final (\w+)\s*=\s*(\w*Provider)(\.autoDispose)?\.family<',
      multiLine: true,
    );
    final found = <String>[];
    for (final file in Directory('lib/providers').listSync().whereType<File>()) {
      final source = file.readAsStringSync();
      for (final m in family.allMatches(source)) {
        final name = m.group(1)!;
        found.add(name);
        expect(m.group(3), isNotNull, reason: '$name is not autoDispose');
        expect(RegExp('\\b$name,').hasMatch(listed), isTrue,
            reason: '$name is missing from perSessionFamilies');
        final body = source.substring(m.end);
        final next = family.firstMatch(body);
        final own = next == null ? body : body.substring(0, next.start);
        final keeps = m.group(2) == 'AsyncNotifierProvider'
            ? source.contains('ref.keepAlive(); // released when the session ends')
            : own.contains('ref.keepAlive();');
        expect(keeps, isTrue, reason: '$name does not keep itself alive');
      }
    }
    expect(found, hasLength(perSessionFamilies.length),
        reason: 'the list and the families agree in number');
  });
}
