// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/unlock_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:garfin/widgets/unlock_gate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_device_unlock.dart';
import 'support/fake_jellyfin_server.dart';

/// The session is checked whenever the app learns something about it, not
/// once at launch.
///
/// **The reported failure.** The launch check was the only one. Ten seconds
/// without Wi-Fi at launch left "can't reach the server" above a working app
/// until a restart, and a device revoked from the dashboard left every screen
/// saying "unauthorized" over a session still signed in, its token still in
/// storage.
///
/// `/Users/Me` is the check (`AuthRepository.verify`), so these tests count
/// calls to it to tell whether one ran.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serverUrl = 'http://host:8096';
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const me = '/Users/Me';

  Map<String, dynamic> admin() => <String, dynamic>{
        'Id': 'admin-1',
        'Name': 'Alex',
        'Policy': <String, dynamic>{
          'IsAdministrator': true,
          'IsDisabled': false,
        },
      };

  late FakeJellyfinServer server;
  late Map<String, String> secure;

  const session = AuthSession(
    serverUrl: serverUrl,
    accessToken: 'token-abc',
    userId: 'admin-1',
    userName: 'Alex',
  );

  Future<ProviderContainer> signedInContainer({
    List<Override> extra = const [],
  }) async {
    secure = <String, String>{'jellyfin_access_token': 'token-abc'};
    FlutterSecureStorage.setMockInitialValues(secure);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_url': serverUrl,
      'user_id': 'admin-1',
      'user_name': 'Alex',
    });
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      // No automatic retry: a test that fails a provider wants the error state,
      // not Riverpod's backoff in front of it.
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
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// The launch, including the check it starts in the background.
  Future<AuthSignedIn> launch(ProviderContainer c) async {
    await c.read(authControllerProvider.future);
    await pumpEventQueue();
    return c.read(authControllerProvider).value! as AuthSignedIn;
  }

  /// A client the way every screen builds one: with the session's token.
  JellyfinApi authenticated(ProviderContainer c) => c
      .read(jellyfinApiFactoryProvider)
      .create(baseUrl: serverUrl, readToken: () => 'token-abc');

  setUp(() => server = FakeJellyfinServer());

  test('offline at launch: the banner comes down on the first call through',
      () async {
    server.onQuery(me, (_) => true, failWith: DioExceptionType.connectionError);
    final c = await signedInContainer();
    expect((await launch(c)).offlineReason, isNotNull,
        reason: 'the launch check could not reach the server');

    server.onQuery('/Items', (_) => true,
        json: <String, dynamic>{'TotalRecordCount': 3});
    await authenticated(c).visibleItemCount(userId: 'admin-1');
    await pumpEventQueue();

    final state = c.read(authControllerProvider).value! as AuthSignedIn;
    expect(state.offlineReason, isNull,
        reason: 'a call got through, so the server is reachable');
  });

  test('a 401 from any authenticated call signs a revoked session out',
      () async {
    server.onQuery(me, (_) => true, json: admin());
    final c = await signedInContainer();
    expect((await launch(c)).verified, isTrue);

    // Revoked from the dashboard: everything is refused from now on.
    server
      ..onQuery(me, (_) => true, status: 401)
      ..onQuery('/Items', (_) => true, status: 401);
    await expectLater(
      authenticated(c).visibleItemCount(userId: 'admin-1'),
      throwsA(isA<JellyfinException>()),
    );
    await pumpEventQueue();

    final state = c.read(authControllerProvider).value;
    expect(state, isA<AuthSignedOut>());
    expect((state! as AuthSignedOut).reason?.kind,
        JellyfinErrorKind.unauthorized);
    expect(secure, isNot(contains('jellyfin_access_token')),
        reason: 'the dead token must not stay in storage');
  });

  test('the check decides: a 401 it does not confirm keeps the session',
      () async {
    server.onQuery(me, (_) => true, json: admin());
    final c = await signedInContainer();
    await launch(c);

    server.onQuery('/Items', (_) => true, status: 401);
    await expectLater(
      authenticated(c).visibleItemCount(userId: 'admin-1'),
      throwsA(isA<JellyfinException>()),
    );
    await pumpEventQueue();

    expect(server.callsTo(me), 2, reason: 'the launch check, and one for the 401');
    expect(c.read(authControllerProvider).value, isA<AuthSignedIn>(),
        reason: 'the server still honours the token');
  });

  test('a burst of 401s asks for one check', () async {
    server.onQuery(me, (_) => true, json: admin());
    final c = await signedInContainer();
    await launch(c);

    // A check slow enough that the whole burst arrives while it is in flight.
    server
      ..onQuery(me, (_) => true,
          status: 401, delay: const Duration(milliseconds: 50))
      ..onQuery('/Items', (_) => true, status: 401);
    final api = authenticated(c);
    await Future.wait([
      for (var i = 0; i < 5; i++)
        api.visibleItemCount(userId: 'admin-1').then((_) {}, onError: (_) {}),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(server.callsTo(me), 2, reason: 'the launch check, and one for five');
  });

  test('a 401 without a token is a wrong password, not a revoked session',
      () async {
    server.onQuery(me, (_) => true, json: admin());
    final c = await signedInContainer();
    await launch(c);

    server.onQuery('/Items', (_) => true, status: 401);
    final anonymous =
        c.read(jellyfinApiFactoryProvider).create(baseUrl: serverUrl);
    await expectLater(
      anonymous.visibleItemCount(userId: 'admin-1'),
      throwsA(isA<JellyfinException>()),
    );
    await pumpEventQueue();

    expect(server.callsTo(me), 1, reason: 'only the launch check');
  });

  /// Runs the fake server's replies to completion inside a widget test, where
  /// the test's clock is fake and a request started by the UI needs both.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('coming back to the app re-checks the session', (tester) async {
    server.onQuery(me, (_) => true, json: admin());
    final c = await signedInContainer(
      extra: [deviceUnlockProvider.overrideWithValue(FakeDeviceUnlock())],
    );
    await tester.runAsync(() => launch(c));
    final before = server.callsTo(me);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UnlockGate(child: SizedBox()),
        ),
      ),
    );
    await settle(tester);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);

    expect(server.callsTo(me), before + 1);
  });

  testWidgets("Kids' Try again re-checks the session", (tester) async {
    server.onQuery(me, (_) => true, json: admin());
    const failing = JellyfinException(JellyfinErrorKind.unreachable);
    final c = await signedInContainer(
      extra: [
        kidsOverviewProvider(session).overrideWith((ref) async => throw failing),
        kidsRosterProvider(session).overrideWith((ref) async => throw failing),
      ],
    );
    await tester.runAsync(() => launch(c));
    final before = server.callsTo(me);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: KidsScreen(session: session)),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byType(FilledButton));
    await settle(tester);

    expect(server.callsTo(me), before + 1);
  });
}
