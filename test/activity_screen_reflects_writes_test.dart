// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/providers/activity_providers.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/assign_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/activity_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// Activity against the log the repository actually writes.
///
/// `activity_log_test.dart` proves a write is recorded — it reads the store
/// back directly, so it is silent about whether anything is ever *told*. That
/// gap was the whole of the bug: the log was correct and the screen showed an
/// empty list for the life of the process.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  const identity = DeviceIdentity(deviceId: 'd', deviceName: 't');

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

  FakeJellyfinServer scripted() => FakeJellyfinServer()
    ..on('/Users/admin-1/Items/item-1', json: <String, dynamic>{
      'Id': 'item-1',
      'Name': 'Paddington',
      'Tags': <String>[],
    })
    ..fallback(json: <String, dynamic>{'TotalRecordCount': 10});

  /// One container, shared by both tests — the widget one drives it through
  /// [UncontrolledProviderScope] so the screen and the write demonstrably share
  /// a store, which is the whole subject here.
  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: scripted()),
        ),
      ],
    );
  }

  Future<void> hand(ProviderContainer container) =>
      container.read(assignRepositoryProvider(session)).apply(
            itemId: 'item-1',
            diff: TagDiff(
              [TagChange(child: emma, label: 'kids-emma', adding: true)],
            ),
          );

  test('a watcher of the log is told when a write lands', () async {
    final c = await container();
    addTearDown(c.dispose);

    // Watched *before* the write, which is the case that failed: a cached
    // empty list with nothing to invalidate it.
    final lengths = <int>[];
    c.listen(
      activityLogProvider,
      (_, next) => lengths.add(next.length),
      fireImmediately: true,
    );
    expect(lengths, [0]);

    await hand(c);

    expect(c.read(activityStoreProvider).read(), hasLength(1),
        reason: 'the store records the write — this half always worked');
    expect(c.read(activityLogProvider), hasLength(1),
        reason: 'and the log the screen reads now agrees with it');
    expect(lengths, [0, 1],
        reason: 'a watcher is notified, rather than having to ask again');
  });

  testWidgets('a write made while Activity is open appears on it',
      (tester) async {
    final c = await container();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ActivityScreen(session: session)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Paddington'), findsNothing,
        reason: 'nothing has been handed over yet');

    // `runAsync`, because the write is real async work over a fake adapter and
    // `testWidgets` drives its own clock: awaited bare, the request never
    // completes and the test hangs until the framework's own timeout.
    await tester.runAsync(() => hand(c));
    // A bounded pump rather than `pumpAndSettle`: the rebuild comes from a
    // listener on the store, and settling is not what is being waited for.
    await tester.pump();

    expect(find.text('Paddington'), findsOneWidget,
        reason: 'the parent just handed this over; Activity is where it shows');
  });
}
