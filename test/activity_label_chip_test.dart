// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/activity_entry.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/providers/activity_providers.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/screens/activity_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each Activity entry names the label that changed, as the spec says.
void main() {
  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  Future<void> pumpWith(WidgetTester tester, List<ActivityEntry> entries) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    for (final entry in entries) {
      await container.read(activityStoreProvider).add(entry);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ActivityScreen(session: session)),
        ),
      ),
    );
    await tester.pump();
  }

  ActivityEntry entry({required String label, required bool gaveAccess}) =>
      ActivityEntry(
        itemId: 'item-1',
        itemName: 'Paddington',
        childId: 'kid-2',
        childName: 'Sam',
        label: label,
        gaveAccess: gaveAccess,
        at: DateTime.now(),
      );

  testWidgets('an entry shows the label that was written', (tester) async {
    // A block-list child: the label was added, and Sam was **taken** from.
    // The verb and the label read opposite ways, which is why both are shown.
    await pumpWith(tester, [entry(label: 'block-sam', gaveAccess: false)]);

    expect(find.text('Taken from Sam'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'block-sam'), findsOneWidget);
  });

  testWidgets('an entry whose label could not be read shows no chip',
      (tester) async {
    await pumpWith(tester, [entry(label: '', gaveAccess: true)]);

    expect(find.text('Paddington'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });
}
