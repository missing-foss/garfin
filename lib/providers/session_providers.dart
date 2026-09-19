// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/active_session.dart';
import '../models/auth_session.dart';
import 'app_providers.dart';
import 'kids_providers.dart';
import 'library_providers.dart';

/// How often the welcome screen re-reads `/Sessions`.
///
/// **One interval, idle or streaming.** It has to poll when nothing is playing
/// or a stream *starting* is never noticed, which is most of what the block is
/// for. Ten seconds is about the latency a parent would accept for "someone
/// just started watching"; shorter buys nothing perceptible and costs a request
/// every time.
///
/// `/Sessions` is flat-cost and does not scale with library size, which is the
/// only reason polling it is affordable at all — see
/// [sessionCommandsInFlightProvider] for what must never be polled alongside it.
const sessionPollInterval = Duration(seconds: 10);

/// How many session commands are between *sent* and *read back*.
///
/// **A poll inside that window undoes the read-back.** Stop and End answer 204
/// whether or not the client obeyed, so both commands re-read `/Sessions` a few
/// seconds later and replace "asked to stop" with what actually happened. A
/// timer that re-reads in the meantime does exactly what `SessionCard._run`
/// already warns against — it asks the server before it can possibly reflect
/// the command, and the card redraws identical.
///
/// So the verifier's answer wins until it has given one: while this is above
/// zero the poll skips its tick entirely rather than racing it. Held as a count
/// rather than a flag because two cards can be commanded before either settles.
final sessionCommandsInFlightProvider =
    NotifierProvider<SessionCommandsInFlight, int>(SessionCommandsInFlight.new);

class SessionCommandsInFlight extends Notifier<int> {
  @override
  int build() => 0;

  void begin() => state = state + 1;

  /// Never below zero: a release that runs twice is a bug in the caller, but
  /// one that left this negative would suppress polling for the rest of the
  /// session and look like the timer had died.
  void end() => state = state > 0 ? state - 1 : 0;
}

/// The signed-in devices belonging to children Garfin manages.
///
/// **Filtered here, not by the server.** Measured: `/Sessions` accepts
/// `userId` and ignores it, answering with every session including the admin's
/// — so a screen that trusted the parameter would put somebody else's device
/// under a child's name.
///
/// Garfin's own device is excluded outright rather than shown and disabled:
/// ending it is a 204 followed by an immediate 401 on the next request, which
/// is signing the parent out of the app from inside the app. A control that
/// does that has no business being on screen at all.
final childSessionsProvider =
    FutureProvider.family<List<ActiveSession>, AuthSession>(
        (ref, session) async {
  final api = ref.watch(libraryApiProvider(session));
  // **The roster, not the overview.** All this needs is which users are
  // children; taking it from the counted payload would put the most expensive
  // query in the app behind every session read, including the polled ones.
  final roster = await ref.watch(kidsRosterProvider(session).future);
  final children = {
    for (final face in roster.shortlisted) face.user.id: face.user.name,
  };
  final ownDevice = ref.watch(deviceIdentityProvider).deviceId;

  final sessions = await api.sessions();
  return sessions
      .where((s) => children.containsKey(s.userId))
      .where((s) => s.deviceId != ownDevice)
      .toList(growable: false);
});
