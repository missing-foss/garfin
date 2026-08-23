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
    required this.startingChildId,
    required this.hideShared,
    required this.themeMode,
    required this.dynamicColour,
    required this.posterSize,
  });

  factory GarfinSettings.from(AppSettingsStore store) => GarfinSettings(
        collectionPrompt: store.collectionPrompt,
        refreshAfterWrite: store.refreshAfterWrite,
        startingChildId: store.startingChildId,
        hideShared: store.hideShared,
        themeMode: store.themeMode,
        dynamicColour: store.dynamicColour,
        posterSize: store.posterSize,
      );

  final CollectionPrompt collectionPrompt;
  final bool refreshAfterWrite;
  final String? startingChildId;
  final bool hideShared;
  final ThemeMode themeMode;
  final bool dynamicColour;
  final PosterSize posterSize;
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

  Future<void> setStartingChildId(String? value) async {
    await _store.setStartingChildId(value);
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
}

final settingsProvider =
    NotifierProvider<SettingsController, GarfinSettings>(SettingsController.new);
