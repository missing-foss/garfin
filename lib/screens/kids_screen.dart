// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../providers/kids_providers.dart';
import '../repositories/jellyfin_exception.dart';
import '../widgets/error_notice.dart';
import '../widgets/kid_card.dart';

/// Build order step 3. The first screen that reads a child's policy.
///
/// Three ground rules are live here at once: allow-list and block-list are
/// opposite verbs (3), visible counts come from the server (4), and Garfin
/// never writes a user policy (8) — which is why the section at the bottom is a
/// boundary rather than a to-do list.
class KidsScreen extends ConsumerWidget {
  const KidsScreen({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(kidsOverviewProvider(session));

    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // Offline-degraded, per the definition of done: a plain explanation and a
      // way out, never a blank screen.
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reuses sign-in's mapping so a parent gets the same sentence for
              // the same cause wherever it happens. A non-Jellyfin error means
              // the failure was local rather than the server's, and `server`
              // is the honest bucket for "it did not work and Garfin cannot
              // tell you more" — there is deliberately no generic catch-all
              // string to reach for.
              ErrorNotice(
                message: jellyfinErrorText(
                  l10n,
                  error is JellyfinException
                      ? error
                      : const JellyfinException(JellyfinErrorKind.server),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(kidsOverviewProvider(session)),
                child: Text(l10n.kidsRetry),
              ),
            ],
          ),
        ),
      ),
      data: (data) => _KidsList(session: session, overview: data),
    );
  }
}

class _KidsList extends ConsumerWidget {
  const _KidsList({required this.session, required this.overview});

  final AuthSession session;
  final KidsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (overview.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.kidsEmpty, style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(kidsOverviewProvider(session)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          for (final kid in overview.shortlisted) ...[
            KidCard(kid: kid, session: session),
            const SizedBox(height: 12),
          ],
          if (overview.withoutShortlist.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.kidsNoShortlistHeading,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.kidsNoShortlistExplanation,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // Non-interactive on purpose (docs/UI-SPEC.md § Kids): Garfin cannot
            // give a child their first label, so a row that looked tappable
            // would be a dead end someone files a bug about. ListTile with no
            // onTap, and `enabled: false` so it is greyed and skipped by screen
            // readers' tap affordances rather than merely inert.
            for (final user in overview.withoutShortlist)
              ListTile(
                enabled: false,
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(_initial(user.name)),
                ),
                title: Text(user.name),
              ),
          ],
        ],
      ),
    );
  }
}

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
