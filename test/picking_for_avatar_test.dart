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
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/widgets/picking_for_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who the Library is about, and the one control that changes it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  KidSummary kid(String id, String name) => KidSummary(
        user: JellyfinUser(
          id: id,
          name: name,
          policy: const UserPolicy(
            isAdministrator: false,
            isDisabled: false,
            allowedTags: ['t'],
            blockedTags: [],
          ),
        ),
      );

  final emma = kid('kid-1', 'Emma');
  final leo = kid('kid-2', 'Leo');

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required List<KidSummary> kids,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      kidsOverviewProvider(session).overrideWith(
        (ref) async => KidsOverview(
          shortlisted: kids,
          withoutShortlist: const <UnshortlistedUser>[],
        ),
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(kidsOverviewProvider(session).future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Library'),
              actions: const [PickingForAvatar(session: session)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('the cycle', () {
    test('runs through the children and lands on Everyone', () {
      // Pure, so the order is testable without a widget — and the order is the
      // whole behaviour: Everyone sits *after* the last child, so the cycle
      // reads as "the children, then all of them".
      final kids = [emma, leo];

      expect(PickingForAvatar.nextAfter(null, kids), 'kid-1');
      expect(PickingForAvatar.nextAfter('kid-1', kids), 'kid-2');
      expect(PickingForAvatar.nextAfter('kid-2', kids), isNull);
    });

    test('one child is a two-state toggle', () {
      expect(PickingForAvatar.nextAfter(null, [emma]), 'kid-1');
      expect(PickingForAvatar.nextAfter('kid-1', [emma]), isNull);
    });

    test('a selection that is no longer a child starts the cycle over', () {
      // A child can lose their shortlist in Jellyfin between two reads. The
      // honest next step is the first child rather than an index arithmetic
      // that would throw or silently pick the last one.
      expect(PickingForAvatar.nextAfter('gone', [emma, leo]), 'kid-1');
    });

    test('with nobody managed there is nowhere to go', () {
      expect(PickingForAvatar.nextAfter(null, const []), isNull);
    });
  });

  testWidgets('tapping it moves to the next child, then to Everyone',
      (tester) async {
    final container = await pump(tester, kids: [emma, leo]);
    expect(container.read(pickingForProvider), isNull,
        reason: 'the Library opens on Everyone');

    await tester.tap(find.byType(PickingForAvatar));
    await tester.pumpAndSettle();
    expect(container.read(pickingForProvider), 'kid-1');

    await tester.tap(find.byType(PickingForAvatar));
    await tester.pumpAndSettle();
    expect(container.read(pickingForProvider), 'kid-2');

    await tester.tap(find.byType(PickingForAvatar));
    await tester.pumpAndSettle();
    expect(container.read(pickingForProvider), isNull);
  });

  testWidgets('with nobody managed it is not a control at all', (tester) async {
    // A control whose only move is back to where it already is teaches a
    // parent that taps here do nothing — worse than an ornament that never
    // claimed to be one.
    await pump(tester, kids: const []);

    expect(find.byType(PickingForAvatar), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
  });
}
