// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/tag_diff.dart';
import '../repositories/assign_repository.dart';

/// Ground rule 1's hard warning, once per removal that would cause it.
///
/// False means the parent backed out, and the caller writes nothing.
///
/// **Every write that can take a label away asks this first**: Apply, the
/// partly-written set's reversal, the toast's Undo and Activity's. Only Apply
/// used to ask, so an Undo of the one thing a child had been given emptied
/// their library with no warning: the same event the warning exists for,
/// reached by a different button.
///
/// [touching] is every item the write takes the label off; see
/// [AssignRepository.lastItemWarningsFor].
Future<bool> confirmLastItem(
  BuildContext context, {
  required AssignRepository repository,
  required TagDiff diff,
  required Set<String> touching,
}) async {
  final l10n = AppLocalizations.of(context);
  final warnings =
      await repository.lastItemWarningsFor(diff, touching: touching);

  for (final warning in warnings) {
    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.assignLastItemTitle(warning.child.name)),
        content: Text(l10n.assignLastItemBody(warning.child.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.assignLastItemConfirm),
          ),
        ],
      ),
    );
    if (proceed != true) return false;
  }
  return true;
}
