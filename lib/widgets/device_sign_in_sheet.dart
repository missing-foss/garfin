// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../providers/app_providers.dart';
import '../repositories/jellyfin_exception.dart';
import 'error_notice.dart';

/// Signing a child in on one of their devices, by approving the code it shows
/// (#40).
///
/// **The child is chosen by construction.** This opens from that child's own
/// card, so there is no list to pick the wrong name from — approving for the
/// wrong child is the failure that matters here and it is silent, and the
/// cheapest way to prevent it is to leave no choice to get wrong.
///
/// **Garfin cannot tell the parent what they are approving.** Measured: only
/// `Authorize` accepts a code, and the one endpoint carrying device details
/// needs the *secret*, which only the requesting device holds — asking for a
/// code's device answers 404. So the confirmation names the child and reads the
/// code back, and says plainly that it cannot check the device. That is the
/// same blindness as approving in Jellyfin's own web UI, and the copy does not
/// pretend otherwise.
Future<void> showDeviceSignInSheet(
  BuildContext context, {
  required AuthSession session,
  required JellyfinUser child,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DeviceSignInSheet(session: session, child: child),
    );

class _DeviceSignInSheet extends ConsumerStatefulWidget {
  const _DeviceSignInSheet({required this.session, required this.child});

  final AuthSession session;
  final JellyfinUser child;

  @override
  ConsumerState<_DeviceSignInSheet> createState() => _DeviceSignInSheetState();
}

class _DeviceSignInSheetState extends ConsumerState<_DeviceSignInSheet> {
  /// The code lives here and nowhere else: not in a provider, not in
  /// preferences, and never in a log line. It is short-lived and single-use,
  /// and it is the value that — in front of an administrator — signs a child in.
  final _code = TextEditingController();
  bool _working = false;
  JellyfinException? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.deviceSignInTitle(widget.child.name),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(l10n.deviceSignInHow, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              enabled: !_working,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontFamily: 'RobotoMono', letterSpacing: 4),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: l10n.deviceSignInCodeLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error case final error?) ...[
              ErrorNotice(message: _errorText(l10n, error)),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _code.text.length == 6 && !_working ? _approve : null,
              child: _working
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.deviceSignInApprove),
            ),
          ],
        ),
      ),
    );
  }

  /// The generic server error is not the useful sentence here.
  ///
  /// Measured: a code that has already been used and a `userId` that no longer
  /// exists **both** answer 500, and the server distinguishes neither. Since
  /// Garfin picks the user id itself, a reused code is much the likelier of the
  /// two — so this offers that as a reason to check rather than asserting it,
  /// the same way the grid offers a reason for a held-back title without
  /// claiming to know one.
  String _errorText(AppLocalizations l10n, JellyfinException error) =>
      error.kind == JellyfinErrorKind.server
          ? l10n.errorQuickConnectRefused
          : jellyfinErrorText(l10n, error);

  /// Ground rule 6: this mints a session on a device, which is consequential
  /// and not obviously reversible from where the parent is standing.
  ///
  /// The confirmation reads the code back — a mistyped digit is the mistake
  /// most likely to be made here, and the only one Garfin can help with, since
  /// it cannot see the device at all.
  Future<void> _approve() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final code = _code.text;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deviceSignInConfirmTitle(widget.child.name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.deviceSignInConfirmCode(code),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontFamily: 'RobotoMono', letterSpacing: 3),
            ),
            const SizedBox(height: 12),
            // Not a disclaimer: it is the one thing the parent knows that
            // Garfin does not, and the only defence against approving a code
            // that came from somewhere else.
            Text(l10n.deviceSignInUnverified(widget.child.name)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deviceSignInApprove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref
          .read(jellyfinApiFactoryProvider)
          .create(
            baseUrl: widget.session.serverUrl,
            readToken: () => widget.session.accessToken,
          )
          .approveQuickConnect(code: code, userId: widget.child.id);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.deviceSignInDone(widget.child.name))),
      );
    } on JellyfinException catch (error) {
      if (mounted) setState(() => _error = error);
    } on Object {
      if (mounted) {
        setState(() =>
            _error = const JellyfinException(JellyfinErrorKind.server));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
