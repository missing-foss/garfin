// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'jellyfin_api.dart';

/// What a stop command actually achieved, read back from `/Sessions` (#70).
enum StopOutcome {
  /// Nothing is playing on that session any more.
  stopped,

  /// The session is still playing. The server accepted the command and the
  /// client did not act on it — which is the case a 204 cannot distinguish.
  stillPlaying,

  /// The read-back did not land. Nothing is claimed.
  unknown,
}

/// What ending a session achieved, read back from `/Sessions` (#70).
enum EndOutcome {
  /// No session for that device. The revoke held.
  signedOut,

  /// A session for that device is back. A client with saved credentials
  /// re-authenticates, and because sessions are keyed by device the new one
  /// wears the same name — indistinguishable, on screen, from a button that
  /// did nothing.
  signedBackIn,

  /// The read-back did not land. Nothing is claimed.
  unknown,
}

/// How long to wait before reading `/Sessions` back.
///
/// **A choice, not a measurement**, and the one number here that is neither
/// derived nor observed. What it has to cover is the client noticing a command
/// and its playback report reaching the server — two round trips over somebody
/// else's network to somebody else's app. Three seconds is long enough that a
/// cooperating client on a LAN has reported back, and short enough to still be
/// an answer to the tap that caused it.
///
/// Getting it wrong is not symmetric, which is why it errs long: too short
/// reports `stillPlaying` for a client that was about to comply — a false
/// accusation the parent then acts on — while too long only costs a few
/// seconds of a toast that already said something true.
///
/// It bounds [sessionToastDuration] in `session_result_toast.dart`: a toast
/// that dies before the read-back lands can never say anything but the pending
/// sentence.
const sessionSettle = Duration(seconds: 3);

/// Reads back what a session command achieved, instead of reporting what was
/// sent (#70).
///
/// **`204` is the server accepting a command, not the child's device obeying
/// it** — measured on 10.11.11, `Message` and `Playing/Stop` both answer 204
/// against a session whose `SupportsRemoteControl` is false and which cannot
/// act on either. Until #70 that left the copy with nothing honest to say
/// beyond "asked", and a parent watching a film carry on reasonably read
/// "asked" as "done".
///
/// So the outcome is observed rather than assumed, which is ground rule 1's
/// habit — the same one #65 and #68 fixed on the assign path — applied to the
/// last place in the app that still reported intent.
///
/// **This cannot make an uncooperative client obey.** Nothing over this API
/// can. It stops Garfin claiming a success it has not got, which is the
/// difference between a broken feature and a limitation a parent can work
/// around.
class SessionVerifier {
  const SessionVerifier(this._api, {this.settle = sessionSettle});

  final JellyfinApi _api;

  /// Injectable so tests do not pay it. See [sessionSettle].
  final Duration settle;

  /// Whether [sessionId] is still playing, a few seconds after being asked to
  /// stop.
  ///
  /// A session that has **disappeared** counts as [StopOutcome.stopped]: within
  /// seconds of an active playing session, absence means the client went away,
  /// and it is not playing anything the server knows about either way. The
  /// alternative — reporting [StopOutcome.unknown] — would say nothing about
  /// the one case where the parent can see for themselves that it worked.
  Future<StopOutcome> verifyStopped({required String sessionId}) async {
    await Future<void>.delayed(settle);
    try {
      final sessions = await _api.sessions();
      for (final session in sessions) {
        if (session.id == sessionId) {
          return session.isPlaying
              ? StopOutcome.stillPlaying
              : StopOutcome.stopped;
        }
      }
      return StopOutcome.stopped;
    } on Object {
      // Deliberately swallowed. A failed read-back is not a failed command:
      // the stop was accepted, and this is the *verification* being unable to
      // report. The caller keeps the sentence it already said.
      return StopOutcome.unknown;
    }
  }

  /// Whether a session for [deviceId] is back, a few seconds after the device
  /// was revoked.
  ///
  /// Matched on the **device**, and on the device alone. Two measurements on
  /// 10.11.11 say why the missing `userId` clause is not an oversight (#104,
  /// `docs/JELLYFIN-API.md` § *Ending a session*):
  ///
  /// - `DELETE /Devices?id=` is **device-wide**. With two users signed in on one
  ///   device id, a single revoke put *both* tokens on 401, while an untouched
  ///   user on another device stayed 200. There is no per-user session left
  ///   behind for a `userId` clause to exclude.
  /// - `/Sessions` holds at most **one row per device id**. A second user signing
  ///   in on the same device takes the existing row over — same session id, new
  ///   user name — rather than adding one, so the sibling's session that a
  ///   device-only match could confuse for the child's own cannot be there.
  ///
  /// Comparing `userId` would also make the sentence *less* true: the copy names
  /// the **device**, and under that takeover a user-scoped match would report the
  /// tablet signed out while it is signed in as someone else.
  ///
  /// Not the session id either — but **not** for the reason first given here. An
  /// earlier draft of this comment said a re-authenticating client gets a *new*
  /// session id, so checking the old one would report success every time. On the
  /// path this method actually runs — revoke, then sign back in on that device —
  /// the id is **identical** either side. Matching it would have worked; it is
  /// simply narrower than the device, which is what the copy is about. The claim
  /// was never measured, and it is the one this file's own § warns of.
  ///
  /// **What this cannot see:** whether a film already in flight kept playing.
  /// Revoking a token ends the session, and an ended session is not in
  /// `/Sessions` to be asked. That route is real and unmeasured
  Future<EndOutcome> verifyEnded({required String deviceId}) async {
    await Future<void>.delayed(settle);
    try {
      final sessions = await _api.sessions();
      for (final session in sessions) {
        if (session.deviceId == deviceId) return EndOutcome.signedBackIn;
      }
      return EndOutcome.signedOut;
    } on Object {
      return EndOutcome.unknown;
    }
  }
}
