// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/sign_in_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The address step and the password fallback, driven through the real
/// providers against a scripted server: what reaches the server, what the
/// screen is told, and what is adopted as the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const enabled = '/QuickConnect/Enabled';
  const authenticate = '/Users/AuthenticateByName';

  late FakeJellyfinServer server;

  Future<ProviderContainer> signedOut() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    server = FakeJellyfinServer();
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
    await c.read(authControllerProvider.future);
    // Kept alive, as the screen keeps it, for the length of the test.
    c.listen(signInControllerProvider, (_, _) {});
    return c;
  }

  SignInController controller(ProviderContainer c) => c.read(signInControllerProvider.notifier);
  SignInState state(ProviderContainer c) => c.read(signInControllerProvider);

  group('the address step', () {
    test('an address that cannot be parsed sends nothing anywhere', () async {
      final c = await signedOut();

      await controller(c).useServer('http://');

      expect(state(c).malformedUrl, isTrue);
      expect(state(c).serverUrl, isNull);
      expect(server.requests, isEmpty);
    });

    test('a server with Quick Connect on is accepted with the tab shown', () async {
      final c = await signedOut();
      server.on(enabled, json: true);

      await controller(c).useServer('host:8096');

      expect(server.requests.single.uri.toString(), startsWith('http://host:8096'));
      expect(state(c).serverUrl, 'http://host:8096');
      expect(state(c).quickConnectAvailable, isTrue);
      expect(state(c).busy, isFalse);
      expect(state(c).error, isNull);
    });

    test('a server with Quick Connect off is accepted without the tab', () async {
      final c = await signedOut();
      server.on(enabled, json: false);

      await controller(c).useServer('http://host:8096');

      expect(state(c).serverUrl, 'http://host:8096');
      expect(state(c).quickConnectAvailable, isFalse);
    });

    test('a Jellyfin too old to know Quick Connect is still accepted', () async {
      // A 404 from the endpoint means the server answered: it is reachable,
      // it just has no Quick Connect.
      final c = await signedOut();
      server.on(enabled, status: 404);

      await controller(c).useServer('http://host:8096');

      expect(state(c).serverUrl, 'http://host:8096');
      expect(state(c).quickConnectAvailable, isFalse);
      expect(state(c).error, isNull);
    });

    test('an unreachable server stays on the address step, named in the error', () async {
      final c = await signedOut();
      server.on(enabled, failWith: DioExceptionType.connectionError);

      await controller(c).useServer('http://host:8096');

      expect(state(c).serverUrl, isNull);
      expect(state(c).busy, isFalse);
      expect(state(c).error?.kind, JellyfinErrorKind.unreachable);
      expect(state(c).error?.detail, 'http://host:8096');
    });

    test('credentials typed into the address are dropped, and the screen is told', () async {
      final c = await signedOut();
      server.on(enabled, json: true);

      await controller(c).useServer('http://alex:secret@host:8096');

      expect(state(c).credentialsDropped, isTrue);
      expect(state(c).serverUrl, 'http://host:8096');
      final sent = server.requests.single;
      expect(sent.uri.userInfo, isEmpty);
      expect(sent.uri.toString(), isNot(contains('secret')));
    });

    test('changing server goes back to an empty address step', () async {
      final c = await signedOut();
      server.on(enabled, json: true);
      await controller(c).useServer('http://host:8096');

      controller(c).changeServer();

      expect(state(c).serverUrl, isNull);
      expect(state(c).quickConnectAvailable, isFalse);
    });
  });

  group('the password fallback', () {
    Map<String, dynamic> authenticated({required bool admin}) => <String, dynamic>{
          'AccessToken': 'token-new',
          'User': <String, dynamic>{
            'Id': 'admin-1',
            'Name': 'Alex',
            'Policy': <String, dynamic>{'IsAdministrator': admin, 'IsDisabled': false},
          },
        };

    Future<ProviderContainer> onPasswordStep() async {
      final c = await signedOut();
      server.on(enabled, json: false);
      await controller(c).useServer('http://host:8096');
      return c;
    }

    test('before an address is accepted it does nothing', () async {
      final c = await signedOut();

      await controller(c).signInWithPassword(username: 'Alex', password: 'pw');

      expect(server.requests, isEmpty);
    });

    test('an administrator is signed in and the session adopted', () async {
      final c = await onPasswordStep();
      server.on(authenticate, json: authenticated(admin: true));

      await controller(c).signInWithPassword(username: 'Alex', password: 'pw');

      final sent = server.requests.lastWhere((r) => r.path == authenticate);
      expect(sent.data, {'Username': 'Alex', 'Pw': 'pw'});
      expect(state(c).busy, isFalse);
      expect(state(c).error, isNull);
      final auth = c.read(authControllerProvider).value;
      expect(auth, isA<AuthSignedIn>());
      expect((auth! as AuthSignedIn).session.userId, 'admin-1');
    });

    test('an account that is not an administrator is refused and nothing adopted', () async {
      final c = await onPasswordStep();
      server.on(authenticate, json: authenticated(admin: false));

      await controller(c).signInWithPassword(username: 'Alex', password: 'pw');

      expect(state(c).error?.kind, JellyfinErrorKind.notAdministrator);
      expect(state(c).busy, isFalse);
      expect(c.read(authControllerProvider).value, isNot(isA<AuthSignedIn>()));
    });

    test('a wrong password is reported, not adopted', () async {
      final c = await onPasswordStep();
      server.on(authenticate, status: 401);

      await controller(c).signInWithPassword(username: 'Alex', password: 'wrong');

      expect(state(c).error?.kind, JellyfinErrorKind.unauthorized);
      expect(c.read(authControllerProvider).value, isNot(isA<AuthSignedIn>()));
    });
  });
}
