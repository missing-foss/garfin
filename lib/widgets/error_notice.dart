// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../repositories/jellyfin_exception.dart';

/// Turns a [JellyfinException] into one plain sentence in the user's language.
///
/// The switch is exhaustive on purpose: adding a [JellyfinErrorKind] without a
/// sentence should fail the analyzer, not fall through to a generic
/// "something went wrong" that tells a parent nothing about what to do next.
///
/// Server text never reaches this function. Jellyfin's error bodies are English
/// and occasionally a stack trace, so `JellyfinException` carries a kind and,
/// at most, a name or an address to slot into a sentence Garfin wrote.
String jellyfinErrorText(AppLocalizations l10n, JellyfinException error) =>
    switch (error.kind) {
      JellyfinErrorKind.unreachable =>
        l10n.errorUnreachable(error.detail ?? ''),
      JellyfinErrorKind.timeout => l10n.errorTimeout,
      JellyfinErrorKind.unauthorized => l10n.errorUnauthorized,
      JellyfinErrorKind.forbidden => l10n.errorForbidden,
      JellyfinErrorKind.notFound => l10n.errorNotFound,
      JellyfinErrorKind.server => l10n.errorServer,
      JellyfinErrorKind.quickConnectUnavailable =>
        l10n.errorQuickConnectUnavailable,
      JellyfinErrorKind.quickConnectExpired => l10n.errorQuickConnectExpired,
      JellyfinErrorKind.notAdministrator =>
        l10n.errorNotAdministrator(error.detail ?? ''),
      JellyfinErrorKind.cancelled => l10n.errorCancelled,
    };

/// An inline error block. Not a SnackBar: sign-in errors need to stay on screen
/// while the user fixes the thing they are about.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }
}

/// A quieter version of [ErrorNotice] for something that is not an error the
/// user caused — the offline banner, mainly.
class InfoNotice extends StatelessWidget {
  const InfoNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: theme.textTheme.bodyMedium),
    );
  }
}
