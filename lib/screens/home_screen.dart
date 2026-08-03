// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/auth_providers.dart';
import '../widgets/error_notice.dart';

/// Where a signed-in session lands until the Library screen exists.
///
/// Placeholder — replace it with the Library (build order step 4), do not build
/// on it. It is here because sign-in has to lead somewhere, and because it is
/// the smallest thing that demonstrates the offline-degraded rule: a restored
/// session that could not be confirmed still shows the account and the server
/// with a plain explanation, rather than a blank screen or a surprise sign-out.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.state});

  final AuthSignedIn state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            child: Text(l10n.signOutAction),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.offlineReason != null) ...[
                InfoNotice(message: l10n.offlineNotice),
                const SizedBox(height: 24),
              ],
              Text(
                l10n.signedInAs(state.session.userName),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.connectedTo(state.session.serverUrl),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.homeNextUpBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
