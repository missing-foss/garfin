// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/active_session.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/session_verifier.dart';
import 'package:garfin/widgets/session_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Seeing and ending a child's session (#41).
///
/// Two measured facts drive most of this. **`/Sessions` ignores `userId`** — it
/// answers with every session, the admin's included — so the filtering is
/// Garfin's and a bug in it puts somebody else's device under a child's name.
/// And **ending a session works on any device including Garfin's own**: 204,
/// then 401 on the very next request, which is the app signing the parent out
/// of itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );
  const ownDevice = 'garfin-phone';

  Map<String, dynamic> sessionJson({
    required String user,
    required String userName,
    required String device,
    String? playing,
    int? position,
    int? runtime,
    bool paused = false,
    bool remote = false,
  }) =>
      <String, dynamic>{
        'Id': 'session-$device',
        'UserId': user,
        'UserName': userName,
        'DeviceId': device,
        'DeviceName': device,
        'Client': 'Jellyfin Android',
        'SupportsRemoteControl': remote,
        if (playing != null)
          'NowPlayingItem': <String, dynamic>{
            'Name': playing,
            'RunTimeTicks': ?runtime,
          },
        'PlayState': <String, dynamic>{
          'PositionTicks': ?position,
          'IsPaused': paused,
        },
      };

  Map<String, dynamic> userJson(String id, String name, List<String> tags) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'Policy': <String, dynamic>{
          'IsAdministrator': false,
          'IsDisabled': false,
          'AllowedTags': tags,
        },
      };

  late FakeJellyfinServer server;

  Future<ProviderContainer> build() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        deviceIdentityProvider.overrideWithValue(
          const DeviceIdentity(deviceId: ownDevice, deviceName: 'Garfin'),
        ),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(
            identity:
                const DeviceIdentity(deviceId: ownDevice, deviceName: 'Garfin'),
            adapter: server,
          ),
        ),
      ],
    );
  }

  setUp(() {
    server = FakeJellyfinServer();
    server
      ..on('/Users', json: [
        userJson('kid-1', 'Emma', ['kids-emma']),
        userJson('kid-2', 'Sam', ['kids-sam']),
        <String, dynamic>{
          'Id': 'admin-1',
          'Name': 'Parent',
          'Policy': <String, dynamic>{
            'IsAdministrator': true,
            'IsDisabled': false,
          },
        },
      ])
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 0, 'Items': []});
  });

  group('whose sessions are shown', () {
    test('only children Garfin manages, filtered here rather than by the server',
        () async {
      // Measured: /Sessions?userId=… answers with everything, so a screen that
      // trusted the parameter would show the admin's laptop under Emma's name.
      server.on('/Sessions', json: [
        sessionJson(user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
        sessionJson(user: 'admin-1', userName: 'Parent', device: 'the-laptop'),
        sessionJson(user: 'nobody', userName: 'Guest', device: 'a-tv'),
      ]);
      final container = await build();
      addTearDown(container.dispose);

      final sessions =
          await container.read(childSessionsProvider(session).future);

      expect(sessions.map((s) => s.deviceId), ['emma-tablet']);
    });

    test("Garfin's own device is never listed", () async {
      // Ending it is a 204 followed by an immediate 401: the app signing the
      // parent out of itself. Excluded rather than shown and disabled.
      server.on('/Sessions', json: [
        sessionJson(user: 'kid-1', userName: 'Emma', device: ownDevice),
        sessionJson(user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
      ]);
      final container = await build();
      addTearDown(container.dispose);

      final sessions =
          await container.read(childSessionsProvider(session).future);

      expect(sessions.map((s) => s.deviceId), ['emma-tablet']);
    });

    test('a session with no user is not a child on a device', () async {
      // The server's own housekeeping sessions carry no user, and one with no
      // device could not be ended even if it did.
      server.on('/Sessions', json: [
        <String, dynamic>{'Id': 's1', 'DeviceId': 'd1', 'UserId': ''},
        <String, dynamic>{'Id': 's2', 'UserId': 'kid-1'},
        sessionJson(user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
      ]);
      final container = await build();
      addTearDown(container.dispose);

      expect(
        (await container.read(childSessionsProvider(session).future))
            .map((s) => s.deviceId),
        ['emma-tablet'],
      );
    });
  });

  group('what the card has to say', () {
    test('nothing playing is the ordinary case, and the key is absent', () {
      final parsed = ActiveSession.fromJson(
          sessionJson(user: 'kid-1', userName: 'Emma', device: 'd'))!;

      expect(parsed.isPlaying, isFalse);
      expect(parsed.nowPlayingName, isNull);
      expect(parsed.progress, isNull);
    });

    test('playing carries the title and how far in', () {
      final parsed = ActiveSession.fromJson(sessionJson(
        user: 'kid-1',
        userName: 'Emma',
        device: 'd',
        playing: 'Paddington',
        position: 300000000,
        runtime: 600000000,
      ))!;

      expect(parsed.isPlaying, isTrue);
      expect(parsed.nowPlayingName, 'Paddington');
      expect(parsed.progress, 0.5);
    });

    test('paused is a third state, not a kind of playing', () {
      final parsed = ActiveSession.fromJson(sessionJson(
        user: 'kid-1',
        userName: 'Emma',
        device: 'd',
        playing: 'Paddington',
        paused: true,
      ))!;

      expect(parsed.isPlaying, isTrue);
      expect(parsed.isPaused, isTrue);
    });

    test('a runtime of zero does not divide by it', () {
      final parsed = ActiveSession.fromJson(sessionJson(
        user: 'kid-1',
        userName: 'Emma',
        device: 'd',
        playing: 'Live TV',
        position: 5,
        runtime: 0,
      ))!;

      expect(parsed.progress, isNull);
    });

    test('progress cannot exceed the bar', () {
      // Measured position past the end is possible on a client that has
      // finished; a progress bar over 1.0 throws in Flutter.
      final parsed = ActiveSession.fromJson(sessionJson(
        user: 'kid-1',
        userName: 'Emma',
        device: 'd',
        playing: 'Paddington',
        position: 700000000,
        runtime: 600000000,
      ))!;

      expect(parsed.progress, 1.0);
    });
  });

  group('the card, which is where the wrong id would be passed', () {
    Future<void> pumpCard(
      WidgetTester tester,
      ActiveSession active, {
      Locale? locale,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            deviceIdentityProvider.overrideWithValue(
              const DeviceIdentity(deviceId: ownDevice, deviceName: 'Garfin'),
            ),
            jellyfinApiFactoryProvider.overrideWithValue(
              JellyfinApiFactory(
                identity: const DeviceIdentity(
                    deviceId: ownDevice, deviceName: 'Garfin'),
                adapter: server,
              ),
            ),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SessionCard(session: session, active: active),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final emma = ActiveSession.fromJson(sessionJson(
      user: 'kid-1',
      userName: 'Emma',
      device: 'emma-tablet',
      playing: 'Paddington',
    ))!;

    /// The same session on a device that accepts remote commands.
    ///
    /// The default fixture reports `SupportsRemoteControl: false`, which is
    /// now enough to disable Stop — so every test that drives that button has
    /// to say it is talking to a device that claims it can be driven.
    final emmaRemote = ActiveSession.fromJson(sessionJson(
      user: 'kid-1',
      userName: 'Emma',
      device: 'emma-tablet',
      playing: 'Paddington',
      remote: true,
    ))!;

    testWidgets('ending a session sends the device id, not the session id',
        (tester) async {
      // The API takes `deviceId:`, and the session carries both — `session-…`
      // and `emma-tablet`. Measured: the wrong one answers **404** and ends
      // nothing, so the mistake is loud rather than silent — but it is still
      // a session that did not end, and testing the API method alone cannot
      // catch it, because there the parameter is already named `deviceId`.
      // This is the call site, where the value is chosen.
      await pumpCard(tester, emma);

      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End session').last);
      await tester.pumpAndSettle();
      // The revoke waits for the stop to settle first, so it has not happened
      // yet at this point — see "the stop goes out before the revoke".
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      final deletes = server.requests.where((r) => r.method == 'DELETE');
      expect(deletes, hasLength(1));
      expect(deletes.single.queryParameters['id'], 'emma-tablet');
      expect(deletes.single.queryParameters['id'], isNot(startsWith('session-')));

      // Both commands now schedule a read-back (#70), which outlives the
      // widget tree unless the test waits for it.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('the confirmation says what ending a session does not do',
        (tester) async {
      // The revoke is real -- the token 401s -- but a film already playing may
      // carry on, and Garfin cannot observe that: an ended session leaves
      // /Sessions, so the read-back that catches an ignored Stop is blind here
      // by construction. The dialog is the only place the limit can be stated,
      // which is why it is pinned by a test rather than left to the catalogue.
      await pumpCard(tester, emma);

      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();

      expect(find.textContaining('will not stop the film'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('and says it in French too', (tester) async {
      // The English half of this sentence is pinned above. This is the other
      // half, and it needs its own assertion for the same reason the sentence
      // exists at all: an ended session is gone from `/Sessions` by
      // definition, so there is no read-back that could catch a film that
      // kept playing. **The wording is the only guard**, and neither l10n
      // gate can tell whether it still says anything -- `gen-l10n` checks
      // that the key is present and its placeholders parse, and the copy
      // rules ban words rather than requiring them. Delete this clause from
      // the French catalogue and, without this test, the suite stays green
      // for the parents who would be reading it.
      //
      // "peut continuer" rather than a longer fragment: it is the half that
      // carries the meaning, and it does not move if the rest is reworded.
      await pumpCard(tester, emma, locale: const Locale('fr'));

      await tester.tap(find.text('Fermer la session'));
      await tester.pumpAndSettle();

      expect(find.textContaining("n'arrêtera pas le film"), findsOneWidget);
    });

    testWidgets('nothing is ended until the parent confirms', (tester) async {
      // Ground rule 6: disruptive, even though #40 makes the way back cheap.
      await pumpCard(tester, emma);

      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });

    testWidgets('stopping playback goes to the session id', (tester) async {
      await pumpCard(tester, emmaRemote);

      await tester.tap(find.text('Stop playback'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop playback').last);
      await tester.pumpAndSettle();

      expect(
        server.requests.where((r) => r.path.endsWith('/Playing/Stop')).single.path,
        '/Sessions/session-emma-tablet/Playing/Stop',
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('a device that cannot be controlled says so', (tester) async {
      // Measured: the message and stop commands answer 204 anyway, so without
      // this the parent is told something was sent to a device that cannot
      // receive it.
      await pumpCard(tester, emma);
      expect(find.textContaining("doesn't accept remote commands"),
          findsOneWidget);
    });

    testWidgets('stop is not offered when nothing is playing', (tester) async {
      await pumpCard(
        tester,
        ActiveSession.fromJson(
            sessionJson(user: 'kid-1', userName: 'Emma', device: 'd'))!,
      );

      expect(find.text('Stop playback'), findsNothing);
      expect(find.text('End session'), findsOneWidget);
      expect(find.text('Nothing playing'), findsOneWidget);
    });

    /// #70: the toast used to end at "asked", and the list was invalidated on
    /// the way out — before the server could reflect anything. These assert on
    /// the artifact the feature exists to produce: the read-back request, and
    /// the sentence on screen after it lands.
    Future<void> confirm(WidgetTester tester, String button) async {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      await tester.tap(find.text(button).last);
      await tester.pumpAndSettle();
    }

    testWidgets('the stop read-back waits, rather than asking immediately',
        (tester) async {
      // Reading /Sessions straight after the command is the bug, not the fix:
      // it answers with the pre-command state, so the card redraws identical
      // and "nothing happened" becomes the obvious reading.
      server.on('/Sessions', json: [
        sessionJson(
            user: 'kid-1',
            userName: 'Emma',
            device: 'emma-tablet',
            playing: 'Paddington'),
      ]);
      await pumpCard(tester, emmaRemote);

      await confirm(tester, 'Stop playback');

      expect(server.callsTo('/Sessions'), 0);
      expect(find.text('Asked emma-tablet to stop.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(server.callsTo('/Sessions'), 1);
    });

    testWidgets('a client that ignores the stop is reported as ignoring it',
        (tester) async {
      server.on('/Sessions', json: [
        sessionJson(
            user: 'kid-1',
            userName: 'Emma',
            device: 'emma-tablet',
            playing: 'Paddington'),
      ]);
      await pumpCard(tester, emmaRemote);

      await confirm(tester, 'Stop playback');
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(find.text("Asked emma-tablet to stop, but it's still playing."),
          findsOneWidget);
      expect(find.text('Asked emma-tablet to stop.'), findsNothing);
    });

    testWidgets('a client that stops is reported as having stopped',
        (tester) async {
      // Same session, no NowPlayingItem — which is how a compliant client
      // looks a moment later.
      server.on('/Sessions', json: [
        sessionJson(user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
      ]);
      await pumpCard(tester, emmaRemote);

      await confirm(tester, 'Stop playback');
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(find.text('emma-tablet stopped playing.'), findsOneWidget);
    });

    testWidgets('a device that signs straight back in is not left looking ended',
        (tester) async {
      // A client holding saved credentials re-authenticates, and sessions are
      // keyed by device, so the returning row wears the same device name. The
      // id below deliberately differs from the original — see the unit test
      // "matched on the device, not the session id" for why it is varied.
      server.on('/Sessions', json: [
        <String, dynamic>{
          ...sessionJson(
              user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
          'Id': 'session-after-the-revoke',
        },
      ]);
      await pumpCard(tester, emma);

      await confirm(tester, 'End session');
      // The stop settles, then the revoke goes out and the pending sentence
      // appears; the return read-back is a second settle after that.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.text('emma-tablet is signed out.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(
          find.text('emma-tablet stopped playing, then signed straight back in.'),
          findsOneWidget);
    });

    testWidgets('the stop goes out before the revoke, not after',
        (tester) async {
      // **The ordering is the fix.** End is specified to stop the film and
      // kill the session; it used to do only the second, and a revoke-first
      // implementation is the same bug wearing the fix's clothes -- the stop
      // would be addressed to a session the revoke had already removed, and
      // the read-back would have nothing left to look at. Reverse the two
      // calls in `_end` and this is what fails.
      server.on('/Sessions', json: [
        sessionJson(
            user: 'kid-1',
            userName: 'Emma',
            device: 'emma-tablet',
            playing: 'Paddington'),
      ]);
      await pumpCard(tester, emma);

      await confirm(tester, 'End session');

      // The stop has gone; the revoke is still waiting on the settle.
      expect(server.requests.where((r) => r.path.endsWith('/Playing/Stop')),
          hasLength(1));
      expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(server.requests.where((r) => r.method == 'DELETE'), hasLength(1));
      final paths = server.requests.map((r) => r.path).toList();
      expect(paths.indexOf('/Sessions/session-emma-tablet/Playing/Stop'),
          lessThan(paths.indexOf('/Devices')));

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('a device that ignores the stop is signed out and said so',
        (tester) async {
      // The case the parent most needs and the one a vanished card hides: the
      // revoke held, and the film is still on the screen. Measured upstream --
      // the media path is not token-gated, so revoking cannot interrupt it.
      // Two read-backs, scripted in the order they happen: still playing when
      // the stop is checked, then gone from the list when the revoke is. Both
      // are queued up front because a lone queued reply is sticky rather than
      // consumed, so a second one added later would answer the wrong call.
      server.on('/Sessions', json: [
        sessionJson(
            user: 'kid-1',
            userName: 'Emma',
            device: 'emma-tablet',
            playing: 'Paddington'),
      ]);
      server.on('/Sessions', json: <Map<String, dynamic>>[]);
      await pumpCard(tester, emma);

      await confirm(tester, 'End session');
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(find.text("emma-tablet is signed out, but it's still playing."),
          findsOneWidget);
    });

    testWidgets('Stop is not offered to a device that says it cannot obey',
        (tester) async {
      // Reverses the decision that previously stood here. The flag is the
      // client's own claim, so this does withdraw a control that might have
      // worked -- that is the price, and the ruling took it: a button known in
      // advance not to work is the same dishonesty as a toast that reports
      // intent as outcome. End stays, because the revoke works regardless.
      await pumpCard(tester, emma);

      final stop = tester.widget<TextButton>(
        find.ancestor(
            of: find.text('Stop playback'), matching: find.byType(TextButton)),
      );
      expect(stop.onPressed, isNull);

      final end = tester.widget<TextButton>(
        find.ancestor(
            of: find.text('End session'), matching: find.byType(TextButton)),
      );
      expect(end.onPressed, isNotNull);
    });

    testWidgets('a controllable device is told the film may be ignored, not that it may not stop',
        (tester) async {
      // The other confirmation body. Both are the only place these limits can
      // be stated, and neither l10n gate reads a sentence for meaning.
      await pumpCard(tester, emmaRemote);

      await tester.tap(find.text('End session'));
      await tester.pumpAndSettle();

      expect(find.textContaining('keeps playing'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('End reports both halves: the film and the device',
        (tester) async {
      // What End is *for*. The revoke is measured to hold, but on its own that
      // says nothing about the screen the child is looking at — so the
      // sentence carries both, and neither half is inferred from a 204.
      server.on('/Sessions', json: <Map<String, dynamic>>[]);
      await pumpCard(tester, emma);

      await confirm(tester, 'End session');
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(find.text('emma-tablet stopped playing and is signed out.'),
          findsOneWidget);
    });
  });

  group('the commands', () {
    late JellyfinApi api;

    setUp(() {
      api = JellyfinApiFactory(
        identity:
            const DeviceIdentity(deviceId: ownDevice, deviceName: 'Garfin'),
        adapter: server,
      ).create(baseUrl: 'http://host:8096');
    });

    test('ending a session is keyed on the device, not the session', () async {
      // `DELETE /Devices?id=` takes the device id. Passing the session id would
      // answer 204 and end nothing.
      await api.endSession(deviceId: 'emma-tablet');

      final request = server.requests.last;
      expect(request.method, 'DELETE');
      expect(request.path, '/Devices');
      expect(request.queryParameters, {'id': 'emma-tablet'});
    });

    test('a message goes to the session id', () async {
      await api.sendSessionMessage(
        sessionId: 'session-1',
        text: 'Ten more minutes',
        header: 'Garfin',
      );

      final request = server.requests.last;
      expect(request.path, '/Sessions/session-1/Message');
      expect(request.data, containsPair('Text', 'Ten more minutes'));
    });

    test('stopping goes to the session id', () async {
      await api.stopSessionPlayback(sessionId: 'session-1');
      expect(server.requests.last.path, '/Sessions/session-1/Playing/Stop');
    });
  });

  /// Reading back what a command achieved (#70), which is the only thing that
  /// can tell an accepted command from an obeyed one — a 204 cannot.
  group('what actually happened', () {
    late SessionVerifier verifier;

    setUp(() {
      verifier = SessionVerifier(
        JellyfinApiFactory(
          identity:
              const DeviceIdentity(deviceId: ownDevice, deviceName: 'Garfin'),
          adapter: server,
        ).create(baseUrl: 'http://host:8096'),
        // The three-second wait is for a real client on a real network. Here
        // it would only be three seconds of test.
        settle: Duration.zero,
      );
    });

    test('a session still playing did not act on the stop', () async {
      server.on('/Sessions', json: [
        sessionJson(
            user: 'kid-1',
            userName: 'Emma',
            device: 'emma-tablet',
            playing: 'Paddington'),
      ]);

      expect(await verifier.verifyStopped(sessionId: 'session-emma-tablet'),
          StopOutcome.stillPlaying);
    });

    test('a session with nothing playing stopped', () async {
      server.on('/Sessions', json: [
        sessionJson(user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
      ]);

      expect(await verifier.verifyStopped(sessionId: 'session-emma-tablet'),
          StopOutcome.stopped);
    });

    test('a session that has gone counts as stopped, not as unknown', () async {
      // The client went away. It is not playing anything the server knows
      // about, and calling that unknown would say nothing about the one case
      // the parent can already see worked.
      server.on('/Sessions', json: <Map<String, dynamic>>[]);

      expect(await verifier.verifyStopped(sessionId: 'session-emma-tablet'),
          StopOutcome.stopped);
    });

    test('other sessions are not mistaken for this one', () async {
      // A busy household: the read-back must find *this* session rather than
      // whichever one happens to be first.
      server.on('/Sessions', json: [
        sessionJson(
            user: 'kid-2', userName: 'Sam', device: 'sam-tv', playing: 'Cars'),
        sessionJson(user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
      ]);

      expect(await verifier.verifyStopped(sessionId: 'session-emma-tablet'),
          StopOutcome.stopped);
    });

    test('a read-back that fails claims nothing', () async {
      // The command was accepted; it is the verification that could not be
      // made. Reporting that as "still playing" would invent a failure.
      server.on('/Sessions', failWith: DioExceptionType.connectionTimeout);

      expect(await verifier.verifyStopped(sessionId: 'session-emma-tablet'),
          StopOutcome.unknown);
      expect(await verifier.verifyEnded(deviceId: 'emma-tablet'),
          EndOutcome.unknown);
    });

    test('no session for the device means the revoke held', () async {
      server.on('/Sessions', json: [
        sessionJson(
            user: 'kid-2', userName: 'Sam', device: 'sam-tv', playing: 'Cars'),
      ]);

      expect(await verifier.verifyEnded(deviceId: 'emma-tablet'),
          EndOutcome.signedOut);
    });

    test('a returning client is matched on the device, not the session id',
        () async {
      // verifyEnded must not lean on the session id. Measured on 10.11.11
      // (#104) that id is in fact **stable** across revoke-and-return, so the
      // fixture varies it deliberately rather than in imitation of the server:
      // a changed id must not be able to make the check miss a returning
      // device, and varying it is also what keeps this gate non-vacuous —
      // match on the id instead of the device and this test fails.
      server.on('/Sessions', json: [
        <String, dynamic>{
          ...sessionJson(
              user: 'kid-1', userName: 'Emma', device: 'emma-tablet'),
          'Id': 'session-after-the-revoke',
        },
      ]);

      expect(await verifier.verifyEnded(deviceId: 'emma-tablet'),
          EndOutcome.signedBackIn);
    });
  });
}
