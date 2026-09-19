// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/widgets/library_filter_bar.dart';
import 'package:garfin/widgets/library_search_field.dart';

/// The filter row is the search field and the tune button, and nothing else.
///
/// It used to carry a chip per filter, which made the row wider than the screen
/// and left the search field a fixed 300dp. The filters did not go anywhere —
/// they are in the tune sheet — so what this test protects is the *row*: one
/// screen wide, no horizontal scrolling, the search field taking what is left.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryFilterBar(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the row carries no filter chips', (tester) async {
    await pump(tester, 412);

    expect(find.byType(LibrarySearchField), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing,
        reason: 'the filters live in the tune sheet, not beside it');
  });

  testWidgets('the row does not scroll horizontally', (tester) async {
    await pump(tester, 412);

    // Not "no horizontal Scrollable": a TextField has one of its own, for the
    // text inside it, and asserting that away would fail on a correct row. The
    // row's own scrolling is a ListView, which is what it used to be.
    expect(find.byType(ListView), findsNothing,
        reason: 'a row that scrolls hides controls off the right edge');
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('the search field takes the width the chips used to', (
    tester,
  ) async {
    await pump(tester, 412);
    final wide = tester.getSize(find.byType(TextField)).width;

    await pump(tester, 360);
    final narrow = tester.getSize(find.byType(TextField)).width;

    // 412 - 32 padding - 8 gap - 48 button = 324, and it follows the screen
    // rather than sitting at the old fixed 300.
    expect(wide, 324);
    expect(narrow, lessThan(wide),
        reason: 'the field is the row minus the button, not a constant');
  });
}
