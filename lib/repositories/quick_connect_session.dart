// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../logging.dart';
import '../models/authentication_result.dart';
import 'jellyfin_api.dart';
import 'jellyfin_exception.dart';

/// One Quick Connect pairing, from `Initiate` to an access token.
///
/// Owns the `Secret` for the whole of its short life and is the only object
/// that ever holds it. The secret is **never written to disk** — see
/// `docs/JELLYFIN-API.md` and the settled decision in `docs/DECISIONS.md` — and
/// is dropped on success, on timeout and on [dispose].
///
/// ## Polling, designed around backgrounding
///
/// Approving the code means opening an already-signed-in Jellyfin session,
/// usually on the same phone. So Garfin being backgrounded mid-pairing is the
/// **normal** path, not an edge case (issue #17), and two things follow:
///
/// * The loop is a plain `Future`-based delay rather than anything tied to a
///   frame callback or a ticker, so it keeps running while the app is not on
///   screen. Nothing here needs the widget tree.
/// * [poke] exists so the screen can shorten the current wait when the app
///   comes back to the foreground. A user who has just approved the code
///   shouldn't sit through the rest of a five-second backoff to find out.
///
/// If Android kills the process, the secret goes with it and pairing restarts
/// with a fresh code. That is the intended behaviour, not a gap to engineer
/// around.
class QuickConnectSession {
  QuickConnectSession({
    required this._api,
    this.timeout = const Duration(minutes: 3),
    this.initialInterval = const Duration(seconds: 1),
    this.maxInterval = const Duration(seconds: 5),
    this.backoffFactor = 1.5,
  });

  final JellyfinApi _api;

  /// How long to keep asking before giving up and offering a fresh code.
  ///
  /// Shorter than Jellyfin's own code expiry so the user is told the code is
  /// dead by Garfin rather than discovering it by typing an expired one.
  final Duration timeout;

  /// The first gap between polls, and the gap [poke] resets to.
  final Duration initialInterval;

  /// The ceiling. "Do not hammer" (`docs/JELLYFIN-API.md`) is the requirement;
  /// a five-second worst case still feels immediate to someone watching a
  /// progress bar.
  final Duration maxInterval;

  final double backoffFactor;

  final CancelToken _cancelToken = CancelToken();

  /// The credential half of the pairing. In memory, for one exchange.
  ///
  /// Dart strings are immutable, so this can be dropped but not overwritten in
  /// place — worth being honest about. Dropping the last reference is the whole
  /// of what "cleared" can mean here, and it is why the secret is never handed
  /// to anyone else: no copy exists to outlive this field.
  String? _secret;

  String? _code;

  /// The six digits, once known. Not a credential — it is inert without the
  /// secret, and it exists to be read aloud off a screen.
  String? get code => _code;

  /// Whether a secret is currently held.
  ///
  /// Deliberately a boolean and not the value: tests need to prove the secret
  /// was dropped on success, on timeout and on [dispose], and none of them
  /// needs to read it. A getter that returned the secret would be a second way
  /// out of this class, which is exactly what the no-copies rule above is for.
  @visibleForTesting
  bool get holdsSecret => _secret != null;

  bool _disposed = false;
  Completer<void>? _wake;
  Timer? _sleepTimer;
  bool _resetBackoff = false;

