// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/main.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
}
