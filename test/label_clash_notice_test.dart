// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/label_collision.dart';
import 'package:garfin/widgets/label_clash_notice.dart';

/// What the notice actually says.
///
/// The claims worth pinning are about what it does **not** say. It must not
/// assert that the children see each other's titles — false on 10.11.11, where
/// a punctuation-only pair collides on neither path — and it must not use one
/// sentence for two events whose consequences are opposites.
void main() {
  JellyfinUser child(String id, String name, List<String> labels,
          {bool block = false}) =>
      JellyfinUser(
        id: id,
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: block ? const [] : labels,
          blockedTags: block ? labels : const [],
        ),
      );

  Future<void> pump(WidgetTester tester, List<JellyfinUser> children,
      {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LabelClashNotice(
          collisions: findLabelCollisions(children,
              normalize: foldLabelLikeJellyfin),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('says nothing at all when there is no clash', (tester) async {
    await pump(tester, [
      child('a', 'Emma', ['kids-emma']),
      child('b', 'Liam', ['kids-liam']),
    ]);

    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('Jellyfin'), findsNothing);
  });

  testWidgets('names both children and both labels', (tester) async {
    await pump(tester, [
      child('a', 'Chloé', ['kids-chloé']),
      child('b', 'Chloe', ['kids-chloe']),
    ]);

    expect(find.textContaining('Chloé, Chloe'), findsOneWidget);
    expect(find.textContaining('kids-chloé, kids-chloe'), findsOneWidget);
  });

  testWidgets('never claims outright that Jellyfin does read them as one',
      (tester) async {
    // The whole point of the conditional. On 10.11.11 a punctuation-only pair
    // collides on neither the count path nor the visibility check, so the
    // strong sentence would be false on current stable.
    await pump(tester, [
      child('a', 'Emma', ['kids-emma']),
      child('b', 'Emmy', ['kids_emma']),
    ]);

    expect(find.textContaining('can read as the same one'), findsOneWidget);
    expect(find.textContaining('see each other'), findsNothing);
  });

  testWidgets('two allow-lists get the reaching sentence', (tester) async {
    await pump(tester, [
      child('a', 'Emma', ['kids-emma']),
      child('b', 'Emmy', ['kids_emma']),
    ]);

    expect(find.textContaining('what you give one of them reaches the others'),
        findsOneWidget);
    expect(find.textContaining('hides it from the other'), findsNothing);
  });

  testWidgets('an allow against a block gets the opposite sentence',
      (tester) async {
    // The consequence inverts, so the sentence has to.
    await pump(tester, [
      child('a', 'Emma', ['kids-emma']),
      child('b', 'Liam', ['kids_emma'], block: true),
    ]);

    expect(find.textContaining('hides it from the other'), findsOneWidget);
    expect(find.textContaining('reaches the others'), findsNothing);
  });

  testWidgets('a child holding two clashing labels is named once',
      (tester) async {
    // Named twice, the sentence reads as two children with the same name —
    // which happens on a real server, and would send a parent looking for an
    // account that does not exist.
    await pump(tester, [
      child('a', 'Emma', ['kids-emma', 'kids_emma']),
      child('b', 'Emmy', ['kids--emma']),
    ]);

    expect(find.textContaining('Emma, Emmy'), findsOneWidget);
    expect(find.textContaining('Emma, Emma'), findsNothing);
  });

  testWidgets('two clashes are two sentences under one heading',
      (tester) async {
    await pump(tester, [
      child('a', 'Emma', ['kids-emma']),
      child('b', 'Emmy', ['kids_emma']),
      child('c', 'Chloé', ['kids-chloé']),
      child('d', 'Chloe', ['kids-chloe']),
    ]);

    expect(find.text('Labels worth changing'), findsOneWidget);
    expect(find.textContaining('Emma, Emmy'), findsOneWidget);
    expect(find.textContaining('Chloé, Chloe'), findsOneWidget);
  });

  testWidgets('it speaks French', (tester) async {
    await pump(
      tester,
      [
        child('a', 'Chloé', ['kids-chloé']),
        child('b', 'Chloe', ['kids-chloe']),
      ],
      locale: const Locale('fr'),
    );

    expect(find.text('Étiquettes à changer'), findsOneWidget);
    expect(find.textContaining('peut lire comme une seule'), findsOneWidget);
  });
}
