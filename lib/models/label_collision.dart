// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:diacritic/diacritic.dart';

import 'jellyfin_user.dart';

/// How the server folds a label before comparing it with another.
///
/// Injected rather than fixed, because the rule is the **server's** and it
/// changes between versions. Nothing in this file knows which rule it has been
/// handed, and that is the point: the detection below is the half of the
/// problem that does not depend on the answer.
typedef LabelNormalizer = String Function(String label);

/// One child's label, inside a collision.
class CollidingLabel {
  const CollidingLabel({
    required this.userId,
    required this.userName,
    required this.label,
    required this.mode,
  });

  /// Keyed on the id, not the name: names repeat on a Jellyfin server and can
  /// be changed without the account changing — the same reason
  /// `pickedChildProvider` keys on one.
  final String userId;

  final String userName;

  /// The label as the policy actually holds it, never the folded form. What a
  /// parent has to go and change is what they typed.
  final String label;

  /// Which verb this child's shortlist is in. Carried because a collision
  /// between two allow-lists and a collision across an allow and a block are
  /// different events with different consequences — see [crossesModes].
  final ShortlistMode mode;
}

/// Two or more children whose labels **differ**, and which the server
/// nonetheless treats as one label.
///
/// The distinction that makes this worth reporting is *differ*: two children
/// deliberately sharing one identical label is an ordinary setup, not an
/// accident, and is never a collision here. See [findLabelCollisions].
class LabelCollision {
  const LabelCollision({required this.normalized, required this.entries});

  /// What all of [entries] fold to. Diagnostic only — it is the server's
  /// internal form and has no business on a screen.
  final String normalized;

  /// Every child caught by this collision, in the order they were given.
  /// Always at least two distinct children.
  final List<CollidingLabel> entries;

  /// The distinct labels involved, in first-seen order.
  ///
  /// Distinct because three children can be caught by two labels — two holding
  /// the same one and a third holding the variant — and listing that label
  /// twice would describe the wrong shape of problem.
  List<String> get labels {
    final seen = <String>[];
    for (final entry in entries) {
      if (!seen.contains(entry.label)) seen.add(entry.label);
    }
    return seen;
  }

  /// Whether the children caught here are not all under the same verb.
  ///
  /// **This changes what the collision means, not just how bad it is.** Two
  /// allow-list children sharing a folded label see each other's titles. An
  /// allow-list child colliding with a block-list one is the opposite shape:
  /// giving the first a title takes it away from the second, because one tag is
  /// now doing both jobs. Anything that puts this in words has to know which it
  /// is looking at, so the detector reports it rather than flattening it.
  bool get crossesModes => entries.any((e) => e.mode != entries.first.mode);
}

/// Every set of children whose labels the server would treat as one.
///
/// Local and cheap: the Kids screen has already read every managed child's
/// policy, so this asks the server nothing.
///
/// Three rules decide what counts, and each one exists to avoid a false
/// positive that would be worse than staying quiet:
///
/// - **At least two distinct children.** One child holding both `kids-emma` and
///   `kids_emma` has a redundant label, not a shared list. Nothing of theirs
///   leaks anywhere.
/// - **The raw labels must not all be identical.** Two children genuinely
///   holding `family-films` are sharing on purpose. That is a common setup and
///   flagging it would put a warning on households that have done nothing
///   wrong — which is the fastest way to teach a parent to ignore the warning
///   that matters.
/// - **Only labels that define a shortlist.** `UserPolicy.shortlistTags` is
///   already empty for an unmanaged child and — deliberately — for one whose
///   policy has both lists live, where there is no single set of tags that
///   means anything.
///
/// Order is first-seen throughout, so the same input gives the same output and
/// a test can say what it expects.
List<LabelCollision> findLabelCollisions(
  Iterable<JellyfinUser> children, {
  required LabelNormalizer normalize,
}) {
  final groups = <String, List<CollidingLabel>>{};
  final order = <String>[];

  for (final child in children) {
    final mode = child.policy.shortlistMode;
    for (final label in child.policy.shortlistTags) {
      final key = normalize(label);
      // A label that folds to nothing is not evidence of anything: it would
      // gather every other empty one into a collision none of them has.
      if (key.isEmpty) continue;
      final group = groups.putIfAbsent(key, () {
        order.add(key);
        return <CollidingLabel>[];
      });
      group.add(CollidingLabel(
        userId: child.id,
        userName: child.name,
        label: label,
        mode: mode,
      ));
    }
  }

  final collisions = <LabelCollision>[];
  for (final key in order) {
    final entries = groups[key]!;
    final children = entries.map((e) => e.userId).toSet();
    if (children.length < 2) continue;
    final labels = entries.map((e) => e.label).toSet();
    if (labels.length < 2) continue;
    collisions.add(LabelCollision(normalized: key, entries: entries));
  }
  return collisions;
}

/// The server's own folding, as Jellyfin 12.0 performs it.
///
/// Transcribed from the two steps the server applies, in that order — strip
/// diacritics and lower-case, then reduce anything that is neither a letter nor
/// a digit to a space and collapse the runs:
///
///     kids-emma  kids_emma  Kids Emma  kids--emma   ->  "kids emma"
///     kids-chloé kids-chloe                          ->  "kids chloe"
///
/// **This is the 12.0 rule, and it is deliberately applied whatever the server
/// is.** The 10.11.11 rule is `strip diacritics + lower-case` with no
/// punctuation step, so 12.0's rule is that rule with a further function
/// applied to its output — which makes every 10.11.11 collision a 12.0
/// collision, and the two-rule "union" the tracker proposed exactly equal to
/// this one rule. Warning on it therefore never *misses* a collision.
///
/// What it can do is warn **early**: on 10.11.11 a pair differing only by
/// punctuation collides under neither the count path nor the visibility check,
/// so nothing is wrong on that server yet. It becomes wrong on upgrade. That is
/// the direction chosen deliberately, and it is why the copy this feeds says
/// Jellyfin *can* read the labels as one rather than asserting that it does —
/// see `kidsLabelClashSame`.
///
/// **Where this and the server disagree — measured on 12.0.0, 2026-08-24, and
/// it is one agreement and one disagreement.** The diacritic step is the
/// `diacritic` package, which folds letters that have no Unicode
/// decomposition. Two of them were put to a live server:
///
/// - **`œ` agrees.** A film tagged `kids-sœur` is matched by `tags=kids-soeur`,
///   and the package folds `œ` to `oe` too. The French case — `sœur`, `cœur`,
///   `Lætitia`, in the language this project keeps complete — is right.
/// - **`ß` disagrees.** A film tagged `kids-straße` is matched by neither
///   `kids-strasse` nor `kids-strase`; the server leaves `ß` alone while the
///   package folds it to one `s`. So two labels differing only by `ß` are
///   reported here as one label and kept apart by the server.
///
/// **`æ`, `ø` and the rest of that family remain unmeasured**, and `œ` folding
/// does not predict that `ø` does — they were only ever alike in having no
/// decomposition.
///
/// The consequence is bounded and is the direction already chosen: this folds
/// *more* than the server does, so it can warn about a pair the server would
/// keep apart, and cannot miss a pair the server folds. Over-warning is the
/// same error this already makes knowingly on 10.11.11, and the copy is
/// conditional for that reason. See `docs/JELLYFIN-API.md`.
String foldLabelLikeJellyfin(String label) => removeDiacritics(label)
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
