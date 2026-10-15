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
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/widgets/assign_sheet.dart';
import 'package:garfin/widgets/item_detail_head.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The kids scroll in the whole sheet, not in what the poster leaves over.
///
/// **The reported failure.** With the head pinned above the rows, a phone gave
/// the kids a strip under the poster: measured at 412x917dp, a Pixel 9 Pro, a
/// 159dp window from three kids up, and at font size 1.3 a 67dp one — less than
/// a single row, so even the second of two kids needed a scroll, in a window a
/// flick crosses at once.
///
/// The fix is the head joining the one scrolling area, with Apply the only
/// thing pinned. These tests hold the three parts of that: one scrollable with
/// the head inside it, on both surfaces; a window the size of the sheet; and
/// Apply on screen whichever kid is being reached.
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

  /// A Pixel 9 Pro at its default display size, and Android's font size.
  void phone(WidgetTester tester, {double textScale = 1.0}) {
    const dpr = 1280 / 412;
    tester.view.physicalSize = const Size(1280, 2850);
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: 24 * dpr);
    tester.view.viewPadding =
        const FakeViewPadding(top: 24 * dpr, bottom: 24 * dpr);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> pump(WidgetTester tester, Widget home, {required int kids}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
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
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The phone's surface: the real modal sheet, opened the way a tap does.
  Future<void> openSheet(WidgetTester tester, {required int kids}) async {
    await pump(
      tester,
      Scaffold(
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
      kids: kids,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The tablet's surface: the view in a panel-shaped box, as `AssignPanel`
  /// lays it out — an `Expanded` under the close button.
  Future<void> openPanel(WidgetTester tester, {required int kids}) => pump(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              height: 600,
              child: Column(
                children: [
                  Expanded(
                    child: AssignView(
                      session: session,
                      item: film,
                      onClose: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        kids: kids,
      );

  Finder scrollables() =>
      find.descendant(of: find.byType(AssignView), matching: find.byType(Scrollable));

  group('one scrollable, with the head inside it', () {
    // On both surfaces, because they are one view and a fix that reached
    // only the sheet would leave the panel's kids under a pinned poster.
    for (final (surface, open) in [
      ('sheet', openSheet),
      ('panel', openPanel),
    ]) {
      testWidgets(surface, (tester) async {
        phone(tester);
        await open(tester, kids: 3);

        expect(scrollables(), findsOneWidget);
        expect(
          find.descendant(
            of: scrollables(),
            matching: find.byType(ItemDetailHead),
          ),
          findsOneWidget,
          reason: 'a head outside the scrollable is pinned, and the kids get '
              'only what it leaves',
        );
      });
    }
  });

  testWidgets('at font size 1.3 the kids scroll in the sheet, not a strip',
      (tester) async {
    phone(tester, textScale: 1.3);
    await openSheet(tester, kids: 2);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final window = tester.getSize(scrollables()).height;
    // Measured before the change: 67dp, under a tenth of the screen. With the
    // head inside, the window is the sheet less the handle and Apply.
    expect(window, greaterThan(screen.height * 0.6),
        reason: 'the scrolling area was ${window.toStringAsFixed(0)}dp of '
            '${screen.height.toStringAsFixed(0)}');
  });

  testWidgets('Apply stays on screen while the last of eight kids is reached',
      (tester) async {
    phone(tester, textScale: 1.3);
    await openSheet(tester, kids: 8);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    bool applyOnScreen() {
      final apply = tester.getRect(find.byType(FilledButton));
      return apply.top >= 0 && apply.bottom <= screen.height;
    }

    expect(applyOnScreen(), isTrue, reason: 'before any scroll');

    await tester.scrollUntilVisible(
      find.text('Kid 8'),
      100,
      scrollable: scrollables(),
    );
    await tester.pumpAndSettle();

    final last = tester.getRect(find.widgetWithText(SwitchListTile, 'Kid 8'));
    final window = tester.getRect(scrollables());
    expect(last.bottom, lessThanOrEqualTo(window.bottom + 0.5),
        reason: 'the last kid can be brought fully into view');
    expect(applyOnScreen(), isTrue, reason: 'after scrolling to the last kid');
  });
}
