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
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/assign_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/collection_screen.dart';
import 'package:garfin/screens/home_screen.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:garfin/widgets/adaptive_layout.dart';
import 'package:garfin/widgets/assign_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The navigation and the write preview at tablet widths (#95).
///
/// The two are one file because they are one claim: **which surface a tap
/// produces depends on the width**, and the answers must not overlap. A sheet
/// opening on top of a panel would be two previews of the same write, either of
/// which could be applied.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  final emmaUser = JellyfinUser(
    id: 'kid-emma',
    name: 'Emma',
    policy: const UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-emma'],
      blockedTags: [],
    ),
  );

  final emma = KidSummary(user: emmaUser, visibleCount: 3, libraryTotal: 40);

  late FakeJellyfinServer server;

  setUp(() {
    server = FakeJellyfinServer();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Map<String, dynamic> json(String id, String name, {String type = 'Movie'}) =>
      <String, dynamic>{
        'Id': id,
        'Name': name,
        'Type': type,
        'Tags': <String>[],
      };

  LibraryItem film(String id, String name) =>
      LibraryItem(id: id, name: name, type: 'Movie', tags: const []);

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    double height = 900,
    Locale? locale,
    required Widget home,
    /// The titles whose assign rows are scripted, so the panel has a switch to
    /// flick. Overridden rather than served by the fake, because what is under
    /// test is the panel's own state and not the per-child counts — those have
    /// their own tests.
    List<LibraryItem> rows = const [],

    /// What the grid's page holds. Passed in rather than scripted by the caller
    /// beforehand: the fake server checks its matchers **newest first**, so a
    /// fallback registered before this one runs would be silently shadowed by
    /// it — and the test would then pass or fail for a reason unrelated to what
    /// it is about.
    List<Map<String, dynamic>>? items,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();

    final page = items ??
        [json('film-1', 'Paddington'), json('film-2', 'Matilda')];
    server.fallback(json: <String, dynamic>{
      'TotalRecordCount': page.length,
      'Items': page,
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
          for (final item in rows)
            assignRowsProvider(AssignRequest(session: session, item: item))
                .overrideWith((ref) async => [
                      AssignRow(
                        child: emmaUser,
                        label: 'kids-emma',
                        hasLabel: false,
                        visibleCount: 3,
                        libraryTotal: 40,
                      ),
                    ]),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the navigation moves off the bottom', () {
    Widget shell() => HomeScreen(
          state: AuthSignedIn(session: session, verified: true),
        );

    testWidgets('a phone keeps the bottom bar', (tester) async {
      await pump(tester, width: 412, home: shell());

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a tablet gets a rail instead — never both', (tester) async {
      await pump(tester, width: 800, home: shell());

      expect(find.byType(NavigationRail), findsOneWidget);
      // The negative half is the one worth having: two navigations offering the
      // same four destinations is a state nothing else would catch.
      expect(find.byType(NavigationBar), findsNothing);
    });

    /// The boundary itself. 599 and 600 are one pixel apart and are the whole
    /// rule; a test at 412 and 800 would pass over a breakpoint written as
    /// `> 600` when it means `>=`.
    testWidgets('the swap happens exactly at the breakpoint', (tester) async {
      await pump(tester, width: kRailBreakpoint - 1, home: shell());
      expect(find.byType(NavigationRail), findsNothing);

      await pump(tester, width: kRailBreakpoint, home: shell());
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('the rail navigates, and the body follows', (tester) async {
      await pump(tester, width: 800, home: shell());

      // Reads the artifact — the screen that appeared — rather than the index
      // the rail is holding.
      expect(find.text('Emma'), findsWidgets);
      // The destination's own label, not `widgetWithText(NavigationRail, …)` —
      // that finder returns the rail, and tapping a rail's centre lands on
      // whichever destination happens to be there.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Refresh what Garfin has cached'), findsOneWidget);
    });

    /// Extended above 1240dp: same destinations, labels beside the icons. The
    /// assertion is the rendered width, because `extended: true` is state and
    /// a rail that ignored it would look identical to one that had it.
    testWidgets('a wide window gets an extended rail', (tester) async {
      await pump(tester, width: kExtendedRailBreakpoint - 1, home: shell());
      final narrow = tester.getRect(find.byType(NavigationRail)).width;

      await pump(tester, width: kExtendedRailBreakpoint, home: shell());
      final wide = tester.getRect(find.byType(NavigationRail)).width;

      expect(wide, greaterThan(narrow));
    });
  });

  /// **The composed case, which nothing else here pins (found in review).**
  ///
  /// Every other panel test builds `LibraryScreen` directly, so the pane it
  /// measures *is* the window. In the app it is not: `HomeScreen` puts the rail
  /// and the content in a `Row`, so the library sees `window − rail − divider`
  /// and the panel arrives later than the raw breakpoint suggests.
  ///
  /// Asserted as the **relationship** rather than as a window figure, because
  /// there is no window figure to assert: `labelType: all` sizes the rail to its
  /// widest label, so the crossover moves with the locale and with text scale —
  /// measured 116.0dp in English and 153.5dp in French, which is 957dp of window
  /// against about 994dp for the same layout.
  for (final locale in const [Locale('en'), Locale('fr')]) {
    testWidgets('the panel arrives on the space left beside the rail — $locale',
        (tester) async {
      for (final width in const [900.0, 956.0, 957.0, 1000.0, 1280.0]) {
        await pump(
          tester,
          width: width,
          locale: locale,
          home: HomeScreen(
            state: AuthSignedIn(session: session, verified: true),
          ),
        );

        final rail = tester.getRect(find.byType(NavigationRail)).width;
        // The 1dp is the `VerticalDivider` between them, which this shell owns.
        final pane = width - rail - 1;
        expect(
          find.byType(AssignPanel).evaluate().isNotEmpty,
          pane >= kTwoPaneBreakpoint,
          reason: 'at ${width}dp the library pane is ${pane}dp',
        );
      }
    });
  }

  group('the write preview picks its surface', () {
    Widget library() => const Scaffold(body: LibraryScreen(session: session));

    testWidgets('a phone still opens the modal sheet', (tester) async {
      await pump(tester, width: 412, home: library());

      await tester.tap(find.text('Paddington'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AssignPanel), findsNothing);
    });

    testWidgets('a tablet opens the panel, and no sheet', (tester) async {
      await pump(
        tester,
        width: 1280,
        home: library(),
        rows: [film('film-1', 'Paddington')],
      );

      // Present before anything is picked, so that picking does not re-flow the
      // grid under the finger that picked.
      expect(
        find.text('Pick a title, and what giving it would change appears here.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Paddington'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      // The preview's own heading, inside the panel rather than anywhere else
      // on the screen.
      expect(
        find.descendant(
          of: find.byType(AssignPanel),
          matching: find.text('Who gets this?'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the panel is exactly as wide as it says, and the grid keeps '
        'the rest', (tester) async {
      await pump(tester, width: 1280, home: library());

      final panel = tester.getRect(find.byType(AssignPanel));
      expect(panel.width, kAssignPanelWidth);
      expect(panel.right, 1280);
    });

    testWidgets('the swap happens exactly at the two-pane breakpoint',
        (tester) async {
      await pump(tester, width: kTwoPaneBreakpoint - 1, home: library());
      expect(find.byType(AssignPanel), findsNothing);

      await pump(tester, width: kTwoPaneBreakpoint, home: library());
      expect(find.byType(AssignPanel), findsOneWidget);
    });

    /// **The defect this pane could ship with, and the only one that writes.**
    ///
    /// The panel's state is the pending toggles. Reused across a selection —
    /// which is what happens without a key on the item — a parent who flicks
    /// *give to Emma* on one film, changes their mind, taps another and presses
    /// Apply writes the *second* film to Emma from a switch they set for the
    /// first. Nothing on screen looks wrong: the switch is on, and it is the
    /// switch they flicked.
    ///
    /// Asserts the switch, which is what Apply reads, rather than the panel's
    /// internals.
    testWidgets('picking another title does not inherit pending toggles',
        (tester) async {
      await pump(
        tester,
        width: 1280,
        home: library(),
        rows: [film('film-1', 'Paddington'), film('film-2', 'Matilda')],
      );

      await tester.tap(find.text('Paddington'));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue);

      await tester.tap(find.text('Matilda'));
      await tester.pumpAndSettle();

      // Matilda's own state, from the server: neither child has it.
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse);
    });

    testWidgets('closing the panel empties it', (tester) async {
      await pump(
        tester,
        width: 1280,
        home: library(),
        rows: [film('film-1', 'Paddington')],
      );

      await tester.tap(find.text('Paddington'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(
        find.text('Pick a title, and what giving it would change appears here.'),
        findsOneWidget,
      );
    });
  });

  /// **Found by rendering the panel to PNG, not by the suite** — the same way
  /// #84 and #89 were found, and for the same reason: everything stayed inside
  /// its box until it didn't, and no assertion was watching the one thing that
  /// mattered.
  ///
  /// The scope notes are one line *per set a film belongs to*, deliberately
  /// plural. Fixed above a flexible list, they pushed Apply off the bottom of a
  /// short window — 192px of overflow measured at 1024x600. The sheet had the
  /// same shape, so a phone in landscape had the same latent bug.
  testWidgets('a film in many sets does not push Apply out of the panel',
      (tester) async {
    await pump(
      tester,
      width: 1024,
      height: 600,
      home: const Scaffold(body: LibraryScreen(session: session)),
      rows: [film('film-1', 'Paddington')],
      // Every one of these is a container as far as the collection index is
      // concerned, so the film reports a scope note for each — which is the
      // shape being tested, not a claim about real libraries.
      items: [
        // First, so it is on screen in a 600dp-tall window without scrolling.
        json('film-1', 'Paddington'),
        for (var i = 2; i < 12; i++) json('film-$i', 'Title $i'),
      ],
    );

    await tester.tap(find.text('Paddington'));
    await tester.pumpAndSettle();

    // Apply is the artifact: an overflow throws in a widget test, but a button
    // clipped by a `SingleChildScrollView` would not — it would simply be
    // unreachable, which is the failure a parent would actually meet.
    final apply = find.descendant(
      of: find.byType(AssignPanel),
      matching: find.text('Apply'),
    );
    expect(apply, findsOneWidget);
    final panel = tester.getRect(find.byType(AssignPanel));
    expect(tester.getRect(apply).bottom, lessThanOrEqualTo(panel.bottom));
  });

  group('a collection is still a place', () {
    testWidgets('opening a set empties the panel rather than carrying a film '
        'into it', (tester) async {
      server.onQuery(
        '/Items',
        (q) => q['parentId'] == 'coll-1',
        json: <String, dynamic>{
          'TotalRecordCount': 1,
          'Items': [json('film-9', 'Iron Man')],
        },
      );
      await pump(
        tester,
        width: 1280,
        home: const Scaffold(body: LibraryScreen(session: session)),
        rows: [film('film-1', 'Paddington')],
        items: [
          json('film-1', 'Paddington'),
          json('coll-1', 'Phase One', type: 'BoxSet'),
        ],
      );

      await tester.tap(find.text('Paddington'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AssignPanel),
          matching: find.text('Who gets this?'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Phase One'));
      await tester.pumpAndSettle();

      // The set's own screen, with its own panel — and that panel is empty. A
      // preview of Paddington beside Iron Man reads as though the two are
      // related, and the first thing here a parent might press is Apply.
      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(find.text('Iron Man'), findsOneWidget);
      expect(
        find.text('Pick a title, and what giving it would change appears here.'),
        findsOneWidget,
      );
    });
  });
}
