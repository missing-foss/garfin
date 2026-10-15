// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/active_session.dart';
import 'package:garfin/models/age_suitability.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/item_holder.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/session_providers.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:garfin/widgets/library_filter_bar.dart';
import 'package:garfin/widgets/library_search_field.dart';
import 'package:garfin/widgets/library_tile.dart';
import 'package:garfin/widgets/picking_for_avatar.dart';
import 'package:garfin/widgets/user_avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Both shipped locales are left-to-right, so nothing here is broken today.
/// These pin that the layouts are written in start/end terms, so a
/// right-to-left locale mirrors them whole instead of half (#219): every
/// distance measured from the start edge left-to-right must be the same
/// distance measured from the start edge right-to-left.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  Widget app(TextDirection direction, Widget home) => MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => Directionality(textDirection: direction, child: child!),
        home: home,
      );

  /// How far [target] sits from the start edge of [within].
  double fromStart(WidgetTester tester, Finder target, Finder within, TextDirection direction) {
    final t = tester.getRect(target);
    final w = tester.getRect(within);
    return direction == TextDirection.ltr ? t.left - w.left : w.right - t.right;
  }

  /// Runs [pump] in each direction and returns [measure]'s reading for both.
  Future<(double, double)> both(
    WidgetTester tester,
    Future<void> Function(TextDirection) pump,
    double Function(TextDirection) measure,
  ) async {
    await pump(TextDirection.ltr);
    final ltr = measure(TextDirection.ltr);
    await pump(TextDirection.rtl);
    final rtl = measure(TextDirection.rtl);
    return (ltr, rtl);
  }

  testWidgets('the library filter row keeps its gap between the search field and the tune button',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (ltr, rtl) = await both(
      tester,
      (d) async {
        await tester.pumpWidget(ProviderScope(
          key: ValueKey(d),
          child: app(d, const Scaffold(body: LibraryFilterBar(session: session))),
        ));
        await tester.pumpAndSettle();
      },
      (d) {
        final search = tester.getRect(find.byType(LibrarySearchField));
        final tune = tester.getRect(find.byIcon(Icons.tune));
        return d == TextDirection.ltr ? tune.left - search.right : search.left - tune.right;
      },
    );
    expect(rtl, closeTo(ltr, 0.5));
  });

  group('a library tile with faces on it', () {
    Future<void> pump(WidgetTester tester, TextDirection d) async {
      await tester.pumpWidget(app(
        d,
        Scaffold(
          body: Align(
            alignment: AlignmentDirectional.topStart,
            child: SizedBox(
              width: 160,
              height: 300,
              child: LibraryTile(
                key: ValueKey(d),
                entry: const LibraryEntry(
                  item: LibraryItem(id: 'a', name: 'Paddington', type: 'Movie', tags: []),
                  state: LibraryItemState.unknown,
                ),
                serverUrl: 'http://host:8096',
                childName: null,
                holders: const [
                  ItemHolder(userId: 'id-Emma', name: 'Emma'),
                  ItemHolder(userId: 'id-Leo', name: 'Leo'),
                ],
                suitability: AgeSuitability.unknown,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the faces sit at the same end of the tile', (tester) async {
      final faces = find.byType(UserAvatar);
      final (ltr, rtl) = await both(
        tester,
        (d) => pump(tester, d),
        (d) => fromStart(tester, faces.first, find.byType(LibraryTile), d),
      );
      expect(rtl, closeTo(ltr, 0.5));
    });

    testWidgets('and stack from the same side', (tester) async {
      final (ltr, rtl) = await both(
        tester,
        (d) => pump(tester, d),
        (d) => fromStart(tester, find.byType(UserAvatar).at(1), find.byType(UserAvatar).first, d),
      );
      expect(rtl, closeTo(ltr, 0.5));
      expect(ltr, greaterThan(0), reason: 'the second face is further from the start than the first');
    });
  });

  testWidgets("a kid card's sign-in button sits at the start of the card", (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final emma = KidSummary(
      user: const JellyfinUser(
        id: 'kid-1',
        name: 'Emma',
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: ['kids-emma'],
          blockedTags: [],
          maxParentalRating: 10,
        ),
      ),
      birthYear: 2016,
    );
    final (ltr, rtl) = await both(
      tester,
      (d) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(ProviderScope(
          key: ValueKey(d),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            kidsOverviewProvider(session).overrideWith(
              (ref) async => KidsOverview(shortlisted: [emma], withoutShortlist: const <UnshortlistedUser>[]),
            ),
            childSessionsProvider(session).overrideWith((ref) async => <ActiveSession>[]),
          ],
          child: app(d, const Scaffold(body: KidsScreen(session: session))),
        ));
        await tester.pumpAndSettle();
      },
      (d) => fromStart(tester, find.widgetWithText(TextButton, 'Sign in on a device'), find.byType(Card).first, d),
    );
    expect(rtl, closeTo(ltr, 0.5));
  });

  testWidgets('with nobody to cycle to, the picking avatar keeps its margin at the end', (tester) async {
    final (ltr, rtl) = await both(
      tester,
      (d) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(ProviderScope(
          key: ValueKey(d),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            kidsOverviewProvider(session).overrideWith(
              (ref) async => const KidsOverview(shortlisted: [], withoutShortlist: <UnshortlistedUser>[]),
            ),
          ],
          child: app(
            d,
            Scaffold(
              appBar: AppBar(title: const Text('Library'), actions: const [PickingForAvatar(session: session)]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      },
      // Measured from the end: the margin is on the side away from the title.
      (d) {
        // With nobody picked the mark is the private "everyone" one.
        final avatar = tester.getRect(find.descendant(
          of: find.byType(PickingForAvatar),
          matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_EveryoneMark'),
        ));
        final bar = tester.getRect(find.byType(AppBar));
        return d == TextDirection.ltr ? bar.right - avatar.right : avatar.left - bar.left;
      },
    );
    expect(rtl, closeTo(ltr, 0.5));
  });
}
