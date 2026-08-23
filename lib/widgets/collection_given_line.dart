// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import '../l10n/gen/app_localizations.dart';
import '../models/collection_set.dart';
import '../models/jellyfin_user.dart';

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
