// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/assign_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/activity_screen.dart';
import 'package:garfin/widgets/assign_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Ground rule 1's hard warning, on every button that can take a label away.
///
/// The warning used to be asked from Apply alone, and only ever about one item.
/// So three ways to leave a child seeing nothing went through unasked: taking
/// back a set that was all they had, the toast's Undo of the one thing they had
/// been given, and Activity's Undo of the same. Each is the event the warning
/// exists for, reached by a different button.
///
/// Each test answers the warning's questions — how many items carry the label,
/// and which — so that the write is the child's last, then checks that the
/// dialog appears and that Cancel writes nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');

  const emma = JellyfinUser(
    id: 'kid-1',
    name: 'Emma',
    policy: UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-emma'],
      blockedTags: [],
    ),
  );

  const film = LibraryItem(
    id: 'item-1',
    name: 'Paddington',
    type: 'Movie',
    tags: <String>[],
  );
  const boxSet = LibraryItem(
    id: 'set-1',
    name: 'Paddington Collection',
    type: 'BoxSet',
    tags: <String>['kids-emma'],
  );
  final set = CollectionSet(
    collection: boxSet,
    members: [
      for (final id in ['film-1', 'film-2', 'film-3'])
        LibraryItem(id: id, name: id, type: 'Movie', tags: const ['kids-emma']),
    ],
  );

  late FakeJellyfinServer server;

  /// Every item readable and every write accepted, unless a test says
  /// otherwise; and the warning's two questions answered so that [ids] are
  /// all the items still carrying Emma's label.
  void script({required List<String> ids}) {
    server = FakeJellyfinServer();
    for (final id in ['item-1', 'set-1', 'film-1', 'film-2', 'film-3']) {
      server.onQuery(
        '/Users/admin-1/Items/$id',
        (_) => true,
        json: <String, dynamic>{'Id': id, 'Name': id, 'Tags': <String>[]},
      );
    }
    server
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 10})
      ..onQuery(
        '/Items',
        (q) => q['tags'] == 'kids-emma' && q['Limit'] == 0,
        json: <String, dynamic>{'TotalRecordCount': ids.length},
      )
      ..onQuery(
        '/Items',
        (q) => q['tags'] == 'kids-emma' && q['Limit'] != 0,
        json: <String, dynamic>{
          'Items': [for (final id in ids) <String, dynamic>{'Id': id}],
          'TotalRecordCount': ids.length,
        },
      );
  }

  int writes() =>
      server.requests.where((r) => r.method == 'POST').length;

  Future<ProviderContainer> container({
    required LibraryItem item,
    required bool hasLabel,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: server),
        ),
        assignRowsProvider(AssignRequest(session: session, item: item))
            .overrideWith(
          (ref) async {
            ref.keepAlive(); // as the real body does
            return [
              AssignRow(
                child: emma,
                label: 'kids-emma',
                hasLabel: hasLabel,
                visibleCount: 3,
                libraryTotal: 10,
              ),
            ];
          },
        ),
        collectionSetProvider(
          const CollectionRequest(session: session, collection: boxSet),
        ).overrideWith((ref) async {
          ref.keepAlive(); // as the real body does
          return set;
        }),
        collectionIndexProvider(session)
            .overrideWith((ref) async {
              ref.keepAlive(); // as the real body does
              return const CollectionIndex.empty();
            }),
        kidsOverviewProvider(session).overrideWith(
          (ref) async {
            ref.keepAlive(); // as the real body does
            return const KidsOverview(
              shortlisted: [KidSummary(user: emma)],
              withoutShortlist: [],
            );
          },
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpApp(
    WidgetTester tester,
    ProviderContainer c,
    Widget body,
  ) async {
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

  Finder warning() => find.text('Emma would see nothing');

  Future<void> cancelAndExpectNoWrite(WidgetTester tester, int before) async {
    expect(warning(), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(warning(), findsNothing);
    expect(writes(), before, reason: 'Cancel must write nothing');
  }

  testWidgets('Apply: taking back a set that is all the child has',
      (tester) async {
    script(ids: ['set-1', 'film-1', 'film-2', 'film-3']);
    final c = await container(item: boxSet, hasLabel: true);
    await pumpApp(
      tester,
      c,
      AssignView(session: session, item: boxSet, onClose: () {}),
    );

    await tester.tap(find.byType(SwitchListTile));
    await settle(tester);
    await tester.tap(find.byType(FilledButton));
    await settle(tester);

    await cancelAndExpectNoWrite(tester, 0);
  });

  testWidgets("the toast's Undo of the only thing the child was given",
      (tester) async {
    // After the give, item-1 is the one item carrying the label.
    script(ids: ['item-1']);
    final c = await container(item: film, hasLabel: false);
    await pumpApp(
      tester,
      c,
      AssignView(session: session, item: film, onClose: () {}),
    );

    await tester.tap(find.byType(SwitchListTile));
    await settle(tester);
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    final afterGive = writes();
    expect(afterGive, 1, reason: 'the give itself is one write');
    expect(warning(), findsNothing, reason: 'a give never warns');

    await tester.tap(find.text('Undo'));
    await settle(tester);

    await cancelAndExpectNoWrite(tester, afterGive);
  });

  testWidgets("Activity's Undo of the only thing the child was given",
      (tester) async {
    script(ids: ['item-1']);
    final c = await container(item: film, hasLabel: false);
    // The give, made through the repository so it lands in the log the
    // screen reads.
    await tester.runAsync(
      () => c.read(assignRepositoryProvider(session)).apply(
            itemId: 'item-1',
            diff: TagDiff(
              [TagChange(child: emma, label: 'kids-emma', adding: true)],
            ),
          ),
    );
    final afterGive = writes();
    // Warm, as it is in the app by the time Activity is reachable: the Undo
    // reads the child as they are now, and an overview still loading reads as
    // an account that is gone.
    await tester.runAsync(() => c.read(kidsOverviewProvider(session).future));
    await pumpApp(tester, c, const ActivityScreen(session: session));

    await tester.tap(find.text('Undo'));
    await settle(tester);

    await cancelAndExpectNoWrite(tester, afterGive);
  });

  testWidgets("Activity's Undo of a set that is all the child has",
      (tester) async {
    script(ids: ['set-1', 'film-1', 'film-2', 'film-3']);
    // What Activity re-resolves the set from: the members, asked fresh.
    server.onQuery(
      '/Items',
      (q) => q['parentId'] == 'set-1',
      json: <String, dynamic>{
        'Items': [
          for (final id in ['film-1', 'film-2', 'film-3'])
            <String, dynamic>{'Id': id, 'Name': id, 'Type': 'Movie'},
        ],
        'TotalRecordCount': 3,
      },
    );
    final c = await container(item: boxSet, hasLabel: false);
    await tester.runAsync(
      () => c.read(assignRepositoryProvider(session)).applyToCollection(
            collectionId: 'set-1',
            memberIds: const ['film-1', 'film-2', 'film-3'],
            diff: TagDiff(
              [TagChange(child: emma, label: 'kids-emma', adding: true)],
            ),
          ),
    );
    final afterGive = writes();
    await tester.runAsync(() => c.read(kidsOverviewProvider(session).future));
    await pumpApp(tester, c, const ActivityScreen(session: session));

    await tester.tap(find.text('Undo'));
    await settle(tester);

    await cancelAndExpectNoWrite(tester, afterGive);
  });

  testWidgets('the reversal of a partly-written set', (tester) async {
    // A give to the whole set where film-2's write fails: the sheet offers
    // "remove all", which takes the label off everything that did land.
    script(ids: ['set-1', 'film-1', 'film-3']);
    server.onQuery('/Items/film-2', (_) => true, status: 500);
    final c = await container(item: boxSet, hasLabel: false);
    await pumpApp(
      tester,
      c,
      AssignView(session: session, item: boxSet, onClose: () {}),
    );

    await tester.tap(find.byType(SwitchListTile));
    await settle(tester);
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(find.byType(OutlinedButton), findsOneWidget,
        reason: 'the set is partly written and the reversal is offered');
    final afterGive = writes();

    await tester.tap(find.byType(OutlinedButton));
    await settle(tester);

    await cancelAndExpectNoWrite(tester, afterGive);
  });
}

/// Lets the fake server's replies land.
///
/// Both clocks, because a request started by a tap lives in the test's fake
/// zone — its timers move only when the fake clock does — while the adapter's
/// own work is real async and needs `runAsync` to complete at all.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
