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
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/providers/settings_providers.dart';
import 'package:garfin/repositories/app_settings_store.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/screens/collection_screen.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:garfin/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The library grid's order is a setting, and both grids obey it.
///
/// **The keys are a measurement, not a preference.** Measured on 12.1 with a
/// film per case: a server with no metadata provider sets `ProductionYear` from
/// the file name and never sets `PremiereDate` at all — yet sorting by
/// `PremiereDate` still returned the grid in year order, and once a real
/// premiere date was written onto one film it sorted by that instead. So
/// release date is one key that is exact where a library has dates and falls
/// back to the year everywhere else. The negative had a positive control: a set
/// premiere date does come back, so "absent" was a reading rather than a field
/// nobody asked for.
///
/// Nothing here asserts the *resulting order*: that is the server's, and a fake
/// that sorted its own fixtures would only be testing itself. What the app is
/// responsible for is which key it asks for, on which screens, and what it does
/// to the open window when the answer changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  group('the key each choice sends', () {
    test('one key per choice, never a chain', () {
      expect(librarySortBy(LibrarySort.dateAdded), 'DateCreated');
      expect(librarySortBy(LibrarySort.releaseDate), 'PremiereDate');
      expect(librarySortBy(LibrarySort.name), 'SortName');

      // A chain is legal and is deliberately not used: `SortOrder` applies to
      // every key in it, so descending would reverse the name tiebreak too and
      // the undated titles would come back Z to A.
      for (final sort in LibrarySort.values) {
        expect(librarySortBy(sort), isNot(contains(',')));
      }
    });

    test('the direction is a single flag', () {
      expect(librarySortOrder(descending: false), 'Ascending');
      expect(librarySortOrder(descending: true), 'Descending');
    });
  });

  group('what the screens ask the server for', () {
    late FakeJellyfinServer server;
    setUp(() => server = FakeJellyfinServer());

    Map<String, dynamic> row(String id, String name, {String type = 'Movie'}) =>
        <String, dynamic>{
          'Id': id,
          'Name': name,
          'Type': type,
          'Tags': const <String>[],
        };

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required Widget home,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final store = await SharedPreferences.getInstance();

      server.fallback(json: <String, dynamic>{
        'TotalRecordCount': 2,
        'Items': [row('f1', 'Alpha'), row('f2', 'Bravo')],
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(store),
            deviceIdentityProvider.overrideWithValue(
              const DeviceIdentity(deviceId: 'd', deviceName: 't'),
            ),
            jellyfinApiFactoryProvider.overrideWithValue(
              JellyfinApiFactory(
                identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
                adapter: server,
              ),
            ),
            collectionIndexProvider(session)
                .overrideWith((ref) async => const CollectionIndex.empty()),
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
            home: home,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    }

    /// The sort parameters of the grid's own query — the one that pages,
    /// identified by `StartIndex`, so a collection's member query cannot be
    /// mistaken for it.
    List<(String?, String?)> gridSorts() => server.requests
        .where((r) =>
            r.path == '/Items' && r.queryParameters.containsKey('StartIndex'))
        .map((r) => (
              r.queryParameters['SortBy'] as String?,
              r.queryParameters['SortOrder'] as String?,
            ))
        .toList();

    testWidgets('the library grid, with nothing chosen', (tester) async {
      await pump(tester, home: const Scaffold(body: LibraryScreen(session: session)));

      expect(gridSorts().first, ('SortName', 'Ascending'),
          reason: 'the default is what the app did before the setting existed');
    });

    testWidgets('the library grid, sorted by date added, newest first',
        (tester) async {
      await pump(
        tester,
        home: const Scaffold(body: LibraryScreen(session: session)),
        prefs: <String, Object>{
          'looks_library_sort': 'dateAdded',
          'looks_library_sort_descending': true,
        },
      );

      expect(gridSorts().first, ('DateCreated', 'Descending'));
    });

    testWidgets('a collection browsed with the same setting', (tester) async {
      // Ruled: both tile screens follow it. Browsing a set is the library
      // narrowed to one container, so the tiles and their order are the same.
      await pump(
        tester,
        home: Scaffold(
          body: CollectionScreen(
            session: session,
            collection: LibraryItem(
              id: 'set-1',
              name: 'Bear Films',
              type: 'BoxSet',
              tags: const [],
            ),
          ),
        ),
        prefs: <String, Object>{'looks_library_sort': 'releaseDate'},
      );

      final members = server.requests.where(
        (r) => r.queryParameters['parentId'] == 'set-1',
      );
      expect(members, isNotEmpty, reason: 'the members were asked for at all');
      expect(members.last.queryParameters['SortBy'], 'PremiereDate');
      expect(members.last.queryParameters['SortOrder'], 'Ascending');
    });

    test('changing the order starts the grid at the top again', () async {
      // A window restored under a new order would hand back the first N of a
      // list whose start the parent has never seen. The window is only restored
      // for the *same* list, and the order is part of what makes a list the
      // same one.
      //
      // **The controller, not the screen.** A grid handed a library larger than
      // its window keeps asking for the next page as it scrolls, so a widget
      // test here would be measuring the scroll listener; `loadMore` is the
      // same call that listener makes.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      // Two full pages of *different* rows, so the window really grows: the
      // feed drops ids it already holds, and a fake that answers every page
      // with the same films would leave nothing to restore.
      const page = LibraryRepository.pageSize;
      server
        ..onQuery('/Items', (q) => '${q['StartIndex']}' == '0',
            json: <String, dynamic>{
              'TotalRecordCount': page * 2,
              'Items': [for (var i = 0; i < page; i++) row('f$i', 'Film $i')],
            })
        ..onQuery('/Items', (q) => '${q['StartIndex']}' == '$page',
            json: <String, dynamic>{
              'TotalRecordCount': page * 2,
              'Items': [
                for (var i = page; i < page * 2; i++) row('f$i', 'Film $i'),
              ],
            });

      final container = ProviderContainer(
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
          kidsOverviewProvider(session).overrideWith(
            (ref) async => const KidsOverview(
              shortlisted: <KidSummary>[],
              withoutShortlist: <UnshortlistedUser>[],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider(session).future);
      await container.read(libraryControllerProvider(session).notifier).loadMore();
      expect(gridSorts().length, 2,
          reason: 'two pages are open, so there is a window to lose');

      await container
          .read(settingsProvider.notifier)
          .setLibrarySort(LibrarySort.dateAdded);
      await container.read(libraryControllerProvider(session).future);

      // **One page, not two.** A refresh of the *same* list asks for as much as
      // was on screen, which here would be both pages; a new list asks for one.
      // That count is the assertion, because both paths begin at index 0 and
      // only the amount they ask for says which one ran.
      final reordered = server.requests
          .where((r) => r.queryParameters['SortBy'] == 'DateCreated')
          .toList();
      expect(reordered, hasLength(1),
          reason: 'a new order is a new list, and a new list starts at the top');
      expect(reordered.single.queryParameters['StartIndex'], 0);
    });

  });

  group('the Settings row', () {
    testWidgets('the arrow flips the direction and keeps it', (tester) async {
      // Ruled: the field is a row and the direction is a control on the same
      // line. The arrow is the one control on that screen whose meaning is a
      // shape, so what it says is asserted as well as what it does — a tooltip
      // is what a screen reader reads out.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SettingsScreen(session: session)),
          ),
        ),
      );
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // The looks group is below the fold on a test-sized window, and a lazy
      // list has not built what has not been reached.
      await tester.scrollUntilVisible(
        find.text(l10n.settingsLibrarySort),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsLibrarySort), findsOneWidget);
      expect(find.text(l10n.settingsLibrarySortName), findsOneWidget,
          reason: 'the row says what it is sorting by, not just that it does');

      await tester.tap(find.byTooltip(l10n.settingsLibrarySortAscending));
      await tester.pump();

      expect(
        AppSettingsStore(prefs).librarySortDescending,
        isTrue,
        reason: 'a direction that is not written is a direction lost on launch',
      );
      expect(find.byTooltip(l10n.settingsLibrarySortDescending), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });
  });
}
