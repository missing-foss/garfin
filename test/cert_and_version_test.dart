// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/server_version.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/repositories/auth_repository.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/repositories/server_settings_store.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:garfin/widgets/error_notice.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Two things a self-hosted server can be that Garfin should name.
///
/// **A certificate the phone does not trust** used to read as "can't reach the
/// server", with the real cause only in the small diagnostic line. It is its
/// own error now, saying what to do — and there is no switch to trust it.
///
/// **A version nobody measured** signs in as before, but the log says so at
/// the top, so a report from it says so too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serverUrl = 'http://host:8096';
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  late FakeJellyfinServer server;
  setUp(() => server = FakeJellyfinServer());

  group('an untrusted certificate', () {
    test('is its own kind, not "unreachable"', () async {
      server.onQuery('/Users/Me', (_) => true,
          failWith: DioExceptionType.badCertificate);
      final api = JellyfinApiFactory(identity: identity, adapter: server)
          .create(baseUrl: 'https://host', readToken: () => 'token');

      await expectLater(
        api.currentUser(),
        throwsA(isA<JellyfinException>().having(
            (e) => e.kind, 'kind', JellyfinErrorKind.untrustedCertificate)),
      );
    });

    test('says what to do about it', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final text = jellyfinErrorText(
        l10n,
        const JellyfinException(JellyfinErrorKind.untrustedCertificate),
      );
      expect(text, contains('http://'));
      expect(text, contains('certificate'));
    });

    test('keeps a stored session signed in, and says so', () async {
      FlutterSecureStorage.setMockInitialValues(
        <String, String>{'jellyfin_access_token': 'token-abc'},
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'server_url': serverUrl,
        'user_id': 'admin-1',
        'user_name': 'Alex',
      });
      final prefs = await SharedPreferences.getInstance();
      server.onQuery('/Users/Me', (_) => true,
          failWith: DioExceptionType.badCertificate);
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceIdentityProvider.overrideWithValue(identity),
          jellyfinApiFactoryProvider.overrideWithValue(
            JellyfinApiFactory(identity: identity, adapter: server),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(authControllerProvider.future);
      await pumpEventQueue();

      final state = c.read(authControllerProvider).value;
      expect(state, isA<AuthSignedIn>());
      expect((state! as AuthSignedIn).offlineReason?.kind,
          JellyfinErrorKind.untrustedCertificate);
    });
  });

  group('the server version', () {
    test('what counts as measured', () {
      expect(isTestedServerVersion('10.11.11'), isTrue);
      expect(isTestedServerVersion('10.11.0'), isTrue);
      expect(isTestedServerVersion('12.0.0'), isTrue);
      expect(isTestedServerVersion('12.1.3'), isTrue);
      expect(isTestedServerVersion('10.10.7'), isFalse);
      expect(isTestedServerVersion('13.0.0'), isFalse);
      expect(isTestedServerVersion('not a version'), isNull,
          reason: 'unknown, which says nothing');
      expect(isTestedServerVersion(null), isNull);
    });

    Future<List<LogRecord>> signInTo(String version) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      server
        ..on('/Users/AuthenticateByName', json: authResultJson())
        ..onQuery('/System/Info/Public', (_) => true,
            json: <String, dynamic>{'Version': version});
      final repository = AuthRepository(
        apiFactory: JellyfinApiFactory(identity: identity, adapter: server),
        tokenStore: const SecureTokenStore(FlutterSecureStorage()),
        settings: ServerSettingsStore(prefs),
        birthYears: BirthYearStore(prefs),
      );
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(sub.cancel);

      final session = await repository.signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: 'pw',
      );
      expect(session.accessToken, isNotEmpty, reason: 'never a gate');
      await pumpEventQueue();
      return records;
    }

    bool warnsAboutVersion(List<LogRecord> records) => records.any((r) =>
        r.level == Level.WARNING && r.message.contains('outside the tested'));

    test('an untested version signs in, with a warning in the log', () async {
      expect(warnsAboutVersion(await signInTo('10.10.7')), isTrue);
    });

    test('a slow version endpoint does not hold the sign-in up', () async {
      // The read is a note for the log, so a sign-in never waits on it.
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      server
        ..on('/Users/AuthenticateByName', json: authResultJson())
        ..onQuery('/System/Info/Public', (_) => true,
            json: <String, dynamic>{'Version': '10.10.7'},
            delay: const Duration(seconds: 3));
      final repository = AuthRepository(
        apiFactory: JellyfinApiFactory(identity: identity, adapter: server),
        tokenStore: const SecureTokenStore(FlutterSecureStorage()),
        settings: ServerSettingsStore(prefs),
        birthYears: BirthYearStore(prefs),
      );

      final watch = Stopwatch()..start();
      await repository.signInWithPassword(
        serverUrl: serverUrl,
        username: 'alex',
        password: 'pw',
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(prefs.getString('user_id'), isNotNull,
          reason: 'the session is stored before the version is known');
      // Let the slow read finish before the test ends.
      await Future<void>.delayed(const Duration(seconds: 4));
    });

    test('a measured one, without', () async {
      expect(warnsAboutVersion(await signInTo('10.11.11')), isFalse);
    });
  });
}
