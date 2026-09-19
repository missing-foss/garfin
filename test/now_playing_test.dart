// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/active_session.dart';
import 'package:garfin/models/auth_session.dart';
import 'package:garfin/widgets/session_card.dart';

/// What a parent can tell from a now-playing card.
///
/// The bug behind this: an episode's own name is often nothing a parent can
/// place — "Chapter 3" — so the card has to name the show, and show its
/// artwork.
///
/// **The fields these tests parse are inferred from `BaseItemDto`, not
/// measured off a server**, which makes the negative tests the important ones.
/// They pin the behaviour when a field is absent or empty, and that is the
/// behaviour a wrong guess about a field name produces: the card as it was,
/// with no artwork and no invented URL.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AuthSession(
    serverUrl: 'http://host:8096',
    accessToken: 'token',
    userId: 'admin-1',
    userName: 'Parent',
  );

  ActiveSession parse(Map<String, dynamic> nowPlaying) => ActiveSession.fromJson(
        <String, dynamic>{
          'Id': 'session-1',
          'UserId': 'kid-1',
          'UserName': 'Emma',
          'DeviceId': 'emma-tablet',
          'DeviceName': 'emma-tablet',
          'Client': 'Jellyfin Android',
          'SupportsRemoteControl': true,
          'NowPlayingItem': nowPlaying,
          'PlayState': <String, dynamic>{'IsPaused': false},
        },
      )!;

  Map<String, dynamic> episode({
    String name = 'Sleepytime',
    String? seriesName = 'Bluey',
    String? seriesId = 'series-9',
    String? seriesTag = 'show-art',
    String? ownTag = 'episode-still',
  }) =>
      <String, dynamic>{
        'Id': 'episode-3',
        'Name': name,
        'Type': 'Episode',
        'SeriesName': ?seriesName,
        'SeriesId': ?seriesId,
        'SeriesPrimaryImageTag': ?seriesTag,
        if (ownTag != null) 'ImageTags': <String, dynamic>{'Primary': ownTag},
      };

  Map<String, dynamic> movie({String? tag = 'poster-1'}) => <String, dynamic>{
        'Id': 'movie-7',
        'Name': 'Paddington',
        'Type': 'Movie',
        if (tag != null) 'ImageTags': <String, dynamic>{'Primary': tag},
      };

  group('what the model makes of NowPlayingItem', () {
    test('an episode keeps its own name and gains the show it belongs to', () {
      final active = parse(episode());

      expect(active.nowPlayingName, 'Sleepytime');
      expect(active.showName, 'Bluey');
    });

    test("an episode's artwork is the show's poster, not the episode's still",
        () {
      // The decision this pins: the episode carries an image of its own and it
      // is deliberately not used. It is a 16:9 frame from the episode and the
      // card's box is a 2:3 poster, so cropping one into the other gives a
      // parent a rectangle they cannot place — which is the problem, not the
      // fix.
      final active = parse(episode());

      expect(active.artwork?.itemId, 'series-9');
      expect(active.artwork?.imageTag, 'show-art');
    });

    test('an episode whose show has no poster falls back to nothing', () {
      // Not to the episode still. See above — and a card with no artwork is a
      // supported state, which is what makes refusing the wrong picture cheap.
      final active = parse(episode(seriesTag: null));

      expect(active.artwork, isNull);
      expect(active.showName, 'Bluey');
    });

    test('a movie uses its own poster and has no show above it', () {
      final active = parse(movie());

      expect(active.showName, isNull);
      expect(active.artwork?.itemId, 'movie-7');
      expect(active.artwork?.imageTag, 'poster-1');
    });

    test('a movie with no poster has no artwork rather than a tagless URL', () {
      expect(parse(movie(tag: null)).artwork, isNull);
    });

    test('an empty tag counts as absent, not as a version to ask for', () {
      // A URL ending `?tag=` asks the server for image version "", which has no
      // answer — a broken poster where the placeholder was the honest answer.
      expect(parse(movie(tag: '')).artwork, isNull);
      expect(parse(episode(seriesTag: '', ownTag: null)).artwork, isNull);
    });

    test('an empty id counts as absent, exactly as an empty tag does', () {
      // Raised in review: the tags were guarded and the ids were not, so an
      // empty id arriving beside a real tag built `/Items//Images/Primary` —
      // a request for nothing, at a path that is not the item's. The guard is
      // on both halves of the reference now, because either one missing means
      // there is no picture to ask for.
      final noSeriesId = parse(episode(seriesId: ''));
      expect(noSeriesId.artwork, isNull);
      // And it does not quietly fall through to the episode's own still.
      expect(noSeriesId.showName, 'Bluey');

      expect(
        parse(<String, dynamic>{
          'Id': '',
          'Name': 'Paddington',
          'Type': 'Movie',
          'ImageTags': <String, dynamic>{'Primary': 'poster-1'},
        }).artwork,
        isNull,
      );
    });

    test('an empty series name says nothing rather than drawing a blank line',
        () {
      expect(parse(episode(seriesName: '')).showName, isNull);
    });

    test('the shape the docs actually measured still parses, and gains nothing',
        () {
      // `docs/JELLYFIN-API.md` records `Name` and `RunTimeTicks` on
      // `NowPlayingItem` and nothing else. That is the shape this feature must
      // degrade into: everything it added is absent and the card is what it
      // was.
      final active = parse(<String, dynamic>{
        'Name': 'Paddington',
        'RunTimeTicks': 1000,
      });

      expect(active.isPlaying, isTrue);
      expect(active.nowPlayingName, 'Paddington');
      expect(active.showName, isNull);
      expect(active.artwork, isNull);
    });

    test('the kind decides the poster, not which fields happen to be present',
        () {
      // Measured: the series fields are absent on a film rather than empty, so
      // probing for `SeriesId` gets the right answer for the two kinds that
      // were measured — and is not what was measured. Anything else carrying a
      // SeriesId must not be drawn with a poster chosen for an episode.
      final notAnEpisode = parse(<String, dynamic>{
        'Id': 'thing-1',
        'Name': 'Something else',
        'Type': 'Season',
        'SeriesName': 'Bluey',
        'SeriesId': 'series-9',
        'SeriesPrimaryImageTag': 'show-art',
        'ImageTags': <String, dynamic>{'Primary': 'its-own'},
      });

      expect(notAnEpisode.artwork?.itemId, 'thing-1');
      expect(notAnEpisode.artwork?.imageTag, 'its-own');
    });

    test('an episode with no show poster draws nothing, whatever else it has',
        () {
      // The episode branch does not fall through to the generic one: its own
      // primary image is the 16:9 still, and there is no third option.
      final active = parse(episode(seriesTag: null, ownTag: 'episode-still'));

      expect(active.nowPlayingType, 'Episode');
      expect(active.artwork, isNull);
    });

    test('an unrecognised kind is treated like a film, not refused', () {
      // The type is the server's own string and this app does not have the
      // list. A `Video` or a `MusicVideo` has a poster of its own and no show
      // above it, which is exactly the movie case.
      final active = parse(<String, dynamic>{
        'Id': 'thing-1',
        'Name': 'Home video',
        'Type': 'Video',
        'ImageTags': <String, dynamic>{'Primary': 'tag-v'},
      });

      expect(active.artwork?.itemId, 'thing-1');
    });
  });

  group('what the card shows', () {
    Future<void> pump(WidgetTester tester, ActiveSession active) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SessionCard(session: session, active: active),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an episode names the show, with the episode underneath it',
        (tester) async {
      // The reported bug: "Sleepytime" on its own told a parent nothing.
      await pump(tester, parse(episode()));

      expect(find.text('Watching Bluey'), findsOneWidget);
      expect(find.text('Sleepytime'), findsOneWidget);
    });

    testWidgets('a paused episode names the show too', (tester) async {
      final active = ActiveSession.fromJson(<String, dynamic>{
        'Id': 'session-1',
        'UserId': 'kid-1',
        'UserName': 'Emma',
        'DeviceId': 'emma-tablet',
        'DeviceName': 'emma-tablet',
        'Client': 'Jellyfin Android',
        'SupportsRemoteControl': true,
        'NowPlayingItem': episode(),
        'PlayState': <String, dynamic>{'IsPaused': true},
      })!;
      await pump(tester, active);

      expect(find.text('Paused — Bluey'), findsOneWidget);
      expect(find.text('Sleepytime'), findsOneWidget);
    });

    testWidgets('a film keeps the single line it always had', (tester) async {
      await pump(tester, parse(movie()));

      expect(find.text('Watching Paddington'), findsOneWidget);
    });

    testWidgets("the poster asked for is the show's, at the show's id",
        (tester) async {
      // Where a wrong id would be passed: the episode carries two of them and
      // only one is the show.
      await pump(tester, parse(episode()));

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, 'http://host:8096/Items/series-9/Images/Primary'
          '?tag=show-art');
      expect(image.imageUrl, isNot(contains('episode-3')));
    });

    testWidgets('a film asks for its own poster', (tester) async {
      await pump(tester, parse(movie()));

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl,
          'http://host:8096/Items/movie-7/Images/Primary?tag=poster-1');
    });

    testWidgets('a trailing slash on the server URL does not double up',
        (tester) async {
      const trailing = AuthSession(
        serverUrl: 'http://host:8096/',
        accessToken: 'token',
        userId: 'admin-1',
        userName: 'Parent',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SessionCard(session: trailing, active: parse(movie())),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(image.imageUrl, isNot(contains('8096//')));
    });

    testWidgets('nothing playing is still one plain line, with no picture',
        (tester) async {
      final idle = ActiveSession.fromJson(<String, dynamic>{
        'Id': 'session-1',
        'UserId': 'kid-1',
        'UserName': 'Emma',
        'DeviceId': 'emma-tablet',
        'DeviceName': 'emma-tablet',
        'Client': 'Jellyfin Android',
        'SupportsRemoteControl': true,
      })!;
      await pump(tester, idle);

      expect(find.text('Nothing playing'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('no artwork reserves no space for a picture that never comes',
        (tester) async {
      // A wrong guess about the field names lands here, and this is what it
      // must look like: the sentence, and no empty grey box beside it.
      await pump(tester, parse(movie(tag: null)));

      expect(find.text('Watching Paddington'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });
}
