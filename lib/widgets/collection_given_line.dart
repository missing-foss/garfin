// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/collection_set.dart';
import '../models/jellyfin_user.dart';
import '../models/library_item.dart';
import '../providers/collection_providers.dart';

/// The sentence for a set's state, in the child's own direction (#107).
///
/// Six strings rather than one with a plural, because two things vary
/// independently and neither is a quantity: **the verb** inverts with the
/// shortlist mode (ground rule 3 — the same label gives to one child and
/// withholds from another), and **all** reads differently from a partial count.
/// "All 8 given to Emma" is the sentence a parent is looking for; "8 of 8"
/// reads like a coincidence.
///
/// Kept out of the models on purpose: [CollectionGiven] is the count and the
/// direction, and it has no opinion about wording.
String collectionGivenText(
  AppLocalizations l10n,
  CollectionGiven given,
  String name,
) {
  if (given.mode == ShortlistMode.block) {
    if (given.none) return l10n.collectionKeptNone(name);
    if (given.all) return l10n.collectionKeptAll(given.total, name);
    return l10n.collectionKeptSome(given.labelled, given.total, name);
  }
  if (given.none) return l10n.collectionGivenNone(name);
  if (given.all) return l10n.collectionGivenAll(given.total, name);
  return l10n.collectionGivenSome(given.labelled, given.total, name);
}


/// The same sentence on a **grid tile**, for one collection.
///
/// The set header and the write preview get this free — their members are
/// already loaded. The grid does not: nothing on its path builds the collection
/// index, and `CollectionRepository.index()` is 1 + N requests, so putting the
/// badge on the grid by way of the index would pay for every collection in the
/// library to label the handful on screen.
///
/// So this asks for **one set**, the one it is drawing, through
/// `collectionSetProvider` — which exists precisely to fetch a single
/// membership without waiting on the index. The cost is one request per visible
/// collection tile, paged with the grid: it scales with what is on screen
/// rather than with the size of the library. Measured and ruled on 2026-08-27;
/// `docs/DECISIONS.md` § Collections carries the arithmetic.
///
/// Falls back to [whenSilent] while the membership is loading, if it fails, and
/// when there is no child to say it about. A share that flickers in and out is
/// harder to trust than one that is simply absent, and there is nothing here
/// worth an error state.
///
/// **It falls back rather than rendering nothing, because it now owns a corner
/// of the tile rather than a line of its own.** An empty render used to cost a
/// line under the title and nothing else; in the badge slot it costs the
/// "{count} titles" badge that stood there — on every collection tile until its
/// membership arrives, and for good if that request fails. The caller cannot
/// pick between them with `??`: this widget is non-null on all three of those
/// paths, and only its own build knows which one it is on.
class CollectionGivenLine extends ConsumerWidget {
  const CollectionGivenLine({
    super.key,
    required this.session,
    required this.collection,
    required this.child,
    this.whenSilent,
  });

  final AuthSession session;
  final LibraryItem collection;

  /// Null when nobody is picked, which is when this has nothing to say: the
  /// sentence names a child and inverts with their mode, so there is no neutral
  /// form.
  final JellyfinUser? child;

  /// What stands in this widget's place whenever it has nothing to say.
  ///
  /// `LibraryTile.collectionCountBadge` on the grid — the plain size of the
  /// set, which is what the corner held before the share moved into it. Null
  /// leaves the corner empty, which is right where the set's size is unknown
  /// too.
  final Widget? whenSilent;

  Widget get _silent => whenSilent ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = child;
    if (picked == null) return _silent;

    final set = ref
        .watch(collectionSetProvider(
            CollectionRequest(session: session, collection: collection)))
        .asData
        ?.value;
    if (set == null) return _silent;

    // A count of **labels**, never of what the child can see. The server
    // decides the latter, tags and rating cap together, and computing it here
    // is what ground rule 4 forbids.
    final owned = picked.policy.shortlistTags;
    final given = CollectionGiven.of(
      labelled: set.members.where((m) => m.hasAnyLabel(owned)).length,
      total: set.size,
      child: picked,
    );
    if (given == null) return _silent;

    final l10n = AppLocalizations.of(context);
    final sentence = collectionGivenText(l10n, given, picked.name);
    final theme = Theme.of(context);

    // **A ring, not the sentence.** "Les 5 partagés avec Emma" was the longest
    // thing on a tile and named a child the app bar already names. Chosen by
    // the owner over numerals, on the reasoning that a set whose ring is
    // ambiguous is one tap from the sentence in full — which the collection
    // screen does show, and which this keeps in the semantic label besides.
    //
    // **Direction is carried by tone.** Ground rule 3 makes an allow list and
    // a block list opposite verbs, and a proportion reads the same either way,
    // so the two tones are the ones this screen already uses for state rather
    // than a new pair. That is a weaker carrier than a word, and it is a
    // deliberate trade rather than an oversight: the sentence is on the
    // collection screen and in the spoken label, and both are reachable.
    // **A badge on the poster, not a line under the title.** The ring alone was
    // 14dp in the tile's smallest text zone and was reported unnoticeable on a
    // phone — it was sized to *fit* at 83dp, and fitting is not being seen at
    // arm's length.
    //
    // The numerals came back with it. A ring is a proportion to interpret; a
    // ring beside `3/6` is one to read, and it costs no more room than the
    // "{count} titles" badge it stands in for — that count is not lost, it is
    // the denominator.
    //
    // `container: true`, so the sentence is a node of its own rather than being
    // merged into the tile's label — which is where it went first, and it did
    // not survive the trip.
    return Semantics(
      container: true,
      label: sentence,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GivenRing(given: given),
                const SizedBox(width: 4),
                Text(
                  '${given.labelled}/${given.total}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How much of a set is the child's, as a filled ring.
///
/// **The all case is the ring being closed**, which is the shape's own answer
/// to what six strings used to separate — "All 5 given" against "3 of 5". A
/// full circle is read as *all* without counting, which is the argument the
/// catalogue already made in words: "8 of 8 reads like a coincidence".
class GivenRing extends StatelessWidget {
  const GivenRing({super.key, required this.given});

  final CollectionGiven given;

  /// Small enough to sit under a title on an 83dp tile, large enough that the
  /// arc's ends are distinguishable from a full circle at that size.
  static const diameter = 14.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      size: const Size(diameter, diameter),
      painter: GivenRingPainter(
        fraction: given.total == 0 ? 0 : given.labelled / given.total,
        // The same two tones the state badge uses, so a parent is not learning
        // a second colour language for the same distinction.
        tone: given.mode == ShortlistMode.block
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
        track: theme.colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

/// Public so a test can read the tone and the fraction the widget actually
/// built, rather than recomputing them from the theme — which is a test that
/// passes whatever the widget does. The same reason [TankDrifter] is public.
class GivenRingPainter extends CustomPainter {
  const GivenRingPainter({
    required this.fraction,
    required this.tone,
    required this.track,
  });

  final double fraction;
  final Color tone;
  final Color track;

  static const _stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _stroke / 2,
      _stroke / 2,
      size.width - _stroke,
      size.height - _stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * pi, false, base);

    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = tone;
    // From the top, clockwise, which is how a dial is read.
    canvas.drawArc(rect, -pi / 2, 2 * pi * fraction.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(covariant GivenRingPainter old) =>
      old.fraction != fraction || old.tone != tone || old.track != track;
}
