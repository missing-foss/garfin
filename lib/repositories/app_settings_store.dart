// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// What to do when a film being handed over belongs to a collection.
///
/// `docs/DECISIONS.md` § Collections: the default is **ask each time**, "because
/// 'Jurassic Park' and 'Jurassic Park III' are not the same decision". The other
/// two answers exist for households where they are.
///
/// Only additions are ever affected. Ground rule 6 — removing a label never
/// cascades — so [never] is not the mirror of [always]; it is "treat a film in
/// a set as a film".
enum CollectionPrompt {
  /// Ask, every time. The default, and the only value that shows the other
  /// titles and their ratings before deciding.
  ask,

  /// Always hand over the whole set.
  always,

  /// Never cascade: the tapped title only.
  never,
}

/// How big the posters are, which is really how many fit across.
enum PosterSize { large, regular, small }

/// The Settings screen's state, minus Unlock, which has its own store.
///
/// All preferences, no credentials — `shared_preferences` is right for every
/// key here, and none of them may ever be used to authenticate. The token lives
/// in `TokenStore` and the rule is in `SECURITY.md`.
class AppSettingsStore {
  const AppSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _collectionPromptKey = 'labels_collection_prompt';
  static const _refreshAfterWriteKey = 'labels_refresh_after_write';
  static const _startingChildKey = 'picking_starting_child';
  static const _hideSharedKey = 'picking_hide_shared';
  static const _themeModeKey = 'looks_theme_mode';
  static const _dynamicColourKey = 'looks_dynamic_colour';
  static const _posterSizeKey = 'looks_poster_size';

  CollectionPrompt get collectionPrompt => switch (
          _prefs.getString(_collectionPromptKey)) {
        'always' => CollectionPrompt.always,
        'never' => CollectionPrompt.never,
        // Anything else, including a value written by a later version, means
        // ask — the answer that takes no decision on the parent's behalf.
        _ => CollectionPrompt.ask,
      };

  Future<void> setCollectionPrompt(CollectionPrompt value) =>
      _prefs.setString(_collectionPromptKey, value.name);

  /// Whether to ask Jellyfin to re-read an item's metadata after a write.
  ///
  /// **Off by default, and the reason is in `docs/JELLYFIN-API.md`.** The safe
  /// call is `Refresh?metadataRefreshMode=FullRefresh`, which measured leaves
  /// Garfin's tag alone; the same call with `replaceAllMetadata=true` wipes it.
  /// The app must never send the second one — see `JellyfinApi.refreshItem`,
  /// which cannot.
  bool get refreshAfterWrite => _prefs.getBool(_refreshAfterWriteKey) ?? false;

  Future<void> setRefreshAfterWrite(bool value) =>
      _prefs.setBool(_refreshAfterWriteKey, value);

