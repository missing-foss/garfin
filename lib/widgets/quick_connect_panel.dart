// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/sign_in_providers.dart';
import 'error_notice.dart';

/// The Quick Connect tab: six digits, an indeterminate bar, and a way back
/// when the code runs out.
///
/// Indeterminate on purpose. A determinate bar would be a countdown Garfin
/// cannot honestly draw — the code's real lifetime belongs to the server, and
/// the user's own approval ends the wait early anyway.
class QuickConnectPanel extends StatelessWidget {
  const QuickConnectPanel({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final QuickConnectState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return switch (state) {
      QuickConnectIdle() || QuickConnectStarting() => _Busy(
          message: l10n.quickConnectStarting,
        ),
      QuickConnectWaiting(:final code) => _Waiting(code: code),
      QuickConnectSucceeded() => const _Busy(message: ''),
      QuickConnectFailed(:final error) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorNotice(message: jellyfinErrorText(l10n, error)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(l10n.quickConnectNewCode),
            ),
          ],
        ),
    };
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.quickConnectHowTo, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Text(
          code,
          textAlign: TextAlign.center,
          // Fredoka carries numbers, per BRANDING.md. The extra tracking is so
          // six digits can be read off a screen at arm's length and typed into
          // another device without losing your place.
          style: theme.textTheme.displayMedium?.copyWith(letterSpacing: 8),
        ),
        const SizedBox(height: 24),
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(l10n.quickConnectWaiting, textAlign: TextAlign.center),
      ],
    );
  }
}