  /// Runs the pairing to completion.
  ///
  /// Throws [JellyfinException] with [JellyfinErrorKind.quickConnectExpired] if
  /// the code is never approved inside [timeout], or
  /// [JellyfinErrorKind.cancelled] if [dispose] is called first.
  Future<AuthenticationResult> run({void Function(String code)? onCode}) async {
    final initiation =
        await _api.initiateQuickConnect(cancelToken: _cancelToken);
    if (_disposed) {
      throw const JellyfinException(JellyfinErrorKind.cancelled);
    }
    _secret = initiation.secret;
    _code = initiation.code;
    onCode?.call(initiation.code);

    try {
      final elapsed = Stopwatch()..start();
      var interval = initialInterval;

      while (true) {
        if (_disposed) {
          throw const JellyfinException(JellyfinErrorKind.cancelled);
        }

        final approved = await _pollOnce();
        if (approved) {
          // Read from a local rather than from `_secret!`. Today that null
          // assertion cannot actually fire — the chain from the poll's HTTP
          // response to this line is one microtask drain, and `dispose()` runs
          // from an event-loop task, so it has no window to interleave. But
          // that is an argument about Dart's scheduling rather than about this
          // class, and one extra `await` inside `_pollOnce` would quietly
          // invalidate it. A local makes the invariant local.
          final secret = _secret;
          if (secret == null || _disposed) {
            throw const JellyfinException(JellyfinErrorKind.cancelled);
          }
          // The trade. After this the secret is spent, and the `finally` below
          // drops it whether or not this call succeeds.
          return await _api.authenticateWithQuickConnect(
            secret,
            cancelToken: _cancelToken,
          );
        }

        if (elapsed.elapsed >= timeout) {
          throw const JellyfinException(
            JellyfinErrorKind.quickConnectExpired,
            message: 'quick connect not approved within the polling window',
          );
        }

        await _sleep(interval);
        interval = _resetBackoff
            ? initialInterval
            : _capped(interval * backoffFactor);
        _resetBackoff = false;
      }
    } finally {
      _secret = null;
    }
  }

  /// One `GET /QuickConnect/Connect`, tolerant of the network going away.
  ///
  /// A dropped connection while the user is over in the Jellyfin app is
  /// expected — the phone may have changed network, or the radio may have been
  /// idle. Those keep polling until [timeout]. An expired code or a rejected
  /// request does not: those are answers, and the user needs to hear them.
  Future<bool> _pollOnce() async {
    try {
      final status = await _api.quickConnectStatus(
        _secret!,
        cancelToken: _cancelToken,
      );
      return status.authenticated;
    } on JellyfinException catch (error) {
      switch (error.kind) {
        // `unusableUserId` is Garfin refusing to *approve* without a user id
        // (#40). Polling never sends one, so it cannot arrive here — named
        // rather than defaulted, so a future kind still fails to compile.
        case JellyfinErrorKind.unusableUserId:
        case JellyfinErrorKind.unreachable:
        case JellyfinErrorKind.timeout:
        case JellyfinErrorKind.server:
          // No secret can reach the log here: JellyfinException never carries
          // the request URI, and `redactSecrets` scrubs the message anyway.
          log.fine('quick connect poll failed, still waiting: ${error.kind.name}');
          return false;
        case JellyfinErrorKind.unauthorized:
        case JellyfinErrorKind.forbidden:
        case JellyfinErrorKind.notFound:
        case JellyfinErrorKind.quickConnectUnavailable:
        case JellyfinErrorKind.quickConnectExpired:
        case JellyfinErrorKind.notAdministrator:
        case JellyfinErrorKind.cancelled:
          rethrow;
      }
    }
  }

  /// Cuts the current wait short and drops the backoff back to
  /// [initialInterval].
  ///
  /// Called when the app returns to the foreground: the likeliest reason the
  /// user is back is that they have just approved the code.
  void poke() {
    _resetBackoff = true;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Abandons the pairing and drops the secret.
  ///
  /// Safe to call twice, and safe to call while [run] is in flight — the loop
  /// notices on its next turn and the in-flight request is cancelled.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _secret = null;
    // Cancel the pending timer here rather than leaving it to `_sleep`'s
    // `finally`. That cleanup only runs once the awaiting loop is resumed, and
    // a screen being popped is exactly the case where nothing gets round to
    // resuming it — the timer would outlive the widget tree.
    _sleepTimer?.cancel();
    _sleepTimer = null;
    poke();
    if (!_cancelToken.isCancelled) _cancelToken.cancel('quick connect disposed');
  }

  Future<void> _sleep(Duration duration) async {
    final completer = Completer<void>();
    _wake = completer;
    _sleepTimer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await completer.future;
    } finally {
      _sleepTimer?.cancel();
      _sleepTimer = null;
      _wake = null;
    }
  }

  Duration _capped(Duration value) =>
      value > maxInterval ? maxInterval : value;
}
