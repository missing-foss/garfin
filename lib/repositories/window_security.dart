// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

import '../logging.dart';

/// Whether the window may be captured, pushed to the platform.
///
/// **`FLAG_SECURE` is what this moves, and it was never only about
/// screenshots.** It exists for the recents thumbnail — measured, without it
/// Android snapshots the window on the way out and writes the full screen,
/// including text typed into the sign-in field, to disk where it survives a
/// relock. Blocking screenshots and screen mirroring was the accepted cost of
/// that, and it is the cost a parent asked to stop paying.
///
/// **From Android 13 they are separable**, which is why this is a setting
/// rather than a refusal: `setRecentsScreenshotEnabled(false)` covers the
/// snapshot without the flag. Below 13 there is no such API, so allowing
/// screenshots there really does give the snapshot back — the difference is
/// stated in `SECURITY.md` rather than smoothed over.
///
/// **A failure is reported rather than swallowed, and the direction is why.**
/// Swallowing is harmless when *allowing* fails — the window stays secure and
/// the switch simply has not taken effect. It is not harmless when *revoking*
/// fails: the window stays capturable while the store says otherwise, and a
/// parent is looking at protection they believe they turned back on. So this
/// answers whether it applied, and the caller writes the preference only then.
class WindowSecurity {
  const WindowSecurity([this._channel = _default]);

  static const _default = MethodChannel('org.missing_foss.garfin/window');

  final MethodChannel _channel;

  /// True when the window flag now matches [allowed].
  Future<bool> setScreenshotsAllowed({required bool allowed}) async {
    try {
      await _channel.invokeMethod<void>('setScreenshotsAllowed', allowed);
      return true;
    } on Object catch (error) {
      log.warning('could not set the window flag: ${error.runtimeType}');
      return false;
    }
  }

  /// Whether the recents thumbnail is covered without [FLAG_SECURE] — that is,
  /// whether allowing capture costs the snapshot as well.
  ///
  /// Asked of the platform rather than assumed from a version constant here:
  /// the activity owns the API check, and one place deciding it is what keeps
  /// the copy and the behaviour from drifting apart.
  ///
  /// **False on anything that cannot answer**, including a failure — the copy
  /// it drives warns about a cost, and the safe error is the warning shown
  /// where it was not needed rather than withheld where it was.
  Future<bool> isRecentsCovered() async {
    try {
      return await _channel.invokeMethod<bool>('isRecentsCovered') ?? false;
    } on Object catch (error) {
      log.warning('could not ask about the thumbnail: ${error.runtimeType}');
      return false;
    }
  }
}
