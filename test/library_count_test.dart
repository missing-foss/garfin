// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_count.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The Library's result line (#81).
///
/// It claimed a total and counted the page buffer, so it climbed as the parent
/// scrolled; and with "Show shared" — the default — the set it counted included
/// the titles the child already had. Two defects in one expression, and both
/// are pinned here against the **requests**, because the number on screen is
/// only right if the two queries behind it describe the same population.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  JellyfinUser user({
    String name = 'Emma',
    List<String> allowed = const ['kids-emma'],
    List<String> blocked = const [],
    int? cap,
  }) =>
      JellyfinUser(
        id: 'id-$name',
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: allowed,
          blockedTags: blocked,
          maxParentalRating: cap,
        ),
      );

  group('the arithmetic, and the verb it belongs to', () {
    test('an allow-list child: what has not been handed over', () {
      final count =
          libraryCountFor(total: 400, tagged: 24, child: user());

      expect(count.kind, LibraryCountKind.notYetGiven);
      expect(count.count, 376);
    });

    test('a block-list child inverts it: the tagged ones are the withheld ones',
        () {
      // Ground rule 3. The same query, the opposite verb — and `400 - 24`
      // would be the number of titles they *can* reach, which is not what the
      // line is for and is a visibility claim besides.
      final count = libraryCountFor(
        total: 400,
        tagged: 24,
        child: user(name: 'Sam', allowed: const [], blocked: const ['no-horror']),
      );

      expect(count.kind, LibraryCountKind.withheld);
      expect(count.count, 24);
    });

    test('a conflicting account gets no number about them at all', () {
      final count = libraryCountFor(
        total: 400,
        tagged: 24,
        child: user(allowed: const ['kids-emma'], blocked: const ['no-horror']),
      );

      expect(count.kind, LibraryCountKind.everything);
      expect(count.count, 400);
    });

    test('no child selected is the library, not a zero', () {
      final count = libraryCountFor(total: 400, tagged: 0, child: null);

      expect(count.kind, LibraryCountKind.everything);
      expect(count.count, 400);
    });

    test('it never goes negative between two requests', () {
      // Two counts are two round trips, so a library that gained a tag in
      // between can answer with more tagged than total. "-3 things Emma hasn't
      // got yet" is a bug report; 0 is what the grid will look like anyway.
      final count = libraryCountFor(total: 10, tagged: 12, child: user());

      expect(count.count, 0);
    });
  });

  group('the two queries describe the same population', () {
    late FakeJellyfinServer server;

    setUp(() => server = FakeJellyfinServer());

    Future<ProviderContainer> build({
      required JellyfinUser child,
      LibraryFilters filters = const LibraryFilters(),
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      server.fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});

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
        kidsOverviewProvider(session).overrideWith(
          (ref) async => KidsOverview(
            shortlisted: [
              KidSummary(user: child),
            ],
            withoutShortlist: const [],
          ),
        ),
      ]);
      await container.read(kidsOverviewProvider(session).future);
      container.read(pickingForProvider.notifier).select(child.id);
      container.read(libraryFiltersProvider.notifier).set(filters);
      return container;
    }

    /// The `Limit=0` count query, which is the only one carrying `tags`.
    Map<String, dynamic> countQuery() => server.requests
        .lastWhere((r) => r.queryParameters.containsKey('tags'))
        .queryParameters;

    test('several labels go out as one OR, not one request each', () async {
      // Measured (`JELLYFIN-API.md` § `tags=` takes `|`): `tags=a|b` is an OR
      // and a comma makes the whole string one tag name, answering 0. Two
      // requests summed would also double-count an item carrying both.
      final container = await build(
        child: user(allowed: const ['kids-emma', 'family-films']),
      );
      addTearDown(container.dispose);

      await container.read(taggedItemCountProvider(session).future);

      expect(countQuery()['tags'], 'kids-emma|family-films');
      expect(
        server.requests.where((r) => r.queryParameters.containsKey('tags')),
        hasLength(1),
      );
    });

    test('every filter the grid carries, the count carries too', () async {
      final container = await build(
        child: user(cap: 8),
        filters: const LibraryFilters(
          type: 'Movie',
          genre: 'Family',
          decade: 1990,
          searchTerm: 'bear',
          withinCap: true,
        ),
      );
      addTearDown(container.dispose);

      final sub =
          container.listen(libraryControllerProvider(session), (_, _) {});
      addTearDown(sub.close);
      await container.read(libraryControllerProvider(session).future);
      await container.read(taggedItemCountProvider(session).future);
      final query = countQuery();

      expect(query['IncludeItemTypes'], 'Movie');
      expect(query['genres'], 'Family');
      expect(query['years'], startsWith('1990,1991'));
      expect(query['searchTerm'], 'bear');
      expect(query['maxOfficialRating'], 8);
      // The denominator side of the same subtraction, so the populations
      // match. Anything present on one and absent on the other subtracts one
      // set from a different one and answers with a plausible wrong number.
      final page = server.requests
          .firstWhere((r) => r.queryParameters.containsKey('StartIndex'))
          .queryParameters;
      expect(page['IncludeItemTypes'], query['IncludeItemTypes']);
      expect(page['genres'], query['genres']);
      expect(page['years'], query['years']);
      expect(page['searchTerm'], query['searchTerm']);
      expect(page['maxOfficialRating'], query['maxOfficialRating']);
    });

    test('the cap rides along only when the cap chip is on', () async {
      // `maxOfficialRating` is the chip, not the child's policy applied
      // silently — `libraryPage` treats it the same way, and the two must
      // agree or the subtraction mixes populations again.
      final container = await build(child: user(cap: 8));
      addTearDown(container.dispose);

      await container.read(taggedItemCountProvider(session).future);

      expect(countQuery().containsKey('maxOfficialRating'), isFalse);
    });

    test('a changed search re-runs the count, not just the grid', () async {
      // Only checkable since #90: `LibraryFilters.==` omitted `searchTerm`, so
      // nothing keyed on the filters was notified when it changed. The count
      // is keyed on exactly that object, and a count left over from the
      // unfiltered library would be subtracted from a searched total — a
      // number wrong in the direction that looks plausible.
      final container = await build(child: user());
      addTearDown(container.dispose);
      await container.read(taggedItemCountProvider(session).future);
      final before = server.requests.length;

      container.read(libraryFiltersProvider.notifier).setSearch('paddington');
      await container.read(taggedItemCountProvider(session).future);

      final after = server.requests
          .skip(before)
          .where((r) => r.queryParameters.containsKey('tags'))
          .toList();
      expect(after, isNotEmpty, reason: 'the count ignored the new search');
      expect(after.last.queryParameters['searchTerm'], 'paddington');
    });

    test('a conflicting account is never asked about', () async {
      // `shortlistTags` is empty for it, and `tags=` with nothing would count
      // the whole library — a number that would then be subtracted from
      // itself and read as "nothing left to give".
      final container = await build(
        child: user(allowed: const ['kids-emma'], blocked: const ['no-horror']),
      );
      addTearDown(container.dispose);

      expect(await container.read(taggedItemCountProvider(session).future), 0);
      expect(
        server.requests.where((r) => r.queryParameters.containsKey('tags')),
        isEmpty,
      );
    });
  });

  group('on screen, where both defects were visible', () {
    late FakeJellyfinServer server;

    setUp(() => server = FakeJellyfinServer());

    Map<String, dynamic> item(int i, {List<String> tags = const []}) =>
        <String, dynamic>{
          'Id': 'item-$i',
          'Name': 'Item $i',
          'Type': 'Movie',
          'Tags': tags,
        };

    Future<void> pumpScreen(
      WidgetTester tester, {
      required JellyfinUser child,
      required int total,
      required int tagged,
      required List<Map<String, dynamic>> page,
      String? search,
      SearchScope scope = SearchScope.title,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      // **Scripted in the order the screen asks, and the last entry is
      // sticky.** `FakeJellyfinServer` consumes queued replies in order but
      // keeps the last one for every later request to that path — so a single
      // `/Items` entry would answer the grid's page *and* the `Limit=0` count
      // with the same total, and `total - tagged` would be 0 no matter what
      // the code did. That is a harness answering confidently and wrongly,
      // which `JELLYFIN-API.md` names as the species to watch for.
      //
      // The order is: the grid's page; then, for an allow-list child with
      // labelled items on it, the visibility lookup `_classify` makes; then
      // the count, which stays as the answer.
      final labelled = page
          .where((i) => (i['Tags']! as List)
              .any((t) => child.policy.shortlistTags.contains(t)))
          .toList();
      server.on('/Items', json: {'Items': page, 'TotalRecordCount': total});
      if (child.policy.shortlistMode == ShortlistMode.allow &&
          labelled.isNotEmpty) {
        server.on('/Items', json: {
          'Items': [
            for (final i in labelled) <String, dynamic>{'Id': i['Id']},
          ],
          'TotalRecordCount': labelled.length,
        });
      }
      server.on('/Items', json: {'Items': <Object>[], 'TotalRecordCount': tagged});

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
        kidsOverviewProvider(session).overrideWith(
          (ref) async => KidsOverview(
            shortlisted: [
              KidSummary(user: child),
            ],
            withoutShortlist: const [],
          ),
        ),
        parentalRatingLadderProvider(session)
            .overrideWith((ref) async => const ParentalRatingLadder.empty()),
        // A search reads the collection index to add the sets its films are
        // in. Stubbed empty so it takes none of the scripted `/Items` replies
        // above, whose order is the whole point of this harness.
        if (search != null)
          collectionIndexProvider(session)
              .overrideWith((ref) async => const CollectionIndex.empty()),
      ]);
      addTearDown(container.dispose);
      if (scope != SearchScope.title) {
        // Resolves, so the query carries `person=` and the grid is drawn.
        // A resolve that found nothing would empty the grid and take the
        // line with it, and a test asserting "no relevance" would then pass
        // on a screen with no line at all.
        server.on('/Search/Hints', json: {
          'SearchHints': [
            {'Name': 'Audrey Tautou', 'Type': 'Person'},
          ],
        });
        container.read(libraryFiltersProvider.notifier).setScope(scope);
      }
      if (search != null) {
        container.read(libraryFiltersProvider.notifier).setSearch(search);
      }
      await container.read(kidsOverviewProvider(session).future);
      container.read(pickingForProvider.notifier).select(child.id);
      // Show shared: the default, and the configuration the second defect
      // lived in — the grid then holds titles the child already has.
      // This test is not about which slice is shown; show all of it.
      container.read(libraryViewProvider.notifier).set(LibraryView.all);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: LibraryScreen(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the number is the library\'s, not the page buffer\'s',
        (tester) async {
      // The original defect: a page of tiles loaded out of 400, and the line
      // said how many *tiles* — a number that grew as you scrolled.
      //
      // The fixture is one whole page, not a short one: `fetch` keeps asking
      // until it has a page, so a short first answer sends it back for another
      // and it consumes the next scripted reply — which is the count's, and
      // the harness then answers the grid with it.
      const buffer = LibraryRepository.pageSize;
      await pumpScreen(
        tester,
        child: user(),
        total: 400,
        tagged: 24,
        page: [for (var i = 0; i < buffer; i++) item(i)],
      );

      expect(find.text("376 things Emma hasn't got yet"), findsOneWidget);
      expect(find.text("\$buffer things Emma hasn't got yet"), findsNothing);
    });

    testWidgets('it counts what is outstanding, not what is on the grid',
        (tester) async {
      // The second defect, and the one that was wrong regardless of
      // scrolling: with Show shared on, the grid holds titles the child
      // already has, and the line still said "hasn't got yet".
      await pumpScreen(
        tester,
        child: user(),
        total: 10,
        tagged: 10,
        page: [
          for (var i = 0; i < 10; i++) item(i, tags: const ['kids-emma']),
        ],
      );

      // Ten tiles on screen, every one of them already given.
      expect(find.text("0 things Emma hasn't got yet"), findsOneWidget);
      expect(find.text("10 things Emma hasn't got yet"), findsNothing);
    });

    testWidgets('a block-list child reads the other way round', (tester) async {
      await pumpScreen(
        tester,
        child: user(
            name: 'Sam', allowed: const [], blocked: const ['no-horror']),
        total: 400,
        tagged: 7,
        page: [for (var i = 0; i < LibraryRepository.pageSize; i++) item(i)],
      );

      expect(find.text('7 things kept from Sam'), findsOneWidget);
    });

    testWidgets('a conflicting account gets the library\'s own count',
        (tester) async {
      await pumpScreen(
        tester,
        child: user(
            allowed: const ['kids-emma'], blocked: const ['no-horror']),
        total: 400,
        tagged: 0,
        page: [for (var i = 0; i < LibraryRepository.pageSize; i++) item(i)],
      );

      expect(find.text('400 things'), findsOneWidget);
      expect(find.textContaining("hasn't got yet"), findsNothing);
    });

    // Ruled on the search issue, option A. The server orders a search by its
    // own relevance and ignores `SortBy`, measured on stock 10.11.11 and
    // 12.1.0, so the sort chosen in Settings does nothing while one is active.
    testWidgets('while a search is active the line says it is sorted by '
        'relevance', (tester) async {
      await pumpScreen(
        tester,
        child: user(
            name: 'Sam', allowed: const [], blocked: const ['no-horror']),
        total: 400,
        tagged: 7,
        page: [for (var i = 0; i < LibraryRepository.pageSize; i++) item(i)],
        search: 'paddington',
      );

      expect(find.text('7 things kept from Sam · sorted by relevance'),
          findsOneWidget);
    });

    testWidgets('a cast & crew search does not claim it: it sends person=, '
        'not searchTerm, and the sort was never measured there', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        child: user(
            name: 'Sam', allowed: const [], blocked: const ['no-horror']),
        total: 400,
        tagged: 7,
        page: [for (var i = 0; i < LibraryRepository.pageSize; i++) item(i)],
        search: 'tautou',
        scope: SearchScope.castAndCrew,
      );

      expect(
        server.requests.any((r) => r.queryParameters['person'] == 'Audrey Tautou'),
        isTrue,
        reason: 'the control: the resolve happened and the filter went out',
      );
      expect(find.text('7 things kept from Sam'), findsOneWidget);
      expect(find.textContaining('relevance'), findsNothing);
    });

    testWidgets('and without one it does not', (tester) async {
      // The control for the case above: the same screen, no search. Without
      // it, a suffix added unconditionally would pass the first test.
      await pumpScreen(
        tester,
        child: user(
            name: 'Sam', allowed: const [], blocked: const ['no-horror']),
        total: 400,
        tagged: 7,
        page: [for (var i = 0; i < LibraryRepository.pageSize; i++) item(i)],
      );

      expect(find.text('7 things kept from Sam'), findsOneWidget);
      expect(find.textContaining('relevance'), findsNothing);
    });
  });
}
