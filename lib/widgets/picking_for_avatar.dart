// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';
import 'user_avatar.dart';

/// Who the Library is about, in the app bar, and the control that changes it.
///
/// **It replaced a row of chips above the filters.** That row was the first
/// thing on the screen and was not the library; the selection is one fact and
/// belongs where the screen says what it is showing. Asked for directly: "in
/// the header where library is displayed it should show the profile of the
/// current kid".
///
/// **A cycle, not a menu.** One tap moves to the next child and past the last
/// one to Everyone. Two or three children is the shape this app is for, and a
/// menu would be a second surface to open for a choice with three answers.
///
/// **Everyone is the app's own mark**, not a group of faces: at 32dp a shoal
/// is a smudge, and the mark is the one silhouette a parent already associates
/// with the whole library rather than with a child.
class PickingForAvatar extends ConsumerWidget {
  const PickingForAvatar({super.key, required this.session});

  final AuthSession session;

  /// The next selection after [current], or null for Everyone.
  ///
  /// Everyone sits after the last child rather than before the first, so the
  /// cycle reads as "the children, then all of them" — and a parent who taps
  /// past the child they wanted comes back round rather than reversing.
  static String? nextAfter(String? current, List<KidSummary> kids) {
    if (kids.isEmpty) return null;
    final index = kids.indexWhere((k) => k.user.id == current);
    if (index < 0) return kids.first.user.id;
    if (index == kids.length - 1) return null;
    return kids[index + 1].user.id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final kids = ref.watch(kidsOverviewProvider(session)).asData?.value
            .shortlisted ??
        const <KidSummary>[];
    final selected = ref.watch(pickedChildProvider(session));

    final avatar = selected == null
        ? const _EveryoneMark()
        : UserAvatar(
            name: selected.name,
            avatarUrl: kids
                .where((k) => k.user.id == selected.id)
                .map((k) => k.avatarUrl)
                .firstOrNull,
            radius: 16,
          );

    // **No tap target with nobody to cycle to.** A control whose only move is
    // back to where it already is teaches a parent that taps here do nothing,
    // which is worse than an ornament that never claimed to be a control.
    if (kids.isEmpty) {
      return Padding(padding: const EdgeInsets.only(right: 12), child: avatar);
    }

    return Semantics(
      button: true,
      label: selected == null
          ? l10n.libraryEveryone
          : l10n.libraryPickingForName(selected.name),
      child: IconButton(
        // The whole 48dp target, with a 32dp face in it: the icon button's own
        // padding is what makes the tap area big enough to hit while walking.
        icon: avatar,
        tooltip: selected == null
            ? l10n.libraryEveryone
            : l10n.libraryPickingForName(selected.name),
        onPressed: () {
          final next = nextAfter(selected?.id, kids);
          ref.read(pickingForProvider.notifier).select(next);
        },
      ),
    );
  }
}

/// Everyone, as the app's mark.
class _EveryoneMark extends StatelessWidget {
  const _EveryoneMark();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 32,
        child: Image.asset(
          'assets/brand/garfin-mark.png',
          // A proper noun and the one string in here, so it is neither
          // translated nor treated as UI copy — the same reasoning the tank
          // screen carries.
          semanticLabel: null,
          excludeFromSemantics: true,
        ),
      );
}
