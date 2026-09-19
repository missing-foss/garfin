// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/label_collision.dart';

/// Children whose labels Jellyfin can read as one, said on the Kids screen.
///
/// **Garfin cannot prevent this and does not try.** It never invents a label
/// and never writes a policy, so the fix belongs to the parent in Jellyfin.
/// What this app can do — and is the only thing in the picture that can — is
/// notice, because it already reads every managed child's policy to build the
/// screen this sits on.
///
/// **Two sentences, not one with a severity.** A clash between two allow-lists
/// means what one child is given reaches the other. A clash across an allow and
/// a block means the opposite: giving one child a title takes it away from the
/// other. Those are different events, and a single sentence general enough to
/// cover both stops being worth reading — see [LabelCollision.crossesModes].
///
/// **It says Jellyfin *can* read them as one, never that it does.** The folding
/// rule differs by server version: a pair differing only by punctuation
/// collides on 12.0 and on neither path of 10.11.11, so asserting the
/// consequence outright would be false on current stable. The conditional
/// carries it instead, and the advice is identical either way.
class LabelClashNotice extends StatelessWidget {
  const LabelClashNotice({super.key, required this.collisions});

  final List<LabelCollision> collisions;

  @override
  Widget build(BuildContext context) {
    if (collisions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.label_outline,
                    color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.kidsLabelClashHeading,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            for (final collision in collisions) ...[
              const SizedBox(height: 8),
              Text(
                _sentence(l10n, collision),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _sentence(AppLocalizations l10n, LabelCollision collision) {
    final names = _names(collision);
    final labels = collision.labels.join(', ');
    return collision.crossesModes
        ? l10n.kidsLabelClashCrossing(names, labels)
        : l10n.kidsLabelClashSame(names, labels);
  }

  /// Each child once, in first-seen order.
  ///
  /// Deduplicated on the **id**: a child holding two labels that both fold into
  /// the clash appears twice in the entries, and naming them twice in one
  /// sentence reads as two children with the same name — which is a thing that
  /// genuinely happens on a Jellyfin server and would send a parent looking for
  /// an account that does not exist.
  static String _names(LabelCollision collision) {
    final seen = <String>{};
    final names = <String>[];
    for (final entry in collision.entries) {
      if (seen.add(entry.userId)) names.add(entry.userName);
    }
    return names.join(', ');
  }
}
