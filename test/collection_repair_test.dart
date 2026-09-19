// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';

/// When a set is holding loose films, and which way the container has to move.
///
/// The repair offer turns on two questions, and both invert with the mode:
/// how many members the child actually **has** (not how many carry a label),
/// and whether an openable container is a labelled one. Getting either
/// backwards offers the repair to the wrong sets and, worse, writes the
/// container the wrong way for half the children on the server.
void main() {
  JellyfinUser kid(ShortlistMode mode) => JellyfinUser(
        id: 'kid-1',
        name: 'Emma',
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: mode == ShortlistMode.allow ? const ['kids-emma'] : const [],
          blockedTags: mode == ShortlistMode.block ? const ['block-emma'] : const [],
        ),
      );

  CollectionGiven given(ShortlistMode mode, {required int labelled}) =>
      CollectionGiven.of(labelled: labelled, total: 8, child: kid(mode))!;

  group('an allow-list child', () {
    test('has the members that carry the label', () {
      expect(given(ShortlistMode.allow, labelled: 3).givenToChild, 3);
    });

    test('needs the container labelled to open the set', () {
      expect(given(ShortlistMode.allow, labelled: 3).containerWantsLabel, isTrue);
    });
  });

  group('a block-list child', () {
    /// The count that would be exactly backwards if `labelled` were used
    /// directly: three labelled members are three they are KEPT FROM, so five
    /// is what they actually have.
    test('has the members that do NOT carry the label', () {
      expect(given(ShortlistMode.block, labelled: 3).givenToChild, 5);
    });

    /// And the repair writes the opposite way: the label is what shuts a set
    /// for them, so an openable container is an unlabelled one.
    test('needs the container UNlabelled to open the set', () {
      expect(given(ShortlistMode.block, labelled: 3).containerWantsLabel, isFalse);
    });

    test('a fully-labelled set is one they have nothing from', () {
      expect(given(ShortlistMode.block, labelled: 8).givenToChild, 0);
    });
  });
}
