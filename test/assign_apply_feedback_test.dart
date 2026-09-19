// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Apply has to look like it is doing something while it is.
///
/// **The reported failure.** Tapping Apply on a film did nothing visible — no
/// spinner, no confirmation — and the app looked broken at the moment it does
/// its main job. The write was never the slow part: measured at two round trips
/// and ~18 ms. What Apply waits on first is the collection index, which is
/// **1 + N calls** — list the sets, then ask each one what is in it — and
/// `_sets()` has to wait for it rather than read it half-built, or a parent is
/// never asked a cascade question they were owed.
///
/// That wait sat outside the busy flag, which was only raised once the write
/// began. So the slow half ran with the button still reading *Apply* and
/// nothing on screen, and the fast half got the spinner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  const film = LibraryItem(
    id: 'item-1',
    name: 'Paddington',
    type: 'Movie',
    tags: <String>[],
  );

  final emma = JellyfinUser(
    id: 'kid-1',
    name: 'Emma',
    policy: const UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-emma'],
      blockedTags: [],
    ),
  );

  final row = AssignRow(
    child: emma,
    label: 'kids-emma',
    hasLabel: false,
    visibleCount: 3,
    libraryTotal: 10,
  );

  /// The sheet, with the collection index deliberately still in flight.
  ///
  /// Returns the completer so a test can decide whether the index ever lands.
  Future<Completer<CollectionIndex>> pumpSheet(
    WidgetTester tester, {
    LibraryItem item = film,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final index = Completer<CollectionIndex>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceIdentityProvider.overrideWithValue(
            const DeviceIdentity(deviceId: 'device-1', deviceName: 'Test'),
          ),
          assignRowsProvider(
            AssignRequest(session: session, item: item),
          ).overrideWith((ref) async => [row]),
          // Still loading, which is the state the report was made in: the sheet
          // starts this on open and the parent taps Apply before it lands.
          collectionIndexProvider(session).overrideWith((ref) => index.future),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AssignView(
              session: session,
              item: item,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return index;
  }

  Finder applyButton() => find.byType(FilledButton);

  testWidgets('Apply shows it is working while it waits on the index',
      (tester) async {
    final index = await pumpSheet(tester);

    // Give the child the film, so there is something to apply.
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'nothing has been asked for yet');

    await tester.tap(applyButton());
    await tester.pump();

    // The index has not landed, so Apply is still in its first, slow half.
    expect(index.isCompleted, isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the wait on the collection index must be visible');
    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull,
        reason: 'and a second tap must not start a second write');
  });

  group('which items the sheet draws the detail head for (#160)', () {
    // Through the sheet, not `ItemDetailHead` alone: the rule lives in one
    // line of `assign_sheet.dart`, and pumping the head directly passes whether
    // or not that line ever draws it. Review measured both mutants of that
    // line -- series dropped, a BoxSet added -- surviving the whole suite.
    LibraryItem ofType(String type) =>
        LibraryItem(id: 'item-1', name: 'Paddington', type: type, tags: const []);

    for (final (type, drawn) in [
      ('Movie', true),
      ('Series', true),
      ('BoxSet', false),
    ]) {
      testWidgets('$type: ${drawn ? 'drawn' : 'not drawn'}', (tester) async {
        await pumpSheet(tester, item: ofType(type));

        expect(
          find.byType(ItemDetailHead),
          drawn ? findsOneWidget : findsNothing,
        );
      });
    }
  });
}
