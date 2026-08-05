// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/tag_diff.dart';
import '../repositories/assign_repository.dart';

/// What a collection write left behind, and the two ways forward from it.
///
/// Ground rule 5: nothing that succeeded is ever undone silently, so this is
/// how a half-finished set is reported — the exact state, and two idempotent
/// choices that are the parent's to make.
///
/// **Every sentence here is direction-specific, and it has to be.** The panel is
/// reached by a removal as well as an addition: the container's removals go
/// first, so a container write that fails while every member succeeds lands
/// here with nothing failed and the set unmarked. Labels left *on* the container
/// and labels left *off* it are opposite situations for the child — an empty
/// collection against films with no collection — and the reversing button
/// removes labels in one direction and puts them back in the other. Copy written
/// for the addition alone tells the parent the wrong thing and names the wrong
/// act, on the one screen whose entire job is saying what really happened.
///
/// A widget of its own so those four cases can be pumped and read, rather than
/// reasoned about inside the sheet.
class BatchResultNotice extends StatelessWidget {
  const BatchResultNotice({
    super.key,
    required this.outcome,
    required this.diff,
    required this.onFinish,
    required this.onReverse,
    this.enabled = true,
  });

  final BatchOutcome outcome;

  /// What was attempted. Its direction chooses the words.
  final TagDiff diff;

  /// Retry the same write. Idempotent: the titles that landed are untouched.
  final VoidCallback onFinish;

  /// The same change backwards, as a fresh forward write — never a restore.
  final VoidCallback onReverse;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_state(l10n), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: enabled ? onReverse : null,
                child: Text(
                  // Only a pure addition is undone by *removing*. Anything else
                  // puts labels back on, and the button must say so.
                  diff.direction == DiffDirection.added
                      ? l10n.assignBatchRemoveAll
                      : l10n.assignBatchPutBack,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: enabled ? onFinish : null,
                child: Text(l10n.assignBatchFinish),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The exact state, in the direction it actually went.
  String _state(AppLocalizations l10n) {
    if (outcome.failed.isNotEmpty) {
      // Some titles landed and some did not, which reads the same either way —
      // and the change preview immediately above already says who gained and
      // who lost.
      return l10n.assignBatchPartial(outcome.written.length, outcome.total);
    }
    return switch (diff.direction) {
      DiffDirection.added => l10n.assignBatchSetIncompleteAdded(outcome.total),
      DiffDirection.removed =>
        l10n.assignBatchSetIncompleteRemoved(outcome.total),
      DiffDirection.mixed => l10n.assignBatchSetIncomplete(outcome.total),
    };
  }
}
