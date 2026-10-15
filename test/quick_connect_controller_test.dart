// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

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

/// One Quick Connect pairing at a time, through the real providers against a
/// scripted server: what the screen is shown, what is adopted, and that a
/// pairing nobody is waiting for any more stops asking.
///
/// The session underneath is `quick_connect_session_test`'s; this is the
/// controller on top of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const serverUrl = 'http://host:8096';
  const initiate = '/QuickConnect/Initiate';
  const connect = '/QuickConnect/Connect';
  const authenticate = '/Users/AuthenticateWithQuickConnect';

  Map<String, dynamic> authenticated({required bool admin}) => <String, dynamic>{
        'AccessToken': 'token-qc',
        'User': <String, dynamic>{
          'Id': 'admin-1',
          'Name': 'Alex',
          'Policy': <String, dynamic>{'IsAdministrator': admin, 'IsDisabled': false},
        },
      };

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
    return c;
  }

  /// Every state the screen would have been shown, in order.
  List<QuickConnectState> watch(ProviderContainer c) {
    final seen = <QuickConnectState>[];
    c.listen(quickConnectControllerProvider, (_, next) => seen.add(next));
    return seen;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue, reason: 'timed out waiting');
  }

  test('an approved pairing shows its code, succeeds and is adopted', () async {
    final c = await signedOut();
    server
      ..on(initiate, json: {'Code': '123456', 'Secret': 's-1'})
      ..on(connect, json: {'Authenticated': true})
      ..on(authenticate, json: authenticated(admin: true));
    final seen = watch(c);

    await c.read(quickConnectControllerProvider.notifier).start(serverUrl);

    expect(seen.map((s) => s.runtimeType), [
      QuickConnectStarting,
      QuickConnectWaiting,
      QuickConnectSucceeded,
    ]);
    expect((seen[1] as QuickConnectWaiting).code, '123456');
    final auth = c.read(authControllerProvider).value;
    expect(auth, isA<AuthSignedIn>());
    expect((auth! as AuthSignedIn).session.userId, 'admin-1');
  });

  test('an approval by an account that is not an administrator fails and adopts nothing', () async {
    final c = await signedOut();
    server
      ..on(initiate, json: {'Code': '123456', 'Secret': 's-1'})
      ..on(connect, json: {'Authenticated': true})
      ..on(authenticate, json: authenticated(admin: false));
    final seen = watch(c);

    await c.read(quickConnectControllerProvider.notifier).start(serverUrl);

    final last = seen.last;
    expect(last, isA<QuickConnectFailed>());
    expect((last as QuickConnectFailed).error.kind, JellyfinErrorKind.notAdministrator);
    expect(c.read(authControllerProvider).value, isNot(isA<AuthSignedIn>()));
  });

  test('a server that has switched Quick Connect off is a failure the screen shows', () async {
    final c = await signedOut();
    server.on(initiate, status: 401);
    final seen = watch(c);

    await c.read(quickConnectControllerProvider.notifier).start(serverUrl);

    expect(seen.last, isA<QuickConnectFailed>());
  });

  test('leaving the screen stops the polling, so the secret is not kept alive', () async {
    final c = await signedOut();
    server
      ..on(initiate, json: {'Code': '123456', 'Secret': 's-1'})
      ..on(connect, json: {'Authenticated': false});
    final sub = c.listen(quickConnectControllerProvider, (_, _) {});

    final run = c.read(quickConnectControllerProvider.notifier).start(serverUrl);
    await until(() => c.read(quickConnectControllerProvider) is QuickConnectWaiting);
    await until(() => server.callsTo(connect) >= 1);

    // The screen is popped: nothing listens, the autoDispose provider goes,
    // and with it the session. Its run then ends at once, cancelled; a session
    // left alive would go on sleeping and polling for its whole three minutes.
    sub.close();
    final ended = await run
        .then((_) => true)
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
    expect(ended, isTrue, reason: 'the pairing outlived the screen');

    final polls = server.callsTo(connect);
    // Longer than the first backoff interval (1 s): a live session would poll.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(server.callsTo(connect), polls);
  });

  test('starting again abandons the first pairing without it overwriting the second', () async {
    final c = await signedOut();
    server
      ..on(initiate, json: {'Code': '111111', 'Secret': 's-1'})
      // Slow, so the first pairing's cancellation lands while the second is
      // still starting: the moment its ending could reach the screen.
      ..on(initiate,
          json: {'Code': '222222', 'Secret': 's-2'}, delay: const Duration(milliseconds: 300))
      ..on(connect, json: {'Authenticated': false});
    final seen = <QuickConnectState>[];
    c.listen(quickConnectControllerProvider, (_, next) => seen.add(next));
    final controller = c.read(quickConnectControllerProvider.notifier);

    final first = controller.start(serverUrl);
    await until(() => switch (c.read(quickConnectControllerProvider)) {
          QuickConnectWaiting(:final code) => code == '111111',
          _ => false,
        });

    final restartedAt = seen.length;
    unawaited(controller.start(serverUrl));
    await until(() => switch (c.read(quickConnectControllerProvider)) {
          QuickConnectWaiting(:final code) => code == '222222',
          _ => false,
        });

    // The first run ends cancelled; its ending must not reach the screen, not
    // even for a frame before the second code replaces it.
    await first.timeout(const Duration(seconds: 5), onTimeout: () {});
    expect(seen.skip(restartedAt).whereType<QuickConnectFailed>(), isEmpty);
    final now = c.read(quickConnectControllerProvider);
    expect(now, isA<QuickConnectWaiting>());
    expect((now as QuickConnectWaiting).code, '222222');
  });
}

