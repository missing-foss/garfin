// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/main.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/token_store.dart';
import 'package:garfin/screens/sign_in_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');

  late FakeJellyfinServer server;
  late SharedPreferences prefs;

  setUp(() async {
    server = FakeJellyfinServer();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    // Since #69 the gate no longer sits over sign-in, so this is belt and
    // braces rather than load-bearing: it keeps these tests about sign-in even
    // if the gate ever moves back up. The gate has its own tests in
    // `unlock_gate_test.dart` and `unlock_start_test.dart`.
    SharedPreferences.setMockInitialValues(
      <String, Object>{'unlock_required': false},
    );
    prefs = await SharedPreferences.getInstance();
  });

  Widget app() => ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceIdentityProvider.overrideWithValue(identity),
          jellyfinApiFactoryProvider.overrideWithValue(
            JellyfinApiFactory(identity: identity, adapter: server),
          ),
        ],
        child: const GarfinApp(),
      );

  /// Types an address and taps Continue.
  ///
  /// Deliberately not followed by `pumpAndSettle`: the Quick Connect panel
  /// carries an indeterminate progress bar, which never settles. The pumps
  /// instead run long enough for every request this triggers to finish — dio
  /// arms a `receiveTimeout` timer per response and cancels it when the body
  /// is drained, so a test that ends mid-request trips the framework's
  /// pending-timer check.
  Future<void> enterServer(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'host:8096');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('starts at the address step when nothing is stored',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Which server?'), findsOneWidget);
    expect(find.text('Server address'), findsOneWidget);
  });

  testWidgets('offers both methods when the server has Quick Connect on',
      (tester) async {
    server
      ..on('/QuickConnect/Enabled', json: true)
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': 'secret-value'})
      ..fallback(json: {'Authenticated': false});

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await enterServer(tester);

    expect(find.byType(Tab), findsNWidgets(2));
    expect(find.text('Quick Connect'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // The typed shorthand is written back with the scheme Garfin resolved, so
    // the address on screen is the one actually being used.
    expect(find.text('Connected to http://host:8096'), findsOneWidget);
  });

  testWidgets('shows the six-digit code once the pairing starts',
      (tester) async {
    server
      ..on('/QuickConnect/Enabled', json: true)
      ..on('/QuickConnect/Initiate',
          json: {'Code': '123456', 'Secret': 'secret-value'})
      ..fallback(json: {'Authenticated': false});

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await enterServer(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('123456'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });

  testWidgets('hides the Quick Connect tab when the server has it off',
      (tester) async {
    // A disabled feature should not look like a broken one: no tab at all,
    // rather than a tab that opens onto an explanation (issue #17).
    server.on('/QuickConnect/Enabled', json: false);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await enterServer(tester);

    expect(find.byType(Tab), findsNothing);
    expect(find.text('Username'), findsOneWidget);
    expect(server.callsTo('/QuickConnect/Initiate'), 0);
  });

  testWidgets('refuses a non-admin account on screen, naming it',
      (tester) async {
    server
      ..on('/QuickConnect/Enabled', json: false)
      ..on(
        '/Users/AuthenticateByName',
        json: authResultJson(name: 'Emma', isAdministrator: false),
      );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await enterServer(tester);

    await tester.enterText(find.byType(TextField).at(0), 'emma');
    await tester.enterText(find.byType(TextField).at(1), 'hunter2');
    // By widget, not by text: the app bar title is also "Sign in".
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // Ground rule 7, as the user meets it: the account named, a plain reason,
    // and what to do instead — not a 403 three screens later.
    expect(find.textContaining("Emma isn't an administrator"), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });

  testWidgets('drops a password typed into the address, and says it did',
      (tester) async {
    server.on('/QuickConnect/Enabled', json: false);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://parent:hunter2@jf.example.org',
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.textContaining('had a username and password in it'),
      findsOneWidget,
    );
    // Nowhere on screen, and nowhere in preferences.
    for (final text in find.byType(Text).evaluate()) {
      expect((text.widget as Text).data ?? '', isNot(contains('hunter2')));
    }
    expect(find.text('Connected to https://jf.example.org'), findsOneWidget);
    for (final key in prefs.getKeys()) {
      expect(prefs.get(key).toString(), isNot(contains('hunter2')));
    }
    // Nor in the request that went out.
    for (final request in server.requests) {
      expect(request.uri.toString(), isNot(contains('hunter2')));
    }
  });

  testWidgets('says so plainly when the server cannot be reached',
      (tester) async {
    server.on(
      '/QuickConnect/Enabled',
      failWith: DioExceptionType.connectionError,
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await enterServer(tester);

    expect(
      find.textContaining("couldn't reach http://host:8096"),
      findsOneWidget,
    );
    // Still on the address step, with the address there to correct.
    expect(find.text('Which server?'), findsOneWidget);
  });

  testWidgets('a secure-storage failure on restore lands on sign-in',
      (tester) async {
    // Issue #35. `flutter_secure_storage` is backed by
    // `EncryptedSharedPreferences`, whose master key lives in the Keystore and
    // is not backed up. So a restored install can hold a blob it cannot
    // decrypt, and the plugin throws rather than returning null. Changing the
    // device credential or re-enrolling biometrics can invalidate the key the
    // same way, so this outlives the backup decision that turned it up —
    // `allowBackup="false"` removes the restore path, not the other causes.
    //
    // `AuthRepository.restore()` calls `TokenStore.read()` with no `try`, so
    // the throw propagates into `AuthController.build()` and surfaces as an
    // `AsyncError`. `app_root.dart` renders that as the sign-in screen, and
    // deliberately — the comment there says so. This pins that, because it was
    // the one link in the chain with nothing holding it in place.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'unlock_required': false,
      // Needed to get past the early return in `restore()` and actually reach
      // the token store. Asserted below rather than assumed: without it this
      // test lands on the sign-in screen anyway, for entirely the wrong
      // reason, and stays green.
      'server_url': 'http://host:8096',
    });
    prefs = await SharedPreferences.getInstance();

    final store = _UndecryptableTokenStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceIdentityProvider.overrideWithValue(identity),
          jellyfinApiFactoryProvider.overrideWithValue(
            JellyfinApiFactory(identity: identity, adapter: server),
          ),
          tokenStoreProvider.overrideWithValue(store),
        ],
        child: const GarfinApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Proves the throw was actually reached. Without this the test passes on
    // a `restore()` that returned early and never touched the store — which
    // it would, quietly, if `server_url` above were ever dropped.
    //
    // Not pinned to an exact count: the controller is re-read while the error
    // settles, and this observed 11 calls rather than 1. Harmless — it is a
    // local read that throws immediately, and it does settle — but the number
    // is an artefact of rebuild scheduling, so asserting it would be pinning
    // something this test is not about.
    expect(store.reads, greaterThan(0));
    expect(find.byType(SignInScreen), findsOneWidget);
    // The point of the test: it surfaced as a screen, not as a crash.
    expect(tester.takeException(), isNull);
  });
}

/// A token store whose `read` fails the way a restored, undecryptable
/// `EncryptedSharedPreferences` does.
class _UndecryptableTokenStore implements TokenStore {
  int reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    throw PlatformException(
      code: 'Exception encountered',
      message: 'read',
      details: 'javax.crypto.AEADBadTagException',
    );
  }

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}
