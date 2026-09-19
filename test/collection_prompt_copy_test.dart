// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/widgets/collection_prompt.dart';

/// What the cascade prompt promises, against what the write now does.
///
/// Ground rule 6 is not "ask about everything" — it is that the app must never
/// do what its own prompt denies. Answering *just this one* labels the film
/// **and** the collection it was given from, because a set the child has no
/// label for is invisible to them and the film would otherwise arrive loose.
/// That is stated in the dialog rather than asked, so this test exists to stop
/// the behaviour and the sentence drifting apart again.
void main() {
  LibraryItem film(String id, String name) =>
      LibraryItem(id: id, name: name, type: 'Movie', tags: const []);

  final set = CollectionSet(
    collection: LibraryItem(
        id: 'set-1', name: 'The Paddington Collection', type: 'BoxSet',
        tags: const []),
    members: [film('film-1', 'Paddington'), film('film-2', 'Paddington 2')],
  );

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => askKeepSetTogether(
                context,
                set: set,
                itemId: 'film-1',
                itemName: 'Paddington',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the prompt says the set will appear, rather than asking again',
      (tester) async {
    await open(tester);

    // The offer itself is unchanged: this is not a second permission question.
    expect(find.text('Just this one'), findsOneWidget);
    expect(find.text('All 2'), findsOneWidget);

    // And the consequence of *either* answer is stated, naming the set.
    expect(
      find.textContaining('appears in their library'),
      findsOneWidget,
      reason: 'answering "just this one" also labels the collection; the '
          'prompt must not deny what the write does',
    );
    expect(find.textContaining('The Paddington Collection'), findsWidgets);
  });

  testWidgets('and says it in French too', (tester) async {
    // The gate refuses an untranslated key, but a key can be translated and
    // still not rendered — the sentence has to reach the dialog in both.
    await open(tester, locale: const Locale('fr'));
    expect(find.textContaining('apparaît dans sa bibliothèque'), findsOneWidget);
  });
}
