// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/unlock_providers.dart';
import 'package:garfin/repositories/unlock_settings_store.dart';
import 'package:garfin/repositories/window_security.dart';
import 'package:garfin/screens/unlock_settings_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_device_unlock.dart';

/// The unlock settings screen: the switch and the timeout are stored where the
/// lock reads them, the timeout cannot be changed while unlocking is off, and
/// the screenshot switch warns about the recent-apps preview only where the
/// preview is not covered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late List<bool> pushed;

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    bool? recentsCovered = true,
  }) async {
    // A phone, not the test default's 800x600: the screen is laid out for one.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    pushed = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceUnlockProvider.overrideWithValue(FakeDeviceUnlock()),
          windowSecurityProvider.overrideWithValue(_Window(pushed, covered: recentsCovered)),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UnlockSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile switchTitled(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));
  RadioListTile<Duration> radioTitled(WidgetTester tester, String title) =>
      tester.widget<RadioListTile<Duration>>(find.widgetWithText(RadioListTile<Duration>, title));

  testWidgets('every timeout choice is offered, labelled in words', (tester) async {
    await pump(tester);

    expect(find.byType(RadioListTile<Duration>),
        findsNWidgets(UnlockSettingsStore.idleTimeoutChoices.length));
    for (final label in ['Straight away', '1 minute', '2 minutes', '5 minutes', '15 minutes']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('a new timeout is stored where the lock reads it', (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.text('5 minutes'));
    await tester.tap(find.text('5 minutes'));
    await tester.pumpAndSettle();

    expect(UnlockSettingsStore(prefs).idleTimeout, const Duration(minutes: 5));
    expect(find.byWidgetPredicate((w) => w is RadioGroup<Duration> && w.groupValue == const Duration(minutes: 5)),
        findsOneWidget);
  });

  testWidgets('turning unlocking off is stored, and the timeout stops being choosable', (tester) async {
    await pump(tester);
    expect(switchTitled(tester, 'Ask when Garfin opens').value, isTrue, reason: 'the default');

    await tester.tap(find.text('Ask when Garfin opens'));
    await tester.pumpAndSettle();

    expect(UnlockSettingsStore(prefs).required, isFalse);
    expect(switchTitled(tester, 'Ask when Garfin opens').value, isFalse);
    expect(radioTitled(tester, '15 minutes').enabled, isFalse);

    final before = UnlockSettingsStore(prefs).idleTimeout;
    await tester.ensureVisible(find.text('15 minutes'));
    await tester.tap(find.text('15 minutes'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(UnlockSettingsStore(prefs).idleTimeout, before);
  });

  testWidgets('the screenshot switch tells the window', (tester) async {
    await pump(tester);
    expect(switchTitled(tester, 'Allow screenshots').value, isFalse, reason: 'the default');

    await tester.tap(find.text('Allow screenshots'));
    await tester.pumpAndSettle();

    expect(pushed, [true]);
    expect(switchTitled(tester, 'Allow screenshots').value, isTrue);
  });

  testWidgets('the recent-apps warning shows only where the preview is not covered', (tester) async {
    const cost = 'On this version of Android, turning this on also lets the recent-apps '
        'preview keep a picture of the screen after Garfin locks.';

    await pump(tester, recentsCovered: true);
    expect(find.textContaining(cost), findsNothing);

    await pump(tester, recentsCovered: false);
    expect(find.textContaining(cost), findsOneWidget);
  });

  testWidgets('while it is not yet known whether the preview is covered, the warning shows', (tester) async {
    // Unknown counts as uncovered: a warning shown where it was not needed is
    // the cheaper mistake than one missing where it was.
    const cost = 'On this version of Android, turning this on also lets the recent-apps '
        'preview keep a picture of the screen after Garfin locks.';

    await pump(tester, recentsCovered: null);
    expect(find.textContaining(cost), findsOneWidget);
  });
}

class _Window implements WindowSecurity {
  _Window(this.pushed, {required this.covered});

  final List<bool> pushed;

  /// Null: the platform never answers, as while the question is in flight.
  final bool? covered;

  @override
  Future<bool> setScreenshotsAllowed({required bool allowed}) async {
    pushed.add(allowed);
    return true;
  }

  @override
  Future<bool> isRecentsCovered() {
    final answer = covered;
    return answer == null ? Completer<bool>().future : Future.value(answer);
  }
}
