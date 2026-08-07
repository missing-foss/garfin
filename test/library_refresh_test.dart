// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/assign_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The result line after a write (#93).
///
/// #92 made the number right and left it **stale**: the grid was invalidated
/// from six call sites and the count from none, so giving a child a title made
/// the tile vanish while the number beside it stood still — in a provider that
/// is not auto-disposed, so it stayed wrong until the app restarted.
///
/// The gate is the one the review named: **write, then read the line.** None of
/// #92's tests exercised a write, which is exactly why its suite was green over
/// this.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  final emma = JellyfinUser(
    id: 'id-Emma',
    name: 'Emma',
    policy: const UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-emma'],
      blockedTags: [],
    ),
  );

  group('a write moves the number, not just the grid', () {
    late FakeJellyfinServer server;

    setUp(() => server = FakeJellyfinServer());

    /// The library page, then the tagged count. A later `fallback` stands in
    /// for the server having gained a tag, so the second refresh sees a
    /// different world rather than a scripted one.
    Future<ProviderContainer> pumpScreen(
      WidgetTester tester, {
      required int total,
      required int tagged,
    }) async {
      // A phone-shaped surface. The default 800x600 puts a poster tile's
      // title at y=617 — off the bottom of the render tree — so tapping a tile
      // silently misses and the sheet never opens.
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      // Matched on the **shape** of the query, not on arrival order: the grid
      // rebuilds when the child is selected, so a positional script hands the
      // second page request the count's answer and the line reads 0 — a
      // plausible wrong number, from the harness rather than the code.
      server
        ..onQuery(
          '/Items',
          (q) => q.containsKey('StartIndex') && q['StartIndex'] == 0,
          json: {
            'TotalRecordCount': total,
            'Items': [
              <String, dynamic>{
                'Id': 'item-1',
                'Name': 'Paddington',
                'Type': 'Movie',
                'Tags': <String>[],
              },
            ],
          },
        )
        // **Page two is empty.** A grid shorter than its viewport reports
        // `maxScrollExtent == 0`, so the paging listener fires on every frame;
        // with a matcher that answers every page the same, the same tile
        // arrives forever. That is the harness, not the app — a real second
        // page carries different ids — but it put six copies of one film in
        // the feed before this line existed.
        ..onQuery(
          '/Items',
          (q) => q.containsKey('StartIndex') && q['StartIndex'] != 0,
          json: {'TotalRecordCount': total, 'Items': <Object>[]},
        )
        ..onQuery('/Items', (q) => q.containsKey('tags'),
            json: {'Items': <Object>[], 'TotalRecordCount': tagged})
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
        kidsOverviewProvider(session).overrideWith(
          (ref) async => KidsOverview(
            shortlisted: [
              KidSummary(user: emma, visibleCount: 0, libraryTotal: 0),
            ],
            withoutShortlist: const [],
          ),
        ),
        parentalRatingLadderProvider(session)
            .overrideWith((ref) async => const ParentalRatingLadder.empty()),
      ]);
      addTearDown(container.dispose);
      await container.read(kidsOverviewProvider(session).future);
      container.read(pickingForProvider.notifier).select(emma.id);
      // Show shared, so the grid asks for exactly one page. With hiding on it
      // refills over an enlarged window and consumes the scripted count reply
      // as a second page — the harness answering a different question, which
      // showed up here as a `total` of 24.
      if (container.read(hideSharedProvider)) {
        container.read(hideSharedProvider.notifier).toggle();
      }

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
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return container;
    }

    testWidgets('giving a child a title changes the line', (tester) async {
      final container = await pumpScreen(tester, total: 400, tagged: 24);
      expect(find.text("376 things Emma hasn't got yet"), findsOneWidget);

      // A real write through the real repository: fresh GET, mutate `Tags`,
      // post the whole object back (ground rule 2).
      server
        ..on('/Users/admin-1/Items/item-1', json: {
          'Id': 'item-1',
          'Name': 'Paddington',
          'Type': 'Movie',
          'Tags': <String>[],
        })
        ..on('/Items/item-1', json: {})
        // The world after the write: the library still holds 400 items and one
        // more of them now carries Emma's label. Registered last, so it wins.
        ..onQuery('/Items', (q) => q.containsKey('tags'),
            json: {'Items': <Object>[], 'TotalRecordCount': 25});

      // **`runAsync`, not a bare await.** `testWidgets` runs in a fake-async
      // zone where timers only advance on `pump`, and the write path is real
      // async — awaiting it directly hangs the test rather than failing it.
      await tester.runAsync(
        () => container.read(assignRepositoryProvider(session)).apply(
              itemId: 'item-1',
              diff: TagDiff([
                TagChange(child: emma, label: 'kids-emma', adding: true),
              ]),
            ),
      );

      // The screen has not been told yet, and this is the defect: the tile is
      // gone from the grid the moment the grid reloads, and without the
      // refresh the number below it never moves.
      container.read(libraryRevisionProvider.notifier).bump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text("375 things Emma hasn't got yet"), findsOneWidget,
          reason: 'the count did not re-run after the write');
      expect(find.text("376 things Emma hasn't got yet"), findsNothing);
    });

    testWidgets('the assign sheet itself refreshes the line after Apply',
        (tester) async {
      // The review's second finding: the write test above bumps the revision
      // itself, so it pins "a bump re-runs the count" and not "the sheet
      // bumps" — delete `refreshLibrary` from the sheet and it still passes.
      // This drives the real sheet: tap the tile, toggle Emma, Apply, and read
      // the line, with nothing in the test touching the refresh.
      await pumpScreen(tester, total: 400, tagged: 24);
      expect(find.text("376 things Emma hasn't got yet"), findsOneWidget);

      // What the sheet asks for on top of the grid's own queries.
      server
        ..on('/Users/admin-1/Items/item-1', json: {
          'Id': 'item-1',
          'Name': 'Paddington',
          'Type': 'Movie',
          'Tags': <String>[],
        })
        ..on('/Items/item-1', json: {})
        ..onQuery(
          '/Items',
          (q) => q['Limit'] == 0 && !q.containsKey('tags'),
          json: {'Items': <Object>[], 'TotalRecordCount': 100},
        );

      await tester.tap(find.text('Paddington'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byType(SwitchListTile), findsOneWidget,
          reason: 'the sheet did not open with Emma on it');

      // The world the write creates: one more item carries her label.
      server.onQuery('/Items', (q) => q.containsKey('tags'),
          json: {'Items': <Object>[], 'TotalRecordCount': 25});

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text("375 things Emma hasn't got yet"), findsOneWidget,
          reason: 'the sheet wrote and the line did not move');

      // The result toast lives for eight seconds (#65); let it go rather than
      // ending the test on a live timer.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(seconds: 9));
    });

    testWidgets('a refresh does not blank the grid to a spinner',
        (tester) async {
      // Raised in review of this PR, and it is a real cost of the design:
      // swapping `invalidate` for a watched dependency is **not** behaviour
      // -neutral in Riverpod. An invalidation emits `AsyncData(prev,
      // isRefreshing)` and `when()` skips the loading branch for it by
      // default; a *dependency change* emits a plain `AsyncLoading`, which is
      // `isReloading`, and `when()` does **not** skip that by default. So the
      // grid a parent was looking at would be replaced by a spinner on every
      // write, every pull-to-refresh and every Undo — the app's most repeated
      // action.
      final container = await pumpScreen(tester, total: 400, tagged: 24);
      expect(find.text('Paddington'), findsOneWidget);

      container.read(libraryRevisionProvider.notifier).bump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'the grid blanked while reloading');
      expect(find.text('Paddington'), findsOneWidget,
          reason: 'the tiles the parent was looking at disappeared');

      // Let the refetch this test deliberately caught mid-flight finish, or
      // the test ends with a live timer and fails for that instead.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    testWidgets('one refresh moves both numbers, never one of them',
        (tester) async {
      // The reason this is a single signal rather than two invalidations side
      // by side: a line that subtracts a count taken now from a total taken
      // before the write is as wrong as one that never refreshed, and looks
      // just as reasonable.
      final container = await pumpScreen(tester, total: 400, tagged: 24);
      final before = server.requests.length;

      container.read(libraryRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();

      final after = server.requests.skip(before).toList();
      expect(
        after.where((r) => r.queryParameters.containsKey('StartIndex')),
        isNotEmpty,
        reason: 'the grid did not reload',
      );
      expect(
        after.where((r) => r.queryParameters.containsKey('tags')),
        isNotEmpty,
        reason: 'the count did not reload',
      );
    });
  });

  testWidgets('refreshLibrary is that bump, from a widget\'s own ref',
      (tester) async {
    // The helper the call sites use, exercised through a real `WidgetRef`
    // rather than assumed equivalent to the notifier the tests above drive.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        }),
      ),
    );

    final before = container.read(libraryRevisionProvider);
    refreshLibrary(captured);
    expect(container.read(libraryRevisionProvider), before + 1);
  });

  group('and no call site can refresh half of it', () {
    // The mechanical half. `CLAUDE.md` gained a convention two PRs ago and a
    // convention is what failed here: six call sites named one provider and
    // none named the other. This reads the source so the seventh cannot.
    final lib = Directory('lib');
    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('library_providers.dart'))
        .toList();

    test('the sweep actually reads something', () {
      // A negative assertion over an empty list is a pass that means nothing —
      // the same trap as asserting no request was made when nothing ran.
      expect(sources, isNotEmpty);
      expect(
        sources.where((f) => f.readAsStringSync().contains('refreshLibrary')),
        isNotEmpty,
        reason: 'no call site uses the helper — is it still wired up?',
      );
    });

    test('nothing outside the provider file invalidates either half', () {
      final offenders = <String>[];
      for (final file in sources) {
        final text = file.readAsStringSync();
        for (final name in const [
          'libraryControllerProvider',
          'taggedItemCountProvider',
        ]) {
          if (text.contains('invalidate($name')) {
            offenders.add('${file.path}: invalidate($name…)');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'refresh the Library with refreshLibrary(ref), which moves '
              'the grid and the count together — naming one of them at a call '
              'site is how the other gets forgotten');
    });
  });
}
