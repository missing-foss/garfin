// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/auth_providers.dart';
import '../widgets/error_notice.dart';
import 'kids_screen.dart';
import 'library_screen.dart';
import 'activity_screen.dart';
import 'settings_screen.dart';

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
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AuthSignedIn state;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Library first, Kids second — `docs/UI-SPEC.md` § Product shape. The task
  /// that opens the app is "find something for a kid", so the app opens on the
  /// thing you act on; the Kids screen is an overview surface.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;

    final titles = [
      l10n.libraryTitle,
      l10n.kidsTitle,
      l10n.activityTitle,
      l10n.settingsTitle,
    ];

    return Scaffold(
      // No actions: Unlock and sign-out are Settings' job from step 7 on, and
      // an app bar carrying a second route to them would be two places to keep
      // in step.
      appBar: AppBar(title: Text(titles[_tab])),
      body: SafeArea(
        child: Column(
          children: [
            if (state.offlineReason != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: InfoNotice(message: l10n.offlineNotice),
              ),
            Expanded(
              child: switch (_tab) {
                0 => LibraryScreen(session: state.session),
                1 => KidsScreen(session: state.session),
                2 => ActivityScreen(session: state.session),
                _ => SettingsScreen(session: state.session),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            label: l10n.libraryTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: l10n.kidsTitle,
          ),
          // `docs/UI-SPEC.md` § Product shape: Library · Kids · Activity ·
          // Settings.
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: l10n.activityTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.settingsTitle,
          ),
        ],
      ),
    );
  }
}
