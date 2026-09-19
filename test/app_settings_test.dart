// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:garfin/models/collection_set.dart';
import 'package:garfin/models/jellyfin_user.dart';
import 'package:garfin/models/tag_diff.dart';
import 'package:garfin/repositories/app_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings, and mostly its **defaults** — which are the part a user never
/// chooses and every user gets.
///
/// `docs/DECISIONS.md` argues for three of them by name: hide-shared on, so the
/// grid is a to-do list; ask-each-time for the collection question, because
/// "Jurassic Park" and "Jurassic Park III" are not the same decision; and
/// dark-first. A default that drifts is a decision quietly reversed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppSettingsStore> store([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    return AppSettingsStore(await SharedPreferences.getInstance());
  }

  group('the defaults are the decisions', () {
    test('nothing set at all', () async {
      final s = await store();

      expect(s.collectionPrompt, CollectionPrompt.ask);
      expect(s.refreshAfterWrite, isFalse);
      expect(s.hideShared, isTrue);
      expect(s.themeMode, ThemeMode.dark);
      expect(s.dynamicColour, isTrue);
      expect(s.posterSize, PosterSize.regular);
      // Name, ascending: what every install did before the setting existed, so
      // nobody's grid changes until they change it.
      expect(s.librarySort, LibrarySort.name);
      expect(s.librarySortDescending, isFalse);
    });

    test('refresh-after-write is off, because it is the slow one', () async {
      // Not because it is dangerous: the dangerous parameter is not reachable
      // (see `JellyfinApi.refreshItem`). It is one more round-trip per title.
      expect((await store()).refreshAfterWrite, isFalse);
    });

    test('a value written by some later version reads as the default',
        () async {
      // Forward compatibility that fails toward asking rather than toward
      // deciding for the parent.
      final s = await store({
        'labels_collection_prompt': 'whatever-comes-next',
        'looks_theme_mode': 'sepia',
        'looks_poster_size': 'enormous',
        'looks_library_sort': 'by-colour',
      });

      expect(s.collectionPrompt, CollectionPrompt.ask);
      expect(s.themeMode, ThemeMode.dark);
      expect(s.posterSize, PosterSize.regular);
      expect(s.librarySort, LibrarySort.name);
    });
  });

  group('every value survives a write and a re-read', () {
    test('round-trip', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsStore(prefs);

      await s.setCollectionPrompt(CollectionPrompt.always);
      await s.setRefreshAfterWrite(true);
      await s.setHideShared(false);
      await s.setThemeMode(ThemeMode.light);
      await s.setDynamicColour(false);
      await s.setPosterSize(PosterSize.small);

      // A second store over the same preferences, which is what the next
      // launch is.
      final reread = AppSettingsStore(prefs);
      expect(reread.collectionPrompt, CollectionPrompt.always);
      expect(reread.refreshAfterWrite, isTrue);
      expect(reread.hideShared, isFalse);
      expect(reread.themeMode, ThemeMode.light);
      expect(reread.dynamicColour, isFalse);
      expect(reread.posterSize, PosterSize.small);
    });

    // "the starting child can be cleared back to Everyone" stood here. The
    // setting is gone: the Library opens on Everyone from the navigation and
    // on a child from that child's face, so a remembered default answered a
    // question the parent had not asked on every visit but the first. Removed
    // with the feature rather than left asserting about a key nothing writes.
  });

  group('poster size is a target width, not a column count (#95)', () {
    test('each size targets its own poster width', () {
      expect(posterTargetWidth(PosterSize.large), 360);
      expect(posterTargetWidth(PosterSize.regular), 175);
      expect(posterTargetWidth(PosterSize.small), 112);
    });

    /// The old `columnsFor` mapped the setting to 2/3/4 columns and took one
    /// off below 400dp. Those numbers are now consequences of the target rather
    /// than special cases, and they are asserted where they can actually be
    /// *observed* — `library_grid_width_test.dart` pumps the grid and measures
    /// the tiles. Pinning the arithmetic here as well would only re-implement
    /// Flutter's delegate in the test, which is the copy that drifts.
    test('the order is the one a parent expects', () {
      expect(
        posterTargetWidth(PosterSize.large),
        greaterThan(posterTargetWidth(PosterSize.regular)),
      );
      expect(
        posterTargetWidth(PosterSize.regular),
        greaterThan(posterTargetWidth(PosterSize.small)),
      );
    });
  });

  group('the collection prompt decides before any dialog', () {
    final emma = JellyfinUser(
      id: 'kid-1',
      name: 'Emma',
      policy: const UserPolicy(
        isAdministrator: false,
        isDisabled: false,
        allowedTags: ['kids-emma'],
      ),
    );
    final give = TagDiff([
      TagChange(child: emma, label: 'kids-emma', adding: true),
    ]);
    final take = TagDiff([
      TagChange(child: emma, label: 'kids-emma', adding: false),
    ]);

    test('ask is the default plan for an addition', () {
      expect(
        cascadePlanFor(diff: give, prompt: CollectionPrompt.ask),
        CascadePlan.ask,
      );
    });

    test('always cascades without asking', () {
      expect(
        cascadePlanFor(diff: give, prompt: CollectionPrompt.always),
        CascadePlan.all,
      );
    });

    test('never cascades nothing, and so looks nothing up', () {
      expect(
        cascadePlanFor(diff: give, prompt: CollectionPrompt.never),
        CascadePlan.none,
      );
    });

    test('a removal never cascades, whatever the setting says', () {
      // Ground rule 6 outranks the preference: it is about the app being
      // predictable, not about taste. "Hand over the whole set" must not turn
      // into "take the whole set away".
      for (final prompt in CollectionPrompt.values) {
        expect(
          cascadePlanFor(diff: take, prompt: prompt),
          CascadePlan.none,
          reason: 'a removal cascaded under $prompt',
        );
      }
    });
  });
}
