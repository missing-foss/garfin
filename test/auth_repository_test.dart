// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/repositories/auth_repository.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/repositories/server_settings_store.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// These are ground-rule tests, not behaviour tests. Ground rule 7 (admin only)
/// and the storage split (token in `flutter_secure_storage`, never in
/// `shared_preferences`) are the two things about sign-in that cause real harm
/// when they go wrong, so they are asserted against the real stores rather than
/// against a mock that would agree with whatever the code did.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const serverUrl = 'http://host:8096';

  late Map<String, String> secureData;
  late FakeJellyfinServer server;
  late SharedPreferences prefs;
  late AuthRepository repository;

  Future<void> setUpRepository() async {
    secureData = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(secureData);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();

    server = FakeJellyfinServer();
    repository = AuthRepository(
      apiFactory: JellyfinApiFactory(identity: identity, adapter: server),
      tokenStore: const SecureTokenStore(FlutterSecureStorage()),
      settings: ServerSettingsStore(prefs),
    );
  }

  setUp(setUpRepository);

  group('ground rule 7 — administrator required', () {
    test('a non-admin account is refused, and nothing is written down',
        () async {
      server.on(
        '/Users/AuthenticateByName',
        json: authResultJson(
          token: 'token-for-a-child',
          name: 'Emma',
          isAdministrator: false,
        ),
      );

      await expectLater(
        repository.signInWithPassword(
          serverUrl: serverUrl,
          username: 'emma',
          password: 'hunter2',
        ),
        throwsA(
          isA<JellyfinException>()
              .having((e) => e.kind, 'kind',
                  JellyfinErrorKind.notAdministrator)
              // The name goes into the message so the refusal names the account
              // that was refused, rather than reading as a generic failure.
              .having((e) => e.detail, 'detail', 'Emma'),
        ),
      );

      // The refusal happens at sign-in, before anything is persisted. If the
      // token were written first and cleaned up afterwards, a crash in between
      // would leave the next launch restoring a session Garfin cannot use.
      expect(secureData, isEmpty);
      expect(prefs.getKeys(), isNot(contains('user_id')));
      expect(
        prefs.getKeys().any((k) => prefs.get(k) == 'token-for-a-child'),
        isFalse,
      );
    });

    test('an admin account is accepted and the session is stored', () async {
      server.on(
        '/Users/AuthenticateByName',
        json: authResultJson(token: 'token-abc', name: 'Alex'),
      );

      final session = await repository.signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: 'hunter2',
      );

      expect(session.userName, 'Alex');
      expect(session.accessToken, 'token-abc');
      expect(prefs.getString('server_url'), serverUrl);
      expect(prefs.getString('user_name'), 'Alex');
    });

    test('a session restored from storage is re-checked, and a demoted '
        'account is signed out', () async {
      server.on('/Users/Me', json: userJson(isAdministrator: false));

      await expectLater(
        repository.verify(
          await _storedSession(repository, prefs, serverUrl),
        ),
        throwsA(
          isA<JellyfinException>().having(
            (e) => e.kind,
            'kind',
            JellyfinErrorKind.notAdministrator,
          ),
        ),
      );
    });
  });

  group('token storage', () {
    test('the access token goes to secure storage and never to preferences',
        () async {
      server.on(
        '/Users/AuthenticateByName',
        json: authResultJson(token: 'token-abc'),
      );

      await repository.signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: 'hunter2',
      );

      expect(secureData.values, contains('token-abc'));
      // `CLAUDE.md` § Stack. The whole point of the split is that this stays
      // true no matter what else the sign-in path grows.
      for (final key in prefs.getKeys()) {
        expect(prefs.get(key).toString(), isNot(contains('token-abc')));
      }
    });

    test('signing out drops the token but keeps the server address', () async {
      server.on('/Users/AuthenticateByName', json: authResultJson());
      await repository.signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: 'hunter2',
      );

      await repository.signOut();

      expect(secureData, isEmpty);
      expect(prefs.getString('user_name'), isNull);
      // The address belongs to the household, not to the session — retyping it
      // after every sign-out would be a small daily annoyance for no gain.
      expect(prefs.getString('server_url'), serverUrl);
    });
  });

  group('offline-degraded restore', () {
    test('restores without touching the network', () async {
      server.on('/Users/AuthenticateByName', json: authResultJson());
      await repository.signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: 'hunter2',
      );
      final callsAfterSignIn = server.requests.length;

      final restored = await repository.restore();

      expect(restored, isNotNull);
      expect(restored!.userName, 'Alex');
      // A cold start with no route to the server still knows who is signed in.
      // Anything else is a blank screen or a spurious sign-out, both of which
      // the definition of done rules out.
      expect(server.requests, hasLength(callsAfterSignIn));
    });

    test('restores nothing when there is no stored token', () async {
      await prefs.setString('server_url', serverUrl);

      expect(await repository.restore(), isNull);
    });
  });

  group('server probe', () {
    test('reports Quick Connect as off rather than failing', () async {
      server.on('/QuickConnect/Enabled', json: false);

      expect(await repository.quickConnectEnabled(serverUrl), isFalse);
    });

    test('an unreachable server surfaces as unreachable', () async {
      server.on(
        '/QuickConnect/Enabled',
        failWith: DioExceptionType.connectionError,
      );

      await expectLater(
        repository.quickConnectEnabled(serverUrl),
        throwsA(
          isA<JellyfinException>().having(
            (e) => e.kind,
            'kind',
            JellyfinErrorKind.unreachable,
          ),
        ),
      );
    });
  });
}

/// Plants a stored session the way a previous launch would have left one.
Future<AuthSession> _storedSession(
  AuthRepository repository,
  SharedPreferences prefs,
  String serverUrl,
) async {
  await prefs.setString('server_url', serverUrl);
  await const SecureTokenStore(FlutterSecureStorage()).write('token-abc');
  final session = await repository.restore();
  return session!;
}
