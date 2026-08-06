// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/widgets/device_sign_in_sheet.dart';

import 'support/fake_jellyfin_server.dart';

/// Approving a child's Quick Connect code on their behalf (#40).
///
/// **The failure that matters is approving for the wrong child, and it is
/// silent** — the child's device signs in as somebody, and nothing on either
/// screen says which account it got. So the assertions here are mostly about
/// the `userId` that goes out, and about nothing going out at all until the
/// parent has confirmed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  JellyfinUser kid(String id, String name) => JellyfinUser(
        id: id,
        name: name,
        policy: const UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: ['kids-emma'],
        ),
      );

  late FakeJellyfinServer server;

  Future<void> pump(WidgetTester tester, JellyfinUser child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceIdentityProvider.overrideWithValue(
            const DeviceIdentity(deviceId: 'd', deviceName: 't'),
          ),
          jellyfinApiFactoryProvider.overrideWithValue(
            JellyfinApiFactory(
              identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
              adapter: server,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDeviceSignInSheet(
                  context,
                  session: session,
                  child: child,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  List<RequestOptions> approvals() => server.requests
      .where((r) => r.path == '/QuickConnect/Authorize')
      .toList(growable: false);

  setUp(() {
    server = FakeJellyfinServer();
    server.fallback(json: true);
  });

  testWidgets('it approves for the child whose card it was opened from',
      (tester) async {
    // The child is not chosen in this sheet — it arrives with one. That is the
    // whole defence against the silent wrong-child failure.
    await pump(tester, kid('kid-2', 'Sam'));

    await tester.enterText(find.byType(TextField), '652316');
    await tester.pump();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();

    expect(approvals(), hasLength(1));
    expect(approvals().single.queryParameters['userId'], 'kid-2');
    expect(approvals().single.queryParameters['code'], '652316');
  });

  testWidgets('nothing is approved until the parent confirms', (tester) async {
    // Ground rule 6. The confirmation also reads the code back, which is the
    // one mistake Garfin can help with — it cannot see the device at all.
    await pump(tester, kid('kid-1', 'Emma'));

    await tester.enterText(find.byType(TextField), '652316');
    await tester.pump();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Code 652316'), findsOneWidget);
    expect(approvals(), isEmpty, reason: 'the dialog is open, nothing sent');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(approvals(), isEmpty, reason: 'cancelling must not approve');
  });

  testWidgets('the confirmation says the device was not checked',
      (tester) async {
    await pump(tester, kid('kid-1', 'Emma'));
    await tester.enterText(find.byType(TextField), '652316');
    await tester.pump();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    // Measured: no endpoint turns a code into device details, so implying a
    // check would be a claim Garfin cannot make.
    expect(find.textContaining("can't check which device"), findsOneWidget);
    expect(find.textContaining("Emma's own screen"), findsOneWidget);
  });

  testWidgets('a short code cannot be submitted at all', (tester) async {
    await pump(tester, kid('kid-1', 'Emma'));
    await tester.enterText(find.byType(TextField), '6523');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  group('the failure modes are told apart', () {
    testWidgets('an unknown or expired code says to ask for a new one',
        (tester) async {
      server.on('/QuickConnect/Authorize', status: 404);
      await pump(tester, kid('kid-1', 'Emma'));

      await tester.enterText(find.byType(TextField), '652316');
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();

      // The existing copy for an expired pairing, reused rather than
              // duplicated: "That code ran out. Ask for a new one."
      expect(find.textContaining('ran out'), findsOneWidget);
    });

    testWidgets('a refused code offers the likely reason without asserting it',
        (tester) async {
      // Measured: a reused code and a userId that no longer exists both answer
      // 500. The server does not distinguish them, so neither does the copy.
      server.on('/QuickConnect/Authorize', status: 500);
      await pump(tester, kid('kid-1', 'Emma'));

      await tester.enterText(find.byType(TextField), '652316');
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('already been used'), findsOneWidget);
    });

    testWidgets('Quick Connect being switched off says so, not "wrong code"',
        (tester) async {
      // A 401 from any /QuickConnect route means the feature is off, not that
      // the token is bad — measured for #17 and remapped ever since.
      server.on('/QuickConnect/Authorize', status: 401);
      await pump(tester, kid('kid-1', 'Emma'));

      await tester.enterText(find.byType(TextField), '652316');
      await tester.pump();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('switched off'), findsOneWidget);
    });
  });

  test('the request carries both parameters, and the code is not in the path',
      () async {
    // The code goes in the query string, where `JellyfinException` cannot pick
    // it up: that class builds its message from `path`, never `uri`.
    final server = FakeJellyfinServer()..fallback(json: true);
    final api = JellyfinApiFactory(
      identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      adapter: server,
    ).create(baseUrl: 'http://host:8096');

    await api.approveQuickConnect(code: '652316', userId: 'kid-1');

    final request = server.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/QuickConnect/Authorize');
    expect(request.path, isNot(contains('652316')));
    expect(request.queryParameters, {'code': '652316', 'userId': 'kid-1'});
  });

  test('a 403 is not swallowed — the server owns the privilege check',
      () async {
    // Measured: a non-admin pointing userId at an administrator is refused with
    // 403. Garfin does not re-implement that check, because a check it
    // implemented would be the one that could be wrong.
    final server = FakeJellyfinServer()
      ..on('/QuickConnect/Authorize', status: 403);
    final api = JellyfinApiFactory(
      identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      adapter: server,
    ).create(baseUrl: 'http://host:8096');

    await expectLater(
      api.approveQuickConnect(code: '652316', userId: 'admin-1'),
      throwsA(isA<JellyfinException>()
          .having((e) => e.kind, 'kind', JellyfinErrorKind.forbidden)),
    );
  });
}
