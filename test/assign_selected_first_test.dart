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
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/assign_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/widgets/assign_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The child the parent is picking for has the first row (UI-SPEC § Assign
/// sheet: "one row per label-controlled child, the selected one first").
///
/// The spec said so and the code did not: the rows came in the server's order
/// of children, whoever was picked. The parent picked that child because they
/// are about to give them something, and on a phone a row further down is a
/// row under a scroll.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  // Every part of the head present, which is what makes it tall.
  const film = LibraryItem(
    id: 'item-1',
    name: 'Paddington 2',
    type: 'Movie',
    tags: <String>[],
    officialRating: 'PG',
    productionYear: 2017,
    runTimeTicks: 62400000000,
    productionLocations: ['United Kingdom', 'France'],
    communityRating: 7.8,
    criticRating: 99,
    genres: ['Adventure', 'Comedy', 'Family'],
    studios: ['Heyday Films', 'StudioCanal'],
  );

  AssignRow rowFor(int i) => AssignRow(
        child: JellyfinUser(
          id: 'kid-$i',
          name: 'Kid $i',
          policy: UserPolicy(
            isAdministrator: false,
            isDisabled: false,
            allowedTags: ['kids-$i'],
            blockedTags: const [],
          ),
        ),
        label: 'kids-$i',
        hasLabel: false,
        visibleCount: 24,
        libraryTotal: 400,
      );

  /// Opens the real sheet for [kids] children with [picked] chosen, or
  /// Everyone when it is null. Returns the container, so a test can change
  /// whom the parent is picking for while the sheet is open.
  Future<ProviderContainer> openSheet(
    WidgetTester tester, {
    required int kids,
    String? picked,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(
          const DeviceIdentity(deviceId: 'device-1', deviceName: 'Test'),
        ),
        assignRowsProvider(const AssignRequest(session: session, item: film))
            .overrideWith(
          (ref) async => [for (var i = 1; i <= kids; i++) rowFor(i)],
        ),
        collectionIndexProvider(session)
            .overrideWith((ref) async => const CollectionIndex.empty()),
      ],
    );
    addTearDown(container.dispose);
    container.read(pickingForProvider.notifier).select(picked);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () =>
                      showAssignSheet(context, session: session, item: film),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  /// A window tall enough that every row is built: the list is lazy, and a
  /// row below the fold would be missing from [order] rather than out of it.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The children's names, top to bottom.
  List<String> order(WidgetTester tester) => [
        for (final tile
            in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)))
          (tile.title! as Text).data!,
      ];

  testWidgets('the picked child first, the rest in the server order',
      (tester) async {
    tall(tester);
    await openSheet(tester, kids: 3, picked: 'kid-3');

    expect(order(tester), ['Kid 3', 'Kid 1', 'Kid 2']);
  });

  testWidgets('Everyone keeps the server order', (tester) async {
    tall(tester);
    final container = await openSheet(tester, kids: 3);
    expect(order(tester), ['Kid 1', 'Kid 2', 'Kid 3']);

    // And picking someone while the sheet is open moves their row up.
    container.read(pickingForProvider.notifier).select('kid-2');
    await tester.pumpAndSettle();
    expect(order(tester), ['Kid 2', 'Kid 1', 'Kid 3']);
  });

  testWidgets('on a phone the picked row is on screen without a scroll',
      (tester) async {
    // A Pixel 9 Pro at its default display size, which is the reference the
    // report was made on.
    const dpr = 1280 / 412;
    tester.view.physicalSize = const Size(1280, 2850);
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: 24 * dpr);
    tester.view.viewPadding =
        const FakeViewPadding(top: 24 * dpr, bottom: 24 * dpr);
    addTearDown(tester.view.reset);

    // The last of eight: under the server's order, the row furthest down.
    await openSheet(tester, kids: 8, picked: 'kid-8');

    final row = tester.getRect(find.widgetWithText(SwitchListTile, 'Kid 8'));
    final apply = tester.getRect(find.byType(FilledButton));
    expect(row.bottom, lessThanOrEqualTo(apply.top),
        reason: 'the picked row must clear Apply before any scroll');
    expect(row.top, greaterThanOrEqualTo(0));
  });
}
