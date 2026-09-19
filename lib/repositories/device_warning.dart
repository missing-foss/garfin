// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

import '../logging.dart';

/// The warning that this app stops installing on certified Android devices.
///
/// Garfin ships as a sideloaded APK from its Releases page, and that is exactly
/// the installation route Google's developer-verification requirement closes.
/// Android is the only platform here, so there is no part of the audience the
/// warning does not reach.
///
/// **The dialog is the platform's, not Flutter's.** It is an
/// `android.app.AlertDialog` raised by the library on the other side of the
/// channel, so nothing in `lib/theme.dart` styles it and it will not match the
/// app around it. That is a known cost of taking the upstream library rather
/// than reimplementing its copy, and reimplementing it would mean maintaining a
/// claim about Google's policy in our own words.
///
/// **Why this is asked for rather than done at startup.** The platform side
/// could call this from `onCreate` in two lines, which is what upstream's
/// sample does. It runs before the first Flutter frame and before the unlock
/// gate, and two of the dialog's three buttons open a browser — `Details` goes
/// to keepandroidopen.org and the red `Solution` button to upstream's own
/// README; only OK is inert. So at that moment it offers a route out to
/// arbitrary web content to whoever is holding the device, authenticated or
/// not. Behind a parental gate that is the wrong trade, so the timing is Dart's
/// and the gate decides it.
///
/// Both destinations are upstream's defaults and are kept as such by a
/// deliberate decision rather than by not having looked. `THIRD_PARTY_NOTICES.md`
/// records them, because a parent leaving the app for a site neither we nor
/// Jellyfin control is not something a reader can infer from "it shows a
/// warning".
class DeviceWarning {
  DeviceWarning([this._channel = _default]);

  static const _default = MethodChannel(
    'org.missing_foss.garfin/device_warning',
  );

  final MethodChannel _channel;

  /// Whether this process has already asked.
  ///
  /// The gate opens more than once per launch — it relocks on resume and on the
  /// idle timeout — and the library only suppresses the dialog *after* someone
  /// taps OK. Dismissing it does not record anything. So without this, a parent
  /// who swipes the dialog away gets it again at every unlock for the rest of
  /// the session, which reads as a malfunction rather than a notice.
  ///
  /// **Once per launch is a choice, not the library's default, and the halves
  /// are deliberate in opposite directions.** Upstream writes `versionCodeWarn`
  /// only when OK is tapped, so a dismissed dialog returns on the next launch;
  /// that half is kept. A notice about the app becoming uninstallable is worth
  /// repeating to someone who has not acknowledged it, and the app cannot tell
  /// a considered dismissal from a stray tap. What is *not* kept is repeating
  /// it within one launch: the gate reopening is not a new session, and a
  /// dialog that returns every time a parent unlocks is read as something
  /// broken, which is the fastest way to teach them to dismiss it unread.
  ///
  /// **Consequence, measured 2026-09-16 on an emulator:** every button closes
  /// the dialog — it is a plain `AlertDialog` — and two of them leave for a
  /// browser, so tapping one ends the warning for that launch and the other
  /// link cannot be reached until the next one. It does come back: only `OK`
  /// writes `versionCodeWarn`, and a link button does not. Tapping `Details`
  /// then relaunching showed all three buttons again; tapping `OK` then
  /// relaunching showed nothing. See `docs/DECISIONS.md` § The certified-device
  /// warning is once a launch, and it comes back.
  bool _asked = false;

  /// Shows the warning if this launch has not already tried.
  ///
  /// **Silent on failure, deliberately, and this is the opposite of
  /// `WindowSecurity.setScreenshotsAllowed`.** There, a failure means a parent
  /// believes a protection is on when it is off, so it is reported. Here the
  /// worst case is that an advisory notice did not appear — nothing is less
  /// safe than it was, and there is no action for anyone to take. Failing loudly
  /// would put a crash in front of the parent in place of a dialog.
  ///
  /// Marked asked even when the call throws: a channel that is not there
  /// (anything that is not the Android app — the widget tests, most obviously)
  /// will not be there on the next unlock either, and retrying every time is
  /// how a missing platform becomes a log full of the same warning.
  Future<void> showIfDue() async {
    if (_asked) return;
    _asked = true;
    try {
      await _channel.invokeMethod<void>('showCertifiedDeviceWarning');
    } on Object catch (error) {
      log.info('no certified-device warning shown: ${error.runtimeType}');
    }
  }
}
