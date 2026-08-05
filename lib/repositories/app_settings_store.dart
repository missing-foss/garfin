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

  /// Material You where the platform offers it. On by default — `CLAUDE.md`
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

/// How many tiles fit across at [size], on a screen [width] logical pixels wide.
///
/// The narrow-screen rule that was in `library_screen.dart` lives here so it can
/// be tested without pumping a grid: below 400dp one column comes off whatever
/// the setting says, because `docs/UI-SPEC.md`'s three columns on a small phone
/// are stamps.
int columnsFor(PosterSize size, double width) {
  final base = switch (size) {
    PosterSize.large => 2,
    PosterSize.regular => 3,
    PosterSize.small => 4,
  };
  return width < 400 ? base - 1 : base;
}
