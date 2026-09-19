// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/active_session.dart';
import '../models/auth_session.dart';
import '../providers/library_providers.dart';
import '../providers/session_providers.dart';
import '../repositories/session_verifier.dart';
import 'session_result_toast.dart';

/// One signed-in device, and the three things a parent can do about it (#41).
///
/// **A 204 is the server accepting a command, not the child's device obeying
/// it.** Measured on 10.11.11: `Message` and `Playing/Stop` both answer 204
/// against a session whose `SupportsRemoteControl` is false and which cannot
/// act on either. So the copy says what Garfin *sent* — "Sent to", "Asked to
/// stop" — and never claims the child saw it.
///
/// **Since #70, saying what was sent is where the two disruptive commands
/// start rather than where they finish.** "Asked to stop" reads as "stopped" to
/// a parent watching a film carry on, and ending a session leaves a list that
/// looks unchanged when the client signs straight back in. So both read
/// `/Sessions` back a few seconds later and replace the sentence with what
/// actually happened — [SessionVerifier]. The message command does not, and
/// that is a decision rather than an oversight: nothing was looked for or
/// measured that would report whether a line of text was displayed, so "sent"
/// stays the whole of what that command claims.
///
/// **End sends the stop command before revoking, and the order is
/// load-bearing.** End is specified to stop what the child is watching *and*
/// kill the session; a revoke on its own was never the whole of it, and until
/// now it never even asked. The stop is addressed to the session and the revoke
/// removes that session from `/Sessions`, so reversed the command goes to
/// something no longer there and there is nothing left to read back either.
///
/// **Stop is disabled when `SupportsRemoteControl` is false**, reversing the
/// decision that previously stood here: offering a button known in advance not
/// to work is the same dishonesty as a toast reporting intent as outcome. The
/// earlier argument — that the flag is the client's own claim, so disabling on
/// it withdraws a control that might have worked on the strength of a
/// self-report — is still true, and is the price of this. End stays enabled,
/// because the revoke works whatever the flag says, but its confirmation no
/// longer promises the film stops.
///
/// The order is deliberate: a message first, because it is the move a parent
/// actually wants most of the time and the only one that costs the child
/// nothing.
class SessionCard extends ConsumerStatefulWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.active,
  });

  final AuthSession session;
  final ActiveSession active;

  @override
  ConsumerState<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<SessionCard> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final active = widget.active;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tv_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(active.userName,
                          style: theme.textTheme.titleMedium),
                      Text(
                        l10n.sessionsOn(_deviceLabel(active)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _NowPlaying(active: active, serverUrl: widget.session.serverUrl),
            if (active.progress case final progress?) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
            if (!active.supportsRemoteControl) ...[
              const SizedBox(height: 8),
              Text(
                l10n.sessionsUncontrollable,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(l10n.sessionsMessage),
                  onPressed: _working ? null : _message,
                ),
                if (active.isPlaying)
                  TextButton.icon(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: Text(l10n.sessionsStop),
                    onPressed: _working || !active.supportsRemoteControl
                        ? null
                        : _stop,
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(l10n.sessionsEnd),
                  onPressed: _working ? null : _end,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A device with no name of its own is described by its client rather than
  /// left blank — "Jellyfin Android" is more use to a parent than nothing.
  static String _deviceLabel(ActiveSession active) =>
      active.deviceName.isNotEmpty ? active.deviceName : active.client;

  Future<void> _message() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sessionsMessage),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(
            hintText: l10n.sessionsMessageHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.sessionsMessageSend),
          ),
        ],
      ),
    );
    controller.dispose();
    // No confirmation for this one: a message is the move that costs the child
    // nothing, and ground rule 6 is about consequential acts.
    if (text == null || text.isEmpty || !mounted) return;

    await _run(
      () => ref.read(libraryApiProvider(widget.session)).sendSessionMessage(
            sessionId: widget.active.id,
            text: text,
            header: 'Garfin',
          ),
      l10n.sessionsMessageSent(_deviceLabel(widget.active)),
    );
  }

  Future<void> _stop() async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      title: l10n.sessionsStopConfirm(widget.active.userName),
      action: l10n.sessionsStop,
    )) {
      return;
    }
    final device = _deviceLabel(widget.active);
    await _run(
      () => ref
          .read(libraryApiProvider(widget.session))
          .stopSessionPlayback(sessionId: widget.active.id),
      l10n.sessionsStopSent(device),
      verify: () async => switch (await _verifier.verifyStopped(
        sessionId: widget.active.id,
      )) {
        StopOutcome.stopped => l10n.sessionsStopStopped(device),
        StopOutcome.stillPlaying => l10n.sessionsStopIgnored(device),
        // Nothing learned, so nothing said: "asked to stop" stays, and it is
        // still true.
        StopOutcome.unknown => null,
      },
    );
  }

  Future<void> _end() async {
    final l10n = AppLocalizations.of(context);
    final active = widget.active;
    if (!await _confirm(
      title: l10n.sessionsEndConfirm(active.userName, _deviceLabel(active)),
      // A device that says it cannot be remote-controlled gets a body that does
      // not promise the film stops, because for that device it will not.
      body: active.supportsRemoteControl
          ? l10n.sessionsEndExplain
          : l10n.sessionsEndExplainUncontrollable,
      action: l10n.sessionsEnd,
    )) {
      return;
    }
    final device = _deviceLabel(active);
    final api = ref.read(libraryApiProvider(widget.session));
    // Read back while the session still exists, because after the revoke it is
    // gone from `/Sessions` and cannot be asked. Null when nothing was playing:
    // there is no stop to report on.
    StopOutcome? playback;
    await _run(
      () async {
        if (active.isPlaying) {
          await api.stopSessionPlayback(sessionId: active.id);
          playback = await _verifier.verifyStopped(sessionId: active.id);
        }
        await api.endSession(deviceId: active.deviceId);
      },
      l10n.sessionsEnded(device),
      verify: () async => _endSentence(
        l10n,
        device,
        playback,
        await _verifier.verifyEnded(deviceId: active.deviceId),
      ),
    );
  }

  /// The two facts End has to leave the parent holding: whether the film
  /// stopped, and whether the device is actually out.
  ///
  /// Null keeps the pending sentence, which already says the device is signed
  /// out. That is the right answer twice over — when nothing was playing, and
  /// when a read-back landed on nothing. Neither is inferred from a 204.
  String? _endSentence(
    AppLocalizations l10n,
    String device,
    StopOutcome? playback,
    EndOutcome session,
  ) =>
      switch ((playback, session)) {
        (StopOutcome.stopped, EndOutcome.signedOut) =>
          l10n.sessionsEndStoppedAndOut(device),
        (StopOutcome.stillPlaying, EndOutcome.signedOut) =>
          l10n.sessionsEndOutStillPlaying(device),
        (StopOutcome.stopped, EndOutcome.signedBackIn) =>
          l10n.sessionsEndStoppedThenReturned(device),
        (StopOutcome.stillPlaying, EndOutcome.signedBackIn) =>
          l10n.sessionsEndReturnedStillPlaying(device),
        // Nothing was playing, or the stop read-back learned nothing. The
        // return is still worth saying on its own.
        (_, EndOutcome.signedBackIn) => l10n.sessionsEndReturned(device),
        (_, _) => null,
      };

  SessionVerifier get _verifier =>
      SessionVerifier(ref.read(libraryApiProvider(widget.session)));

  /// Ground rule 6, for the two commands that take something away.
  Future<bool> _confirm({
    required String title,
    required String action,
    String? body,
  }) async {
    final l10n = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer == true && mounted;
  }

  /// Runs a command, says what was sent, and — where there is something to read
  /// back — replaces that with what happened (#70).
  ///
  /// [verify] resolving to `null` leaves [sent] on screen. A verification that
  /// could not be made is not a failure to report; the command was still
  /// accepted, and the sentence already shown is still true.
  Future<void> _run(
    Future<void> Function() command,
    String sent, {
    Future<String?> Function()? verify,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Held from *sent* until *read back*, so the welcome screen's timer does
    // not re-read `/Sessions` in between and redraw the card with a state the
    // server has not caught up to yet. Released on every exit, including the
    // ones that never reach a verification — a counter left raised would stop
    // the poll for good and read as a dead timer.
    final inFlight = ref.read(sessionCommandsInFlightProvider.notifier);
    inFlight.begin();
    var released = false;
    void release() {
      if (released) return;
      released = true;
      inFlight.end();
    }

    setState(() => _working = true);
    try {
      await command();
      if (!mounted) {
        release();
        return;
      }

      if (verify == null) {
        ref.invalidate(childSessionsProvider(widget.session));
        messenger.showSnackBar(SnackBar(content: Text(sent)));
        release();
        return;
      }

      // Started here rather than inside the toast so that one read-back serves
      // both the sentence and the card, and so it survives the toast being
      // swiped away.
      final outcome = verify();
      messenger.showSnackBar(
        sessionResultToast(pending: sent, resolved: outcome),
      );
      // **Refreshed after the read-back, not before.** Invalidating on the way
      // out re-reads `/Sessions` before the server can possibly reflect the
      // command, so the card redraws identical — which is half of what made
      // "nothing happened" the obvious reading (#70).
      unawaited(
        outcome.whenComplete(() {
          if (mounted) ref.invalidate(childSessionsProvider(widget.session));
          // After the invalidate, not before: releasing first would let a tick
          // land between the two and re-read the very state this is replacing.
          release();
        }),
      );
    } on Object {
      release();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorServer)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

/// What the child is watching, said in as many words as the server gives.
///
/// **An episode name on its own is not an answer.** Reported from use: a card
/// reading "Chapter 3" or "The One Where…" tells a parent nothing about what is
/// on the screen. So an episode shows the show it belongs to as its title and
/// the episode name underneath it, and a film — which was always
/// self-describing — keeps the single line it had.
///
/// The artwork is the other half of the same fix, and it is a glance-level
/// answer where the words are a reading one.
///
/// **Absent artwork is a supported state, not a failure**, and it is the state
/// this widget was written to degrade into: the fields it needs are inferred
/// from `BaseItemDto` rather than measured off a server (see [ActiveSession]),
/// so if they are named something else the row is the plain sentence the card
/// showed before. Nothing here reserves space for a picture that never comes.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.active, required this.serverUrl});

  final ActiveSession active;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // Three distinct facts, and the server reports which: watching, paused, or
    // signed in with nothing playing — which is the ordinary case,
    // `NowPlayingItem` simply being absent.
    if (!active.isPlaying) {
      return Text(l10n.sessionsNotPlaying, style: theme.textTheme.bodyMedium);
    }

    // The show's name is the title when there is one, and the episode name
    // moves below it. With no show — a film — the item's own name is the title
    // and there is no second line, which is the card as it was.
    final show = active.showName;
    final title = show ?? active.nowPlayingName!;
    final secondary = show == null ? null : active.nowPlayingName;

    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          active.isPaused
              ? l10n.sessionsPaused(title)
              : l10n.sessionsWatching(title),
          style: theme.textTheme.bodyMedium,
        ),
        if (secondary != null)
          Text(
            secondary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );

    final artwork = active.artwork;
    if (artwork == null) return lines;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Artwork(artwork: artwork, serverUrl: serverUrl),
        const SizedBox(width: 12),
        Expanded(child: lines),
      ],
    );
  }
}

/// The poster beside what is playing.
///
/// A poster's shape, at a size that reads on a card rather than competing with
/// it: the library grid is where artwork is the point, and here it is a hint
/// beside a sentence that already says the answer.
///
/// **Nothing is announced to a screen reader.** The title is in the text
/// alongside, in full; a second rendering of it as an image label would be the
/// same fact twice — the same reasoning that keeps the library tile's faces out
/// of its own semantics.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.artwork, required this.serverUrl});

  final NowPlayingArtwork artwork;
  final String serverUrl;

  /// Poster proportions, 2:3, like the grid's tiles.
  static const _width = 44.0;
  static const _height = 66.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;

    return SizedBox(
      width: _width,
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          // The tag is what makes the URL change when the artwork does;
          // without it a cached poster would outlive the picture it shows.
          imageUrl: '$base/Items/${artwork.itemId}/Images/Primary'
              '?tag=${artwork.imageTag}',
          fit: BoxFit.cover,
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => placeholder,
        ),
      ),
    );
  }
}
