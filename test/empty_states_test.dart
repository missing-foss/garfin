// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
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
import 'package:garfin/repositories/jellyfin_exception.dart';
import 'package:garfin/screens/collection_screen.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/roster_from_overview.dart';
import 'support/fake_jellyfin_server.dart';

/// What an empty or failed screen says, and whether it offers a way out.
///
/// **The reported failures.** A search that matched nothing read "Nothing here
/// yet", and with a child in the giving view "{name} has everything already" —
/// true of the filtered slice, false of the child. The collection screen's
/// error had no retry. The repair button spun and did nothing on a failure. And
/// the Kids screen's help link ignored a failed launch that About reports.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );
  const identity = DeviceIdentity(deviceId: 'd', deviceName: 't');
  const serverError = 'The server ran into a problem. Try again in a moment.';

  final emma = KidSummary(
    user: const JellyfinUser(
      id: 'emma',
      name: 'Emma',
      policy: UserPolicy(
        isAdministrator: false,
        isDisabled: false,
        allowedTags: ['kids-emma'],
      ),
    ),
  );

  late FakeJellyfinServer server;
  setUp(() => server = FakeJellyfinServer());

  Future<ProviderContainer> container({
    List<KidSummary> kids = const [],
    List<UnshortlistedUser> unmanaged = const [],
    List<Override> extra = const [],
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: server),
        ),
        rosterFromOverview(session),
        kidsOverviewProvider(session).overrideWith(
          (ref) async => KidsOverview(
            shortlisted: kids,
            withoutShortlist: unmanaged,
          ),
        ),
        parentalRatingLadderProvider(session)
            .overrideWith((ref) async => const ParentalRatingLadder.empty()),
        collectionIndexProvider(session)
            .overrideWith((ref) async => const CollectionIndex.empty()),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    await c.read(kidsOverviewProvider(session).future);
    return c;
  }

  Future<void> show(WidgetTester tester, ProviderContainer c, Widget body) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: body),
        ),
      ),
    );
    await settle(tester);
  }

  group('an empty grid', () {
    testWidgets('a search that matched nothing says so, with the search',
        (tester) async {
      server.fallback(json: <String, dynamic>{'Items': <Object>[], 'TotalRecordCount': 0});
      final c = await container();
      c.read(libraryFiltersProvider.notifier)
          .set(const LibraryFilters(searchTerm: 'zzz'));

      await show(tester, c, const LibraryScreen(session: session));

      expect(find.text('Nothing here matches “zzz”.'), findsOneWidget);
      expect(find.text('Nothing here yet.'), findsNothing);
    });

    testWidgets('a filter in the giving view is not "has everything"',
        (tester) async {
      // Two Comedies, both already Emma's: the giving view drops them, and
      // the slice is empty with a total of two.
      final given = [
        for (final id in ['f1', 'f2'])
          <String, dynamic>{
            'Id': id,
            'Name': id,
            'Type': 'Movie',
            'Tags': ['kids-emma'],
          },
      ];
      server.fallback(json: <String, dynamic>{'Items': given, 'TotalRecordCount': 2});
      final c = await container(kids: [emma]);
      c.read(pickingForProvider.notifier).select('emma');
      c.read(libraryViewProvider.notifier).set(LibraryView.toGive);
      c.read(libraryFiltersProvider.notifier)
          .set(const LibraryFilters(genre: 'Comedy'));

      await show(tester, c, const LibraryScreen(session: session));

      expect(find.text('Nothing here matches these filters.'), findsOneWidget);
      expect(find.text('Emma has everything already.'), findsNothing,
          reason: 'true of the Comedies, not of Emma');
    });
  });

  testWidgets('a rating filter on a child with no cap is not a filter',
      (tester) async {
    // What a face tap leaves on for every child, capped or not. For Emma, who
    // has no cap, it narrows nothing, so everything given is still "has
    // everything", not "matches nothing".
    final given = [
      <String, dynamic>{
        'Id': 'f1',
        'Name': 'f1',
        'Type': 'Movie',
        'Tags': ['kids-emma'],
      },
    ];
    server.fallback(json: <String, dynamic>{'Items': given, 'TotalRecordCount': 1});
    final c = await container(kids: [emma]);
    c.read(pickingForProvider.notifier).select('emma');
    c.read(libraryViewProvider.notifier).set(LibraryView.toGive);
    c.read(libraryFiltersProvider.notifier)
        .set(const LibraryFilters(withinCap: true));

    await show(tester, c, const LibraryScreen(session: session));

    expect(find.text('Emma has everything already.'), findsOneWidget);
    expect(find.text('Nothing here matches these filters.'), findsNothing);
  });

  const boxSet = LibraryItem(
    id: 'set-1',
    name: 'Paddington Collection',
    type: 'BoxSet',
    tags: <String>[],
  );

  testWidgets("a collection that failed to load can be tried again",
      (tester) async {
    var reads = 0;
    final c = await container(extra: [
      collectionSetProvider(
        const CollectionRequest(session: session, collection: boxSet),
      ).overrideWith((ref) async {
        reads++;
        if (reads == 1) {
          throw const JellyfinException(JellyfinErrorKind.unreachable);
        }
        return const CollectionSet(collection: boxSet, members: []);
      }),
    ]);
    server.fallback(json: <String, dynamic>{'Items': <Object>[], 'TotalRecordCount': 0});

    await show(
      tester,
      c,
      const CollectionScreen(session: session, collection: boxSet),
    );
    expect(reads, 1);

    await tester.tap(find.text('Try again'));
    await settle(tester);

    expect(reads, 2, reason: 'the set is read again, not its cached failure');
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a repair that failed says so', (tester) async {
    // Both films given to Emma, the container not: the set is shut, and the
    // repair is offered.
    final films = [
      for (final id in ['f1', 'f2'])
        LibraryItem(id: id, name: id, type: 'Movie', tags: const ['kids-emma']),
    ];
    final c = await container(kids: [emma], extra: [
      collectionSetProvider(
        const CollectionRequest(session: session, collection: boxSet),
      ).overrideWith(
        (ref) async => CollectionSet(collection: boxSet, members: films),
      ),
    ]);
    c.read(pickingForProvider.notifier).select('emma');
    server
      ..fallback(json: <String, dynamic>{'Items': <Object>[], 'TotalRecordCount': 0})
      // The repair's write reads the container first, and that read fails.
      ..onQuery('/Users/admin-1/Items/set-1', (_) => true, status: 500);

    await show(
      tester,
      c,
      const CollectionScreen(session: session, collection: boxSet),
    );
    await tester.tap(find.text('Show them the collection'));
    await settle(tester);

    expect(find.text(serverError), findsOneWidget);
  });

  testWidgets("the Kids help link says so when it cannot open", (tester) async {
    // Accounts, none of them managed: the first-run welcome with its link.
    // The test binding has no URL launcher, so the launch fails as an
    // unhandled one would on a phone with nothing to open it.
    final c = await container(unmanaged: const [
      UnshortlistedUser(
        user: JellyfinUser(
          id: 'adult',
          name: 'Alex',
          policy: UserPolicy(isAdministrator: false, isDisabled: false),
        ),
        avatarUrl: null,
      ),
    ]);
    await show(tester, c, const KidsScreen(session: session));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.kidsWelcomeNoneLink));
    await settle(tester);

    expect(find.text("Couldn't open that link."), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}

/// Lets the fake server's replies land: a request started by the UI needs
/// both the fake clock and `runAsync`.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
