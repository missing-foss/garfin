// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/item_holder.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_item.dart';

/// Who the grid says already has a title (#84).
///
/// The claim being pinned is narrow on purpose: a face means *the label is on
/// the item*, for a child whose labels are an allow-list. Every other account
/// shape is left out, and the reason differs per shape — which is why each gets
/// its own test rather than one "only allow-mode" assertion.
void main() {
  KidSummary kid(
    String name, {
    List<String> allowed = const [],
    List<String> blocked = const [],
    String? avatarUrl,
  }) =>
      KidSummary(
        user: JellyfinUser(
          id: 'id-$name',
          name: name,
          policy: UserPolicy(
            isAdministrator: false,
            isDisabled: false,
            allowedTags: allowed,
            blockedTags: blocked,
          ),
        ),
        avatarUrl: avatarUrl,
      );

  LibraryItem film({List<String> tags = const []}) =>
      LibraryItem(id: 'a', name: 'Paddington', type: 'Movie', tags: tags);

  group('an avatar means the label is on the item', () {
    test('a child whose label matches is listed', () {
      final holders = holdersOf(
        item: film(tags: const ['kids-emma']),
        children: [kid('Emma', allowed: const ['kids-emma'])],
      );

      expect(holders.single.name, 'Emma');
      expect(holders.single.userId, 'id-Emma');
    });

    test('a child whose label does not match is not', () {
      final holders = holdersOf(
        item: film(tags: const ['kids-leo']),
        children: [kid('Emma', allowed: const ['kids-emma'])],
      );

      expect(holders, isEmpty);
    });

    test("the scraper's own tags are not labels", () {
      // Measured on 10.11.11: a tagged film also carried "kidnapping" and
      // "alien abduction". Anything treating "has tags" as "shared" would put
      // every child's face on every poster.
      final holders = holdersOf(
        item: film(tags: const ['kidnapping', 'alien abduction', 'dinosaur']),
        children: [kid('Emma', allowed: const ['kids-emma'])],
      );

      expect(holders, isEmpty);
    });

    test('matching is case-insensitive, agreeing with the server', () {
      final holders = holdersOf(
        item: film(tags: const ['KIDS-EMMA']),
        children: [kid('Emma', allowed: const ['kids-emma'])],
      );

      expect(holders, hasLength(1));
    });

    test('any of a child\'s labels counts, because the server matches any', () {
      final holders = holdersOf(
        item: film(tags: const ['family-films']),
        children: [
          kid('Emma', allowed: const ['kids-emma', 'family-films']),
        ],
      );

      expect(holders, hasLength(1));
    });

    test('several children on one title, in the order they were given', () {
      // The order of the Kids overview, which is the order of the picker row
      // above the grid. A row that reshuffled between tiles would make the
      // faces harder to read than no faces.
      final holders = holdersOf(
        item: film(tags: const ['kids-emma', 'kids-leo']),
        children: [
          kid('Emma', allowed: const ['kids-emma']),
          kid('Sam', allowed: const ['kids-sam']),
          kid('Léo', allowed: const ['kids-leo']),
        ],
      );

      expect(holders.map((h) => h.name), ['Emma', 'Léo']);
    });

    test('the picture comes along, and null stays null', () {
      final holders = holdersOf(
        item: film(tags: const ['kids-emma', 'kids-leo']),
        children: [
          kid('Emma',
              allowed: const ['kids-emma'],
              avatarUrl: 'http://host:8096/Users/id-Emma/Images/Primary?tag=t'),
          kid('Léo', allowed: const ['kids-leo']),
        ],
      );

      expect(holders[0].avatarUrl, contains('/Users/id-Emma/Images/Primary'));
      // Null rather than a URL that 404s — `UserAvatar` shows the initial.
      expect(holders[1].avatarUrl, isNull);
    });
  });

  group('the accounts a face would misdescribe', () {
    test('a block-list child is left out, though the tag matches', () {
      // The failure this prevents is the worst kind: for a block-list child a
      // matching tag means the title is *withheld*, so their face on the
      // poster would say the exact opposite of what every other face says.
      final holders = holdersOf(
        item: film(tags: const ['no-horror']),
        children: [kid('Sam', blocked: const ['no-horror'])],
      );

      expect(holders, isEmpty);
    });

    test('a block-list child is left out of an unmatched title too', () {
      // The inverse reading — "no tag, so they can reach it" — is also not
      // what an avatar row means. Either way they are simply not in it.
      final holders = holdersOf(
        item: film(tags: const ['dinosaur']),
        children: [kid('Sam', blocked: const ['no-horror'])],
      );

      expect(holders, isEmpty);
    });

    test('a conflicting account is left out entirely — ground rule 3', () {
      // Both lists live at once. There is no correct verb to pick, so there is
      // no correct per-item answer either, and a face is an answer.
      //
      // Two independent things enforce this, and neither is redundant:
      // the mode check here, and `UserPolicy.shortlistTags` answering empty
      // for a conflicting account. Mutating either one alone leaves this test
      // green — mutating both together turns it red, which is what says the
      // test is a gate rather than a description.
      final holders = holdersOf(
        item: film(tags: const ['kids-emma', 'no-horror']),
        children: [
          kid('Alex',
              allowed: const ['kids-emma'], blocked: const ['no-horror']),
        ],
      );

      expect(holders, isEmpty);
    });

    test('an account with no shortlist at all has nothing to match', () {
      final holders = holdersOf(
        item: film(tags: const ['kids-emma']),
        children: [kid('Mum')],
      );

      expect(holders, isEmpty);
    });

    test('one household, one title, and only the allow-list child on it', () {
      // The three shapes together, which is how they arrive: a family where
      // one child is on an allow-list, one on a block-list and one account is
      // unmanaged. Each of the tests above passes on its own for a helper that
      // returned nothing at all.
      final holders = holdersOf(
        item: film(tags: const ['kids-emma', 'no-horror']),
        children: [
          kid('Emma', allowed: const ['kids-emma']),
          kid('Sam', blocked: const ['no-horror']),
          kid('Alex',
              allowed: const ['kids-emma'], blocked: const ['no-horror']),
          kid('Mum'),
        ],
      );

      expect(holders.map((h) => h.name), ['Emma']);
    });
  });

  group('the selected child comes first (#99)', () {
    // **Order is load-bearing since the plain-share badge was dropped.** The
    // row draws holders in order and collapses the overflow into a `+N`, so on
    // a narrow tile the face that survives is whoever is first. If that is not
    // the selected child, the tile says nothing about the child it is
    // selected for — which is the whole thing the face is now carrying.
    final children = [
      kid('Ana', allowed: const ['t']),
      kid('Emma', allowed: const ['t']),
      kid('Leo', allowed: const ['t']),
    ];

    test('they are moved to the front, and the rest keep their order', () {
      final holders = holdersOf(
        item: film(tags: const ['t']),
        children: children,
        selectedChildId: 'id-Emma',
      );

      expect(holders.map((h) => h.name), ['Emma', 'Ana', 'Leo']);
    });

    test('with nobody selected the order is untouched', () {
      // Everyone: there is no child for the row to favour, and reordering
      // would be inventing a priority the screen does not have.
      final holders = holdersOf(
        item: film(tags: const ['t']),
        children: children,
      );

      expect(holders.map((h) => h.name), ['Ana', 'Emma', 'Leo']);
    });

    test('a selected child who does not hold it changes nothing', () {
      final holders = holdersOf(
        item: film(tags: const ['t']),
        children: children,
        selectedChildId: 'id-Nobody',
      );

      expect(holders.map((h) => h.name), ['Ana', 'Emma', 'Leo']);
    });

    test('a selected child already first is left alone', () {
      // The `index <= 0` branch: rebuilding the list would be the same answer
      // by a longer route, and getting the sublist arithmetic wrong here is
      // exactly how a list loses an entry.
      final holders = holdersOf(
        item: film(tags: const ['t']),
        children: children,
        selectedChildId: 'id-Ana',
      );

      expect(holders.map((h) => h.name), ['Ana', 'Emma', 'Leo']);
    });
  });
}
