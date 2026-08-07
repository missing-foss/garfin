// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/widgets/library_search_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

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

  testWidgets('the debounce timer does not outlive the field', (tester) async {
    // **This test ends deliberately early.** The obvious version — dispose the
    // field, pump past the debounce, assert nothing was set — was *vacuous*:
    // the `mounted` guard inside the callback makes it pass whether or not the
    // timer was cancelled, which the mutation run duly reported.
    //
    // What the cancel is actually for is not leaving a live timer behind on a
    // fast back-tap. So: type, leave, and stop — with no pump long enough for
    // it to fire. `flutter_test` fails a test that ends with a timer pending,
    // and that failure is the assertion.
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'bear');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
  });

  testWidgets('and the callback checks mounted as well', (tester) async {
    // The second line of defence, kept because it is cheap and because the
    // first one is easy to delete by accident: even if a timer did survive,
    // firing it must not write into a ref that is gone.
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

  group('the search reaches the server (#73 never did)', () {
    // Every test above this one asserts on `libraryFiltersProvider`'s own
    // state, and every one of them passed while the feature did nothing: the
    // filter was set correctly and the grid never asked. `LibraryFilters.==`
    // omitted `searchTerm`, so Riverpod compared old state to new, found them
    // equal, and notified nobody.
    //
    // The lesson is the one `CLAUDE.md` § Conventions already states — check
    // the artifact, not the action. The artifact here is a request.

    const session = AuthSession(
      serverUrl: 'http://host:8096',
      accessToken: 'token',
      userId: 'admin-1',
      userName: 'Parent',
    );

    Future<(ProviderContainer, FakeJellyfinServer)> build() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final server = FakeJellyfinServer()
        ..fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(
          const DeviceIdentity(deviceId: 'd', deviceName: 't'),
        ),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(
            identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
            adapter: server,
          ),
        ),
      ]);
      return (container, server);
    }

    test('a search the parent typed is a search the server is asked for',
        () async {
      final (container, server) = await build();
      addTearDown(container.dispose);
      // Listened to, as the screen does: an unwatched provider is disposed
      // between reads and would re-fetch for reasons that have nothing to do
      // with the filter.
      final sub = container.listen(libraryControllerProvider(session), (_, _) {});
      addTearDown(sub.close);
      await container.read(libraryControllerProvider(session).future);
      final before = server.requests.length;

      container.read(libraryFiltersProvider.notifier).setSearch('paddington');
      await container.read(libraryControllerProvider(session).future);

      final searched = server.requests
          .skip(before)
          .where((r) => r.queryParameters['searchTerm'] == 'paddington');
      expect(searched, isNotEmpty,
          reason: 'the grid never asked the server for the search');
    });

    test('and changing it asks again, rather than keeping the first answer',
        () async {
      // The second half, and the one a hashCode-only fix would miss: 'bear'
      // and 'paddington' are both non-null searches, so an `==` that merely
      // knew "there is a search" would stop here.
      final (container, server) = await build();
      addTearDown(container.dispose);
      final sub = container.listen(libraryControllerProvider(session), (_, _) {});
      addTearDown(sub.close);
      container.read(libraryFiltersProvider.notifier).setSearch('paddington');
      await container.read(libraryControllerProvider(session).future);
      final before = server.requests.length;

      container.read(libraryFiltersProvider.notifier).setSearch('bear');
      await container.read(libraryControllerProvider(session).future);

      expect(
        server.requests
            .skip(before)
            .where((r) => r.queryParameters['searchTerm'] == 'bear'),
        isNotEmpty,
      );
    });

    test('clearing it asks for the unfiltered library again', () async {
      final (container, server) = await build();
      addTearDown(container.dispose);
      final sub = container.listen(libraryControllerProvider(session), (_, _) {});
      addTearDown(sub.close);
      container.read(libraryFiltersProvider.notifier).setSearch('paddington');
      await container.read(libraryControllerProvider(session).future);
      final before = server.requests.length;

      container.read(libraryFiltersProvider.notifier).setSearch('');
      await container.read(libraryControllerProvider(session).future);

      // Pinned to being a *library page* request, not merely "something
      // happened": the assertion below is a negative one, and a negative that
      // can pass because nothing was asked is the failure this whole PR is
      // about. `StartIndex` is on the grid's query and on nothing else.
      final after = server.requests
          .skip(before)
          .where((r) => r.queryParameters.containsKey('StartIndex'))
          .toList();
      expect(after, isNotEmpty, reason: 'clearing the search changed nothing');
      expect(
        after.where((r) => r.queryParameters.containsKey('searchTerm')),
        isEmpty,
        reason: 'an empty search must be absent, not sent blank',
      );
    });

    test('two filters differing only by their search are not equal', () {
      // The unit-level statement of the same fact. Kept alongside the
      // behavioural tests rather than instead of them: this one would have
      // been written to match the broken behaviour just as easily.
      expect(
        const LibraryFilters(searchTerm: 'paddington'),
        isNot(const LibraryFilters(searchTerm: 'bear')),
      );
      expect(
        const LibraryFilters(searchTerm: 'bear'),
        isNot(const LibraryFilters()),
      );
      expect(
        const LibraryFilters(searchTerm: 'bear').hashCode,
        isNot(const LibraryFilters().hashCode),
      );
    });
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
