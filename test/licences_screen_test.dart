// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/app_info.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/screens/licences_screen.dart';

/// The short licence list, which exists because the full one is 201 packages.
///
/// **What must not happen here is under-reporting.** Grouping the display is
/// fine; dropping a dependency from the list Garfin says it uses is not. The
/// tempting shortcut — hide packages the registry has no entry for, because
/// their row opens on nothing — would do exactly that, silently, and the screen
/// would look tidier for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  Future<void> pump(WidgetTester tester) async {
    // Tall enough for all eleven rows: `ListView.builder` does not build what
    // is below the fold, so on a default surface the assertion would be about
    // the viewport rather than about the list.
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LicencesScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every direct dependency gets a row', (tester) async {
    // Nothing registered: every package is in the "no entry of its own" case,
    // which is the one a filter would silently swallow.
    await pump(tester);

    for (final package in directDependencies) {
      expect(find.text(package), findsOneWidget,
          reason: '$package is a dependency and must be listed');
    }
  });

  testWidgets('a package with a licence opens it; one without does not',
      (tester) async {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(['dio'], 'THE DIO TERMS');
    });
    await pump(tester);

    // The one with an entry is tappable and shows the text verbatim.
    await tester.tap(find.text('dio'));
    await tester.pumpAndSettle();
    expect(find.text('THE DIO TERMS'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // The one without keeps its row — it is still a dependency — but has
    // nothing to open, and says so by not being tappable rather than by
    // opening an empty page.
    final bare = tester.widget<ListTile>(
      find.ancestor(
          of: find.text('logging'), matching: find.byType(ListTile)),
    );
    expect(bare.onTap, isNull);
  });
}
