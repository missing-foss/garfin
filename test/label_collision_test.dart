// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/label_collision.dart';

/// Which children the server would treat as sharing one label.
///
/// **The normalizer is a stand-in, on purpose.** Which folding rule is right is
/// the server's business and differs between versions; the one used here is the
/// 12.0 rule as described on the tracker — lower-case, strip diacritics,
/// punctuation to space, collapse — written inline so these tests pin the
/// *detection* and not somebody's implementation of the folding. The real one
/// is a separate decision and is not in this change.
///
/// The tests worth reading twice are the negative ones. A warning about
/// children sharing a list is only worth having if it stays quiet for the
/// households that meant to.
void main() {
  // A deliberately small diacritic map: enough for the tracker's own example
  // and nothing more, because this is scaffolding for the tests rather than the
  // implementation under test.
  const folded = <String, String>{'é': 'e', 'è': 'e', 'ç': 'c', 'ï': 'i'};

  String normalize(String label) {
    final lowered = label.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(folded[ch] ?? ch);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  JellyfinUser child(
    String id,
    String name,
    List<String> labels, {
    bool block = false,
    bool conflicting = false,
  }) =>
      JellyfinUser(
        id: id,
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: (block && !conflicting) ? const [] : labels,
          blockedTags: (block || conflicting) ? labels : const [],
        ),
      );

  List<LabelCollision> find(List<JellyfinUser> children) =>
      findLabelCollisions(children, normalize: normalize);

  group('what counts as a collision', () {
    test('punctuation-only variants are caught', () {
      // The tracker's own list: every one of these folds to `kids emma`.
      final collisions = find([
        child('a', 'Emma', ['kids-emma']),
        child('b', 'Emmy', ['kids_emma']),
      ]);

      expect(collisions, hasLength(1));
      expect(collisions.single.labels, ['kids-emma', 'kids_emma']);
      expect(collisions.single.entries.map((e) => e.userName), ['Emma', 'Emmy']);
    });

    test('an accent alone is enough', () {
      final collisions = find([
        child('a', 'Chloé', ['kids-chloé']),
        child('b', 'Chloe', ['kids-chloe']),
      ]);

      expect(collisions, hasLength(1));
      expect(collisions.single.labels, ['kids-chloé', 'kids-chloe']);
    });

    test('case alone is enough', () {
      expect(
        find([
          child('a', 'Emma', ['kids-emma']),
          child('b', 'Emmy', ['Kids Emma']),
        ]),
        hasLength(1),
      );
    });

    test('three children on two labels are all named', () {
      // Two sharing deliberately, plus one variant. All three now hold one
      // list, so naming only the odd one out would describe the wrong problem.
      final collisions = find([
        child('a', 'Emma', ['kids-emma']),
        child('b', 'Emmy', ['kids-emma']),
        child('c', 'Em', ['kids_emma']),
      ]);

      expect(collisions, hasLength(1));
      expect(collisions.single.entries, hasLength(3));
      // The shared label appears once, not twice: two labels are involved.
      expect(collisions.single.labels, ['kids-emma', 'kids_emma']);
    });

    test('the raw label is reported, never the folded one', () {
      // What a parent has to go and change is what they typed.
      final collisions = find([
        child('a', 'Chloé', ['Kids-Chloé']),
        child('b', 'Chloe', ['kids_chloe']),
      ]);

      expect(collisions.single.labels, ['Kids-Chloé', 'kids_chloe']);
      expect(collisions.single.labels, isNot(contains('kids chloe')));
    });
  });

  group('what must NOT be a collision', () {
    test('two children deliberately sharing one identical label', () {
      // The common setup, and the false positive that would teach a parent to
      // ignore the warning that matters.
      expect(
        find([
          child('a', 'Emma', ['family-films']),
          child('b', 'Liam', ['family-films']),
        ]),
        isEmpty,
      );
    });

    test('one child holding two labels that fold together', () {
      // Redundant, not shared. Nothing of theirs reaches anybody else.
      expect(
        find([
          child('a', 'Emma', ['kids-emma', 'kids_emma']),
        ]),
        isEmpty,
      );
    });

    test('labels that genuinely differ', () {
      expect(
        find([
          child('a', 'Emma', ['kids-emma']),
          child('b', 'Liam', ['kids-liam']),
        ]),
        isEmpty,
      );
    });

    test('a child with no shortlist at all', () {
      expect(
        find([
          child('a', 'Emma', ['kids-emma']),
          child('b', 'Nobody', const []),
        ]),
        isEmpty,
      );
    });

    test('a child whose policy has both lists live contributes nothing', () {
      // `shortlistTags` is deliberately empty there: with two opposite verbs
      // in force, neither list means anything on its own, and a collision
      // built from one of them would be a guess wearing the clothes of an
      // answer.
      final both = child('b', 'Confused', ['kids_emma'], conflicting: true);
      expect(both.policy.shortlistMode, ShortlistMode.conflicting);

      expect(find([child('a', 'Emma', ['kids-emma']), both]), isEmpty);
    });

    test('a label that folds away to nothing gathers nobody', () {
      // Two children each holding punctuation would otherwise be collected
      // into a collision neither of them has.
      expect(
        find([
          child('a', 'Emma', ['---']),
          child('b', 'Liam', ['...']),
        ]),
        isEmpty,
      );
    });

    test('no children at all', () {
      expect(find(const []), isEmpty);
    });
  });

  group('which verbs are involved', () {
    test('two allow-lists do not cross modes', () {
      final collisions = find([
        child('a', 'Emma', ['kids-emma']),
        child('b', 'Emmy', ['kids_emma']),
      ]);

      expect(collisions.single.crossesModes, isFalse);
      expect(
        collisions.single.entries.map((e) => e.mode),
        everyElement(ShortlistMode.allow),
      );
    });

    test('an allow-list colliding with a block-list is flagged as crossing',
        () {
      // A different event, not a worse one: giving Emma a title would take it
      // away from Liam, because one tag is now doing both jobs. Anything that
      // puts this in words has to know which shape it is looking at.
      final collisions = find([
        child('a', 'Emma', ['kids-emma']),
        child('b', 'Liam', ['kids_emma'], block: true),
      ]);

      expect(collisions, hasLength(1));
      expect(collisions.single.crossesModes, isTrue);
      expect(
        collisions.single.entries.map((e) => e.mode),
        [ShortlistMode.allow, ShortlistMode.block],
      );
    });
  });

  group('the detector does not decide the rule', () {
    test('a stricter normalizer finds fewer collisions', () {
      // The whole reason the rule is injected: on a server that folds case but
      // not punctuation, the same two children are not sharing anything.
      final children = [
        child('a', 'Emma', ['kids-emma']),
        child('b', 'Emmy', ['kids_emma']),
      ];

      expect(find(children), hasLength(1));
      expect(
        findLabelCollisions(children, normalize: (l) => l.toLowerCase()),
        isEmpty,
      );
    });
  });

  group('the real folding rule, as Jellyfin 12.0 performs it', () {
    // The stand-in above pins the detection. This pins the rule itself, which
    // is the half that has to match somebody else's source.
    test('every variant the tracker lists folds to one value', () {
      const variants = [
        'kids-emma',
        'kids emma',
        'Kids Emma',
        'kids_emma',
        'kids--emma',
      ];
      expect(
        variants.map(foldLabelLikeJellyfin).toSet(),
        {'kids emma'},
      );
    });

    test('an accent folds away, which is what needs a real implementation', () {
      expect(foldLabelLikeJellyfin('kids-chloé'), 'kids chloe');
      expect(foldLabelLikeJellyfin('kids-chloe'), 'kids chloe');
    });

    test('a spread of accents, not just the one in the tracker', () {
      expect(foldLabelLikeJellyfin('Enfants-Noël'), 'enfants noel');
      expect(foldLabelLikeJellyfin('niño'), 'nino');
    });

    test('letters with no decomposition are folded too, and that is recorded',
        () {
      // Pinned as the behaviour that IS, not the behaviour that ought to be.
      // `ß` folds to one `s` rather than `ss`, which is not how German
      // transliterates it, and `æ`/`ø` fold at all — none of these three has a
      // Unicode decomposition, so an implementation built on decomposing and
      // stripping combining marks would leave them alone.
      //
      // Whether the server agrees is **unverified** — see the note on
      // `foldLabelLikeJellyfin`. The direction of any disagreement is
      // over-warning, which is the same direction this feature already errs in
      // deliberately.
      expect(foldLabelLikeJellyfin('Straße'), 'strase');
      expect(foldLabelLikeJellyfin('Ærø'), 'aero');
    });

    test('runs of punctuation collapse rather than leaving gaps', () {
      expect(foldLabelLikeJellyfin('kids -_- emma'), 'kids emma');
      expect(foldLabelLikeJellyfin('  kids-emma  '), 'kids emma');
    });

    test('digits survive, because a label may be one', () {
      expect(foldLabelLikeJellyfin('kids-emma-2'), 'kids emma 2');
    });

    test('a label of nothing but punctuation folds to empty', () {
      // Which the detector then refuses to gather anybody into.
      expect(foldLabelLikeJellyfin('---'), '');
    });

    test('labels that should NOT fold together still do not', () {
      expect(
        foldLabelLikeJellyfin('kids-emma'),
        isNot(foldLabelLikeJellyfin('kids-emmy')),
      );
    });

    test('driving the detector with the real rule finds the tracker pairs', () {
      final collisions = findLabelCollisions(
        [
          child('a', 'Chloé', ['kids-chloé']),
          child('b', 'Chloe', ['kids-chloe']),
        ],
        normalize: foldLabelLikeJellyfin,
      );
      expect(collisions, hasLength(1));
      expect(collisions.single.normalized, 'kids chloe');
    });
  });
}
