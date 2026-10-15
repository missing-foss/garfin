// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

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
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/widgets/assign_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// What Apply does before it writes, made visible.
///
/// **Two reported failures.** On a set, a tap made while the membership was
/// still loading read it as it stood, found nothing, and said "The server ran
/// into a problem" — a server error that had not happened. And on a removal,
/// the last-item question went to the server before the busy state was set,
/// so the button sat reading *Apply* for a round trip: the symptom the busy
/// state was introduced to fix.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );
  const identity = DeviceIdentity(deviceId: 'device-1', deviceName: 'Test');
  const serverError = 'The server ran into a problem. Try again in a moment.';

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
    tags: <String>['kids-emma'],
  );
  const boxSet = LibraryItem(
    id: 'set-1',
    name: 'Paddington Collection',
    type: 'BoxSet',
    tags: <String>[],
  );

  late FakeJellyfinServer server;

  Future<void> pump(
    WidgetTester tester, {
    required LibraryItem item,
    required bool hasLabel,
    Future<CollectionSet> Function()? set,
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
        assignRowsProvider(AssignRequest(session: session, item: item))
            .overrideWith(
          (ref) async => [
            AssignRow(
              child: emma,
              label: 'kids-emma',
              hasLabel: hasLabel,
              visibleCount: 3,
              libraryTotal: 10,
            ),
          ],
        ),
        if (set != null)
          collectionSetProvider(
            const CollectionRequest(session: session, collection: boxSet),
          ).overrideWith((ref) => set()),
        collectionIndexProvider(session)
            .overrideWith((ref) async => const CollectionIndex.empty()),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AssignView(session: session, item: item, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets real async work over the fake adapter finish: a request started by
  /// a tap needs both the fake clock and `runAsync`.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder spinner() => find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      );
  bool applyEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  setUp(() {
    server = FakeJellyfinServer()
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});
    for (final id in ['item-1', 'set-1', 'film-1']) {
      server.onQuery(
        '/Users/admin-1/Items/$id',
        (_) => true,
        json: <String, dynamic>{'Id': id, 'Name': id, 'Tags': <String>[]},
      );
    }
  });

  testWidgets('a set still loading is waited for, not called a server error',
      (tester) async {
    final membership = Completer<CollectionSet>();
    await pump(tester,
        item: boxSet, hasLabel: false, set: () => membership.future);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text(serverError), findsNothing,
        reason: 'nothing has failed; the membership is on its way');
    expect(spinner(), findsOneWidget, reason: 'and the wait is visible');
    expect(applyEnabled(tester), isFalse);

    membership.complete(
      const CollectionSet(
        collection: boxSet,
        members: [
          LibraryItem(id: 'film-1', name: 'film-1', type: 'Movie', tags: []),
        ],
      ),
    );
    await settle(tester);

    expect(find.text(serverError), findsNothing);
    expect(
      server.requests.where((r) => r.method == 'POST').map((r) => r.path),
      containsAll(<String>['/Items/film-1', '/Items/set-1']),
      reason: 'once the membership landed, the set was written',
    );
  });

  testWidgets('Apply shows it is working while the last-item question is asked',
      (tester) async {
    // The question's count, slow: the round trip that used to pass with the
    // button still reading Apply.
    server.onQuery(
      '/Items',
      (q) => q['tags'] == 'kids-emma',
      json: <String, dynamic>{'TotalRecordCount': 10},
      delay: const Duration(milliseconds: 200),
    );
    await pump(tester, item: film, hasLabel: true);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(spinner(), findsOneWidget,
        reason: 'the question is real work, and it shows');
    expect(applyEnabled(tester), isFalse,
        reason: 'and a second tap must not ask it twice');

    await settle(tester);
  });
}