  /// The child the Library opens on, or null for Everyone.
  ///
  /// A user id rather than a name: names are not unique on a Jellyfin server
  /// and can be changed without the account changing.
  String? get startingChildId {
    final value = _prefs.getString(_startingChildKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> setStartingChildId(String? value) => value == null
      ? _prefs.remove(_startingChildKey)
      : _prefs.setString(_startingChildKey, value);

  /// On by default: `docs/DECISIONS.md` § Product shape — hiding already-shared
  /// titles turns the grid into a to-do list rather than an inventory.
  bool get hideShared => _prefs.getBool(_hideSharedKey) ?? true;

  Future<void> setHideShared(bool value) =>
      _prefs.setBool(_hideSharedKey, value);

  /// Dark by default. The app is used in the evening, on a sofa.
  ThemeMode get themeMode => switch (_prefs.getString(_themeModeKey)) {
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        _ => ThemeMode.dark,
      };

  Future<void> setThemeMode(ThemeMode value) =>
      _prefs.setString(_themeModeKey, value.name);

  /// Material You where the platform offers it. On by default — `docs/ENGINEERING.md`
  /// § Stack asks for `DynamicColorBuilder`, and this is how it is turned off
  /// by someone who would rather have the brand seed.
  bool get dynamicColour => _prefs.getBool(_dynamicColourKey) ?? true;

  Future<void> setDynamicColour(bool value) =>
      _prefs.setBool(_dynamicColourKey, value);

  PosterSize get posterSize => switch (_prefs.getString(_posterSizeKey)) {
        'large' => PosterSize.large,
        'small' => PosterSize.small,
        _ => PosterSize.regular,
      };

  Future<void> setPosterSize(PosterSize value) =>
      _prefs.setString(_posterSizeKey, value.name);
}

/// How wide a poster should aim to be at [size], in logical pixels.
///
/// **A target width, not a column count (#95).** The grid used to map the
/// setting to a fixed 2/3/4 columns with one taken off below 400dp, which has
/// no upper end: the same three columns were used at 412dp and at 1280dp, so a
/// tablet in landscape drew posters 3.4x wider than the phone they were
/// designed for — ~703dp tall against a ~800dp viewport, so not one complete
/// row was visible. At the large setting a single poster was taller than the
/// screen.
///
/// Handing the delegate a maximum extent instead makes the column count fall
/// out of the window, so the grid is right at widths nobody has thought of —
/// tablets, foldables, split-screen, desktop — rather than at the three this
/// function used to know about. It is also closer to what the setting already
/// means to a parent: "how big should the pictures be", not "how many fit".
///
/// **A continuous rule cannot reproduce the old cliff, and these numbers do not
/// pretend to.** The old mapping dropped a column below a hard boundary at
/// 400dp. Flutter's `SliverGridDelegateWithMaxCrossAxisExtent` takes
/// `ceil(extent / (max + spacing))` columns, so with the grid's own 16dp
/// padding either side and 12dp spacing, the crossover lands wherever the
/// arithmetic puts it. Forcing it onto 400 exactly pins `small` into a ~0.3dp
/// window and `large` into a ~1dp one — fitted constants that the next change
/// to padding or aspect ratio would silently break.
///
/// So the question is **which band moves**, and these targets are chosen to put
/// it where it does least harm:
///
///     width | small          | regular        | large
///     ------+----------------+----------------+----------------
///       360 | 3c 101.3dp     | 2c 158.0dp     | 1c 328.0dp
///       384 | 3c 109.3dp     | 2c 170.0dp     | 1c 352.0dp
///       393 | 3c 112.3dp     | 2c 174.5dp     | 1c 361.0dp
///       399 | 3c 114.3dp     | 2c 177.5dp     | 1c 367.0dp
///       400 | 3c 114.7dp *   | 2c 178.0dp *   | 1c 368.0dp *
///       404 | 3c 116.0dp *   | 2c 180.0dp *   | 1c 372.0dp *
///       406 | 4c  84.5dp     | 2c 181.0dp *   | 2c 181.0dp
///       412 | 4c  86.0dp     | 3c 118.7dp     | 2c 184.0dp
///       800 | 7c  99.4dp *   | 5c 144.0dp *   | 3c 248.0dp *
///      1280 | 11c 102.5dp *  | 7c 168.0dp *   | 4c 303.0dp *
///
///     * differs from the old fixed-count mapping
///
/// **Every phone width below 400dp is unchanged**, which is the half that
/// matters: 393dp is a Pixel 4a / 5 / 5a, and an earlier draft of these numbers
/// (105/165/330) gave *three* columns there at the default setting — posters
/// 36% smaller, on real hardware, which is precisely what the deleted rule
/// existed to prevent. Caught in review of #95.
///
/// What moves instead is **400–406dp**, where a window now gets one column
/// fewer than the old mapping gave it. That direction is the safe one — posters
/// get bigger, not smaller — and it is the band the old code least meant
/// anything by: its boundary at exactly 400 was a round number, not a measured
/// one. It does mean `docs/UI-SPEC.md`'s old "2 columns under 400dp" now
/// effectively reads "under about 406dp", which is written down there.
double posterTargetWidth(PosterSize size) => switch (size) {
      PosterSize.large => 360,
      PosterSize.regular => 175,
      PosterSize.small => 112,
    };
