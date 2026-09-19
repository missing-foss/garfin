// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../providers/library_providers.dart';
import 'library_search_field.dart';

/// `docs/UI-SPEC.md` § Library — one row: the search field, then a tune button
/// that opens every group with Reset.
///
/// **The row does not scroll.** It used to carry a chip per filter after the
/// tune button — Type, Genre, Decade and the rating toggle — which made the row
/// wider than the screen and pushed the search field into a fixed 300dp corner
/// of it. Every one of those filters is in the tune sheet, so the chips added
/// reach, not capability, and they cost the search field the width it wanted.
/// What is lost with them is reading the *values* at a glance; what replaces it
/// is the count on the tune button's badge, which was already there.
///
/// Every filter here is applied by the **server**. The rating toggle included —
/// it goes out as `maxOfficialRating`, so no rating is compared on the phone.
/// What it must not be called is "what they can see": measured, an unrated
/// title passes every cap in that filter while a child whose policy sets
/// `BlockUnratedItems` cannot see it. Filtering the administrator's view and
/// predicting the child's are different things, and ground rule 4 is about the
/// second.
class LibraryFilterBar extends ConsumerWidget {
  const LibraryFilterBar({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filters = ref.watch(libraryFiltersProvider);

    return SizedBox(
      height: 48,
      child: Padding(
        // 16 to match the rest of the column this sits in the middle of --
        // the picking-for row above, and the result header and poster grid
        // below, are all at 16. The search field that leads this row draws an
        // outlined box, so its left edge is a visible one: at 12 it sat 4dp
        // outside the poster edges directly beneath it.
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Takes the rest of the row. It is the thing most likely to be
            // reached for and the only one that answers "the film they asked
            // for at dinner"; the tune sheet narrows.
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 8, top: 2, bottom: 2),
                child: LibrarySearchField(),
              ),
            ),
            IconButton(
              tooltip: l10n.filterAll,
              isSelected: !filters.isEmpty,
              icon: Badge(
                isLabelVisible: filters.activeCount > 0,
                label: Text(l10n.filterActiveCount(filters.activeCount)),
                child: const Icon(Icons.tune),
              ),
              onPressed: () => _showAllFilters(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  /// The tune button: every group at once, with Reset.
  void _showAllFilters(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return SafeArea(
          child: Consumer(
            builder: (context, ref, _) {
              final filters = ref.watch(libraryFiltersProvider);
              final genres =
                  ref.watch(libraryGenresProvider(session)).asData?.value ??
                  const <String>[];
              final decades =
                  ref.watch(libraryDecadesProvider(session)).asData?.value ??
                  const <int>[];
              final child = ref.watch(pickedChildProvider(session));

              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.filterAll,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: filters.isEmpty
                            ? null
                            : () => ref
                                  .read(libraryFiltersProvider.notifier)
                                  .reset(),
                        child: Text(l10n.filterReset),
                      ),
                    ],
                  ),
                  _Group(
                    title: l10n.filterType,
                    options: {
                      null: l10n.filterAny,
                      'Movie': l10n.filterTypeMovie,
                      'Series': l10n.filterTypeSeries,
                      'BoxSet': l10n.filterTypeCollection,
                    },
                    value: filters.type,
                    onChanged: (value) => ref
                        .read(libraryFiltersProvider.notifier)
                        .set(filters.copyWith(type: value)),
                  ),
                  if (genres.isNotEmpty)
                    _Group<String?>(
                      title: l10n.filterGenre,
                      options: {
                        null: l10n.filterAny,
                        for (final genre in genres) genre: genre,
                      },
                      value: filters.genre,
                      onChanged: (value) => ref
                          .read(libraryFiltersProvider.notifier)
                          .set(filters.copyWith(genre: value)),
                    ),
                  if (decades.isNotEmpty)
                    _Group<int?>(
                      title: l10n.filterDecade,
                      options: {
                        null: l10n.filterAny,
                        for (final decade in decades)
                          decade: l10n.filterDecadeValue(decade),
                      },
                      value: filters.decade,
                      onChanged: (value) => ref
                          .read(libraryFiltersProvider.notifier)
                          .set(filters.copyWith(decade: value)),
                    ),
                  if (child?.policy.maxParentalRating != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: filters.withinCap,
                      title: Text(l10n.filterWithinCap(child!.name)),
                      onChanged: (value) => ref
                          .read(libraryFiltersProvider.notifier)
                          .set(filters.copyWith(withinCap: value)),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// One group of radio options inside the tune sheet.
class _Group<T> extends StatelessWidget {
  const _Group({
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.labelLarge),
      Wrap(
        spacing: 8,
        children: [
          for (final entry in options.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: entry.key == value,
              onSelected: (_) => onChanged(entry.key),
            ),
        ],
      ),
    ],
  );
}
