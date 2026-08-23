// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/app_info.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/providers/update_providers.dart';
import 'package:garfin/screens/about_screen.dart';

import 'support/fake_jellyfin_server.dart';

/// The About screen (#66): the mark, the version, four links that open, and an
/// update check that only ever runs on a press.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeJellyfinServer github;

  Widget app() {
    github = FakeJellyfinServer();
    return ProviderScope(
      overrides: [
        updateDioProvider
            .overrideWithValue(Dio()..httpClientAdapter = github),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    );
  }

  testWidgets('shows the mark, the wordmark and the version', (tester) async {
    await tester.pumpWidget(app());

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/brand/garfin-mark.png');
    expect(find.text(appClientName), findsOneWidget);
    expect(find.textContaining(appVersion), findsWidgets);
  });

  testWidgets('the four links carry the addresses they claim', (tester) async {
    // The subtitle is the address, and it is there so that someone can see
    // where a tap goes before taking it. Asserting the strings keeps a typo
    // from shipping as a link to nowhere.
    await tester.pumpWidget(app());

    expect(find.text(sourceUrl), findsOneWidget);
    expect(find.text('$sourceUrl/issues'), findsOneWidget);
    expect(find.text('$sourceUrl/releases'), findsOneWidget);
    expect(find.text('$sourceUrl/tree/main/docs'), findsOneWidget);
    // Every one of them is tappable — the whole reason url_launcher was taken.
    expect(find.byIcon(Icons.open_in_new), findsNWidgets(4));
  });

  testWidgets('nothing is asked of GitHub until the button is pressed',
      (tester) async {
    // The privacy claim in one assertion: opening the screen contacts nobody.
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 1));

    expect(github.requests, isEmpty);
  });

  testWidgets('a press reports being up to date', (tester) async {
    await tester.pumpWidget(app());
    github.fallback(json: <dynamic>[
      <String, Object?>{
        'tag_name': 'v$appVersion',
        'html_url': 'https://example.invalid/r',
      },
    ]);

    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(github.requests, hasLength(1));
    expect(find.text('Garfin is up to date'), findsOneWidget);
  });

  testWidgets('a newer release is named, and offers to open its page',
      (tester) async {
    await tester.pumpWidget(app());
    github.fallback(json: <dynamic>[
      <String, Object?>{
        'tag_name': 'v9.9.9',
        'html_url': 'https://example.invalid/r',
      },
    ]);

    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The tag verbatim, so the screen and the releases page agree.
    expect(find.text('v9.9.9 is available'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a check that cannot reach GitHub says so and stays usable',
      (tester) async {
    await tester.pumpWidget(app());
    github.fallback(status: 500);

    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Couldn't read GitHub's answer."), findsOneWidget);
    // Not stuck spinning: the button must come back, or one bad answer ends
    // the feature until the app is restarted.
    // `bySubtype`, not `byType`: `FilledButton.tonalIcon` builds a private
    // subclass, and `byType` compares runtime types exactly — it finds nothing
    // and the test then fails on an empty iterable rather than on the button's
    // state, which is a confusing way to learn that.
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Check for updates'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  group('the bundled mark', () {
    test('exists at every density and is the mark, not a placeholder',
        () async {
      // Same lesson as the launcher icon (#67): a file that exists and is
      // non-empty can still be the wrong picture. `garfin-mark.svg` is the
      // source; these are output, and the brand lilac is what says the render
      // actually produced the fish.
      for (final path in [
        'assets/brand/garfin-mark.png',
        'assets/brand/2.0x/garfin-mark.png',
        'assets/brand/3.0x/garfin-mark.png',
      ]) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing $path');

        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        final data =
            await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        var lilac = 0;
        var opaque = 0;
        for (var i = 0; i < data!.lengthInBytes; i += 4) {
          if (data.getUint8(i + 3) == 0) continue;
          opaque++;
          if (data.getUint8(i) == 0xB6 &&
              data.getUint8(i + 1) == 0x9D &&
              data.getUint8(i + 2) == 0xF8) {
            lilac++;
          }
        }
        expect(opaque, greaterThan(0), reason: '$path is entirely transparent');
        expect(lilac, greaterThan(0),
            reason: '$path has no brand lilac — it is not the mark');
      }
    });

    test('the generator that made them is in the repo', () {
      final script = File('brand/make-app-assets.sh');
      expect(script.existsSync(), isTrue);
      expect(script.readAsStringSync(), contains('garfin-mark.svg'));
    });
  });
}
