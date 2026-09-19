// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/library_count.dart';
import 'package:garfin/models/library_item.dart';

/// Standing a collection in for its members (#144), and the count line above
/// them.
///
/// The ruling: BoxSets only, the line shows the number displayed, and the
/// subtraction is *narrowed* — applied only where it is exact.
///
/// **The rows themselves are asserted through the screen**, in
/// `collapse_on_screen_test.dart`. A predicate reimplemented here passed while
/// the shipped one was deleted — measured in review — so this file keeps to the
/// two pieces that are genuinely shared: the member set, and the count.
void main() {
  LibraryItem film(String id) =>
      LibraryItem(id: id, name: id, type: 'Movie', tags: const []);

  CollectionSet setOf(String id, List<String> memberIds) => CollectionSet(
        collection: LibraryItem(
          id: id,
          name: id,
          type: 'BoxSet',
          tags: const [],
        ),
        members: memberIds.map(film).toList(),
      );

  group('which ids a collection stands for', () {
    test('every member, once, across all the sets', () {
      final index = CollectionIndex([
        setOf('set-a', ['f1', 'f2']),
        setOf('set-b', ['f3']),
      ]);

      expect(index.allMemberIds, {'f1', 'f2', 'f3'});
    });

    test('a film in two sets is counted once', () {
      final index = CollectionIndex([
        setOf('set-a', ['f1', 'f2']),
        setOf('set-b', ['f2', 'f3']),
      ]);

      expect(index.allMemberIds, {'f1', 'f2', 'f3'},
          reason: 'it is one row on the grid, so it is one row dropped');
    });

    test('an empty index hides nothing', () {
      expect(const CollectionIndex.empty().allMemberIds, isEmpty);
    });
  });

  group('the count line', () {
    test('subtracts the hidden members when the subtraction is exact', () {
      expect(
        collapsedLibraryTotal(total: 240, hiddenMembers: 40, exact: true),
        200,
      );
    });

    test('leaves the server count alone when it is not', () {
      // Under a genre, decade, search or cap the index cannot say how many
      // members the server would have returned, so subtracting all of them
      // would report fewer titles than the grid holds.
      expect(
        collapsedLibraryTotal(total: 240, hiddenMembers: 40, exact: false),
        240,
      );
    });

    test('never goes below zero', () {
      expect(
        collapsedLibraryTotal(total: 3, hiddenMembers: 99, exact: true),
        0,
        reason: 'the two numbers are two requests and can disagree',
      );
    });

    test('still subtracts tagged from the collapsed total, not the raw one',
        () {
      final child = JellyfinUser(
        id: 'kid-1',
        name: 'Emma',
        policy: const UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: ['kids-emma'],
          blockedTags: [],
        ),
      );

      final collapsed =
          collapsedLibraryTotal(total: 240, hiddenMembers: 40, exact: true);
      final count = libraryCountFor(total: collapsed, tagged: 30, child: child);

      expect(count.kind, LibraryCountKind.notYetGiven);
      expect(count.count, 170);
    });
  });
}
