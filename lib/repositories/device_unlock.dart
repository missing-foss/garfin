// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../logging.dart';

/// How an unlock attempt ended, in the terms the lock screen needs.
enum UnlockOutcome {
  /// The user proved who they are.
  unlocked,

  /// They tried and it did not match. Worth offering another go.
  failed,

  /// They backed out, or the system took the prompt away.
  cancelled,

  /// Too many attempts. Waiting helps.
  temporarilyLockedOut,

  /// Biometrics are locked until a device credential is used. The prompt
  /// already allows one, so this is mostly informational.
  biometricLockedOut,

  /// **The device has no PIN, pattern or biometric at all.**
  ///
  /// Garfin cannot ask for something the phone does not have. This is the case
  /// issue #18 is explicit about: say so plainly and let the user carry on. A
  /// lock Garfin cannot enforce must not become a lock-out.
  cannotEnforce,

  /// Something went wrong that is not the user's doing.
  error,
}

/// The device's own unlock, wrapped.
///
/// An interface so the gate can be tested without a fingerprint reader — the
/// cases worth testing (no credential set, cancelled, locked out) are exactly
/// the ones that are hardest to produce on a real device on demand.
abstract class DeviceUnlock {
  /// Whether the phone has anything Garfin could ask for.
  Future<bool> canBeEnforced();

  /// Shows the system prompt. [reason] is what the OS displays.
  Future<UnlockOutcome> authenticate({required String reason});
}

class LocalDeviceUnlock implements DeviceUnlock {
  LocalDeviceUnlock([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canBeEnforced() async {
    try {
      // True when there is a biometric enrolled *or* a device credential set.
      // Read from `local_auth_android`: `isDeviceSupported()` is
      // `isDeviceSecure() || canAuthenticateWithBiometrics()`.
      return await _auth.isDeviceSupported();
    } on LocalAuthException catch (error) {
      log.warning('could not read device unlock capability: ${error.code.name}');
      return false;
    }
  }

  /// One prompt: biometric where there is one, device credential otherwise.
  ///
  /// `biometricOnly: false` is what makes the fallback happen, and it is also
  /// what covers **API 26–27**. Issue #18 describes those as going "straight to
  /// device credential" because `android.hardware.biometrics.BiometricPrompt`
  /// arrived in API 28. Read from the plugin's source, the mechanism is a step
  /// removed from that: `local_auth_android` uses **androidx**'s
  /// `BiometricPrompt`, which has its own compatibility path below 28, and
  /// decides with `allowCredentials = !biometricOnly &&
  /// canAuthenticateWithDeviceCredential()` — where, below API 30, that second
  /// term is just `KeyguardManager.isDeviceSecure()`.
  ///
  /// The outcome on 26–27 is the one the issue asks for — a phone with only a
  /// PIN gets the device-credential prompt — but it is reached by asking what
  /// the device *can do* rather than what version it runs. That is the better
  /// branch anyway: it also covers a modern phone whose fingerprint reader is
  /// broken, enrolled-then-removed, or temporarily unavailable, none of which a
  /// version check would catch. Not measured on a 26–27 device; there is no
  /// emulator image installed and no such handset here.
  ///
  /// `persistAcrossBackgrounding` matters more here than it looks: on some
  /// devices the prompt itself backgrounds the app, and without it the gate
  /// would report a cancellation the user never made.
  @override
  Future<UnlockOutcome> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? UnlockOutcome.unlocked : UnlockOutcome.failed;
    } on LocalAuthException catch (error) {
      return mapExceptionCode(error.code);
    }
  }

  /// The mapping from the plugin's failure codes to Garfin's.
  ///
  /// Public for tests: the codes that matter most here — no credential set,
  /// locked out — are the ones that cannot be produced on a real device on
  /// demand, and the switch is exhaustive so a plugin upgrade that adds a code
  /// fails the analyzer rather than falling through to something wrong.
  @visibleForTesting
  static UnlockOutcome mapExceptionCode(LocalAuthExceptionCode code) =>
      switch (code) {
        LocalAuthExceptionCode.noCredentialsSet => UnlockOutcome.cannotEnforce,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout =>
          UnlockOutcome.cancelled,
        LocalAuthExceptionCode.temporaryLockout =>
          UnlockOutcome.temporarilyLockedOut,
        LocalAuthExceptionCode.biometricLockout =>
          UnlockOutcome.biometricLockedOut,
        // With a device credential allowed, none of these should end the
        // attempt — but if the platform reports one anyway, "try again" is both
        // true and the only useful thing to offer.
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.authInProgress =>
          UnlockOutcome.failed,
        LocalAuthExceptionCode.uiUnavailable ||
        LocalAuthExceptionCode.deviceError ||
        LocalAuthExceptionCode.unknownError =>
          UnlockOutcome.error,
      };
}
