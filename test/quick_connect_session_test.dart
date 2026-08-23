// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/repositories/auth_repository.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/repositories/quick_connect_session.dart';
import 'package:garfin/repositories/server_settings_store.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The Quick Connect `Secret` is a credential that must never be written to
/// disk, and the poll must not hammer the server. Both are stated rules
/// (`docs/JELLYFIN-API.md`, `docs/DECISIONS.md`, issue #17) and both fail
/// quietly, so they are tested rather than asserted in a comment.
///
/// The intervals here are milliseconds rather than the production seconds. The
/// schedule under test is the *shape* — grows, is capped, resets on a poke —
/// which is scale-free.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const secret = 'secret-value-do-not-persist';

  JellyfinApi apiFor(FakeJellyfinServer server) =>
      JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: 'http://host:8096');

  QuickConnectSession sessionFor(
    FakeJellyfinServer server, {
    Duration timeout = const Duration(milliseconds: 500),
  }) =>
      QuickConnectSession(
        api: apiFor(server),
        timeout: timeout,
        initialInterval: const Duration(milliseconds: 2),
        maxInterval: const Duration(milliseconds: 8),
      );

  test('polls until the code is approved, then trades the secret', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..on('/QuickConnect/Connect', json: {'Authenticated': false})
      ..on('/QuickConnect/Connect', json: {'Authenticated': false})
      ..on('/QuickConnect/Connect', json: {'Authenticated': true})
      ..on('/Users/AuthenticateWithQuickConnect', json: authResultJson());

    final session = sessionFor(server);
    String? seenCode;

    final result = await session.run(onCode: (code) => seenCode = code);

    expect(seenCode, '123456');
    expect(result.user.name, 'Alex');
    expect(server.callsTo('/QuickConnect/Connect'), 3);
  });

  test('the secret is sent as a query value and never as a stored one',
      () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..on('/QuickConnect/Connect', json: {'Authenticated': true})
      ..on('/Users/AuthenticateWithQuickConnect', json: authResultJson());

    final secureData = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(secureData);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final repository = AuthRepository(
      apiFactory: JellyfinApiFactory(identity: identity, adapter: server),
      tokenStore: const SecureTokenStore(FlutterSecureStorage()),
      settings: ServerSettingsStore(prefs),
      birthYears: BirthYearStore(prefs),
    );

    final session = sessionFor(server);
    final result = await session.run();
    await repository.completeSignIn(
      serverUrl: 'http://host:8096',
      result: result,
    );

    // Not in secure storage, which is the tempting place to put it, and not in
    // preferences either. "Secure storage" is still storage: persisting the
    // secret would only create a stale-credential-after-crash case that
    // memory-only cannot have.
    expect(secureData.values, isNot(contains(secret)));
    for (final key in prefs.getKeys()) {
      expect(prefs.get(key).toString(), isNot(contains(secret)));
    }
  });

  test('the secret is dropped once the exchange succeeds', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..on('/QuickConnect/Connect', json: {'Authenticated': true})
      ..on('/Users/AuthenticateWithQuickConnect', json: authResultJson());

    final session = sessionFor(server);
    await session.run();

    // Nothing holds it afterwards. Dart strings are immutable so this is
    // "dropped the reference", not "overwrote the bytes" — which is why the
    // secret is never handed to anyone else in the first place.
    expect(session.code, '123456');
    expect(session.holdsSecret, isFalse);
  });

  test('the secret is dropped when the code expires', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..fallback(json: {'Authenticated': false});

    final session = sessionFor(server, timeout: const Duration(milliseconds: 30));

    await expectLater(
      session.run(),
      throwsA(
        isA<JellyfinException>().having(
          (e) => e.kind,
          'kind',
          JellyfinErrorKind.quickConnectExpired,
        ),
      ),
    );
    expect(session.holdsSecret, isFalse);
  });

  test('the secret is dropped on dispose, mid-pairing', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..fallback(json: {'Authenticated': false});

    final session = sessionFor(server, timeout: const Duration(seconds: 30));
    final pending = expectLater(
      session.run(),
      throwsA(
        isA<JellyfinException>()
            .having((e) => e.kind, 'kind', JellyfinErrorKind.cancelled),
      ),
    );

    // Let the pairing get as far as holding a secret, then close the screen.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    session.dispose();

    await pending;
    expect(session.holdsSecret, isFalse);
  });

  test('backs off between polls and stops growing at the cap', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..fallback(json: {'Authenticated': false});

    final session = QuickConnectSession(
      api: apiFor(server),
      timeout: const Duration(milliseconds: 260),
      initialInterval: const Duration(milliseconds: 10),
      maxInterval: const Duration(milliseconds: 40),
      backoffFactor: 2,
    );

    await _settle(session.run());

    // Flat 10ms polling over 260ms would be ~26 calls. The backoff schedule is
    // 10, 20, 40, 40, … so it lands far below that. The bound is loose on
    // purpose — this asserts "does not hammer", not a precise clock.
    final calls = server.callsTo('/QuickConnect/Connect');
    expect(calls, greaterThan(2));
    expect(calls, lessThan(15));
  });

  test('a poke cuts the wait short, so a resume is answered quickly', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..fallback(json: {'Authenticated': false});

    // A long first interval: without a poke, only the very first poll happens
    // inside the window this test waits for.
    final session = QuickConnectSession(
      api: apiFor(server),
      timeout: const Duration(seconds: 30),
      initialInterval: const Duration(seconds: 5),
      maxInterval: const Duration(seconds: 5),
    );
    unawaited(_settle(session.run()));

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(server.callsTo('/QuickConnect/Connect'), 1);

    // The app came back to the foreground — the user has probably just approved
    // the code, so ask now rather than in five seconds.
    session.poke();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(server.callsTo('/QuickConnect/Connect'), greaterThan(1));

    session.dispose();
  });

  test('a dropped connection keeps the pairing alive', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..on('/QuickConnect/Connect',
          failWith: DioExceptionType.connectionError)
      ..on('/QuickConnect/Connect', json: {'Authenticated': true})
      ..on('/Users/AuthenticateWithQuickConnect', json: authResultJson());

    // Backgrounding mid-pairing is the normal path, and a phone that has been
    // in a pocket may lose the network on the way. One failed poll is not an
    // answer, so it must not end the pairing.
    final result = await sessionFor(server).run();

    expect(result.user.name, 'Alex');
  });

  test('starts the pairing with a POST, which is the documented route',
      () async {
    // Measured on 10.11.11: the server's own openapi.json lists only `post` for
    // /QuickConnect/Initiate. The GET this project's docs used to specify still
    // answers 200 today, which is precisely why a wrong method here would not
    // show up until the version that finally removes it.
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..on('/QuickConnect/Connect', json: {'Authenticated': true})
      ..on('/Users/AuthenticateWithQuickConnect', json: authResultJson());

    await sessionFor(server).run();

    final initiate = server.requests
        .firstWhere((r) => r.path == '/QuickConnect/Initiate');
    expect(initiate.method, 'POST');
  });

  test('Quick Connect being switched off mid-pairing says so, not "wrong '
      'password"', () async {
    // Measured: every /QuickConnect/* route answers 401 "Quick connect is
    // disabled" when the feature is off. Left as a plain 401 the user would be
    // told their password was wrong, and would go and change a password that
    // was never involved.
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..on('/QuickConnect/Connect', json: <String, dynamic>{}, status: 401);

    await expectLater(
      sessionFor(server).run(),
      throwsA(
        isA<JellyfinException>().having(
          (e) => e.kind,
          'kind',
          JellyfinErrorKind.quickConnectUnavailable,
        ),
      ),
    );
  });

  test('a rejected poll does end the pairing', () async {
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': secret})
      ..on('/QuickConnect/Connect', json: <String, dynamic>{}, status: 404);

    // A 404 is the server saying it has forgotten this secret. That *is* an
    // answer, and the user needs to hear it rather than watch a bar for three
    // more minutes.
    await expectLater(
      sessionFor(server).run(),
      throwsA(
        isA<JellyfinException>().having(
          (e) => e.kind,
          'kind',
          JellyfinErrorKind.quickConnectExpired,
        ),
      ),
    );
  });
}

/// Runs a pairing to whatever end it reaches and swallows the failure.
///
/// Several tests here are about what happened *along the way* — how many polls
/// went out, whether the secret was dropped — and the pairing's own outcome is
/// an expiry or a cancellation that has already been asserted elsewhere.
Future<void> _settle(Future<Object?> future) async {
  try {
    await future;
  } on JellyfinException {
    // Expected: these pairings are meant to end without an access token.
  }
}
