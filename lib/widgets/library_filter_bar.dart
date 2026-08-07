// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/library_filters.dart';
import '../providers/library_providers.dart';
import 'library_search_field.dart';

/// `docs/UI-SPEC.md` § Library — one row: a tune button that opens every group
/// with Reset, then dropdown chips for Type, Genre and Decade, then the rating
/// toggle when a child is selected.
///
/// **A chip shows the filter's name when unset and its value when set**, which
/// is what makes the row readable at a glance: anything showing a value is
/// doing something.
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
    final child = ref.watch(pickedChildProvider(session));
    final genres = ref.watch(libraryGenresProvider(session)).asData?.value ??
        const <String>[];
    final decades = ref.watch(libraryDecadesProvider(session)).asData?.value ??
        const <int>[];

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // First in the row, because it is the thing most likely to be
          // reached for and the only one that answers "the film they asked for
          // at dinner". The category chips narrow; this one finds.
          const Padding(
            padding: EdgeInsets.only(right: 8, top: 2, bottom: 2),
            child: LibrarySearchField(),
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
          _Chip(
            label: filters.type == null
                ? l10n.filterType
                : _typeLabel(l10n, filters.type!),
            set: filters.type != null,
            onTap: () => _pickType(context, ref, filters),
          ),
          // Hidden rather than empty when the server's genre index has nothing
          // in it — an empty menu is a dead end that looks like a bug.
          if (genres.isNotEmpty)
            _Chip(
              label: filters.genre ?? l10n.filterGenre,
              set: filters.genre != null,
              onTap: () => _pick<String?>(
                context,
                title: l10n.filterGenre,
                value: filters.genre,
                options: {
                  null: l10n.filterAny,
                  for (final genre in genres) genre: genre,
                },
                onChanged: (value) => ref
                    .read(libraryFiltersProvider.notifier)
                    .set(filters.copyWith(genre: value)),
              ),
            ),
          if (decades.isNotEmpty)
            _Chip(
              label: filters.decade == null
                  ? l10n.filterDecade
                  : l10n.filterDecadeValue(filters.decade!),
              set: filters.decade != null,
              onTap: () => _pick<int?>(
                context,
                title: l10n.filterDecade,
                value: filters.decade,
                options: {
                  null: l10n.filterAny,
                  for (final decade in decades)
                    decade: l10n.filterDecadeValue(decade),
                },
                onChanged: (value) => ref
                    .read(libraryFiltersProvider.notifier)
                    .set(filters.copyWith(decade: value)),
              ),
            ),
          // Only with a child selected: there is no cap to filter by otherwise,
          // and a chip that silently does nothing is worse than no chip.
          if (child?.policy.maxParentalRating != null)
            _Chip(
              label: l10n.filterWithinCap(child!.name),
              set: filters.withinCap,
              onTap: () => ref
                  .read(libraryFiltersProvider.notifier)
                  .set(filters.copyWith(withinCap: !filters.withinCap)),
            ),
        ],
      ),
    );
  }

  static String _typeLabel(AppLocalizations l10n, String type) =>
      switch (type) {
        'Movie' => l10n.filterTypeMovie,
        'Series' => l10n.filterTypeSeries,
        _ => l10n.filterTypeCollection,
      };

  void _pickType(BuildContext context, WidgetRef ref, LibraryFilters filters) =>
      _pick<String?>(
        context,
        title: AppLocalizations.of(context).filterType,
        value: filters.type,
        options: {
          null: AppLocalizations.of(context).filterAny,
          'Movie': AppLocalizations.of(context).filterTypeMovie,
          'Series': AppLocalizations.of(context).filterTypeSeries,
          'BoxSet': AppLocalizations.of(context).filterTypeCollection,
        },
        onChanged: (value) => ref
            .read(libraryFiltersProvider.notifier)
            .set(filters.copyWith(type: value)),
      );

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
                        child: Text(l10n.filterAll,
                            style: Theme.of(context).textTheme.titleMedium),
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

/// One chip: the filter's name when unset, its value when set.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.set, required this.onTap});

  final String label;
  final bool set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: FilterChip(
          label: Text(label),
          selected: set,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );
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

/// A radio dialog for one filter.
Future<void> _pick<T>(
  BuildContext context, {
  required String title,
  required T value,
  required Map<T, String> options,
  required void Function(T) onChanged,
}) async {
  final chosen = await showDialog<_Choice<T>>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final entry in options.entries)
          ListTile(
            selected: entry.key == value,
            title: Text(entry.value),
            // Wrapped, because the "any" option's value is null and a bare
            // `pop(null)` is indistinguishable from dismissing the dialog.
            onTap: () => Navigator.of(context).pop(_Choice<T>(entry.key)),
          ),
      ],
    ),
  );
  if (chosen != null) onChanged(chosen.value);
}

class _Choice<T> {
  const _Choice(this.value);
  final T value;
}
