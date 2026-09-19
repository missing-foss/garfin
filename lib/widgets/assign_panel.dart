// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../providers/library_providers.dart';
import 'assign_sheet.dart';

/// The write preview as a side panel, beside the grid (#95).
///
/// On a phone this is a modal sheet, and a sheet is the right shape there: it
/// covers a screen that has room for one thing at a time. On a tablet it is the
/// wrong shape — "pick a child, pick a film" is a comparison, and the grid is
/// what a parent is comparing against. So the same [AssignView] sits here
/// instead, and the tiles stay on screen and stay tappable while it is open.
///
/// The panel is present at every width above the breakpoint, empty or not.
/// Appearing only once something is picked would re-flow the grid — and
/// therefore move the poster that was just tapped, out from under the finger
/// that tapped it — on every selection.
class AssignPanel extends ConsumerWidget {
  const AssignPanel({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final target = ref.watch(assignPanelProvider);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: target == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  l10n.assignPanelEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    // The framework's own string, in every locale Flutter
                    // ships: a close affordance is not Garfin's vocabulary and
                    // does not belong in the ARB.
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () =>
                        ref.read(assignPanelProvider.notifier).clear(),
                  ),
                ),
                Expanded(
                  child: AssignView(
                    // **Keyed by the item.** Without this, picking a second
                    // title reuses the first one's state — and that state is
                    // the pending toggles. A parent who flicked "give to Emma"
                    // on one film, changed their mind, tapped another, and
                    // pressed Apply would write the second film to Emma from a
                    // switch they set for the first. Nothing on screen would
                    // look wrong: the switch is on, and it is the switch they
                    // flicked.
                    key: ValueKey(target.item.id),
                    session: session,
                    item: target.item,
                    fromCollection: target.from,
                    onClose: () =>
                        ref.read(assignPanelProvider.notifier).clear(),
                  ),
                ),
              ],
            ),
    );
  }
}
