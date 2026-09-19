// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/collection_screen.dart';
import 'package:garfin/widgets/picking_for_avatar.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Opening a collection shows what is in it, and asks nothing (#83).
///
/// The assertion that matters is the **negative** one: tapping a box set used
/// to open the assign sheet for the whole set, whose Apply writes to every
/// member and to the container. A parent tapping a set is looking. So these
/// pin the artifact a tap produces — the screen that appeared, the request that
/// went out — rather than any state it passed through on the way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  final emma = KidSummary(
    user: JellyfinUser(
      id: 'kid-emma',
      name: 'Emma',
      policy: const UserPolicy(
        isAdministrator: false,
        isDisabled: false,
        allowedTags: ['kids-emma'],
        blockedTags: [],
      ),
    ),
  );

  late FakeJellyfinServer server;

  setUp(() => server = FakeJellyfinServer());

  Map<String, dynamic> item(
    String id,
    String name, {
    String type = 'Movie',
    int? childCount,
    int? recursiveItemCount,
    List<String> tags = const [],
  }) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'Type': type,
        'Tags': tags,
        'ChildCount': ?childCount,
        'RecursiveItemCount': ?recursiveItemCount,
      };

  Future<void> pumpLibrary(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    // The set's membership, keyed on `parentId` so it cannot be handed the
    // grid's page by accident — the trap the fake server's own doc warns about.
    server.onQuery(
      '/Items',
      (q) => q['parentId'] == 'coll-1',
      json: <String, dynamic>{
        'TotalRecordCount': 2,
        'Items': [
          item('film-1', 'Paddington'),
          item('film-2', 'Paddington 2'),
        ],
      },
    );

    server.fallback(json: <String, dynamic>{
      'TotalRecordCount': 1,
      'Items': [item('coll-1', 'The Paddington Collection',
          type: 'BoxSet', childCount: 2)],
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
          kidsOverviewProvider(session).overrideWith(
            (ref) async => KidsOverview(
              shortlisted: [emma],
              withoutShortlist: const <UnshortlistedUser>[],
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
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a collection opens it instead of the assign sheet',
      (tester) async {
    await pumpLibrary(tester);
    expect(find.text('The Paddington Collection'), findsOneWidget);

    await tester.tap(find.text('The Paddington Collection'));
    await tester.pumpAndSettle();

    // The artifact: the set's own screen, with its members on it.
    expect(find.byType(CollectionScreen), findsOneWidget);
    expect(find.text('Paddington 2'), findsOneWidget);

    // And the thing that must NOT have happened. `assignTitle` is the sheet's
    // heading; before #83 this tap produced it, over a set of two.
    expect(find.text('Who gets this?'), findsNothing);
  });

  testWidgets('the members come from the set, not the grid page',
      (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('The Paddington Collection'));
    await tester.pumpAndSettle();

    // A positive control on the harness itself: the request went out with the
    // container's id, so an empty member grid would mean something.
    expect(
      server.requests.any((r) => r.queryParameters['parentId'] == 'coll-1'),
      isTrue,
    );
    expect(find.text('Paddington'), findsOneWidget);
    expect(find.text('2 titles in this collection'), findsOneWidget);
  });

  testWidgets('handing the whole set over is a button, not the tap',
      (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('The Paddington Collection'));
    await tester.pumpAndSettle();

    // Enabled with nobody picked (#154), which is how a parent arrives from
    // the grid. The sheet builds its rows from the shortlist and never reads
    // the selection — the same sheet opens from a film on the grid with
    // Everyone showing — so a gate here only produced a dead control.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
      reason: 'the question a gate would ask is answered inside the sheet',
    );

    await tester.tap(find.text('Give the whole set'));
    await tester.pumpAndSettle();

    // The old behaviour, still reachable — deliberately, and only on purpose.
    //
    // Asserts the sheet, not its contents: this harness scripts the membership
    // and the grid page, not the per-child counts the sheet then asks for, so
    // it renders its error state. What is being pinned here is which artifact
    // the button produces, and `assign_sheet` has its own tests for what goes
    // in it.
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('and with a child picked it still opens', (tester) async {
    // The selection is not an input to the sheet, but it is carried on this
    // screen and a parent who picked someone is the commoner path. Both, so
    // that enabling the button did not quietly break the flow it replaced.
    await pumpLibrary(tester);
    await tester.tap(find.text('The Paddington Collection'));
    await tester.pumpAndSettle();

    // The picker row is gone; the child is chosen by cycling the app bar's
    // avatar, which on a collection screen is the only way to switch child
    // without leaving the set.
    await tester.tap(find.byType(PickingForAvatar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Give the whole set'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  /// A set can contain a set, and the fixture above could not see it: only the
  /// container was a `BoxSet`, so every member was a film and the tap had one
  /// answer. Measured on 10.11.11 in review — `collectionMembers()` sends no
  /// `IncludeItemTypes`, so a nested collection arrives as an ordinary member
  /// with `Type='BoxSet'`. A franchise split into phases is the canonical
  /// shape.
  testWidgets('a collection inside a collection opens too, and assigns nothing',
      (tester) async {
    await pumpLibrary(tester);

    // Registered AFTER pumpLibrary, deliberately: matchers are checked newest
    // first, so scripting this before it would be silently overridden by the
    // two-film membership pumpLibrary registers — and the test would pass or
    // fail for a reason unrelated to nesting.
    //
    // `ChildCount` is deliberately absent here, which is now a *server*
    // that did not send it rather than a request that did not ask — the
    // members query asks for it (#119, in review). Still the degrade path
    // worth covering: absent is not zero, and the label must not invent one.
    server.onQuery(
      '/Items',
      (q) => q['parentId'] == 'coll-1',
      json: <String, dynamic>{
        'TotalRecordCount': 1,
        'Items': [item('coll-2', 'Phase One', type: 'BoxSet')],
      },
    );
    server.onQuery(
      '/Items',
      (q) => q['parentId'] == 'coll-2',
      json: <String, dynamic>{
        'TotalRecordCount': 1,
        'Items': [item('film-9', 'Iron Man')],
      },
    );

    await tester.tap(find.text('The Paddington Collection'));
    await tester.pumpAndSettle();

    expect(find.text('Phase One'), findsOneWidget);
    // Below the 800x600 viewport, like the second member tile elsewhere here.
    await tester.ensureVisible(find.text('Phase One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phase One'));
    await tester.pumpAndSettle();

    // Opened, not assigned: the nested set's own screen, with its own member.
    expect(find.text('Iron Man'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // One, not two: an opaque MaterialPageRoute takes the route below it out
    // of the tree, so the outer set is on the navigator stack but not in the
    // widget tree. The nested screen is identified by its own app bar title
    // instead.
    expect(find.byType(CollectionScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Phase One'), findsOneWidget);
  });

  testWidgets('a member opens the ordinary assign sheet for itself',
      (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('The Paddington Collection'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Paddington 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paddington 2'));
    await tester.pumpAndSettle();

    // Same as above: the sheet is the artifact. The point is that a member is
    // an ordinary title here — its tap does what the grid's tap does.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(CollectionScreen), findsOneWidget);
  });

  group('a member tile says what the same tile says on the grid (#119)', () {
    /// **The gap this closes was invisible from either side alone.** The
    /// collection screen renders members through `LibraryGrid` — the same
    /// widget, the same tiles — but `collectionMembers()` asked only for
    /// `Fields: 'Tags'`. A count field is absent unless named, so a series
    /// inside a set drew no episode badge and a set inside a set drew no
    /// count, on tiles that carry both one tap away on the main grid.
    ///
    /// Found in review of the change that put the episode badge on the grid.
    testWidgets('the members query asks for the counts the tiles draw',
        (tester) async {
      await pumpLibrary(tester);
      await tester.tap(find.text('The Paddington Collection'));
      await tester.pumpAndSettle();

      final members = server.requests
          .where((r) => r.queryParameters['parentId'] == 'coll-1')
          .toList();
      expect(members, isNotEmpty,
          reason: 'the control: the members query was made at all');
      expect(members.first.queryParameters['Fields'],
          'Tags,ChildCount,RecursiveItemCount,ProductionLocations,Genres,Studios',
          reason: 'the same fields the grid asks for, because these are the '
              'same tiles');
    });

    // **This one cannot stand in for the query assertion above, and does not
    // try to.** `FakeJellyfinServer` answers with whatever the fixture holds
    // regardless of the `Fields` sent, so this stays green against a client
    // that never asks for the counts — measured, by reverting the query and
    // watching only the assertion above fail. The pair is the coverage: this
    // proves the tile draws the number, that one proves the number is asked
    // for. Either alone is the shape that let a badge ship undrawn.
    testWidgets('so a show inside a set counts its episodes', (tester) async {
      await pumpLibrary(tester);

      // Registered after `pumpLibrary`: matchers are checked newest first.
      server.onQuery(
        '/Items',
        (q) => q['parentId'] == 'coll-1',
        json: <String, dynamic>{
          'TotalRecordCount': 1,
          // Both counts, deliberately different, so a tile reading the wrong
          // field is visible rather than merely unproven — `ChildCount` on a
          // series is its seasons.
          'Items': [
            item('show-1', 'Alpha Show',
                type: 'Series', childCount: 2, recursiveItemCount: 5),
          ],
        },
      );

      await tester.tap(find.text('The Paddington Collection'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha Show'), findsOneWidget);
      await tester.ensureVisible(find.text('Alpha Show'));
      await tester.pumpAndSettle();
      expect(find.text('5 episodes'), findsOneWidget);
      expect(find.text('2 episodes'), findsNothing,
          reason: 'two is the seasons, here as much as on the grid');
    });
  });
}
