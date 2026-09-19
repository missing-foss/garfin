// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shell's four destinations, in the order they appear.
///
/// **Named rather than numbered**, because the shell keeps three lists in step
/// — the icons, the labels, and the body it builds — and an integer index is
/// how two of them drift apart while the third does not. `Kids` opening the app
/// and `Kids` being first are now the same fact rather than two that have to
/// agree.
enum HomeTab { kids, library, activity, settings }

/// Which destination is showing.
///
/// **Out of the shell's own state on purpose.** Tapping a child's picture on
/// the landing screen goes to the Library filtered for that child, and a screen
/// cannot change a sibling's `setState`. Holding it here lets that tap set the
/// destination and the selection together, and lets a test read where the app
/// went without reaching into a private state class.
final homeTabProvider =
    NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);

class HomeTabController extends Notifier<HomeTab> {
  /// `docs/UI-SPEC.md` § Product shape: the app opens on the children.
  @override
  HomeTab build() => HomeTab.kids;

  void go(HomeTab tab) => state = tab;
}
