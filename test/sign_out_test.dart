// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/repositories/birth_year_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/repositories/auth_repository.dart';
import 'package:garfin/repositories/server_settings_store.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:garfin/screens/settings_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Signing out ends the sign-in on the server, not only on this phone, and is
/// asked before it happens.
///
/// **The reported failure.** Sign-out cleared local storage and nothing else.
/// A Jellyfin token does not expire, the default address is plain `http://`,
/// and the token rides on every request — so one that was ever observed kept
/// working after the parent signed out. And the Settings row did it on a
/// plain tap, among rows a parent taps freely.
///
/// Measured on 10.11.11 and 12.1: `POST /Sessions/Logout` answers 204 and the
/// token answers 401 from then on, while another device's token for the same
/// account keeps working.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serverUrl = 'http://host:8096';
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const logout = '/Sessions/Logout';
  const me = '/Users/Me';
  const tokenKey = 'jellyfin_access_token';

  late FakeJellyfinServer server;
  late Map<String, String> secure;
  late SharedPreferences prefs;

  Future<void> stored() async {
    secure = <String, String>{tokenKey: 'token-abc'};
    FlutterSecureStorage.setMockInitialValues(secure);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': serverUrl,
      'user_id': 'admin-1',
      'user_name': 'Alex',
    });
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() => server = FakeJellyfinServer());

  group('the repository', () {
    late AuthRepository repository;

    setUp(() async {
      await stored();
      repository = AuthRepository(
        apiFactory: JellyfinApiFactory(identity: identity, adapter: server),
        tokenStore: const SecureTokenStore(FlutterSecureStorage()),
        settings: ServerSettingsStore(prefs),
        birthYears: BirthYearStore(prefs),
      );
    });

    test('revokes the token on the server, with that token', () async {
      server.onQuery(logout, (_) => true, status: 204);

      await repository.signOut();

      final revoke = server.requests.singleWhere((r) => r.path == logout);
      expect(revoke.method, 'POST');
      expect(revoke.headers['Authorization'], contains('Token="token-abc"'),
          reason: 'the token being revoked is the one sent');
      expect(secure, isNot(contains(tokenKey)));
    });

    test('still signs out when the server cannot be reached', () async {
      server.onQuery(logout, (_) => true,
          failWith: DioExceptionType.connectionError);

      await repository.signOut();

      expect(secure, isNot(contains(tokenKey)),
          reason: 'sign-out must work with no network');
      expect(prefs.getString('user_id'), isNull);
    });

    test('a slow server does not hold the sign-out up', () async {
      server.onQuery(logout, (_) => true,
          status: 204, delay: const Duration(seconds: 30));

      final watch = Stopwatch()..start();
      await repository.signOut();

      expect(watch.elapsed, lessThan(AuthRepository.revokeTimeout * 2));
      expect(secure, isNot(contains(tokenKey)));
    });

    test('revoke: false asks nothing of the server', () async {
      await repository.signOut(revoke: false);

      expect(server.callsTo(logout), 0);
      expect(secure, isNot(contains(tokenKey)));
    });
  });

  group('the controller', () {
    Map<String, dynamic> user({required bool admin}) => <String, dynamic>{
          'Id': 'admin-1',
          'Name': 'Alex',
          'Policy': <String, dynamic>{
            'IsAdministrator': admin,
            'IsDisabled': false,
          },
        };

    Future<ProviderContainer> signedIn() async {
      await stored();
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
      return c;
    }

    Future<AuthState?> launch(ProviderContainer c) async {
      await c.read(authControllerProvider.future);
      await pumpEventQueue();
      return c.read(authControllerProvider).value;
    }

    test('a token the server refused is not sent back to be revoked',
        () async {
      server.onQuery(me, (_) => true, status: 401);
      final c = await signedIn();

      final state = await launch(c);

      expect((state! as AuthSignedOut).reason?.kind,
          JellyfinErrorKind.unauthorized);
      expect(server.callsTo(logout), 0);
    });

    test("a demoted account's token still works, so it is revoked",
        () async {
      server
        ..onQuery(me, (_) => true, json: user(admin: false))
        ..onQuery(logout, (_) => true, status: 204);
      final c = await signedIn();

      final state = await launch(c);

      expect((state! as AuthSignedOut).reason?.kind,
          JellyfinErrorKind.notAdministrator);
      expect(server.callsTo(logout), 1);
    });

    test('a revoke the server refuses does not start a check mid-sign-out',
        () async {
      // Revoked from the dashboard meanwhile: the revoke itself answers 401,
      // which reports to the session relay like any other. Checking the
      // session being given up would race the sign-out and could end it as
      // "unauthorized" rather than as the parent's own sign-out.
      server.onQuery(me, (_) => true, json: user(admin: true));
      final c = await signedIn();
      await launch(c);
      server
        ..onQuery(me, (_) => true, status: 401)
        ..onQuery(logout, (_) => true, status: 401);

      await c.read(authControllerProvider.notifier).signOut();
      await pumpEventQueue();

      expect(server.callsTo(me), 1, reason: 'the launch check only');
      final state = c.read(authControllerProvider).value;
      expect((state! as AuthSignedOut).reason, isNull,
          reason: "the parent's own sign-out, not a refusal");
    });

    testWidgets('Settings asks first, and Cancel keeps the session',
        (tester) async {
      server
        ..onQuery(me, (_) => true, json: user(admin: true))
        ..onQuery(logout, (_) => true, status: 204);
      final c = await signedIn();
      final signedInState =
          (await tester.runAsync(() => launch(c)))! as AuthSignedIn;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SettingsScreen(session: signedInState.session),
            ),
          ),
        ),
      );
      await tester.pump();

      Future<void> tapSignOut() async {
        await tester.scrollUntilVisible(find.text('Sign out'), 200);
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
      }

      await tapSignOut();
      expect(find.text('Sign out?'), findsOneWidget,
          reason: 'the row asks before it signs out');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.read(authControllerProvider).value, isA<AuthSignedIn>());
      expect(server.callsTo(logout), 0);

      await tapSignOut();
      // The dialog's own button, not the row behind it.
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Sign out'),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(c.read(authControllerProvider).value, isA<AuthSignedOut>());
      expect(server.callsTo(logout), 1);
    });
  });
}
