// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

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
/// **Stop stays enabled when `SupportsRemoteControl` is false**, rather than
/// being disabled as #70 also suggested. The flag is the client's own claim and
/// the commands answer 204 either way, so disabling on it withdraws a control
/// that may well work on the strength of a self-report. What made the button
/// dishonest was the copy, and the copy now reads back — a client that ignores
/// the command is reported as having ignored it, whatever it claimed in
/// advance. The card still says the device does not accept remote commands.
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
            Text(
              // Three distinct facts, and the server reports which: watching,
              // paused, or signed in with nothing playing — which is the
              // ordinary case, `NowPlayingItem` simply being absent.
              switch ((active.isPlaying, active.isPaused)) {
                (false, _) => l10n.sessionsNotPlaying,
                (true, true) => l10n.sessionsPaused(active.nowPlayingName!),
                (true, false) => l10n.sessionsWatching(active.nowPlayingName!),
              },
              style: theme.textTheme.bodyMedium,
            ),
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
                    onPressed: _working ? null : _stop,
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
    if (!await _confirm(
      title: l10n.sessionsEndConfirm(
        widget.active.userName,
        _deviceLabel(widget.active),
      ),
      body: l10n.sessionsEndExplain,
      action: l10n.sessionsEnd,
    )) {
      return;
    }
    final device = _deviceLabel(widget.active);
    await _run(
      () => ref
          .read(libraryApiProvider(widget.session))
          .endSession(deviceId: widget.active.deviceId),
      l10n.sessionsEnded(device),
      verify: () async => switch (await _verifier.verifyEnded(
        deviceId: widget.active.deviceId,
      )) {
        // The revoke is measured to hold — 204, then 401 on the next request —
        // so confirming it adds nothing the opening sentence did not say.
        EndOutcome.signedOut => null,
        EndOutcome.signedBackIn => l10n.sessionsEndReturned(device),
        EndOutcome.unknown => null,
      },
    );
  }

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
    setState(() => _working = true);
    try {
      await command();
      if (!mounted) return;

      if (verify == null) {
        ref.invalidate(childSessionsProvider(widget.session));
        messenger.showSnackBar(SnackBar(content: Text(sent)));
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
        }),
      );
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorServer)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
