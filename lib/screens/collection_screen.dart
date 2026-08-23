// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/collection_set.dart';
import '../models/library_item.dart';
import '../providers/collection_providers.dart';
import '../providers/library_providers.dart';
import '../repositories/jellyfin_exception.dart';
import '../repositories/library_repository.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/assign_panel.dart';
import '../widgets/assign_sheet.dart';
import '../widgets/collection_given_line.dart';
import '../widgets/error_notice.dart';
import '../widgets/library_grid.dart';
import '../widgets/picking_for_row.dart';

/// Open a collection to see what is in it (#83).
///
/// A push rather than a sheet: this is a place, and the parent has to be able
/// to come back out of it to the grid they were on.
Future<void> openCollection(
  BuildContext context, {
  required AuthSession session,
  required LibraryItem collection,
}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            CollectionScreen(session: session, collection: collection),
      ),
    );

/// What tapping a tile does, wherever a tile is shown.
///
/// One place decides, because the library and a collection show the same tiles
/// and must answer a tap the same way. It lives next to [openCollection]
/// because opening a set is one of the two outcomes.
void openFor(
  BuildContext context,
  WidgetRef ref, {
  required AuthSession session,
  required LibraryItem item,
  required bool twoPane,
}) {
  if (item.isCollection) {
    // A collection is a place, not an action (#83). The panel is emptied on the
    // way in: a preview of some other film left open beside this set's members
    // reads as though the two are related, and the first thing here a parent
    // might press is Apply.
    ref.read(assignPanelProvider.notifier).clear();
    openCollection(context, session: session, collection: item);
    return;
  }
  openAssign(context, ref, session: session, item: item, twoPane: twoPane);
}

/// The write preview for [item], on whichever surface this width has.
///
/// Separate from [openFor] because one caller means it about a collection: the
/// *Give the whole set* button on a collection screen, where routing a BoxSet
/// to [openCollection] would re-open the screen it was pressed on. Nothing is
/// written by either branch — ground rule 1 — so the only difference is where
/// the preview appears.
void openAssign(
  BuildContext context,
  WidgetRef ref, {
  required AuthSession session,
  required LibraryItem item,
  required bool twoPane,
}) {
  if (twoPane) {
    ref.read(assignPanelProvider.notifier).select(item);
    return;
  }
  showAssignSheet(context, session: session, item: item);
}

/// What is inside one collection.
///
/// **Opening a set asks nothing.** Before #83 a collection tile behaved like a
/// film — one tap opened the assign sheet for the whole set, whose Apply writes
/// to every member and to the container. A parent tapping a box set is looking,
/// and being asked "give all eight to Emma?" is an answer to a question they
/// did not ask. So the tap is navigation, and handing the set over is a button
/// on this screen: nothing is lost from the old flow except that it stops
/// happening by accident.
///
/// The tiles are the library's own ([LibraryGrid]), so a member says exactly
/// what it says on the grid — given, held back, above their age, who else has
/// it. The child chips stay on screen because deciding about a set is when a
/// parent is most likely to want to check it against a second child.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({
    super.key,
    required this.session,
    required this.collection,
  });

  final AuthSession session;
  final LibraryItem collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final child = ref.watch(pickedChildProvider(session));
    final request =
        CollectionRequest(session: session, collection: collection);
    final members = ref.watch(collectionMembersProvider(request));

    return Scaffold(
      appBar: AppBar(title: Text(collection.name)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // A set is browsed for the same reason the grid is, so it gets the
          // same panel (#95) rather than a modal sheet over the members a
          // parent is deciding about.
          final twoPane = constraints.maxWidth >= kTwoPaneBreakpoint;
          final browsing = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PickingForRow(session: session),
              Expanded(
                child: members.when(
                  // Same reasoning as the grid (#93): a child switch re-runs the
                  // classification, and the default `when` would replace the
                  // titles a parent is reading with a spinner every time they
                  // compared two children.
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ErrorNotice(
                        message: jellyfinErrorText(
                          l10n,
                          error is JellyfinException
                              ? error
                              : const JellyfinException(JellyfinErrorKind.server),
                        ),
                      ),
                    ),
                  ),
                  data: (entries) => _Members(
                    session: session,
                    collection: collection,
                    entries: entries,
                    childName: child?.name,
                    twoPane: twoPane,
                  ),
                ),
              ),
            ],
          );

          if (!twoPane) return browsing;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: browsing),
              const VerticalDivider(width: 1, thickness: 1),
              SizedBox(
                width: kAssignPanelWidth,
                child: AssignPanel(session: session),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Members extends ConsumerWidget {
  const _Members({
    required this.session,
    required this.collection,
    required this.entries,
    required this.childName,
    required this.twoPane,
  });

  final AuthSession session;
  final LibraryItem collection;
  final List<LibraryEntry> entries;
  final String? childName;
  final bool twoPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final child = ref.watch(pickedChildProvider(session));

    // A count of **labels**, never of what the child can see: `isShared` is
    // "the label is on it" in both modes, and what the server then shows them
    // is its own answer (ground rule 4). Null when there is no verb — nobody
    // picked, or an account ground rule 3 refuses to interpret.
    final given = CollectionGiven.of(
      labelled: entries.where((e) => e.isShared).length,
      total: entries.length,
      child: child,
    );

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.collectionEmpty,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // The count of what is *in the set*, which is a fact
                      // about the library rather than about the child — so
                      // unlike the grid's result line it does not change with
                      // the selection.
                      l10n.collectionTitleCount(entries.length),
                      style: theme.textTheme.bodyMedium,
                    ),
                    // ...and how much of it is theirs (#107). The state this
                    // answers — some given, not all — was invisible to the
                    // parent as well as to the child, which is why giving one
                    // film from inside a set could leave a half-handed-over
                    // collection nobody could see.
                    //
                    // **Free.** `entries` are already classified per child, so
                    // this is a count of what is on screen rather than a
                    // question for the server.
                    if (given != null)
                      Text(
                        collectionGivenText(l10n, given, child!.name),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              // The old tap, made explicit. Disabled with nobody picked
              // because the sheet it opens is a write preview *for a child*,
              // and there is no answer to "give it to whom" yet.
              FilledButton(
                onPressed: child == null
                    ? null
                    : () => openAssign(
                          context,
                          ref,
                          session: session,
                          item: collection,
                          twoPane: twoPane,
                        ),
                child: Text(l10n.collectionGiveWholeSet),
              ),
            ],
          ),
        ),
        Expanded(
          child: LibraryGrid(
            session: session,
            entries: entries,
            child: child,
            // The same routing as the grid, and for the same reason: a set can
            // contain a set. Measured on 10.11.11 — `collectionMembers()` sends
            // no `IncludeItemTypes`, so a nested BoxSet comes back as an
            // ordinary member with `Type='BoxSet'`, and a franchise split into
            // phases is the canonical shape rather than an exotic one.
            //
            // Without this the tile announces "Collection" (#99) and the tap
            // then assigns the whole nested set — the tile saying one thing and
            // the gesture doing another, which is the bug this screen exists to
            // remove, surviving one level down. Caught in review.
            //
            // Otherwise the normal write path. `showAssignSheet` re-reads the
            // item it is given — ground rule 2 — which matters here because a
            // member arrives from `GET /Items?parentId=` with 16 fields against
            // the write path's 41, and posting one of those bodies back would
            // strip the rest.
            onTap: (item) => openFor(
              context,
              ref,
              session: session,
              item: item,
              twoPane: twoPane,
            ),
          ),
        ),
      ],
    );
  }
}
