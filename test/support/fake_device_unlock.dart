// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:garfin/repositories/device_unlock.dart';

/// A device whose unlock behaviour the test decides.
///
/// The cases worth testing are the ones that are hardest to produce on a real
/// handset on demand: a phone with no credential set at all, a rate-limited
/// lockout, a prompt the system took away. None of them can be arranged by
/// tapping a fingerprint reader.
class FakeDeviceUnlock implements DeviceUnlock {
  FakeDeviceUnlock({
    this.enforceable = true,
    this.outcome = UnlockOutcome.unlocked,
  });

  /// Whether the phone has a PIN, pattern or biometric at all.
  bool enforceable;

  /// What the prompt answers with.
  UnlockOutcome outcome;

  /// When false, [authenticate] hangs until [answer] is called.
  ///
  /// A real prompt sits on screen while the user looks at it, and some of what
  /// is worth testing — that the gate is up and the Unlock button is disabled
  /// *during* the prompt — only exists in that window. A fake that answers
  /// instantly skips straight past it.
  bool autoAnswer = true;

  int prompts = 0;
  String? lastReason;

  Completer<UnlockOutcome>? _pending;

  @override
  Future<bool> canBeEnforced() async => enforceable;

  @override
  Future<UnlockOutcome> authenticate({required String reason}) {
    prompts++;
    lastReason = reason;
    if (autoAnswer) return Future<UnlockOutcome>.value(outcome);
    final completer = Completer<UnlockOutcome>();
    _pending = completer;
    return completer.future;
  }

  /// Answers a prompt left hanging by `autoAnswer = false`.
  void answer(UnlockOutcome value) {
    final pending = _pending;
    _pending = null;
    pending?.complete(value);
  }
}
