// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/auth_providers.dart';
import '../providers/home_tab_providers.dart';
import '../providers/library_providers.dart';
import '../providers/unlock_providers.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/error_notice.dart';
import '../widgets/picking_for_avatar.dart';
import 'kids_screen.dart';
import 'library_screen.dart';
import 'activity_screen.dart';
import 'settings_screen.dart';

/// Where a signed-in session lands.
///
/// A shell, not a screen: the app bar and the offline notice live here, and the
/// body is whichever destination is selected — `docs/UI-SPEC.md` § Product
/// shape — so this stays a shell rather than growing content of its own.
///
/// **The app opens on Kids, which is also first in the nav.** This comment used
/// to say the opposite, because it did: the Library was the landing screen from
/// build order step 4 until 0.2.0, on the reasoning that the task which opens
/// the app is *find something for a kid*. That is overruled — a parent wants an
/// answer about their children before a grid of films — and both the initial
/// tab and the nav order moved together rather than only one of them.
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
  /// **Kids first, Library second** — `docs/UI-SPEC.md` § Product shape.
  ///
  /// This reverses the order that stood until now, which opened on the Library
  /// because "the task that opens the app is *find something for a kid*, so the
  /// app opens on the thing you act on". The reversal is the account owner's,
  /// and the reason is that the first thing a parent wants is not a grid of
  /// films but an answer about their children: who they are, what each of them
  /// can see, and whether anyone is watching something right now.
  ///
  /// **The nav order moved with it, not only the initial tab.** A landing
  /// screen sitting second in its own navigation is a small lie about which
  /// screen the app is built around, and it puts the highlighted destination
  /// somewhere other than where the app opened.
  /// Held in [homeTabProvider] rather than here, because tapping a child's
  /// picture on the landing screen has to move the shell to the Library, and a
  /// screen cannot reach a sibling's `setState`.
  HomeTab get _tab => ref.watch(homeTabProvider);

  /// Whether the gate is **down** — the app is reachable and the lock overlay
  /// is not on screen.
  ///
  /// Read for the back gesture only; [UnlockGate] owns everything else about
  /// it. The name and the predicate agree; an earlier version of this sentence
  /// said the opposite, which is the kind of comment that survives until
  /// someone uses it to decide whether to negate a condition.
  bool get _unlocked => ref.watch(lockControllerProvider).isOpen;
  /// A destination chosen from the navigation.
  ///
  /// **Arriving at the Library this way shows Everyone.** Coming from a child's
  /// face means "this child"; coming from the navigation means "the library",
  /// and carrying the last child over would answer a question the parent did
  /// not ask. The face tap sets the selection and calls the notifier directly,
  /// so it does not pass through here.
  void _go(HomeTab tab) {
    if (tab == HomeTab.library) {
      ref.read(pickingForProvider.notifier).select(null);
    }
    ref.read(homeTabProvider.notifier).go(tab);
  }

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
                HomeTab.kids => KidsScreen(session: state.session),
                HomeTab.library => LibraryScreen(session: state.session),
                HomeTab.activity => ActivityScreen(session: state.session),
                HomeTab.settings => SettingsScreen(session: state.session),
              },
            ),
          ],
        );

        // **Back returns to Kids, and only from another tab.**
        //
        // The app was one route with an internal tab switch and no `PopScope`
        // anywhere, so every back gesture went to the system and finished the
        // activity — reported as "the android back gesture is not supported at
        // all and using it just exits the app".
        //
        // Only the tab switch needs this. A collection is a real route
        // (`openCollection` pushes one) and so are the sheets and dialogs, so
        // Flutter already pops those correctly; this must not and does not
        // reach them, because a route on top of this one receives the gesture
        // first.
        //
        // **Inert while locked.** The lock screen is an overlay in a `Stack`,
        // not a route, so back there already means *leave the app* and cannot
        // dismiss the lock. Intercepting would consume the gesture and send a
        // parent to a tab they cannot see — leaving them with a back button
        // that does nothing behind a lock, which is worse than exiting.
        return PopScope(
          canPop: !_unlocked || _tab == HomeTab.kids,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            ref.read(homeTabProvider.notifier).go(HomeTab.kids);
          },
          child: Scaffold(
          // Unlock and sign-out are Settings' job from step 7 on, and an app
          // bar carrying a second route to them would be two places to keep in
          // step. The one action here is not a route: it says who the Library
          // is about, which is the screen's subject rather than a destination.
          appBar: AppBar(
            title: Text(titles[_tab.index]),
            actions: [
              if (_tab == HomeTab.library)
                PickingForAvatar(session: state.session),
            ],
          ),
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
          ),
        );
      },
    );
  }

  /// `docs/UI-SPEC.md` § Product shape: Kids · Library · Activity · Settings.
  ///
  /// The order and the icons are shared with [_bar] deliberately — a parent who
  /// unfolds a foldable mid-task should find the same four things in the same
  /// order, and two lists drift one destination at a time.
  ///
  /// **Two lists are index-aligned here**, not three: these icons and
  /// [_labels], both indexed by [HomeTab]'s own order. The body is a `switch`
  /// on the enum rather than on a number, so it cannot drift out of step with
  /// them — it stops compiling instead. A test still asserts which screen the
  /// app opens on, because the two remaining lists can still be reordered
  /// without the compiler noticing.
  static const _destinations = [
    (Icons.people_outline, Icons.people),
    (Icons.grid_view_outlined, Icons.grid_view),
    (Icons.history_outlined, Icons.history),
    (Icons.settings_outlined, Icons.settings),
  ];

  List<String> _labels(AppLocalizations l10n) => [
        l10n.kidsTitle,
        l10n.libraryTitle,
        l10n.activityTitle,
        l10n.settingsTitle,
      ];

  Widget _bar(AppLocalizations l10n) {
    final labels = _labels(l10n);
    return NavigationBar(
      selectedIndex: _tab.index,
      onDestinationSelected: (index) => _go(HomeTab.values[index]),
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
      selectedIndex: _tab.index,
      onDestinationSelected: (index) => _go(HomeTab.values[index]),
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
