// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/authentication_result.dart';
import 'package:garfin/models/quick_connect.dart';
import 'package:garfin/repositories/auth_repository.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/quick_connect_session.dart';
import 'package:garfin/repositories/server_settings_store.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// `SECURITY.md` § Data at rest, made checkable (#19).
///
/// That section states three things: the access token goes to
/// `flutter_secure_storage` and never to `shared_preferences`; the Quick Connect
/// `Secret` never touches disk at all; and nothing that could carry a credential
/// is logged. Those were design commitments with the implementation tested
/// piecemeal around them.
///
/// This runs both real sign-in paths end to end and then sweeps **everything
/// they wrote or said** for the three credentials, rather than asserting about
/// the call sites one at a time. The difference matters: a future feature that
/// stores a credential somewhere nobody thought to check fails here, and would
/// pass a per-call-site test.
///
/// The log assertions read the records **before** `redactSecrets` runs.
/// Redaction is the backstop; the property worth holding is that the app never
/// hands a credential to the logger in the first place. `logging_test.dart`
/// covers the backstop separately.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Distinctive enough that a substring match means something, and
  // deliberately low-entropy english rather than realistic-looking credentials.
  // The first version used `QCSECRET-DA4C1F204EB7A91C`, which tripped gitleaks'
  // `generic-api-key` rule in CI — a high-entropy literal assigned to something
  // named `secret` is exactly what a secret scanner is for. A file whose whole
  // purpose is proving credentials do not escape should not need the scanner
  // silenced to live in the tree.
  const token = 'sentinel-access-token-must-never-be-stored-or-logged';
  const password = 'sentinel-password-must-never-be-stored-or-logged';
  const secret = 'sentinel-quick-connect-secret-must-never-touch-disk';
  const credentials = {token, password, secret};

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const serverUrl = 'http://host:8096';

  late Map<String, String> secureData;
  late SharedPreferences prefs;
  late FakeJellyfinServer server;
  late AuthRepository repository;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> logSub;

  setUp(() async {
    secureData = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(secureData);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();

    server = FakeJellyfinServer();
    repository = AuthRepository(
      apiFactory: JellyfinApiFactory(identity: identity, adapter: server),
      tokenStore: const SecureTokenStore(FlutterSecureStorage()),
      settings: ServerSettingsStore(prefs),
      birthYears: BirthYearStore(prefs),
    );

    // Everything, including `fine` — the Quick Connect poll logs at that level.
    records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    logSub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await logSub.cancel();
  });

  /// Every string the app wrote to preferences, keys included — a credential
  /// used as a *key* would be just as leaked as one used as a value.
  Iterable<String> prefsContents() sync* {
    for (final key in prefs.getKeys()) {
      yield key;
      yield '${prefs.get(key)}';
    }
  }

  Iterable<String> secureContents() sync* {
    for (final entry in secureData.entries) {
      yield entry.key;
      yield entry.value;
    }
  }

  /// Everything handed to the logger, pre-redaction.
  Iterable<String> loggedContents() sync* {
    for (final record in records) {
      yield record.message;
      if (record.error != null) yield '${record.error}';
      if (record.stackTrace != null) yield '${record.stackTrace}';
    }
  }

  void expectAbsent(Iterable<String> haystack, Set<String> needles, String where) {
    final joined = haystack.join('\x00');
    for (final needle in needles) {
      expect(
        joined,
        isNot(contains(needle)),
        reason: '$needle reached $where',
      );
    }
  }

  group('password sign-in', () {
    setUp(() async {
      server.on(
        '/Users/AuthenticateByName',
        json: authResultJson(token: token, name: 'Alex'),
      );
      await repository.signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: password,
      );
    });

    test('the access token is in secure storage, and only there', () {
      expect(secureData.values, contains(token),
          reason: 'the token must survive a restart, so it has to be stored');
      expectAbsent(prefsContents(), {token}, 'shared_preferences');
    });

    test('the password is stored nowhere at all', () {
      // It is a credential Garfin holds for the length of one request. There is
      // no reason for it to outlive that, in either store.
      expectAbsent(prefsContents(), {password}, 'shared_preferences');
      expectAbsent(secureContents(), {password}, 'flutter_secure_storage');
    });

    test('neither reaches the logger', () {
      expectAbsent(loggedContents(), {token, password}, 'the logger');
    });

    test('no credential is anywhere it should not be', () {
      // The whole rule in one assertion, over the whole surface. The tests
      // above name individual paths; this one is what catches a credential
      // landing somewhere nobody thought to name — add a fourth secret to
      // `credentials` and it is covered here for free.
      expectAbsent(prefsContents(), credentials, 'shared_preferences');
      expectAbsent(loggedContents(), credentials, 'the logger');
      expectAbsent(secureContents(), {password, secret},
          'flutter_secure_storage');
    });
  });

  group('quick connect', () {
    setUp(() async {
      server
        ..on('/QuickConnect/Initiate', json: {'Code': '123456', 'Secret': secret})
        ..on('/QuickConnect/Connect',
            failWith: DioExceptionType.connectionError)
        ..on('/QuickConnect/Connect', json: {'Authenticated': true})
        ..on('/Users/AuthenticateWithQuickConnect',
            json: authResultJson(token: token, name: 'Alex'));

      final session = QuickConnectSession(
        api: JellyfinApiFactory(identity: identity, adapter: server)
            .create(baseUrl: serverUrl),
        initialInterval: const Duration(milliseconds: 2),
        maxInterval: const Duration(milliseconds: 4),
        timeout: const Duration(milliseconds: 500),
      );
      final result = await session.run();
      await repository.completeSignIn(serverUrl: serverUrl, result: result);
    });

    test('the secret never touches disk, in either store', () {
      // docs/DECISIONS.md: it is a credential for one exchange and inert once
      // traded, so persisting it would only add a stale-credential-after-crash
      // case. "Secure storage" is still storage.
      expectAbsent(prefsContents(), {secret}, 'shared_preferences');
      expectAbsent(secureContents(), {secret}, 'flutter_secure_storage');
    });

    test('the secret never reaches the logger', () {
      // The failed poll in this flow logs at `fine` — that path exists, and it
      // is the one most likely to carry a URI with `?secret=` in it.
      expect(records.any((r) => r.level == Level.FINE), isTrue,
          reason: 'the tolerated-failure log path must actually have run');
      expectAbsent(loggedContents(), {secret}, 'the logger');
    });

    test('the token still lands in secure storage', () {
      expect(secureData.values, contains(token));
      expectAbsent(prefsContents(), {token}, 'shared_preferences');
    });

    test('no credential is anywhere it should not be', () {
      // The whole rule in one assertion, over the whole surface. The tests
      // above name individual paths; this one is what catches a credential
      // landing somewhere nobody thought to name — add a fourth secret to
      // `credentials` and it is covered here for free.
      expectAbsent(prefsContents(), credentials, 'shared_preferences');
      expectAbsent(loggedContents(), credentials, 'the logger');
      expectAbsent(secureContents(), {password, secret},
          'flutter_secure_storage');
    });
  });

  group('the crash path — what an uncaught object would print', () {
    test('no model puts a credential in toString()', () {
      // These end up in Riverpod state, in exception messages, and in whatever
      // an uncaught error handler prints. `toString()` is the crash path.
      final result = AuthenticationResult.fromJson(
        authResultJson(token: token, name: 'Alex'),
      );

      expect(result.toString(), isNot(contains(token)));
      expect(
        const QuickConnectInitiation(code: '123456', secret: secret).toString(),
        isNot(contains(secret)),
      );
      expect(
        const AuthSession(
          serverUrl: serverUrl,
          accessToken: token,
          userId: 'u1',
          userName: 'Alex',
        ).toString(),
        isNot(contains(token)),
      );
    });
  });
}
