// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/unlock_providers.dart';
import 'package:garfin/repositories/device_unlock.dart';
import 'package:garfin/screens/lock_screen.dart';
import 'package:garfin/widgets/unlock_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_device_unlock.dart';

/// The gate as the user meets it, including the lifecycle wiring — which is
/// the half that cannot be tested by calling the controller directly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDeviceUnlock device;
  late SharedPreferences prefs;
  late DateTime now;

  setUp(() async {
    device = FakeDeviceUnlock();
    now = DateTime(2026, 8, 3, 20, 0);
  });

  Future<Widget> gatedApp(
      [Map<String, Object> stored = const <String, Object>{}]) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceUnlockProvider.overrideWithValue(device),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UnlockGate(child: _BehindTheGate()),
      ),
    );
  }

  /// Drives the real Android lifecycle sequence.
  ///
  /// Flutter enforces the state machine, so jumping straight to `paused` is not
  /// something the framework will let a test do — and stepping through it is
  /// closer to what actually happens anyway.
  Future<void> background(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  /// The app is still mounted behind the gate — that is deliberate, so a relock
  /// does not throw away what the user was in the middle of — but it must be
  /// covered, untouchable and invisible to a screen reader while the gate is
  /// up.
  void expectCovered(WidgetTester tester) {
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('behind the gate').hitTestable(), findsNothing);
    // Asserted on the wiring rather than on the compiled semantics tree, which
    // is only built while something holds a semantics handle and so makes for a
    // test that passes or fails depending on what ran before it.
    final excluded = tester.widget<ExcludeSemantics>(
      find
          .descendant(
            of: find.byType(UnlockGate),
            matching: find.byType(ExcludeSemantics),
          )
          .first,
    );
    expect(excluded.excluding, isTrue,
        reason: 'a screen reader must not read out the app behind the gate');
  }

  testWidgets('covers the app on a cold start and asks straight away',
      (tester) async {
    // Leave the prompt hanging, the way a real one sits on screen.
    device.autoAnswer = false;

    await tester.pumpWidget(await gatedApp());
    await tester.pump();

    expect(find.text('Garfin is locked'), findsOneWidget);
    expectCovered(tester);
    expect(device.prompts, 1);
    expect(device.lastReason, 'Unlock Garfin');

    // The button is disabled while the system prompt is up, so a second tap
    // cannot stack a second prompt behind the first.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    device.answer(UnlockOutcome.unlocked);
    await tester.pumpAndSettle();
    expect(find.text('behind the gate'), findsOneWidget);
  });

  testWidgets('opens once the device says yes', (tester) async {
    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();

    expect(find.text('behind the gate'), findsOneWidget);
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('stays up after a wrong fingerprint, and says why',
      (tester) async {
    device.outcome = UnlockOutcome.failed;

    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();

    expect(find.text("That didn't match. Try again."), findsOneWidget);
    expectCovered(tester);

    // The button is the way back, and it is the only way back — the gate does
    // not re-prompt on its own.
    expect(device.prompts, 1);
    device.outcome = UnlockOutcome.unlocked;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('behind the gate'), findsOneWidget);
    expect(device.prompts, 2);
  });

  testWidgets('a platform-channel failure leaves a working Unlock button',
      (tester) async {
    // The failure this whole feature must never produce: a lock screen with no
    // working control. `canBeEnforced()` reaches the platform through pigeon,
    // which raises PlatformException rather than LocalAuthException.
    device.throwOnCanBeEnforced =
        PlatformException(code: 'channel-error', message: 'no channel');

    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();

    expect(
      find.text("The phone couldn't ask for that just now. Try again."),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull,
        reason: 'a disabled button here is a permanent lock-out');

    // And the button works once the channel comes back.
    device.throwOnCanBeEnforced = null;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('behind the gate'), findsOneWidget);
  });

  testWidgets('a phone with no PIN is told plainly and let through',
      (tester) async {
    device.enforceable = false;

    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no PIN, pattern or fingerprint set'),
      findsOneWidget,
    );
    expectCovered(tester);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('behind the gate'), findsOneWidget);
  });

  testWidgets('locks again on resume after the idle timeout', (tester) async {
    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();
    expect(find.text('behind the gate'), findsOneWidget);

    await background(tester);
    now = now.add(const Duration(minutes: 3));
    // Keep the gate up this time so the assertion is about the relock rather
    // than about how fast the fake answers.
    device.outcome = UnlockOutcome.failed;
    await foreground(tester);
    await tester.pumpAndSettle();

    expect(find.text('Garfin is locked'), findsOneWidget);
    expectCovered(tester);
  });

  testWidgets('does not lock for a glance at a notification', (tester) async {
    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();

    await background(tester);
    now = now.add(const Duration(seconds: 15));
    await foreground(tester);
    await tester.pumpAndSettle();

    expect(find.text('behind the gate'), findsOneWidget);
    // Still the one prompt from the cold start.
    expect(device.prompts, 1);
  });

  testWidgets('the app behind the gate keeps its state across a relock',
      (tester) async {
    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('behind the gate'));
    await tester.pumpAndSettle();
    expect(find.text('tapped 1'), findsOneWidget);

    await background(tester);
    now = now.add(const Duration(minutes: 5));
    device.outcome = UnlockOutcome.failed;
    await foreground(tester);
    await tester.pumpAndSettle();
    expect(find.text('Garfin is locked'), findsOneWidget);

    device.outcome = UnlockOutcome.unlocked;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    // Not rebuilt from scratch: locking on resume should not throw away the
    // grid position or the sheet someone was halfway through.
    expect(find.text('tapped 1'), findsOneWidget);
  });

  testWidgets('what is behind the gate cannot be tapped while it is up',
      (tester) async {
    device.outcome = UnlockOutcome.failed;

    await tester.pumpWidget(await gatedApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('behind the gate'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('tapped 1'), findsNothing);
  });

  testWidgets('is absent entirely when the setting is off', (tester) async {
    await tester.pumpWidget(
      await gatedApp(<String, Object>{'unlock_required': false}),
    );
    await tester.pumpAndSettle();

    expect(find.text('behind the gate'), findsOneWidget);
    expect(device.prompts, 0);
  });
}

/// Stands in for the app. Counts taps so a test can tell "still mounted with
/// its state" from "rebuilt from scratch".
class _BehindTheGate extends StatefulWidget {
  const _BehindTheGate();

  @override
  State<_BehindTheGate> createState() => _BehindTheGateState();
}

class _BehindTheGateState extends State<_BehindTheGate> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => setState(() => _taps++),
              child: const Text('behind the gate'),
            ),
            if (_taps > 0) Text('tapped $_taps'),
          ],
        ),
      ),
    );
  }
}
