// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// A number next to a counted word is a plural, in every language.
///
/// **The reported failure.** Six strings were ICU plurals and the rest that
/// counted something were a bare `{count}`: "1 titles", "1 episodes", "1 years
/// old", "1 things Emma hasn't got yet", and in French "1 titres". The gates
/// check that each language has every key and the same placeholders; neither
/// reads a word, so a new bare count would ship as quietly as these did.
///
/// So the rule is enforced here: **every message with a number placeholder is
/// a plural**, unless it is listed below with the reason it cannot be one.
void main() {
  /// Number placeholders that are not counts of anything: a rating, a range,
  /// a year, a fraction whose noun-free form reads the same at one.
  const notCounts = <String, String>{
    'kidsRatingCapValue': 'a rating, not a count',
    'kidsRatingCapPair': 'a rating, not a count',
    'kidsBirthYearInvalid': 'the bounds of a year',
    'filterDecadeValue': 'a decade, not a count',
    'filterActiveCount': 'a bare number on a badge',
    'libraryHoldersMore': 'a bare "+N" on an avatar row',
    'assignSees': '"sees 1 of 400" reads the same at one',
    'assignResult': '"now sees 1 of 400" reads the same at one',
    'collectionGivenSome': '"1 of 3 given" reads the same at one',
    'collectionKeptSome': '"1 of 3 kept" reads the same at one',
  };

  for (final file in ['lib/l10n/app_en.arb', 'lib/l10n/app_fr.arb']) {
    test('$file: every counted string is a plural', () {
      final arb = jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
      // Placeholder types live on the English template.
      final template = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;

      final bare = <String>[];
      for (final key in arb.keys.where((k) => !k.startsWith('@'))) {
        final meta = template['@$key'];
        final placeholders = meta is Map ? meta['placeholders'] : null;
        if (placeholders is! Map) continue;
        final numbers = [
          for (final entry in placeholders.entries)
            if (entry.value is Map &&
                const {'int', 'num', 'double'}.contains(entry.value['type']))
              entry.key,
        ];
        if (numbers.isEmpty || notCounts.containsKey(key)) continue;
        if (!(arb[key] as String).contains(', plural,')) bare.add(key);
      }

      expect(bare, isEmpty,
          reason: 'a number placeholder outside a plural: make it '
              '{count, plural, one{…} other{…}}, or list it in notCounts with '
              'why it cannot be one');
    });
  }

  test('and the words agree with the number', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final fr = await AppLocalizations.delegate.load(const Locale('fr'));

    expect(en.libraryItemCount(1), '1 thing');
    expect(en.libraryItemCount(2), '2 things');
    expect(en.kidsAgeYears(1), '1 year old');
    expect(en.libraryEpisodeCount(1), '1 episode');
    expect(en.libraryNotYetGiven(1, 'Emma'), "1 thing Emma hasn't got yet");
    // French counts zero as singular.
    expect(fr.libraryItemCount(0), '0 titre');
    expect(fr.libraryItemCount(1), '1 titre');
    expect(fr.libraryItemCount(2), '2 titres');
    expect(fr.kidsAgeYears(1), '1 an');
    // The selector is per language: French agrees with what was changed.
    expect(fr.assignBatchPartial(1, 3), '1 titre modifié sur 3.');
    expect(en.assignBatchPartial(1, 3), '1 of 3 titles changed.');
  });
}
