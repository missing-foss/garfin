// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/age_suitability.dart';
import '../models/library_item.dart';
import '../repositories/library_repository.dart';

/// One poster on the grid.
///
/// Nothing here renders `LibraryItem.tags`. That list is the metadata
/// provider's as much as Garfin's — measured, a tagged film also carried
/// "kidnapping" and "alien abduction" — so only the derived [LibraryEntry.state]
/// reaches the screen.
class LibraryTile extends StatelessWidget {
  const LibraryTile({
    super.key,
    required this.entry,
    required this.serverUrl,
    this.childName,
    this.suitability = AgeSuitability.unknown,
  });

  final LibraryEntry entry;
  final String serverUrl;

  /// The selected child, for the sentence explaining a held-back item.
  final String? childName;

  /// The age hint (#43). **Advice, and it never changes which tiles appear.**
  ///
  /// [AgeSuitability.suitsAge] shows nothing: the grid is a to-do list, and
  /// marking the majority case would be noise. Only "above their age" and
  /// "not known" are worth a parent's attention, and the second is worth it
  /// precisely because it is not a pass.
  final AgeSuitability suitability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final item = entry.item;

    return Semantics(
      label: _semanticLabel(l10n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _Poster(item: item, serverUrl: serverUrl),
                ),
                if (_badge(l10n) case final badge?)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _Badge(label: badge, tone: _tone(theme)),
                  ),
                if (_ageHint(l10n) case final hint?)
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: _Badge(
                      label: hint,
                      tone: suitability == AgeSuitability.aboveAge
                          ? theme.colorScheme.tertiaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                if (item.isCollection && item.childCount != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: _Badge(
                      label: l10n.libraryCollectionCount(item.childCount!),
                      tone: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// The age hint, or null when there is nothing useful to say.
  ///
  /// Silent with no child selected — there is no age to compare against — and
  /// silent when the title suits, because that is most of the grid.
  String? _ageHint(AppLocalizations l10n) {
    if (childName == null) return null;
    return switch (suitability) {
      AgeSuitability.aboveAge => l10n.libraryHintAboveAge(childName!),
      AgeSuitability.unknown => l10n.libraryHintUnknownAge,
      AgeSuitability.suitsAge => null,
    };
  }

  String? _badge(AppLocalizations l10n) => switch (entry.state) {
        LibraryItemState.given => l10n.libraryBadgeGiven,
        LibraryItemState.givenButHidden => l10n.libraryBadgeHeldBack,
        LibraryItemState.blocked => l10n.libraryBadgeBlocked,
        // Not-given is the default state of the grid, and badging it would
        // put a marker on almost every tile — noise rather than signal.
        LibraryItemState.notGiven ||
        LibraryItemState.available ||
        LibraryItemState.unknown =>
          null,
      };

  Color _tone(ThemeData theme) => switch (entry.state) {
        LibraryItemState.givenButHidden => theme.colorScheme.errorContainer,
        LibraryItemState.blocked => theme.colorScheme.surfaceContainerHighest,
        _ => theme.colorScheme.primaryContainer,
      };

  /// What a screen reader says, including the explanation a sighted user gets
  /// from tapping.
  ///
  /// The held-back sentence **offers** the reason rather than asserting it: the
  /// server does not say why it hid an item, and a folder permission is
  /// indistinguishable from a rating cap here.
  String _semanticLabel(AppLocalizations l10n) {
    final name = entry.item.name;
    if (entry.state == LibraryItemState.givenButHidden && childName != null) {
      return '$name. ${l10n.libraryHeldBackExplanation(childName!)}';
    }
    final parts = <String>[name, ?_badge(l10n), ?_ageHint(l10n)];
    return parts.join('. ');
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item, required this.serverUrl});

  final LibraryItem item;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          item.isCollection ? Icons.collections_outlined : Icons.movie_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final tag = item.primaryImageTag;
    if (tag == null) return placeholder;

    final base =
        serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;

    return CachedNetworkImage(
      // The tag is what makes the URL change when the artwork does; without it
      // a cached poster would outlive the picture it shows.
      imageUrl: '$base/Items/${item.id}/Images/Primary?tag=$tag',
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
