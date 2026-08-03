// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/unlock_providers.dart';
import '../repositories/device_unlock.dart';
import '../widgets/error_notice.dart';

/// The gate. Opaque, and the only thing on screen while it is up.
///
/// It asks the device as soon as it appears — a cold start and a resume after
/// the idle timeout both land here, and in both cases the user's next action
/// would be to tap Unlock anyway. It does **not** ask again on its own after a
/// failure: the button is there, and automatic retries are how someone gets
/// locked out of their own phone by a rate limiter.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so there is a localised string to hand the system
    // prompt and an Activity for it to attach to.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
  }

  void _prompt() {
    if (!mounted) return;
    ref
        .read(lockControllerProvider.notifier)
        .unlock(reason: AppLocalizations.of(context).unlockPromptReason);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(lockControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.appTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 24),
                if (state.phase == LockPhase.cannotEnforce)
                  const _CannotEnforce()
                else
                  _Prompt(state: state, onUnlock: _prompt),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.state, required this.onUnlock});

  final UnlockState state;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failure = state.lastFailure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.unlockTitle, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(l10n.unlockBody, textAlign: TextAlign.center),
        if (failure != null) ...[
          const SizedBox(height: 24),
          ErrorNotice(message: unlockFailureText(l10n, failure)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed:
              state.phase == LockPhase.unlocking ? null : onUnlock,
          child: Text(l10n.unlockAction),
        ),
      ],
    );
  }
}

/// The phone has no PIN, pattern or biometric.
///
/// Issue #18: say so plainly and let the user continue. Garfin cannot ask for
/// something the device does not have, and a lock it cannot enforce must not
/// become a lock-out.
class _CannotEnforce extends ConsumerWidget {
  const _CannotEnforce();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoNotice(message: l10n.unlockCannotEnforce),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => ref
              .read(lockControllerProvider.notifier)
              .acknowledgeCannotEnforce(),
          child: Text(l10n.unlockContinue),
        ),
      ],
    );
  }
}

/// One plain sentence per way an unlock can fail.
///
/// Exhaustive, so a new [UnlockOutcome] without a sentence fails the analyzer
/// rather than reaching a user as silence.
String unlockFailureText(AppLocalizations l10n, UnlockOutcome outcome) =>
    switch (outcome) {
      UnlockOutcome.failed => l10n.unlockFailed,
      UnlockOutcome.cancelled => l10n.unlockCancelled,
      UnlockOutcome.temporarilyLockedOut => l10n.unlockTooManyTries,
      UnlockOutcome.biometricLockedOut => l10n.unlockUsePinInstead,
      UnlockOutcome.error => l10n.unlockError,
      // Neither is a failure: both leave the gate, so the lock screen never
      // renders them.
      UnlockOutcome.unlocked || UnlockOutcome.cannotEnforce => '',
    };
