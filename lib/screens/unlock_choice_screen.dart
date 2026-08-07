// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/auth_providers.dart';
import '../providers/unlock_providers.dart';

/// The unlock question, asked once, at the only moment its answer means
/// something (#69).
///
/// **Ground rule 9 is unchanged; when it starts is what changed.** The gate
/// exists because Garfin holds a Jellyfin admin token on a phone that gets
/// handed to children — and that is not true before sign-in, when the app holds
/// no token, no server address and no children. Demanding biometrics there
/// protects an empty app, at the moment a new user is deciding whether the
/// thing works at all.
///
/// So the question is asked right after the first successful sign-in, where the
/// reason can be given truthfully in the present tense. The default is still
/// on: `docs/DECISIONS.md` argues that the rule is the default and switching it
/// off should be the deliberate act, and offering the choice does not change
/// that — it changes whether the parent meets the choice before or after being
/// surprised by it.
///
/// Asked only after an *interactive* sign-in, never after a restored session:
/// see `AuthSignedIn.justSignedIn`.
///
/// **And only while that sign-in is still the current moment.** Provenance was
/// the whole gate on this question, and provenance does not expire by itself:
/// sign in, leave it unanswered, put the phone down, and a resume hours later
/// still showed this screen with "Not now" on it — offering to skip the gate to
/// whoever is holding the phone, which is precisely what the gate exists to
/// deny. Narrow, because it needs the process to stay resident, but unbounded
/// in time. Caught in review, not by a test: the suite covered provenance
/// exhaustively and never backgrounded the app.
///
/// So this screen watches the lifecycle and drops the flag on `paused`. The
/// next frame routes through the gated branch and the lock screen stands in
/// front of the app.
///
/// **Not wrapped in `UnlockGate` instead**, which was the cheaper-looking fix:
/// the gate's controller starts locked whenever unlock is required, and it is
/// required by default — so a parent who had just typed their Jellyfin
/// password would be asked for a fingerprint *before* being asked whether they
/// wanted to be. The question has to be reachable at the moment it is asked;
/// what it must not do is outlive that moment.
class UnlockChoiceScreen extends ConsumerStatefulWidget {
  const UnlockChoiceScreen({super.key});

  @override
  ConsumerState<UnlockChoiceScreen> createState() => _UnlockChoiceScreenState();
}

class _UnlockChoiceScreenState extends ConsumerState<UnlockChoiceScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `paused` only, never `inactive`. The same distinction the lock
    // controller draws: a system prompt or a notification shade makes the app
    // inactive, and treating that as "the parent walked away" would snatch the
    // question away mid-answer.
    if (state == AppLifecycleState.paused) {
      ref.read(authControllerProvider.notifier).noteNoLongerFresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline,
                    size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  l10n.unlockChoiceTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.unlockChoiceBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.unlockChoiceChangeable,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => _answer(ref, required: true),
                  child: Text(l10n.unlockChoiceAsk),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _answer(ref, required: false),
                  child: Text(l10n.unlockChoiceNotNow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Either answer is an answer: both record that the question was asked, so it
  /// is never put twice.
  void _answer(WidgetRef ref, {required bool required}) {
    ref.read(unlockChoiceProvider.notifier).record(required: required);
  }
}
