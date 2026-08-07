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
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      // Matched on the **shape** of the query, not on arrival order: the grid
      // rebuilds when the child is selected, so a positional script hands the
      // second page request the count's answer and the line reads 0 — a
      // plausible wrong number, from the harness rather than the code.
      server
        ..onQuery('/Items', (q) => q.containsKey('StartIndex'), json: {
          'TotalRecordCount': total,
          'Items': [
            <String, dynamic>{
              'Id': 'item-1',
              'Name': 'Paddington',
              'Type': 'Movie',
              'Tags': <String>[],
            },
          ],
        })
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
