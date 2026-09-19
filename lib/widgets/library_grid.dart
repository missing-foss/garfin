// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/age_suitability.dart';
import '../models/auth_session.dart';
import '../models/item_holder.dart';
import '../models/jellyfin_user.dart';
import '../models/kid_summary.dart';
import '../models/library_item.dart';
import '../models/parental_rating.dart';
import '../providers/app_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';
import '../providers/settings_providers.dart';
import '../repositories/app_settings_store.dart';
import '../repositories/library_repository.dart';
import 'collection_given_line.dart';
import 'library_tile.dart';

/// A grid of posters, and everything a tile needs to mean something.
///
/// Extracted, when browsing a collection became a second place that
/// shows library tiles. The three overlays a tile carries — the state badge,
/// the age hint (#43) and the faces of who already has it (#84) — are each
/// derived from a different provider, and a second screen assembling its own
/// copy of that would drift one overlay at a time. A member tile inside a set
/// has to say exactly what the same title says on the grid, or the set is a
/// different app.
///
/// Deliberately **not** responsible for scrolling behaviour: the library wraps
/// this in pull-to-refresh and scroll-position paging, and a collection does
/// not page at all — its membership arrives in one call. Putting either in here
/// would hand the collection screen machinery it has no use for.
class LibraryGrid extends ConsumerWidget {
  const LibraryGrid({
    super.key,
    required this.session,
    required this.entries,
    required this.child,
    required this.onTap,
    this.notes = const {},
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
  });

  final AuthSession session;

  /// Already classified, and already substituted for a stale selection where
  /// that applies (#96) — this widget renders what it is handed rather than
  /// deciding whose answer the entries are.
  final List<LibraryEntry> entries;

  final JellyfinUser? child;

  /// What a tap means here. The library opens the assign sheet; a collection
  /// opens the set. Passing the item rather than the entry, because every
  /// caller so far wants the thing, not its per-child state.
  final void Function(LibraryItem item) onTap;

  /// A line to draw under a tile's title, by item id (#147): the collections a
  /// search found through one of their members say so.
  final Map<String, String> notes;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `MediaQuery.sizeOf` is the **window**, not the display, so this already
    // does the right thing in split-screen and on a folded foldable. What was
    // missing (#95) was the mapping from that width to a layout, not the
    // measurement — so the width is no longer read here at all: the delegate
    // takes a target poster width and derives the columns from whatever space
    // it is actually given, which is also correct inside a narrower parent than
    // the window.
    final target = posterTargetWidth(ref.watch(settingsProvider).posterSize);

    // The hint's two inputs (#43). Either being unavailable answers "not
    // known" for every tile, which is the honest degradation — never a pass.
    final ladder =
        ref.watch(parentalRatingLadderProvider(session)).asData?.value ??
            const ParentalRatingLadder.empty();
    final childAge = _ageOf(ref, child);

    // Who already has what (#84), joined here rather than fetched. An overview
    // that has not arrived — or failed — costs the avatars and nothing else.
    final kids =
        ref.watch(kidsOverviewProvider(session)).asData?.value.shortlisted ??
            const <KidSummary>[];

    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: target,
        childAspectRatio: 0.58,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return InkWell(
          onTap: () => onTap(entry.item),
          child: LibraryTile(
            entry: entry,
            note: notes[entry.item.id],
            serverUrl: session.serverUrl,
            childName: child?.name,
            childId: child?.id,
            holders: holdersOf(
              item: entry.item,
              children: kids,
              selectedChildId: child?.id,
            ),
            // Only a collection has members to count, and only with a child
            // picked is there a verb to say it with.
            //
            // The set's plain size travels with it as the silent form. The
            // share widget cannot know until its own build whether it has
            // anything to say, and it stands in the corner the count used to
            // hold, so the fallback has to be inside it rather than beside it.
            givenBadge: entry.item.isCollection && child != null
                ? CollectionGivenLine(
                    session: session,
                    collection: entry.item,
                    child: child,
                    whenSilent:
                        LibraryTile.collectionCountBadge(context, entry.item),
                  )
                : null,
            suitability: suitabilityFor(
              item: entry.item,
              ladder: ladder,
              childAge: childAge,
            ),
          ),
        );
      },
    );
  }
}

/// The selected child's age, for the hint (#43).
///
/// Null when no child is selected or no year has been set. Both then make every
/// title "not known", and the tile now says nothing at all for that — so this
/// is no longer where a missing birth year becomes visible.
///
/// It is still visible, and in a better place: the child's own card offers *Add
/// a birth year* in the age slot, in the primary colour, which is both where a
/// parent would look for it and where they can fix it. Saying it once there
/// beats repeating it on every tile in the grid.
int? _ageOf(WidgetRef ref, JellyfinUser? child) {
  if (child == null) return null;
  final year = ref.watch(birthYearStoreProvider).read(child.id);
  if (year == null) return null;
  // The age they are *certainly* old enough to be, not the one they might have
  // reached — see `guaranteedAge`. Erring high here would tilt the hint toward
  // "suitable" for every child whose birthday has not come round yet.
  return guaranteedAge(birthYear: year, today: DateTime.now());
}
