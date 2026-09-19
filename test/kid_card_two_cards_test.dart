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
import 'package:garfin/models/media_library.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/widgets/kid_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the tap reveals, and in how many cards.
///
/// Two unrelated things were sharing one run of lines: what Jellyfin enforces
/// on the account, and what the child can see library by library. A heading was
/// keeping them apart; a card does it in the shape.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  final emma = KidSummary(
    user: const JellyfinUser(
      id: 'kid-1',
      name: 'Emma',
      policy: UserPolicy(
        isAdministrator: false,
        isDisabled: false,
        allowedTags: ['kids-emma'],
        blockedTags: [],
      ),
    ),
    birthYear: 2016,
  );

  /// Deliberately not already in the right order, and not in reverse either:
  /// a list that is sorted by accident would pass an unsorted implementation.
  const libraries = [
    LibraryVisibleCount(
      library: MediaLibrary(id: 'l1', name: 'Films', collectionType: 'movies'),
      visible: 12,
    ),
    LibraryVisibleCount(
      library: MediaLibrary(id: 'l2', name: 'Shows', collectionType: 'tvshows'),
      visible: 40,
    ),
    LibraryVisibleCount(
      library: MediaLibrary(id: 'l3', name: 'Shorts', collectionType: 'movies'),
      visible: 3,
    ),
  ];

  Future<void> pump(WidgetTester tester, {required bool open}) async {
    await tester.binding.setSurfaceSize(const Size(412, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          childLibraryCountsProvider(
            ChildLibrariesRequest(session: session, childId: 'kid-1'),
          ).overrideWith((ref) async => libraries),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: KidCard(kid: emma, session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (open) {
      await tester.tap(find.text('Emma'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('closed, the child is one card', (tester) async {
    await pump(tester, open: false);

    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('open, the two kinds of fact are two cards', (tester) async {
    await pump(tester, open: true);

    expect(find.byType(Card), findsNWidgets(3),
        reason: 'the child, what Jellyfin enforces, and what they can see');
    // Both headings name the child: two cards about Emma, not two cards
    // about a generic "them".
    expect(find.text('Parental controls for Emma'), findsOneWidget);
    expect(find.text('Emma has access to'), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);
  });

  testWidgets('the libraries read most-seen first', (tester) async {
    await pump(tester, open: true);

    double topOf(String name) => tester.getRect(find.text(name)).top;

    // 40, 12, 3 — the order a parent asked for: start with what the child can
    // see most of. Asserted by position rather than by the provider's list, so
    // it fails if the widget stops honouring the order it is given.
    expect(topOf('Shows'), lessThan(topOf('Films')));
    expect(topOf('Films'), lessThan(topOf('Shorts')));
  });

  testWidgets('and the headline count is gone from both', (tester) async {
    await pump(tester, open: true);

    // The per-library rows answer the same question with more resolution, and
    // keeping both meant a headline that could disagree with the breakdown
    // directly beneath it.
    expect(find.textContaining('things visible'), findsNothing);
    expect(find.text('12 of 40 things visible'), findsNothing);
  });
}
