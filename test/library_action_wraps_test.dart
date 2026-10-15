// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/collection_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';
import 'support/roster_from_overview.dart';

/// The result line's action says what it does in full, in every language.
///
/// It shares a row with the result text. Held to one line, the French
/// "Afficher ce qu'il reste à donner" was cut to "Afficher ce qu'il reste à …"
/// on a phone, and the action no longer said where it went. It wraps instead,
/// as the text beside it does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );
  const leo = JellyfinUser(
    id: 'kid-leo',
    name: 'Leo',
    policy: UserPolicy(
      isAdministrator: false,
      isDisabled: false,
      allowedTags: ['kids-leo'],
      blockedTags: [],
    ),
  );

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    required Locale locale,
    required double width,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    // One film Leo has, so the grid draws and the result line with it.
    final server = FakeJellyfinServer()
      ..fallback(json: <String, dynamic>{
        'Items': <Object>[
          <String, dynamic>{
            'Id': 'item-1',
            'Name': 'Marble Run',
            'Type': 'Movie',
            'Tags': <String>['kids-leo'],
          },
        ],
        'TotalRecordCount': 2,
      });
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      deviceIdentityProvider.overrideWithValue(
        const DeviceIdentity(deviceId: 'd', deviceName: 't'),
      ),
      jellyfinApiFactoryProvider.overrideWithValue(
        JellyfinApiFactory(
          identity: const DeviceIdentity(deviceId: 'd', deviceName: 't'),
          adapter: server,
        ),
      ),
      rosterFromOverview(session),
      kidsOverviewProvider(session).overrideWith(
        (ref) async => const KidsOverview(
          shortlisted: [KidSummary(user: leo)],
          withoutShortlist: [],
        ),
      ),
      parentalRatingLadderProvider(session)
          .overrideWith((ref) async => const ParentalRatingLadder.empty()),
      collectionIndexProvider(session)
          .overrideWith((ref) async => const CollectionIndex.empty()),
    ]);
    addTearDown(container.dispose);
    await container.read(kidsOverviewProvider(session).future);
    await container.read(kidsRosterProvider(session).future);
    container.read(pickingForProvider.notifier).select(leo.id);
    // Where a face tap lands, and where the long label is.
    container.read(libraryViewProvider.notifier).set(LibraryView.given);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(LibraryScreen)));
  }

  for (final locale in const [Locale('fr'), Locale('en')]) {
    for (final width in const <double>[360, 412]) {
      testWidgets('the action is laid out whole: $locale at ${width.toInt()}dp',
          (tester) async {
        final l10n = await pump(tester, locale: locale, width: width);

        final label = find.text(l10n.libraryShowToGive);
        expect(label, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse,
            reason: '"${l10n.libraryShowToGive}" was cut short');
        expect(tester.takeException(), isNull, reason: 'and the row fits');
      });
    }
  }
}
