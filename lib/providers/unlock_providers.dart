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

    final UnlockOutcome outcome;
    try {
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
      outcome = await _unlock.authenticate(reason: reason);
    } on Object catch (error, stack) {
      // **This catch is the difference between a gate and a lock-out.**
      //
      // `canBeEnforced()` reaches the platform through pigeon, which raises
      // `PlatformException` when the channel is unavailable. Without this, that
      // escapes an un-awaited call in `LockScreen`, `phase` never leaves
      // `unlocking`, and the Unlock button is disabled in exactly that phase —
      // leaving the user on a lock screen with no working control, no message,
      // and the same outcome on every relaunch.
      //
      // Landing on `locked` with `error` is the honest state: the button is
      // live, `unlockError` explains it, and Garfin is *not* claiming to know
      // whether this phone has a credential. That last part matters — the
      // `cannotEnforce` path waves the user through and remembers doing so, and
      // a transient channel error must never be mistaken for it.
      if (!ref.mounted) return;
      log.warning('unlock attempt failed: ${error.runtimeType}', error, stack);
      state = const UnlockState(
        phase: LockPhase.locked,
        lastFailure: UnlockOutcome.error,
      );
      return;
    }

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

  /// Applies the one-time answer from `UnlockChoiceScreen` (#69).
  ///
  /// [UnlockChoice] owns writing the answer down; this half is only about where
  /// the gate stands afterwards. Answering "keep asking" must not leave the app
  /// unlocked behind the question — the gate has not run in this session, so it
  /// starts locked exactly as a cold start would. Answering "not now" opens it.
  ///
  /// Kept separate from [setRequired] because the two happen at different
  /// moments for different reasons: this one is a first-run choice, that one is
  /// a parent changing their mind in Settings, and that one must *not* throw
  /// them out of the screen they are on.
  ///
  /// The direction that actually needs this is "not now". On a fresh boot the
  /// controller is *built* after the preference is written, so [build] reads the
  /// new value and lands in the right phase unaided — a mutation removing this
  /// call left the "locks immediately" test green. A controller that is already
  /// alive keeps its state, and before any answer that state is locked; so the
  /// case that needs telling is opening the gate, and `unlock_start_test.dart`
  /// pins the controller alive to test exactly that.
  void applyUnlockChoice(bool required) {
    state = UnlockState(
      phase: required ? LockPhase.locked : LockPhase.unlocked,
    );
  }

  Future<void> setIdleTimeout(Duration value) => _settings.setIdleTimeout(value);

  /// What Settings should show as the current values.
  bool get isRequired => _settings.required;
  Duration get idleTimeout => _settings.idleTimeout;
}

/// Whether the parent has been asked the unlock question yet (#69).
///
/// A notifier rather than a plain read of [UnlockSettingsStore] at the call
/// site, because the answer changes *while the app is running* and the screen
/// asking the question is the thing that has to disappear when it does. A
/// `Provider` returning the store cannot do that: the store's identity never
/// changes when a preference is written, so nothing rebuilds and the question
/// stays on screen after being answered. That was the actual behaviour until a
/// test caught it.
class UnlockChoice extends Notifier<bool> {
  @override
  bool build() => ref.watch(unlockSettingsStoreProvider).choiceRecorded;

  /// Writes the answer down, then tells the gate where to stand.
  Future<void> record({required bool required}) async {
    await ref
        .read(unlockSettingsStoreProvider)
        .recordChoice(required: required);
    if (!ref.mounted) return;
    ref.read(lockControllerProvider.notifier).applyUnlockChoice(required);
    state = true;
  }
}

final unlockChoiceProvider =
    NotifierProvider<UnlockChoice, bool>(UnlockChoice.new);
