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
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/screens/kids_screen.dart';
import 'package:garfin/widgets/adaptive_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the layout does at widths nobody had run (#95).
///
/// The grid's half of that issue is in `library_grid_width_test.dart`; this is
/// everything else — the list screens, the navigation, and the two-pane
/// library, which are in `tablet_two_pane_test.dart`.
///
/// Every assertion here **renders and measures**. Re-deriving the padding in
/// the test would agree with a cap that was never applied, which is the same
/// mistake the old `columnsFor` arithmetic made for a year.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pump(WidgetTester tester, Widget child, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a list stops widening', () {
    /// Twenty rows so the list is longer than any window tested — a list that
    /// fitted would still be capped, but a short one cannot catch a cap applied
    /// to the wrong axis.
    Widget list() => ReadableList(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (var i = 0; i < 20; i++)
              ListTile(key: ValueKey('row$i'), title: Text('Row $i')),
          ],
        );

    testWidgets('1280dp caps the rows and centres them', (tester) async {
      await pump(tester, list(), 1280);

      final row = tester.getRect(find.byKey(const ValueKey('row0')));
      expect(row.width, kReadableMaxWidth);
      // Centred, not left-aligned: the two margins are the assertion, because
      // a single `EdgeInsets.only(left:)` would pass a width check alone.
      expect(row.left, 1280 - row.right);
    });

    /// The reason the cap is in the list's padding rather than around the list.
    ///
    /// Wrapping the `ListView` in a `ConstrainedBox` produces an identical
    /// screenshot and a different app: the scrollable itself narrows, so a drag
    /// started in the margin of a tablet scrolls nothing and the scrollbar
    /// leaves the window's edge to meet the text. Nothing about the pixels
    /// would say so.
    testWidgets('the scrollable still spans the whole window', (tester) async {
      await pump(tester, list(), 1280);

      expect(tester.getRect(find.byType(Scrollable)).width, 1280);
    });

    testWidgets('a phone is untouched', (tester) async {
      await pump(tester, list(), 412);

      final row = tester.getRect(find.byKey(const ValueKey('row0')));
      expect(row.width, 412);
      expect(row.left, 0);
    });

    /// The boundary, pinned deliberately: one pixel either side of the cap
    /// decides whether anything moves at all, and a rule that only fires far
    /// from its threshold is a rule nobody has tested.
    testWidgets('the cap starts exactly where it says', (tester) async {
      await pump(tester, list(), kReadableMaxWidth);
      expect(tester.getRect(find.byKey(const ValueKey('row0'))).width,
          kReadableMaxWidth);

      await pump(tester, list(), kReadableMaxWidth + 100);
      final row = tester.getRect(find.byKey(const ValueKey('row0')));
      expect(row.width, kReadableMaxWidth);
      expect(row.left, 50);
    });

    /// A list inside a pane is capped against the pane, not the window — the
    /// same correction #108 made for the grid. Without it, a 640dp column
    /// inside a 400dp pane would simply overflow.
    testWidgets('a narrow pane inside a wide window caps against the pane',
        (tester) async {
      await pump(
        tester,
        Row(children: [SizedBox(width: 400, child: list()), const Spacer()]),
        1280,
      );

      expect(tester.getRect(find.byKey(const ValueKey('row0'))).width, 400);
    });

    testWidgets('a form scrolls under the same cap', (tester) async {
      await pump(
        tester,
        ReadableScroll(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(key: const ValueKey('field'), onChanged: (_) {}),
            ],
          ),
        ),
        1280,
      );

      final field = tester.getRect(find.byKey(const ValueKey('field')));
      // The cap is on the content, and the widget's own padding sits outside
      // it — so the field is the full cap wide, with 24dp of its own beyond
      // that. The alternative (cap the padded box) would make every screen's
      // text column a different width depending on how much padding it happened
      // to declare.
      expect(field.width, kReadableMaxWidth);
      expect(field.left, 1280 - field.right);
    });
  });

  group('the Kids screen is wired to it', () {
    /// The primitives above prove the cap works; this proves a screen uses it.
    /// Both halves are needed — a correct widget nobody called is how the
    /// title search shipped doing nothing (#90).
    KidSummary kid(String id, String name) => KidSummary(
          user: JellyfinUser(
            id: id,
            name: name,
            policy: UserPolicy(
              isAdministrator: false,
              isDisabled: false,
              allowedTags: ['kids-$id'],
              blockedTags: [],
            ),
          ),
          visibleCount: 12,
          libraryTotal: 40,
        );

    Future<void> pumpKids(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kidsOverviewProvider(session).overrideWith(
              (ref) async => KidsOverview(
                shortlisted: [kid('emma', 'Emma')],
                withoutShortlist: const <UnshortlistedUser>[],
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: KidsScreen(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a kid card does not run the width of a tablet',
        (tester) async {
      await pumpKids(tester, 1280);

      final card = tester.getRect(find.byType(Card).first);
      // The list's own 16dp horizontal padding is outside the cap — see the
      // form test above.
      expect(card.width, kReadableMaxWidth);
      expect(card.left, 1280 - card.right);
    });

    testWidgets('and is unchanged on a phone', (tester) async {
      await pumpKids(tester, 412);

      final card = tester.getRect(find.byType(Card).first);
      expect(card.width, 412 - 32);
    });
  });
}
