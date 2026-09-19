// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The collapse as the screen actually runs it (#144).
///
/// **The rule has to be asserted through the screen, not through a copy of it.**
/// The first version of this pinned a local reimplementation of the predicate,
/// and review measured the consequence: deleting the collapse from
/// `library_screen.dart` left all 790 tests green.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  late FakeJellyfinServer server;
  setUp(() => server = FakeJellyfinServer());

  LibraryItem film(String id, String name) =>
      LibraryItem(id: id, name: name, type: 'Movie', tags: const []);

  /// The grid holds a set and two films, one of which the set contains.
  /// What the server returns. Defaults to the whole grid; a search fixture
  /// passes the rows a real `searchTerm` would match.
  ///
  /// **Which may include the set.** `searchTerm` matches any substring of an
  /// item's own title, so *Paddington* matches *Paddington Collection* as well
  /// as the film. What the server cannot do is find a set through a member
  /// whose title it does not share — *Bear Films* holding *Paddington* — and
  /// that is the case #147 exists for. Both are fixtures here: a term matching
  /// only the film, and a term matching both.
  Future<void> pumpScreen(
    WidgetTester tester, {
    required CollectionIndex index,
    LibraryFilters filters = const LibraryFilters(),
    List<Map<String, dynamic>>? items,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final rows = items ??
        [
          <String, dynamic>{
            'Id': 'set-1',
            'Name': 'Paddington Collection',
            'Type': 'BoxSet',
            'ChildCount': 1,
          },
          <String, dynamic>{'Id': 'f1', 'Name': 'Paddington', 'Type': 'Movie'},
          <String, dynamic>{
            'Id': 'f2',
            'Name': 'Something Else',
            'Type': 'Movie',
          },
        ];
    server.fallback(json: <String, dynamic>{
      'TotalRecordCount': rows.length,
      'Items': rows,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          collectionIndexProvider(session).overrideWith((ref) async => index),
          kidsOverviewProvider(session).overrideWith(
            (ref) async => const KidsOverview(
              shortlisted: <KidSummary>[],
              withoutShortlist: <UnshortlistedUser>[],
            ),
          ),
          parentalRatingLadderProvider(session)
              .overrideWith((ref) async => const ParentalRatingLadder.empty()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    // The filter is set after the first frame, the way a parent sets one.
    if (!filters.isEmpty) {
      final element = tester.element(find.byType(LibraryScreen));
      ProviderScope.containerOf(element)
          .read(libraryFiltersProvider.notifier)
          .set(filters);
    }
    await tester.pumpAndSettle();
  }

  CollectionIndex indexHolding(String memberId) => CollectionIndex([
        CollectionSet(
          collection: LibraryItem(
            id: 'set-1',
            name: 'Paddington Collection',
            type: 'BoxSet',
            tags: const [],
          ),
          members: [film(memberId, 'Paddington')],
        ),
      ]);

  testWidgets('a member is not drawn; the set that holds it is', (tester) async {
    await pumpScreen(tester, index: indexHolding('f1'));

    expect(find.text('Paddington Collection'), findsOneWidget);
    expect(find.text('Paddington'), findsNothing,
        reason: 'the set stands in for it');
    expect(find.text('Something Else'), findsOneWidget,
        reason: 'a film in no set is untouched');
  });

  testWidgets('with no collections, every film is its own row', (tester) async {
    await pumpScreen(tester, index: const CollectionIndex.empty());

    expect(find.text('Paddington'), findsOneWidget);
    expect(find.text('Something Else'), findsOneWidget);
  });

  testWidgets('a search does not hide a film behind a set that is not there',
      (tester) async {
    // The hazard review named: `searchTerm` matches a film's title and not the
    // set's name, so the server would not return the set — and hiding the film
    // would leave the grid with nothing for a title that exists.
    await pumpScreen(
      tester,
      index: indexHolding('f1'),
      filters: const LibraryFilters(searchTerm: 'padding'),
    );

    expect(find.text('Paddington'), findsOneWidget,
        reason: 'nothing may be collapsed while a filter narrows the grid');
  });

  testWidgets('a search finds the set through the film inside it (#147)',
      (tester) async {
    // `searchTerm` matches an item's own title, so the server never returns
    // the set. The app adds it, first, and says why.
    await pumpScreen(
      tester,
      index: indexHolding('f1'),
      filters: const LibraryFilters(searchTerm: 'padding'),
      items: [
        <String, dynamic>{'Id': 'f1', 'Name': 'Paddington', 'Type': 'Movie'},
      ],
    );

    expect(find.text('Paddington'), findsOneWidget,
        reason: 'nothing the parent typed is taken away');
    expect(find.text('Paddington Collection'), findsOneWidget,
        reason: 'the set that holds it is added');

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.librarySearchInCollection), findsOneWidget,
        reason: 'a row nobody searched for has to explain itself');
  });

  testWidgets('the set is the first result', (tester) async {
    await pumpScreen(
      tester,
      index: indexHolding('f1'),
      filters: const LibraryFilters(searchTerm: 'padding'),
      items: [
        <String, dynamic>{'Id': 'f1', 'Name': 'Paddington', 'Type': 'Movie'},
      ],
    );

    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'Paddington Collection' || d == 'Paddington')
        .toList();

    expect(titles.first, 'Paddington Collection',
        reason: 'ruled: the set is always the first result');
  });

  testWidgets('no set is added when the search matches nothing in one',
      (tester) async {
    await pumpScreen(
      tester,
      index: const CollectionIndex.empty(),
      filters: const LibraryFilters(searchTerm: 'padding'),
      items: [
        <String, dynamic>{'Id': 'f1', 'Name': 'Paddington', 'Type': 'Movie'},
      ],
    );

    expect(find.text('Paddington Collection'), findsNothing);
  });

  testWidgets('a set the server already returned is not added twice',
      (tester) async {
    // *Paddington* matches *Paddington Collection* too, so the server returns
    // both rows. Without the guard against what is already on the grid, the
    // parent sees the same collection twice in one result.
    await pumpScreen(
      tester,
      index: indexHolding('f1'),
      filters: const LibraryFilters(searchTerm: 'Paddington'),
      items: [
        <String, dynamic>{
          'Id': 'set-1',
          'Name': 'Paddington Collection',
          'Type': 'BoxSet',
          'ChildCount': 1,
        },
        <String, dynamic>{'Id': 'f1', 'Name': 'Paddington', 'Type': 'Movie'},
      ],
    );

    expect(find.text('Paddington Collection'), findsOneWidget,
        reason: 'once, whether the server returned it or the app added it');
    expect(find.text('Paddington'), findsOneWidget);
  });

  testWidgets('a type filter also switches the collapse off', (tester) async {
    await pumpScreen(
      tester,
      index: indexHolding('f1'),
      filters: const LibraryFilters(type: 'Movie'),
    );

    expect(find.text('Paddington'), findsOneWidget);
  });
}
