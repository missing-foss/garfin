// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/settings_providers.dart';
import 'package:garfin/repositories/app_settings_store.dart';
import 'package:garfin/repositories/window_security.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The window's capture flag, and the setting that moves it.
///
/// `FLAG_SECURE` was never only about screenshots: it exists for the recents
/// thumbnail, and blocking capture was the accepted cost. This is a parent
/// choosing to stop paying that cost, so the default has to be the protected
/// one and the stored answer has to reach the window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Records what the platform was told, instead of telling it.
  late List<bool> pushed;

  ProviderContainer container(SharedPreferences prefs, {bool applies = true}) {
    pushed = <bool>[];
    return ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      windowSecurityProvider
          .overrideWithValue(_Recording(pushed, applies: applies)),
    ]);
  }

  test('the default is protected', () async {
    // The whole reason this is a setting and not a removal: a parent who never
    // opens it keeps the behaviour that was measured and chosen.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = AppSettingsStore(await SharedPreferences.getInstance());

    expect(store.allowScreenshots, isFalse);
  });

  test('it survives a relaunch', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = AppSettingsStore(prefs);

    await store.setAllowScreenshots(true);

    expect(AppSettingsStore(prefs).allowScreenshots, isTrue,
        reason: 'a second store over the same preferences is the next launch');
  });

  test('turning it on tells the window, not only the store', () async {
    // The half that would be easy to miss: a preference that is written and
    // never pushed leaves a parent looking at a switch that says yes and a
    // window that still refuses, until the next launch.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs);
    addTearDown(c.dispose);

    await c.read(settingsProvider.notifier).setAllowScreenshots(true);

    expect(pushed, [true]);
    expect(c.read(settingsProvider).allowScreenshots, isTrue);

    await c.read(settingsProvider.notifier).setAllowScreenshots(false);

    expect(pushed, [true, false]);
  });

  test('a window that refuses does not get recorded as if it agreed', () async {
    // **The direction that matters is revoking.** A failed *allow* leaves the
    // window secure and the switch simply not yet in effect. A failed *revoke*
    // would leave the window capturable while the store said otherwise — a
    // parent looking at protection they believe they turned back on. So the
    // preference follows the window rather than leading it, and neither
    // direction can write through a push that did not apply.
    SharedPreferences.setMockInitialValues(
      <String, Object>{'unlock_allow_screenshots': true},
    );
    final prefs = await SharedPreferences.getInstance();
    final c = container(prefs, applies: false);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).allowScreenshots, isTrue);

    await c.read(settingsProvider.notifier).setAllowScreenshots(false);

    expect(pushed, [false], reason: 'it did try');
    expect(c.read(settingsProvider).allowScreenshots, isTrue,
        reason: 'the switch stays where it was rather than claiming a state '
            'the window is not in');
    expect(AppSettingsStore(prefs).allowScreenshots, isTrue,
        reason: 'and nothing was written for the next launch to believe');
  });
}

class _Recording implements WindowSecurity {
  _Recording(this.pushed, {this.applies = true});

  final List<bool> pushed;

  /// Whether the platform accepts the change. False is the case the store must
  /// not write through.
  final bool applies;

  @override
  Future<bool> setScreenshotsAllowed({required bool allowed}) async {
    pushed.add(allowed);
    return applies;
  }

  @override
  Future<bool> isRecentsCovered() async => true;
}
