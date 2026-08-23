// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/auth_providers.dart';
import '../widgets/adaptive_layout.dart';
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

    // The app bar's title and the destinations' labels are the same four
    // strings, from one list.
    final titles = _labels(l10n);

    // The rail's own width comes out of the space the body then has, so the
    // decision is made on the constraints this shell is handed rather than on
    // the window (#95, and the same correction #108 made for the grid).
    return LayoutBuilder(
      builder: (context, constraints) {
        final rail = constraints.maxWidth >= kRailBreakpoint;

        final content = Column(
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
        );

        return Scaffold(
          // No actions: Unlock and sign-out are Settings' job from step 7 on,
          // and an app bar carrying a second route to them would be two places
          // to keep in step.
          appBar: AppBar(title: Text(titles[_tab])),
          body: SafeArea(
            child: rail
                ? Row(
                    children: [
                      _rail(
                        l10n,
                        extended: constraints.maxWidth >=
                            kExtendedRailBreakpoint,
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: content),
                    ],
                  )
                : content,
          ),
          // One or the other, never both: the destinations are the same four
          // either way, and the rail is only a different place to put them.
          bottomNavigationBar: rail ? null : _bar(l10n),
        );
      },
    );
  }

  /// `docs/UI-SPEC.md` § Product shape: Library · Kids · Activity · Settings.
  ///
  /// The order and the icons are shared with [_bar] deliberately — a parent who
  /// unfolds a foldable mid-task should find the same four things in the same
  /// order, and two lists drift one destination at a time.
  static const _destinations = [
    (Icons.grid_view_outlined, Icons.grid_view),
    (Icons.people_outline, Icons.people),
    (Icons.history_outlined, Icons.history),
    (Icons.settings_outlined, Icons.settings),
  ];

  List<String> _labels(AppLocalizations l10n) => [
        l10n.libraryTitle,
        l10n.kidsTitle,
        l10n.activityTitle,
        l10n.settingsTitle,
      ];

  Widget _bar(AppLocalizations l10n) {
    final labels = _labels(l10n);
    return NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      destinations: [
        for (final (index, (icon, selected)) in _destinations.indexed)
          NavigationDestination(
            icon: Icon(icon),
            selectedIcon: Icon(selected),
            label: labels[index],
          ),
      ],
    );
  }

  Widget _rail(AppLocalizations l10n, {required bool extended}) {
    final labels = _labels(l10n);
    return NavigationRail(
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      // Labels under the icons at tablet widths, beside them once there is
      // room for words — `extended` and `labelType` are mutually exclusive, so
      // this is one choice rather than two.
      extended: extended,
      labelType: extended ? null : NavigationRailLabelType.all,
      destinations: [
        for (final (index, (icon, selected)) in _destinations.indexed)
          NavigationRailDestination(
            icon: Icon(icon),
            selectedIcon: Icon(selected),
            label: Text(labels[index]),
          ),
      ],
    );
  }
}
