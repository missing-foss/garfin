// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/age_suitability.dart';
import '../models/kid_summary.dart';
import '../models/parental_rating.dart';
import '../providers/app_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';
import '../providers/settings_providers.dart';
import '../repositories/app_settings_store.dart';
import '../repositories/jellyfin_exception.dart';
import '../repositories/library_repository.dart';
import '../widgets/error_notice.dart';
import '../widgets/assign_sheet.dart';
import '../widgets/library_tile.dart';

/// Build order step 4. The grid, and the child selector above it.
///
/// The grid is always the **administrator's** view. Selecting a child changes
/// what each tile *means*, never which tiles exist — which is what makes "not
/// given yet" answerable at all: an item the child cannot see has to still be
/// on the grid to be given to them.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final slice = ref.watch(librarySliceProvider(session));
    final child = ref.watch(pickedChildProvider(session));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PickingForRow(session: session),
        Expanded(
          child: slice.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ErrorNotice(
                      message: jellyfinErrorText(
                        l10n,
                        error is JellyfinException
                            ? error
                            : const JellyfinException(JellyfinErrorKind.server),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(librarySliceProvider(session)),
                      child: Text(l10n.libraryRetry),
                    ),
                  ],
                ),
              ),
            ),
            data: (data) => _Grid(session: session, slice: data, child: child),
          ),
        ),
      ],
    );
  }
}

/// The avatars along the top. Everyone, then one per label-controlled child.
class _PickingForRow extends ConsumerWidget {
  const _PickingForRow({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(kidsOverviewProvider(session));
    final selected = ref.watch(pickingForProvider);

    final kids = overview.asData?.value.shortlisted ?? const <KidSummary>[];
    if (kids.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.libraryPickingFor,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PickChip(
                  label: l10n.libraryEveryone,
                  selected: selected == null,
                  onTap: () =>
                      ref.read(pickingForProvider.notifier).select(null),
                ),
                for (final kid in kids)
                  _PickChip(
                    label: kid.user.name,
                    selected: selected == kid.user.id,
                    onTap: () =>
                        ref.read(pickingForProvider.notifier).select(kid.user.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

/// The selected child's age, from the birth year the parent entered.
///
/// Null when no child is selected or no year has been set — both of which make
/// every hint "not known" rather than suppressing the hint entirely, because a
/// missing year is a thing the parent can fix and should be able to see.
int? _ageOf(WidgetRef ref, JellyfinUser? child) {
  if (child == null) return null;
  final year = ref.watch(birthYearStoreProvider).read(child.id);
  if (year == null) return null;
  // The age they are *certainly* old enough to be, not the one they might have
  // reached — see `guaranteedAge`. Erring high here would tilt the hint toward
  // "suitable" for every child whose birthday has not come round yet.
  return guaranteedAge(birthYear: year, today: DateTime.now());
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.session,
    required this.slice,
    required this.child,
  });

  final AuthSession session;
  final LibrarySlice slice;
  final JellyfinUser? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hideShared = ref.watch(hideSharedProvider);
    final columns = columnsFor(
      ref.watch(settingsProvider).posterSize,
      MediaQuery.sizeOf(context).width,
    );

    // The hint's two inputs (#43). Either being unavailable answers "not
    // known" for every tile, which is the honest degradation — never a pass.
    final ladder =
        ref.watch(parentalRatingLadderProvider(session)).asData?.value ??
        const ParentalRatingLadder.empty();
    final childAge = _ageOf(ref, child);

    if (slice.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            // "Nothing left to give" and "nothing here at all" are different
            // facts, and only one of them is a reason to check the server.
            hideShared && child != null && slice.totalRecordCount > 0
                ? l10n.libraryNothingLeft(child!.name)
                : l10n.libraryEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // Says what has *not been handed over*, never what the child
                  // can see. The second is the server's answer, tags and cap
                  // together, and claiming it here is what ground rule 4
                  // forbids.
                  child == null
                      ? l10n.libraryItemCount(slice.totalRecordCount)
                      : l10n.libraryNotYetGiven(
                          slice.entries.length,
                          child!.name,
                        ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (child != null)
                TextButton(
                  onPressed: () =>
                      ref.read(hideSharedProvider.notifier).toggle(),
                  child: Text(
                    hideShared
                        ? l10n.libraryShowShared
                        : l10n.libraryHideShared,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(librarySliceProvider(session)),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.58,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: slice.entries.length,
              itemBuilder: (context, index) {
                final entry = slice.entries[index];
                return InkWell(
                  // Step 5: tapping a tile is what opens the write preview.
                  // Nothing is written until Apply — ground rule 1.
                  onTap: () => showAssignSheet(
                    context,
                    session: session,
                    item: entry.item,
                  ),
                  child: LibraryTile(
                    entry: entry,
                    serverUrl: session.serverUrl,
                    childName: child?.name,
                    suitability: suitabilityFor(
                      item: entry.item,
                      ladder: ladder,
                      childAge: childAge,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
