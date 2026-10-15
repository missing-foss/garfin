// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/l10n/app_delegates.dart';
import 'package:garfin/l10n/gen/app_localizations.dart';
import 'package:garfin/models/age_suitability.dart';
import 'package:garfin/models/library_item.dart';
import 'package:garfin/repositories/library_repository.dart';
import 'package:garfin/widgets/library_tile.dart';
import 'package:garfin/widgets/server_image.dart';

/// Images are asked for, and decoded at, the size they are shown: a poster
/// at Jellyfin's full resolution decodes to 6 MB.
void main() {
  group('coverWidthPx', () {
    test('a poster filling a poster-shaped slot needs the slot width', () {
      expect(coverWidthPx(120, 180, 2 / 3, 3), 360);
    });

    test('a slot taller than the poster needs the width its height implies', () {
      // Covering 100x300 scales a 2:3 poster to 200 wide.
      expect(coverWidthPx(100, 300, 2 / 3, 1), 240);
    });

    test('a square avatar needs its side', () {
      expect(coverWidthPx(36, 36, 1, 3), 120);
    });

    test('widths round up to the next step, never down', () {
      expect(coverWidthPx(121, 0, 2 / 3, 1), 240);
      expect(coverWidthPx(120, 0, 2 / 3, 1), 120);
    });

    test('a slot with no finite size asks for nothing in particular', () {
      expect(coverWidthPx(double.infinity, double.infinity, 2 / 3, 3), isNull);
    });
  });

  test('withMaxWidth adds to an existing query or starts one', () {
    expect(withMaxWidth('http://h/Items/a/Images/Primary?tag=t', 360),
        'http://h/Items/a/Images/Primary?tag=t&maxWidth=360');
    expect(withMaxWidth('http://h/Items/a/Images/Primary', 360),
        'http://h/Items/a/Images/Primary?maxWidth=360');
  });

  testWidgets('a library tile asks Jellyfin for its own width and decodes at it',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 118,
            height: 300,
            child: LibraryTile(
              entry: const LibraryEntry(
                item: LibraryItem(
                  id: 'a',
                  name: 'Paddington',
                  type: 'Movie',
                  tags: [],
                  primaryImageTag: 'poster-1',
                ),
                state: LibraryItemState.unknown,
              ),
              serverUrl: 'http://host:8096',
              childName: 'Emma',
              suitability: AgeSuitability.unknown,
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    final shown = tester.getSize(find.byType(CachedNetworkImage));
    final px = coverWidthPx(shown.width, shown.height, 2 / 3, 3)!;
    expect(px, lessThan(1000), reason: 'the request is the tile, not the original');
    expect(px, greaterThanOrEqualTo(shown.width * 3));
    expect(image.imageUrl, 'http://host:8096/Items/a/Images/Primary?tag=poster-1&maxWidth=$px');
    expect(image.memCacheWidth, px);
  });
}
