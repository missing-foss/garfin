// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/unlock_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/unlock_settings_store.dart';
import 'package:garfin/screens/app_root.dart';
import 'package:garfin/screens/lock_screen.dart';
import 'package:garfin/screens/sign_in_screen.dart';
import 'package:garfin/screens/unlock_choice_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_device_unlock.dart';
import 'support/fake_jellyfin_server.dart';

/// **When** the unlock gate starts, and who gets asked (#69).
///
/// Ground rule 9 is unchanged and not under test here. What is under test is
/// the amendment: the gate guarded sign-in too, where Garfin holds no token, no
/// server address and no children — an empty app — and demanded biometrics
/// before a new user had typed an address.
///
/// The safety-critical case is the third one. A *restored* session must still
/// be gated with no question asked: offering "not now" to whoever has picked
/// the phone up would be offering to skip the gate to exactly the person it
/// exists for. The question is only ever put to someone who has just proved
/// they hold the Jellyfin credentials.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  late SharedPreferences prefs;
  late FakeJellyfinServer server;

  Future<void> boot(Map<String, Object> stored) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    // The app behind the gate starts loading as soon as it is built, so the
    // endpoints it reaches for must answer *something*: dio arms a
    // receiveTimeout per response and the framework fails a test that ends
    // with a timer pending. Same trap widget_test.dart documents.
    server = FakeJellyfinServer()
      ..on('/Users', json: <dynamic>[])
      ..fallback(json: <String, dynamic>{
        'TotalRecordCount': 0,
        'Items': <dynamic>[],
      });
  }

  /// `AppRoot` with the auth state pinned, so this is about what the root does
  /// with a state rather than about how the state is reached.
  Future<void> pump(WidgetTester tester, AuthState auth) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceIdentityProvider.overrideWithValue(identity),
          jellyfinApiFactoryProvider.overrideWithValue(
            JellyfinApiFactory(identity: identity, adapter: server),
          ),
          // `autoAnswer: false` leaves the prompt hanging, which is the only
          // window in which the gate is observably *up*: a fake that answers
          // instantly unlocks on the first frame and the lock screen is gone
          // before the assertion runs. What is under test here is where the
          // gate lives, not what the prompt does — `unlock_gate_test.dart`
          // owns that.
          deviceUnlockProvider
              .overrideWithValue(FakeDeviceUnlock()..autoAnswer = false),
          authControllerProvider.overrideWith(() => _FixedAuth(auth)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppRoot(),
        ),
      ),
    );
    // Long enough for the screens behind the gate to finish their requests —
    // not `pumpAndSettle`, which never returns while a progress indicator is
    // animating.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('signed out, nothing is gated — there is nothing to gate',
      (tester) async {
    // The default is unlock-required, and this must still land on sign-in:
    // before a session there is no token, no server address, no children.
    await boot(<String, Object>{});

    await pump(tester, const AuthSignedOut());

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(UnlockChoiceScreen), findsNothing);
  });

  testWidgets('just signed in, the question is put once', (tester) async {
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );

    expect(find.byType(UnlockChoiceScreen), findsOneWidget);
    expect(find.text('Ask every time'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('a RESTORED session is gated, and is never asked',
      (tester) async {
    // The safety-critical one. `justSignedIn` is false, so whoever is holding
    // the phone has not proved anything — offering them "not now" would be
    // offering to skip the gate to the person it exists for.
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: false),
    );

    expect(find.byType(UnlockChoiceScreen), findsNothing);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('once answered, the question is not put again', (tester) async {
    await boot(<String, Object>{
      'unlock_choice_made': true,
      'unlock_required': true,
    });

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );

    expect(find.byType(UnlockChoiceScreen), findsNothing);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('answering "not now" is remembered, and opens the app',
      (tester) async {
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );
    await tester.tap(find.text('Not now'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final store = UnlockSettingsStore(prefs);
    expect(store.choiceRecorded, isTrue);
    expect(store.required, isFalse);
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('answering "ask every time" locks immediately', (tester) async {
    // Not merely "records true": the gate has never run in this session, so
    // saying yes must leave the app locked exactly as a cold start would —
    // not open until the next time the phone is backgrounded.
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );
    await tester.tap(find.text('Ask every time'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final store = UnlockSettingsStore(prefs);
    expect(store.choiceRecorded, isTrue);
    expect(store.required, isTrue);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('the answer moves a gate that is already standing',
      (tester) async {
    // Why this is separate from the two above: on a fresh boot the lock
    // controller is *built* after the preference is written, so its own
    // `build()` reads the new value and lands in the right phase without being
    // told. That makes the "tell the gate" step look redundant — it is not.
    // A controller that is already alive keeps its state, and the default state
    // before any answer is locked. So the case that needs telling is a parent
    // answering "not now" while the gate is standing behind the question.
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AppRoot)));
    // Reading it is what brings it to life, and it starts locked.
    expect(container.read(lockControllerProvider).phase, LockPhase.locked);

    await tester.tap(find.text('Not now'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(container.read(lockControllerProvider).isOpen, isTrue);
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('backgrounding ends the moment the question belonged to',
      (tester) async {
    // **The hold from #72's review, and the case the nine other tests could
    // not express: none of them ever sends the app to the background.**
    //
    // Provenance was the only thing gating this question, and provenance does
    // not expire on its own. Sign in, leave it unanswered, put the phone down —
    // and a resume later showed the same screen with "Not now" still on it, to
    // whoever is now holding the phone. That is the offer this whole feature
    // exists to withhold from them.
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );
    expect(find.byType(UnlockChoiceScreen), findsOneWidget, reason: 'control');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.byType(UnlockChoiceScreen), findsNothing,
        reason: 'the moment has passed; the question goes with it');
    expect(find.byType(LockScreen), findsOneWidget,
        reason: 'and the gate stands in front of the app, as for any resumed '
            'session');
  });

  testWidgets('a notification shade does not snatch the question away',
      (tester) async {
    // `inactive`, not `paused` — the same distinction the lock controller
    // draws. A system prompt or a pulled-down shade must not read as "the
    // parent walked away" and take the question off screen mid-answer.
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byType(UnlockChoiceScreen), findsOneWidget);
  });

  testWidgets('nothing is recorded, so the next sign-in asks properly',
      (tester) async {
    // Backgrounding is not an answer. If it recorded one, a parent who was
    // interrupted would silently get whichever default the code picked, and
    // would never be asked again.
    await boot(<String, Object>{});

    await pump(
      tester,
      const AuthSignedIn(session: session, verified: true, justSignedIn: true),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(UnlockSettingsStore(prefs).choiceRecorded, isFalse);
  });

  group('the store', () {
    test('being asked and being required are different facts', () async {
      await boot(<String, Object>{});
      final store = UnlockSettingsStore(prefs);

      // Fresh install: required by default, and nobody has been asked.
      expect(store.required, isTrue);
      expect(store.choiceRecorded, isFalse);

      await store.recordChoice(required: false);
      expect(store.required, isFalse);
      expect(store.choiceRecorded, isTrue);
    });

    test('a recorded "no" survives a restart', () async {
      await boot(<String, Object>{
        'unlock_choice_made': true,
        'unlock_required': false,
      });
      expect(UnlockSettingsStore(prefs).required, isFalse);
      expect(UnlockSettingsStore(prefs).choiceRecorded, isTrue);
    });
  });
}

/// An auth controller pinned to one state.
class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  Future<AuthState> build() async => _state;
}
