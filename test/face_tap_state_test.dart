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
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/auth_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/home_screen.dart';
import 'package:garfin/widgets/library_filter_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/roster_from_overview.dart';
import 'support/fake_jellyfin_server.dart';

/// What a tap on a child's face sets, and what has to go with the child.
///
/// **The reported failure.** The face tap opens the Library on that child,
/// showing what they already see, with the rating filter on. Navigating back
/// to the Library reset the child and nothing else: the next child picked from
/// the app bar landed on "what they already see" instead of the giving grid,
/// and the rating filter stayed on. And for a child with no cap, that filter
/// still counted on the tune button's badge, with its switch hidden and the
/// query ignoring it — a "1" with nothing to clear but Reset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );
  const identity = DeviceIdentity(deviceId: 'd', deviceName: 't');

  KidSummary kid(String id, String name, {int? cap}) => KidSummary(
        user: JellyfinUser(
          id: id,
          name: name,
          policy: UserPolicy(
            isAdministrator: false,
            isDisabled: false,
            allowedTags: ['kids-$id'],
            maxParentalRating: cap,
          ),
        ),
      );
  final capped = kid('emma', 'Emma', cap: 10);
  final uncapped = kid('leo', 'Léo');

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeJellyfinServer()
      ..fallback(json: <String, dynamic>{'Items': <Object>[], 'TotalRecordCount': 0});
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdentityProvider.overrideWithValue(identity),
        jellyfinApiFactoryProvider.overrideWithValue(
          JellyfinApiFactory(identity: identity, adapter: server),
        ),
        rosterFromOverview(session),
        kidsOverviewProvider(session).overrideWith(
          (ref) async {
            ref.keepAlive(); // as the real body does
            return KidsOverview(
              shortlisted: [capped, uncapped],
              withoutShortlist: const <UnshortlistedUser>[],
            );
          },
        ),
        collectionIndexProvider(session)
            .overrideWith((ref) async {
              ref.keepAlive(); // as the real body does
              return const CollectionIndex.empty();
            }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(kidsOverviewProvider(session).future);
    return c;
  }

  /// What `KidCard._pick` sets: the child, the view of what they see, and the
  /// rating filter.
  void faceTap(ProviderContainer c, KidSummary child) {
    c.read(pickingForProvider.notifier).select(child.user.id);
    c.read(libraryViewProvider.notifier).set(LibraryView.given);
    c.read(libraryFiltersProvider.notifier).set(
          c.read(libraryFiltersProvider).copyWith(withinCap: true),
        );
  }

  testWidgets('the Library tab takes the face tap\'s view and filter with it',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = await container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            state: AuthSignedIn(session: session, verified: true),
          ),
        ),
      ),
    );
    await tester.pump();
    faceTap(c, capped);
    await tester.pump();

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Library'),
    ));
    await tester.pump();

    expect(c.read(pickingForProvider), isNull, reason: 'Everyone, as before');
    expect(c.read(libraryViewProvider), LibraryView.toGive,
        reason: 'the giving grid, which is the Settings default');
    expect(c.read(libraryFiltersProvider).withinCap, isFalse,
        reason: 'the rating filter went with the child it was for');

    // The shell's screens start real work on the fake clock — the sessions
    // poll, the grid's requests. Unmount and let it run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  group('the tune badge counts what narrows the grid', () {
    Future<Badge> badgeFor(WidgetTester tester, KidSummary child) async {
      final c = await container();
      faceTap(c, child);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: LibraryFilterBar(session: session)),
          ),
        ),
      );
      await tester.pump();
      return tester.widget<Badge>(find.byType(Badge));
    }

    testWidgets('a child with no cap: the rating filter is not counted',
        (tester) async {
      expect((await badgeFor(tester, uncapped)).isLabelVisible, isFalse);
    });

    testWidgets('a child with a cap: it is', (tester) async {
      expect((await badgeFor(tester, capped)).isLabelVisible, isTrue);
    });
  });
}
