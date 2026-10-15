// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/widgets/library_grid.dart';
import 'package:garfin/widgets/library_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A library tile is announced as a button, with what pressing it does: a film
/// opens "who gets this", a collection opens the collection (#219).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  final entries = [
    const LibraryEntry(
      item: LibraryItem(id: 'f', name: 'Paddington', type: 'Movie', tags: []),
      state: LibraryItemState.notGiven,
    ),
    const LibraryEntry(
      item: LibraryItem(id: 'c', name: 'Paddington Collection', type: 'BoxSet', tags: [], childCount: 3),
      state: LibraryItemState.notGiven,
    ),
  ];

  Future<void> pump(WidgetTester tester, Locale locale) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          kidsOverviewProvider(session).overrideWith(
            (ref) async => const KidsOverview(shortlisted: [], withoutShortlist: <UnshortlistedUser>[]),
          ),
          parentalRatingLadderProvider(session).overrideWith((ref) async => const ParentalRatingLadder.empty()),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LibraryGrid(session: session, entries: entries, child: null, onTap: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tile(String id) =>
      find.byWidgetPredicate((w) => w is LibraryTile && w.entry.item.id == id);

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('in ${locale.toLanguageTag()}, a film is a button that opens who gets it', (tester) async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final handle = tester.ensureSemantics();
      await pump(tester, locale);

      final node = tester.getSemantics(tile('f'));
      expect(node, isSemantics(isButton: true, hasTapAction: true, hint: l10n.libraryTileAssignHint));
      expect(node.label, contains('Paddington'), reason: 'the tile still says what it is');
      handle.dispose();
    });

    testWidgets('in ${locale.toLanguageTag()}, a collection is a button that opens it', (tester) async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final handle = tester.ensureSemantics();
      await pump(tester, locale);

      final node = tester.getSemantics(tile('c'));
      expect(node, isSemantics(isButton: true, hasTapAction: true, hint: l10n.libraryTileOpenHint));
      expect(node.label, contains('Paddington Collection'));
      handle.dispose();
    });
  }
}
