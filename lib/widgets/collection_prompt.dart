// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/collection_set.dart';

/// "Keep the set together?" — asked once, for one collection.
///
/// Ground rule 6, and `docs/DECISIONS.md` § Collections: handing over a film
/// that belongs to a set prompts, listing the other members **with their
/// ratings**, because "Jurassic Park" and "Jurassic Park III" are not the same
/// decision and the rating is what tells them apart.
///
/// **The question only fires on additions.** Taking a label off one film never
/// strips the rest — a silent cascading unshare would make the app's behaviour
/// unpredictable in the direction that matters least to a parent and most to a
/// child.
///
/// Returns true for the whole set, false for just the one film, and null if the
/// parent dismissed the dialog — which is a cancel, not a "no".
Future<bool?> askKeepSetTogether(
  BuildContext context, {
  required CollectionSet set,
  required String itemId,
  required String itemName,
}) {
  final others = set.othersThan(itemId);
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.assignSetTogetherTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assignSetTogetherBody(itemName, set.collection.name),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            // Bounded: a set can hold dozens, and a dialog that runs off the
            // screen has no buttons on it.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final member in others)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                member.name,
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              // No rating is a fact worth showing rather than
                              // a blank: an unrated title can be held back by
                              // a cap all the same.
                              member.officialRating ?? l10n.libraryHintUnknownAge,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.assignSetTogetherJustThis),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.assignSetTogetherAll(set.size)),
          ),
        ],
      );
    },
  );
}
