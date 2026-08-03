// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging.dart';
import '../repositories/device_unlock.dart';
import '../repositories/unlock_settings_store.dart';
import 'app_providers.dart';

/// Wall clock, injectable so the idle-timeout tests do not have to wait out a
/// real two minutes.
typedef Clock = DateTime Function();

final clockProvider = Provider<Clock>((ref) => DateTime.now);

final deviceUnlockProvider =
    Provider<DeviceUnlock>((ref) => LocalDeviceUnlock());

final unlockSettingsStoreProvider = Provider<UnlockSettingsStore>(
  (ref) => UnlockSettingsStore(ref.watch(sharedPreferencesProvider)),
);

enum LockPhase {
  /// The gate is up. Nothing behind it is reachable.
  locked,

  /// The system prompt is on screen.
  unlocking,

  /// Through.
  unlocked,

  /// The device has no PIN, pattern or biometric, so there is nothing to ask
  /// for. The user is told, once, and then let through.
  cannotEnforce,
}

class UnlockState {
  const UnlockState({required this.phase, this.lastFailure});

  final LockPhase phase;

  /// Why the last attempt did not get through, for the lock screen to explain.
  /// Null on a fresh lock — there is nothing to apologise for yet.
  final UnlockOutcome? lastFailure;

  /// Whether the app behind the gate is reachable.
  ///
  /// [LockPhase.cannotEnforce] is **not** open. The gate stays up showing the
  /// explanation until the user acknowledges it — a notice nobody has to look
  /// at is a notice nobody reads, and this one is the difference between a
  /// phone that is gated and one that only appears to be.
  bool get isOpen => phase == LockPhase.unlocked;
}

final lockControllerProvider =
    NotifierProvider<LockController, UnlockState>(LockController.new);

/// Ground rule 9: Garfin holds an admin token on a phone that gets handed to
/// children, which is the one case device lock does not cover.
///
/// Two triggers, and the second is the one that matters. A cold start is the
/// easy path and the least useful — a phone that is handed over is almost
/// always *resumed*, not cold-started (issue #18, `SECURITY.md`). So the idle
/// timeout on resume is the real feature and the rest is scaffolding around it.
class LockController extends Notifier<UnlockState> {
  /// When Garfin was last actually backgrounded.
  ///
  /// Deliberately only set for [AppLifecycleState.paused] and not for
  /// `inactive`: the system unlock prompt itself makes the app inactive, so
  /// treating that as "backgrounded" would start the idle clock during the very
  /// prompt meant to stop it.
  DateTime? _backgroundedAt;

  /// Set once the user has read the "this phone has nothing to ask for"
  /// notice. After that the gate stops repeating itself for the rest of the
  /// session: the phone still has no credential, and saying so on every resume
  /// would be nagging about something the user has already been told and
  /// cannot fix from here.
  bool _cannotEnforceAcknowledged = false;

  UnlockSettingsStore get _settings => ref.read(unlockSettingsStoreProvider);
  DeviceUnlock get _unlock => ref.read(deviceUnlockProvider);
  DateTime get _now => ref.read(clockProvider)();

  @override
  UnlockState build() => _settings.required
      ? const UnlockState(phase: LockPhase.locked)
      : const UnlockState(phase: LockPhase.unlocked);

  /// Asks the device who this is.
  ///
  /// [reason] is what the system prompt displays, so it is user-facing copy and
  /// comes in already localised from the screen — there is no `BuildContext`
  /// here to resolve `AppLocalizations` from.
  ///
  /// Called once each time the lock screen appears, and again when the user
  /// taps Unlock. Never in a loop: a failed attempt leaves the gate up with an
  /// explanation and a button, because re-prompting automatically is how a
  /// user ends up locked out of their own phone by a rate limiter.
  Future<void> unlock({required String reason}) async {
    if (state.phase == LockPhase.unlocking) return;
    state = const UnlockState(phase: LockPhase.unlocking);

    if (!await _unlock.canBeEnforced()) {
      if (!ref.mounted) return;
      // A lock Garfin cannot enforce must not become a lock-out.
      log.info('device has no credential set; the gate cannot be enforced');
      state = UnlockState(
        phase: _cannotEnforceAcknowledged
            ? LockPhase.unlocked
            : LockPhase.cannotEnforce,
      );
      return;
    }

    final outcome = await _unlock.authenticate(reason: reason);
    if (!ref.mounted) return;

    switch (outcome) {
      case UnlockOutcome.unlocked:
        state = const UnlockState(phase: LockPhase.unlocked);
      case UnlockOutcome.cannotEnforce:
        state = UnlockState(
          phase: _cannotEnforceAcknowledged
              ? LockPhase.unlocked
              : LockPhase.cannotEnforce,
        );
      case UnlockOutcome.failed:
      case UnlockOutcome.cancelled:
      case UnlockOutcome.temporarilyLockedOut:
      case UnlockOutcome.biometricLockedOut:
      case UnlockOutcome.error:
        state = UnlockState(phase: LockPhase.locked, lastFailure: outcome);
    }
  }

  /// The user has read the "this phone has nothing to ask for" notice.
  void acknowledgeCannotEnforce() {
    if (state.phase != LockPhase.cannotEnforce) return;
    _cannotEnforceAcknowledged = true;
    state = const UnlockState(phase: LockPhase.unlocked);
  }

  /// Garfin went to the background. Starts the idle clock.
  void noteBackgrounded() {
    if (!state.isOpen) return;
    _backgroundedAt = _now;
  }

  /// Garfin came back. Locks again if it was away for longer than the setting.
  ///
  /// A zero timeout means "every time", which is why the comparison is `>=`.
  void noteResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || !_settings.required || !state.isOpen) return;

    final away = _now.difference(since);
    if (away >= _settings.idleTimeout) {
      log.info('locking after ${away.inSeconds}s in the background');
      state = const UnlockState(phase: LockPhase.locked);
    }
  }

  /// Applies a Settings change straight away.
  ///
  /// Switching the gate off should not leave it standing; switching it on
  /// should not immediately throw the user out of the screen they are on, since
  /// they are demonstrably already here. The next background locks it.
  Future<void> setRequired(bool value) async {
    await _settings.setRequired(value);
    if (!ref.mounted) return;
    if (!value && !state.isOpen) {
      state = const UnlockState(phase: LockPhase.unlocked);
    }
  }

  Future<void> setIdleTimeout(Duration value) => _settings.setIdleTimeout(value);

  /// What Settings should show as the current values.
  bool get isRequired => _settings.required;
  Duration get idleTimeout => _settings.idleTimeout;
}
