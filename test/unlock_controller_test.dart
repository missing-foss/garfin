// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/unlock_providers.dart';
import 'package:garfin/repositories/device_unlock.dart';
import 'package:garfin/repositories/unlock_settings_store.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_device_unlock.dart';

/// Ground rule 9's timing, tested against a clock the test owns.
///
/// The case that matters is **resume after idle**, not cold start: a phone that
/// gets handed to a child is almost always resumed, and `SECURITY.md` names
/// that as the path needing verification.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDeviceUnlock device;
  late SharedPreferences prefs;
  late DateTime now;

  Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    device = FakeDeviceUnlock();
    now = DateTime(2026, 8, 3, 20, 0);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceUnlockProvider.overrideWithValue(device),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('cold start', () {
    test('starts locked when the gate is on, which is the default', () async {
      final container = await containerWith(<String, Object>{});

      expect(
        container.read(lockControllerProvider).phase,
        LockPhase.locked,
      );
    });

    test('starts open when the gate has been switched off', () async {
      final container =
          await containerWith(<String, Object>{'unlock_required': false});

      expect(container.read(lockControllerProvider).isOpen, isTrue);
    });

    test('a successful unlock opens the gate', () async {
      final container = await containerWith(<String, Object>{});
      device.outcome = UnlockOutcome.unlocked;

      await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'Unlock Garfin');

      expect(container.read(lockControllerProvider).phase, LockPhase.unlocked);
      expect(device.lastReason, 'Unlock Garfin');
    });

    test('a failed unlock leaves the gate up and keeps the reason', () async {
      final container = await containerWith(<String, Object>{});
      device.outcome = UnlockOutcome.temporarilyLockedOut;

      await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'Unlock Garfin');

      final state = container.read(lockControllerProvider);
      expect(state.phase, LockPhase.locked);
      expect(state.lastFailure, UnlockOutcome.temporarilyLockedOut);
      // One prompt, not a retry loop: re-prompting automatically is how a user
      // gets locked out of their own phone by a rate limiter.
      expect(device.prompts, 1);
    });
  });

  group('a phone with no credential set', () {
    test('is not locked out — it is told, and let through', () async {
      final container = await containerWith(<String, Object>{});
      device.enforceable = false;

      await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'Unlock Garfin');

      final state = container.read(lockControllerProvider);
      expect(state.phase, LockPhase.cannotEnforce);
      // The gate stays up until the notice has been acknowledged — a notice
      // nobody has to look at is a notice nobody reads.
      expect(state.isOpen, isFalse);
      // But it is one tap, not a dead end: a lock Garfin cannot enforce must
      // not become a lock-out.
      container
          .read(lockControllerProvider.notifier)
          .acknowledgeCannotEnforce();
      expect(container.read(lockControllerProvider).phase, LockPhase.unlocked);

      // No point showing a prompt the device cannot answer.
      expect(device.prompts, 0);
    });

    test('stops repeating itself once the notice has been read', () async {
      final container = await containerWith(<String, Object>{});
      final controller = container.read(lockControllerProvider.notifier);
      device.enforceable = false;

      await controller.unlock(reason: 'Unlock Garfin');
      controller.acknowledgeCannotEnforce();

      // Backgrounded long enough to relock, then back.
      controller.noteBackgrounded();
      now = now.add(const Duration(hours: 1));
      controller.noteResumed();
      await controller.unlock(reason: 'Unlock Garfin');

      // Straight through. The phone still has no credential and the user
      // cannot fix that from here, so saying it again on every resume would be
      // nagging.
      expect(container.read(lockControllerProvider).phase, LockPhase.unlocked);
    });
  });

  group('resume after idle — the case that actually matters', () {
    Future<ProviderContainer> unlocked([Map<String, Object>? stored]) async {
      final container = await containerWith(stored ?? <String, Object>{});
      await container
          .read(lockControllerProvider.notifier)
          .unlock(reason: 'Unlock Garfin');
      expect(container.read(lockControllerProvider).phase, LockPhase.unlocked);
      return container;
    }

    test('locks again after longer than the timeout', () async {
      final container = await unlocked();
      final controller = container.read(lockControllerProvider.notifier);

      controller.noteBackgrounded();
      // Default is two minutes. This is the phone being handed over and coming
      // back later.
      now = now.add(const Duration(minutes: 3));
      controller.noteResumed();

      expect(container.read(lockControllerProvider).phase, LockPhase.locked);
    });

    test('does not lock for a glance at a message', () async {
      final container = await unlocked();
      final controller = container.read(lockControllerProvider.notifier);

      controller.noteBackgrounded();
      now = now.add(const Duration(seconds: 20));
      controller.noteResumed();

      // Long enough not to nag while a parent is picking something. Two
      // minutes is the default for exactly this.
      expect(container.read(lockControllerProvider).phase, LockPhase.unlocked);
    });

    test('locks exactly at the timeout, not a second later', () async {
      final container = await unlocked();
      final controller = container.read(lockControllerProvider.notifier);

      controller.noteBackgrounded();
      now = now.add(UnlockSettingsStore.defaultIdleTimeout);
      controller.noteResumed();

      expect(container.read(lockControllerProvider).phase, LockPhase.locked);
    });

    test('a zero timeout means every time', () async {
      final container = await unlocked(
        <String, Object>{'unlock_idle_timeout_seconds': 0},
      );
      final controller = container.read(lockControllerProvider.notifier);

      controller.noteBackgrounded();
      controller.noteResumed();

      expect(container.read(lockControllerProvider).phase, LockPhase.locked);
    });

    test('a resume with no backgrounding before it changes nothing', () async {
      // The system unlock prompt makes the app *inactive*, not paused, and the
      // gate ignores inactive. If that ever changed, the prompt meant to end
      // the lock would be what re-armed it — so this asserts the resume alone
      // is inert.
      final container = await unlocked();

      container.read(lockControllerProvider.notifier).noteResumed();

      expect(container.read(lockControllerProvider).phase, LockPhase.unlocked);
    });

    test('does not lock when the gate has been switched off', () async {
      final container =
          await unlocked(<String, Object>{'unlock_required': false});
      final controller = container.read(lockControllerProvider.notifier);

      controller.noteBackgrounded();
      now = now.add(const Duration(hours: 2));
      controller.noteResumed();

      expect(container.read(lockControllerProvider).isOpen, isTrue);
    });
  });

  group('settings', () {
    test('two minutes is the default', () async {
      final container = await containerWith(<String, Object>{});

      expect(
        container.read(unlockSettingsStoreProvider).idleTimeout,
        const Duration(minutes: 2),
      );
      expect(container.read(unlockSettingsStoreProvider).required, isTrue);
    });

    test('a stored timeout is used, and a nonsense one is not', () async {
      var container = await containerWith(
        <String, Object>{'unlock_idle_timeout_seconds': 300},
      );
      expect(
        container.read(unlockSettingsStoreProvider).idleTimeout,
        const Duration(minutes: 5),
      );

      container = await containerWith(
        <String, Object>{'unlock_idle_timeout_seconds': -1},
      );
      expect(
        container.read(unlockSettingsStoreProvider).idleTimeout,
        UnlockSettingsStore.defaultIdleTimeout,
      );
    });

    test('switching the gate off takes the gate down', () async {
      final container = await containerWith(<String, Object>{});
      expect(container.read(lockControllerProvider).phase, LockPhase.locked);

      await container.read(lockControllerProvider.notifier).setRequired(false);

      expect(container.read(lockControllerProvider).isOpen, isTrue);
    });
  });

  group('plugin failure codes', () {
    test('no credential set is the one that must not lock anyone out', () {
      expect(
        LocalDeviceUnlock.mapExceptionCode(
          LocalAuthExceptionCode.noCredentialsSet,
        ),
        UnlockOutcome.cannotEnforce,
      );
    });

    test('a cancelled prompt is not a failed one', () {
      // Backing out of the dialog should not read as "that didn't match".
      for (final code in [
        LocalAuthExceptionCode.userCanceled,
        LocalAuthExceptionCode.systemCanceled,
        LocalAuthExceptionCode.timeout,
      ]) {
        expect(LocalDeviceUnlock.mapExceptionCode(code),
            UnlockOutcome.cancelled);
      }
    });

    test('lockouts are told apart, because the way out differs', () {
      // Waiting clears one; only a device credential clears the other.
      expect(
        LocalDeviceUnlock.mapExceptionCode(
          LocalAuthExceptionCode.temporaryLockout,
        ),
        UnlockOutcome.temporarilyLockedOut,
      );
      expect(
        LocalDeviceUnlock.mapExceptionCode(
          LocalAuthExceptionCode.biometricLockout,
        ),
        UnlockOutcome.biometricLockedOut,
      );
    });

    test('every code the plugin can report has an outcome', () {
      // The switch is exhaustive, so this is really a guard against a future
      // plugin version adding a code and this file not noticing.
      for (final code in LocalAuthExceptionCode.values) {
        expect(LocalDeviceUnlock.mapExceptionCode(code), isNotNull);
      }
    });
  });
}
