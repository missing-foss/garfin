// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/widgets/library_search_field.dart';

/// The search field (#73): debounced, clearable, and it must not fire into a
/// disposed ref.
///
/// Every keystroke here costs a **server-side library query**, and #68 measured
/// what one of those costs: up to half a second, growing with the library. So
/// the debounce is not polish — typing "paddington" undebounced is ten of them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibrarySearchField()),
        ),
      ),
    );
  }

  LibraryFilters filters() => container.read(libraryFiltersProvider);

  testWidgets('typing does not query on every letter', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'p');
    await tester.enterText(find.byType(TextField), 'pa');
    await tester.enterText(find.byType(TextField), 'pad');
    await tester.pump(const Duration(milliseconds: 100));

    expect(filters().searchTerm, isNull,
        reason: 'mid-typing, nothing has been asked of the server yet');

    await tester.pump(LibrarySearchField.debounce);

    expect(filters().searchTerm, 'pad',
        reason: 'and then exactly once, with the final text');
  });

  testWidgets('submitting skips the wait', (tester) async {
    // Waiting out a debounce after a deliberate Enter reads as being ignored.
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'bear');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(filters().searchTerm, 'bear');
  });

  testWidgets('clearing empties the filter rather than searching for nothing',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'bear');
    await tester.pump(LibrarySearchField.debounce);
    expect(filters().searchTerm, 'bear', reason: 'control');

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(filters().searchTerm, isNull);
    expect(filters().isEmpty, isTrue,
        reason: 'a cleared search leaves the grid unfiltered, not filtered by '
            'an empty string');
  });

  testWidgets('whitespace never becomes a filter', (tester) async {
    // The server answers a whitespace searchTerm with the entire library
    // (measured), so storing one would badge an unfiltered grid as filtered.
    await pump(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump(LibrarySearchField.debounce);

    expect(filters().searchTerm, isNull);
    expect(filters().activeCount, 0);
  });

  testWidgets('a pending debounce does not fire into a disposed widget',
      (tester) async {
    // The standing trap in this repo's widget tests, and a real crash on a fast
    // back-tap: type, leave immediately, and the timer lands on a ref that is
    // gone. The framework fails a test that ends with a timer pending, so this
    // also catches a cancel that was never wired.
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'bear');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
    await tester.pump(LibrarySearchField.debounce * 2);

    expect(filters().searchTerm, isNull,
        reason: 'the field is gone; its pending search went with it');
  });

  testWidgets('it shows the search already in the filter', (tester) async {
    // Scrolling the row or rebuilding must not silently empty a field whose
    // filter is still applied — the grid would stay narrowed with nothing on
    // screen saying why.
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(libraryFiltersProvider.notifier).setSearch('paddington');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibrarySearchField()),
        ),
      ),
    );

    expect(find.text('paddington'), findsOneWidget);
  });

  test('setting the same search again does not churn the grid', () {
    // A debounce can fire with text the filter already holds. Re-setting
    // identical state invalidates the library controller and re-fetches a page
    // for nothing — and #68 measured what a page costs.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(libraryFiltersProvider.notifier);

    notifier.setSearch('bear');
    final first = container.read(libraryFiltersProvider);
    notifier.setSearch('bear');
    notifier.setSearch('  bear  ');

    expect(identical(container.read(libraryFiltersProvider), first), isTrue,
        reason: 'same search, same object — nothing downstream rebuilds');
  });
}
