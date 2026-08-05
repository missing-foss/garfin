// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/auth_providers.dart';
import '../widgets/error_notice.dart';
import 'kids_screen.dart';
import 'unlock_settings_screen.dart';

/// Where a signed-in session lands.
///
/// A shell, not a screen: the app bar and the offline notice live here, and the
/// body is the Kids screen (build order step 3). The Library becomes the
/// landing screen at step 4 and the Kids screen moves to second in the nav —
/// `docs/UI-SPEC.md` § Product shape — so this stays a shell rather than
/// growing content of its own.
///
/// The offline notice is here rather than inside the Kids screen deliberately:
/// it is about the *session* being unconfirmed, not about this screen's data
/// having failed, and the two have different remedies.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.state});

  final AuthSignedIn state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.kidsTitle),
        actions: [
          // Until the Settings screen exists (build order step 7), this is how
          // the Unlock section is reached. It moves there when it does.
          IconButton(
            tooltip: l10n.settingsUnlockTitle,
            icon: const Icon(Icons.lock_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UnlockSettingsScreen(),
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            child: Text(l10n.signOutAction),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.offlineReason != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: InfoNotice(message: l10n.offlineNotice),
              ),
            Expanded(child: KidsScreen(session: state.session)),
          ],
        ),
      ),
    );
  }
}
