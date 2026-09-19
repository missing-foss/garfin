// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/app_settings_store.dart';
import 'app_providers.dart';

/// Every Settings value, as one immutable snapshot.
///
/// One object rather than a provider per key so a screen cannot watch half of
/// them: `MaterialApp` depends on two of these, and a rebuild that missed one
/// would leave the theme and the colour scheme disagreeing for a frame.
class GarfinSettings {
  const GarfinSettings({
    required this.collectionPrompt,
    required this.refreshAfterWrite,
    required this.hideShared,
    required this.allowScreenshots,
    required this.themeMode,
    required this.dynamicColour,
    required this.posterSize,
    required this.librarySort,
    required this.librarySortDescending,
  });

  factory GarfinSettings.from(AppSettingsStore store) => GarfinSettings(
        collectionPrompt: store.collectionPrompt,
        refreshAfterWrite: store.refreshAfterWrite,
        hideShared: store.hideShared,
        allowScreenshots: store.allowScreenshots,
        themeMode: store.themeMode,
        dynamicColour: store.dynamicColour,
        posterSize: store.posterSize,
        librarySort: store.librarySort,
        librarySortDescending: store.librarySortDescending,
      );

  final CollectionPrompt collectionPrompt;
  final bool refreshAfterWrite;
  final bool hideShared;
  final bool allowScreenshots;
  final ThemeMode themeMode;
  final bool dynamicColour;
  final PosterSize posterSize;
  final LibrarySort librarySort;
  final bool librarySortDescending;
}

final appSettingsStoreProvider = Provider<AppSettingsStore>(
  (ref) => AppSettingsStore(ref.watch(sharedPreferencesProvider)),
);

/// Reads the store once, then holds the values.
///
/// Every setter writes through to `shared_preferences` **and** replaces the
/// state, so what the screen shows and what the next launch reads cannot drift.
class SettingsController extends Notifier<GarfinSettings> {
  @override
  GarfinSettings build() =>
      GarfinSettings.from(ref.watch(appSettingsStoreProvider));

  AppSettingsStore get _store => ref.read(appSettingsStoreProvider);

  Future<void> setCollectionPrompt(CollectionPrompt value) async {
    await _store.setCollectionPrompt(value);
    state = GarfinSettings.from(_store);
  }

  Future<void> setRefreshAfterWrite(bool value) async {
    await _store.setRefreshAfterWrite(value);
    state = GarfinSettings.from(_store);
  }

  /// Pushes to the window **first**, and stores the answer only if it applied.
  ///
  /// That order is the whole of the invariant: the preference follows the
  /// window rather than leading it, so the store can never claim a state the
  /// window is not in. A push that fails leaves the switch where it was, which
  /// a parent can see, rather than leaving them believing protection is back
  /// when it is not.
  Future<void> setAllowScreenshots(bool value) async {
    final applied = await ref
        .read(windowSecurityProvider)
        .setScreenshotsAllowed(allowed: value);
    if (!applied) return;
    await _store.setAllowScreenshots(value);
    state = GarfinSettings.from(_store);
  }

  Future<void> setHideShared(bool value) async {
    await _store.setHideShared(value);
    state = GarfinSettings.from(_store);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _store.setThemeMode(value);
    state = GarfinSettings.from(_store);
  }

  Future<void> setDynamicColour(bool value) async {
    await _store.setDynamicColour(value);
    state = GarfinSettings.from(_store);
  }

  Future<void> setPosterSize(PosterSize value) async {
    await _store.setPosterSize(value);
    state = GarfinSettings.from(_store);
  }

  Future<void> setLibrarySort(LibrarySort value) async {
    await _store.setLibrarySort(value);
    state = GarfinSettings.from(_store);
  }

  Future<void> setLibrarySortDescending({required bool value}) async {
    await _store.setLibrarySortDescending(value: value);
    state = GarfinSettings.from(_store);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, GarfinSettings>(SettingsController.new);
