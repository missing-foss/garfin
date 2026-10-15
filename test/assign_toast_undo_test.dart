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
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/widgets/assign_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// The toast after Apply, on a phone: the sheet it came from is gone.
///
/// **Measured before the change**, through the real modal sheet: pressing the
/// toast's Undo wrote the reversal and then threw `Bad state: Using "ref" when
/// a widget is about to or has been unmounted` — so even an Undo that worked
/// refreshed nothing and never said "Put back". A failed one was an uncaught
/// error and looked the same. And a write to two children reported only the
/// first.
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

  JellyfinUser kid(String id, String name) => JellyfinUser(
        id: id,
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: ['kids-$id'],
          blockedTags: const [],
        ),
      );
  final emma = kid('emma', 'Emma');
  final leo = kid('leo', 'Léo');

  const film = LibraryItem(
    id: 'item-1',
    name: 'Paddington',
    type: 'Movie',
    tags: <String>[],
  );

  late FakeJellyfinServer server;

  int writes() => server.requests.where((r) => r.method == 'POST').length;

  /// Opens the real modal sheet for [rows]. Counts answer 10, which is also
  /// more than a write to one item touches, so the last-item question never
  /// stops these writes.
  Future<ProviderContainer> openSheet(
    WidgetTester tester,
    List<AssignRow> rows,
  ) async {
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
        assignRowsProvider(const AssignRequest(session: session, item: film))
            .overrideWith((ref) async => rows),
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
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showAssignSheet(context, session: session, item: film),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return c;
  }

  AssignRow row(JellyfinUser child, {required bool hasLabel}) => AssignRow(
        child: child,
        label: 'kids-${child.id}',
        hasLabel: hasLabel,
        visibleCount: 3,
        libraryTotal: 10,
      );

  Future<void> applyAll(WidgetTester tester) async {
    for (final tile in find.byType(SwitchListTile).evaluate().toList()) {
      await tester.tap(find.byWidget(tile.widget));
      await tester.pump();
    }
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(find.byType(AssignView), findsNothing,
        reason: 'the sheet closed on the write, as it does on a phone');
  }

  setUp(() {
    server = FakeJellyfinServer()
      ..onQuery(
        '/Users/admin-1/Items/item-1',
        (_) => true,
        json: <String, dynamic>{'Id': 'item-1', 'Name': 'Paddington', 'Tags': <String>[]},
      )
      ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});
  });

  testWidgets('Undo after the sheet has closed refreshes, and says so',
      (tester) async {
    final c = await openSheet(tester, [row(emma, hasLabel: false)]);
    await applyAll(tester);
    final revision = c.read(libraryRevisionProvider);
    final afterGive = writes();

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(writes(), afterGive + 1, reason: 'the reversal was written');
    expect(find.text('Put back'), findsOneWidget);
    expect(c.read(libraryRevisionProvider), isNot(revision),
        reason: 'and the grid was told to refresh');
  });

  testWidgets('a failed Undo says so', (tester) async {
    await openSheet(tester, [row(emma, hasLabel: false)]);
    await applyAll(tester);

    // The reversal's write is refused.
    server.onQuery('/Items/item-1', (_) => true, status: 500);
    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(serverError), findsOneWidget);
    expect(find.text('Put back'), findsNothing);
  });

  testWidgets('a give to two children does not name only the first',
      (tester) async {
    // The first sentence is said before any count lands, so the counts are
    // slowed to catch it. Both are gives, so the diff's direction alone would
    // say "Shared with Emma" — the omission, in the first sentence.
    server.onQuery(
      '/Items',
      (q) => q['userId'] == 'emma' || q['userId'] == 'leo',
      json: <String, dynamic>{'TotalRecordCount': 4},
      delay: const Duration(milliseconds: 600),
    );
    await openSheet(
      tester,
      [row(emma, hasLabel: false), row(leo, hasLabel: false)],
    );
    await applyAll(tester);

    expect(find.text('Changes applied'), findsOneWidget);
    expect(find.text('Shared with Emma'), findsNothing);

    // Let the slowed counts land before the test ends.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 700)),
    );
    await settle(tester);
  });

  testWidgets('a write to two children names both', (tester) async {
    await openSheet(
      tester,
      [row(emma, hasLabel: false), row(leo, hasLabel: true)],
    );
    await applyAll(tester);

    expect(find.textContaining('Emma now sees'), findsOneWidget);
    expect(find.textContaining('Léo now sees'), findsOneWidget,
        reason: "the second child's outcome is spoken too");
  });
}

/// Lets the fake server's replies land: a request started by a tap needs both
/// the fake clock and `runAsync`.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
