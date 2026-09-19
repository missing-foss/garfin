// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/library_filters.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/kid_summary.dart';
import 'package:garfin/models/parental_rating.dart';
import 'package:garfin/providers/app_providers.dart';
import 'package:garfin/providers/kids_providers.dart';
import 'package:garfin/providers/library_providers.dart';
import 'package:garfin/repositories/device_identity.dart';
import 'package:garfin/repositories/jellyfin_api.dart';
import 'package:garfin/screens/library_screen.dart';
import 'package:garfin/widgets/library_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_jellyfin_server.dart';

/// What a tile says while a new child's query is in flight (#96).
///
/// #94 stopped the grid blanking to a spinner on every refresh, which is right
/// — a write, a pull-to-refresh and an Undo all happen constantly and all used
/// to throw away the tiles the parent was looking at. It applies to *every*
/// dependency change though, and choosing a different child is one, so the
/// previous child's feed now stays on screen for as long as the new query
/// takes: up to half a second, measured.
///
/// Every per-child marker on those tiles was computed for somebody else.
/// Measured on this branch, one frame after selecting Léo:
///
///     before the fix:  Paddington. Leo has this, but the server isn't
///                      showing it to them. Their age limit is the usual
///                      reason.
///     after:           Paddington. Given to Emma
///
/// He had never been given it. That is the one shape of claim this app is most
/// careful about — ground rule 4 exists to stop it — and it was being said in
/// a sentence naming a specific child.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  JellyfinUser kid(String name, String tag) => JellyfinUser(
        id: 'id-$name',
        name: name,
        policy: UserPolicy(
          isAdministrator: false,
          isDisabled: false,
          allowedTags: [tag],
          blockedTags: const [],
        ),
      );

  testWidgets('a tile says nothing about a child it was not computed for',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final emma = kid('Emma', 'kids-emma');
    final leo = kid('Leo', 'kids-leo');

    // Léo's birth year, so the age hint has something to say about the child
    // who is selected *after* the switch. Without it every hint is "not
    // known", which this screen no longer draws at all — and the distinction
    // this test exists for would have nothing to stand on.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'birth_year_id-Leo': DateTime.now().year - 9,
    });
    final prefs = await SharedPreferences.getInstance();
    final server = FakeJellyfinServer()
      // One film, tagged for Emma. The visibility lookup says the server does
      // NOT show it to her, so it classifies as given-but-hidden for Emma.
      ..onQuery('/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] == 0,
          json: {
            'TotalRecordCount': 1,
            'Items': [
              <String, dynamic>{
                'Id': 'item-1',
                'Name': 'Paddington',
                'Type': 'Movie',
                'Tags': ['kids-emma'],
                'OfficialRating': '15',
              },
            ],
          })
      ..onQuery('/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] != 0,
          json: {'TotalRecordCount': 1, 'Items': <Object>[]})
      ..onQuery('/Items', (q) => q.containsKey('ids'),
          json: {'TotalRecordCount': 0, 'Items': <Object>[]})
      ..fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});

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
      kidsOverviewProvider(session).overrideWith(
        (ref) async => KidsOverview(
          shortlisted: [
            KidSummary(user: emma),
            KidSummary(user: leo),
          ],
          withoutShortlist: const [],
        ),
      ),
      // A ladder with a rung the film's rating lands on, so the hint is a real
      // comparison rather than "not known".
      parentalRatingLadderProvider(session).overrideWith(
        (ref) async => const ParentalRatingLadder(
          [ParentalRating(name: '15', value: 15)],
        ),
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(kidsOverviewProvider(session).future);
    container.read(pickingForProvider.notifier).select(emma.id);
    // This test is not about which slice is shown; show all of it.
    container.read(libraryViewProvider.notifier).set(LibraryView.all);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // The control: with Emma selected, the tile does say Emma's sentence.
    // Without this the test would pass over a grid that never classified
    // anything at all.
    expect(tester.getSemantics(find.byType(LibraryTile)).label,
        contains("Emma has this, but the server isn't showing it to them"));
    expect(find.text('Held back'), findsOneWidget);

    // Switch to Léo and look at the very next frame.
    container.read(pickingForProvider.notifier).select(leo.id);
    await tester.pump();

    // The tiles stay — that is #94 working, and throwing them away is the
    // cure that is worse than the disease.
    expect(find.byType(LibraryTile), findsOneWidget);
    expect(find.text('Paddington'), findsOneWidget);

    final mid = tester.getSemantics(find.byType(LibraryTile)).label;
    expect(mid, isNot(contains('Leo has this')),
        reason: 'the tile made a claim about a child it was not computed for');
    expect(mid, isNot(contains("isn't showing it to them")));
    expect(find.text('Held back'), findsNothing,
        reason: 'the badge is a per-child claim too');

    // The avatar row is untouched, because it is not relative to the
    // selection: it says who *has* the title, which is as true mid-flight as
    // after. (The issue expected this to need suppressing; it does not.)
    expect(mid, contains('Given to Emma'));

    // And neither is the age hint, which is the other half of the same
    // distinction: it is computed on this screen from the *current* child's
    // age against the item's own rating, so it already describes Léo.
    // Suppressing everything per-child would have removed a true statement
    // and made the hint flicker on every switch.
    //
    // It used to be enough to find "No age rating" here, because that was
    // drawn for every unrated title. The grid no longer says anything for an
    // unrated one, so the distinction is pinned with the hint that does still
    // speak — and it names Léo, one frame after the switch, while every stale
    // claim about him is withheld.
    expect(find.text("Above Leo's age"), findsOneWidget,
        reason: 'the fresh age hint was suppressed along with the stale ones');

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // And once the new feed lands, the tile speaks about Léo again: he has not
    // been given it, so there is no badge and no held-back sentence.
    final after = tester.getSemantics(find.byType(LibraryTile)).label;
    expect(after, isNot(contains('Leo has this')));
    expect(after, contains('Given to Emma'));
  });

  testWidgets('a narrowed grid shows nothing rather than the wrong rows',
      (tester) async {
    // The half `classifiedFor` could not reach. Substituting `unknown` fixes a
    // stale *label*; in a view that narrows by child the stale feed contains
    // the wrong **items**, and there is no substitution for a row that should
    // not be on screen. Reported as "the displayed media are not the correct
    // one despite the fact that the library seems to reload".
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final emma = kid('Emma', 'kids-emma');
    final leo = kid('Leo', 'kids-leo');

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeJellyfinServer()
      ..onQuery(
          '/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] == 0,
          json: {
            'TotalRecordCount': 1,
            'Items': [
              <String, dynamic>{
                'Id': 'item-1',
                'Name': 'Paddington',
                'Type': 'Movie',
                'Tags': ['kids-emma'],
              },
            ],
          })
      ..onQuery(
          '/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] != 0,
          json: {'TotalRecordCount': 1, 'Items': <Object>[]})
      ..onQuery('/Items', (q) => q.containsKey('ids'),
          json: {'TotalRecordCount': 0, 'Items': <Object>[]})
      ..fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});

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
      kidsOverviewProvider(session).overrideWith(
        (ref) async => KidsOverview(
          shortlisted: [KidSummary(user: emma), KidSummary(user: leo)],
          withoutShortlist: const [],
        ),
      ),
      parentalRatingLadderProvider(session)
          .overrideWith((ref) async => const ParentalRatingLadder.empty()),
    ]);
    addTearDown(container.dispose);
    await container.read(kidsOverviewProvider(session).future);
    container.read(pickingForProvider.notifier).select(emma.id);
    // Where a face tap lands, and the view the report was made against.
    container.read(libraryViewProvider.notifier).set(LibraryView.given);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // The control: Emma's own row is there, so a failure below means the row
    // was withheld rather than that nothing ever rendered.
    expect(find.text('Paddington'), findsOneWidget);

    container.read(pickingForProvider.notifier).select(leo.id);
    await tester.pump();

    expect(find.text('Paddington'), findsNothing,
        reason: 'that row is in the grid because of Emma\'s labels, and Léo '
            'is selected');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the honest state while the right rows are on their way');

    // Let the new query finish: dio arms a receiveTimeout timer per response
    // and cancels it when the body is drained, so a test that ends mid-request
    // trips the framework's pending-timer check.
    // Tear the tree down before the test ends: something on the error branch
    // arms a timer, and pumping only lets it re-arm. Disposing the widget
    // cancels it, which is what the framework's pending-timer check wants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('and a refresh of the same child still keeps its tiles',
      (tester) async {
    // The guard #94 put there, which this must narrow rather than undo: a
    // write, a pull-to-refresh and an Undo all reload the same child, and
    // throwing the tiles away on each was the bug #94 fixed. Only a change of
    // child reaches the new branch.
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final emma = kid('Emma', 'kids-emma');

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeJellyfinServer()
      ..onQuery(
          '/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] == 0,
          json: {
            'TotalRecordCount': 1,
            'Items': [
              <String, dynamic>{
                'Id': 'item-1',
                'Name': 'Paddington',
                'Type': 'Movie',
                'Tags': ['kids-emma'],
              },
            ],
          })
      ..onQuery(
          '/Items', (q) => q.containsKey('StartIndex') && q['StartIndex'] != 0,
          json: {'TotalRecordCount': 1, 'Items': <Object>[]})
      ..onQuery('/Items', (q) => q.containsKey('ids'),
          json: {'TotalRecordCount': 0, 'Items': <Object>[]})
      ..fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});

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
      kidsOverviewProvider(session).overrideWith(
        (ref) async => KidsOverview(
          shortlisted: [KidSummary(user: emma)],
          withoutShortlist: const [],
        ),
      ),
      parentalRatingLadderProvider(session)
          .overrideWith((ref) async => const ParentalRatingLadder.empty()),
    ]);
    addTearDown(container.dispose);
    await container.read(kidsOverviewProvider(session).future);
    container.read(pickingForProvider.notifier).select(emma.id);
    container.read(libraryViewProvider.notifier).set(LibraryView.given);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Paddington'), findsOneWidget);

    // What `refreshLibrary` does, from a container rather than a WidgetRef.
    container.read(libraryRevisionProvider.notifier).bump();
    await tester.pump();

    expect(find.text('Paddington'), findsOneWidget,
        reason: 'same child, same rows — the tiles must survive a refresh');

    // Tear the tree down before the test ends: something on the error branch
    // arms a timer, and pumping only lets it re-arm. Disposing the widget
    // cancels it, which is what the framework's pending-timer check wants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a failed load says so rather than spinning forever',
      (tester) async {
    // The case the suite had no example of: the library load *fails* while a
    // child is selected. Withholding a stale success is right; withholding a
    // failure leaves an indeterminate spinner and no sentence, and no control
    // on screen recovers from it — the button that leaves a narrowed view
    // lives in the data branch, and Try again lives in the error branch.
    //
    // `toGive` rather than `given`, because it is the default view: this is an
    // ordinary cold start against a server that is down or a token that has
    // expired, not an exotic path.
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final emma = kid('Emma', 'kids-emma');

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeJellyfinServer()
      // The page query fails. A 500 rather than a transport error on purpose:
      // both land in the same error branch, and a connection error puts a
      // retry with a quadrupling backoff behind it — the timer outruns any
      // amount of pumping, so the test could never end cleanly.
      ..onQuery('/Items', (q) => q.containsKey('StartIndex'), status: 500)
      ..fallback(json: {'Items': <Object>[], 'TotalRecordCount': 0});

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
      kidsOverviewProvider(session).overrideWith(
        (ref) async => KidsOverview(
          shortlisted: [KidSummary(user: emma)],
          withoutShortlist: const [],
        ),
      ),
      parentalRatingLadderProvider(session)
          .overrideWith((ref) async => const ParentalRatingLadder.empty()),
    ]);
    addTearDown(container.dispose);
    await container.read(kidsOverviewProvider(session).future);
    container.read(pickingForProvider.notifier).select(emma.id);
    container.read(libraryViewProvider.notifier).set(LibraryView.toGive);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryScreen(session: session)),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Try again'), findsOneWidget,
        reason: 'a spinner is an honest answer to loading, not to failed');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Drain the failed requests' timers: dio arms one per response and cancels
    // it when the body is drained, and a connection error leaves the same
    // machinery to unwind.
    // Tear the tree down before the test ends: something on the error branch
    // arms a timer, and pumping only lets it re-arm. Disposing the widget
    // cancels it, which is what the framework's pending-timer check wants.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
