// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The collection index is started when the library appears, not when the
/// assign sheet opens.
///
/// **Why this is a test and not just a line.** The index is 1 + N calls — list
/// the sets, then ask each what is in it — and the assign sheet must wait for
/// it before writing, or a parent is never asked a cascade question they were
/// owed. Built when the sheet opened, that wait sat between the parent tapping
/// Apply and anything happening: at 162 collections, 42 round trips four wide.
///
/// Started when the grid appears it runs while they are still browsing. Nothing
/// on screen shows that it happened, so the only thing standing between this
/// and a silent regression is an assertion that it was asked for at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  testWidgets('the library starts the collection index without a sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    var asked = false;
    // Never completes: this asserts the index was *started*, which is the whole
    // point of warming it. A future that resolved would also pass a test that
    // only looked at the end state.
    final never = Completer<CollectionIndex>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          collectionIndexProvider(session).overrideWith((ref) {
            asked = true;
            return never.future;
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    await tester.pump();

    expect(asked, isTrue,
        reason: 'the grid must warm the index so Apply does not wait on it');
    expect(never.isCompleted, isFalse,
        reason: 'and it is a warm-up, so nothing here waits for it to finish');
  });
}
