// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../providers/auth_providers.dart';
import '../providers/collection_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';
import '../providers/settings_providers.dart';
import '../repositories/app_settings_store.dart';
import 'about_screen.dart';
import 'unlock_settings_screen.dart';

/// Build order step 7 (#52).
///
/// Six sections in `docs/UI-SPEC.md`, and what is here is the part with
/// something behind it. Three switches the spec lists are **not** here and are
/// not oversights:
///
/// - **the tag prefix**, because Garfin never composes a label — it writes back
///   the one already in the child's policy, so there is nothing to prefix
///   (ground rule 8, the same consequence as a child's first label);
/// - **cascade to collection members**, because a collection *always* writes to
///   its members, and #50 measured that the alternative hands the child a
///   visible empty collection;
/// - **cascade to episodes**, which is a real gap with no write path yet (#53).
///
/// A switch that controls nothing is worse than a missing one: it reads as a
/// promise.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Section(title: l10n.settingsUnlockTitle),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(l10n.settingsUnlockTitle),
          subtitle: Text(l10n.settingsUnlockRequireSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const UnlockSettingsScreen(),
            ),
          ),
        ),

        _Section(title: l10n.settingsSectionServer),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(l10n.connectedTo(session.serverUrl)),
          subtitle: Text(l10n.signedInAs(session.userName)),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: Text(l10n.settingsRefreshCache),
          onTap: () {
            // Everything the app holds about this server, dropped. Cheaper to
            // offer than to explain when a change made in Jellyfin's own admin
            // has not appeared here yet.
            ref.invalidate(kidsOverviewProvider(session));
            refreshLibrary(ref);
            ref.invalidate(collectionIndexProvider(session));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsRefreshCacheDone)),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l10n.signOutAction),
          onTap: () => ref.read(authControllerProvider.notifier).signOut(),
        ),

        _Section(title: l10n.settingsSectionLabels),
        ListTile(
          leading: const Icon(Icons.collections_outlined),
          title: Text(l10n.settingsCollectionPrompt),
          subtitle: Text(_promptLabel(l10n, settings.collectionPrompt)),
          onTap: () => _pick<CollectionPrompt>(
            context,
            title: l10n.settingsCollectionPrompt,
            value: settings.collectionPrompt,
            options: {
              for (final option in CollectionPrompt.values)
                option: _promptLabel(l10n, option),
            },
            onChanged: controller.setCollectionPrompt,
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          value: settings.refreshAfterWrite,
          title: Text(l10n.settingsRefreshAfterWrite),
          subtitle: Text(l10n.settingsRefreshAfterWriteSubtitle),
          onChanged: controller.setRefreshAfterWrite,
        ),

        _Section(title: l10n.settingsSectionPicking),
        _StartingChildTile(session: session),
        SwitchListTile(
          secondary: const Icon(Icons.filter_alt_outlined),
          value: settings.hideShared,
          title: Text(l10n.settingsHideShared),
          onChanged: controller.setHideShared,
        ),

        _Section(title: l10n.settingsSectionLooks),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: Text(l10n.settingsTheme),
          subtitle: Text(_themeLabel(l10n, settings.themeMode)),
          onTap: () => _pick<ThemeMode>(
            context,
            title: l10n.settingsTheme,
            value: settings.themeMode,
            options: {
              ThemeMode.system: l10n.settingsThemeSystem,
              ThemeMode.light: l10n.settingsThemeLight,
              ThemeMode.dark: l10n.settingsThemeDark,
            },
            onChanged: controller.setThemeMode,
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          value: settings.dynamicColour,
          title: Text(l10n.settingsDynamicColour),
          onChanged: controller.setDynamicColour,
        ),
        ListTile(
          leading: const Icon(Icons.grid_view_outlined),
          title: Text(l10n.settingsPosterSize),
          subtitle: Text(_posterLabel(l10n, settings.posterSize)),
          onTap: () => _pick<PosterSize>(
            context,
            title: l10n.settingsPosterSize,
            value: settings.posterSize,
            options: {
              for (final option in PosterSize.values)
                option: _posterLabel(l10n, option),
            },
            onChanged: controller.setPosterSize,
          ),
        ),

        _Section(title: l10n.settingsSectionAbout),
        // One tile where four used to be (#66). The version, the licences and
        // the non-affiliation line all moved to `AboutScreen`, which is a
        // screen rather than a section because the mark, the links and the
        // update check need room that the bottom of a settings list does not
        // have.
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.settingsAbout),
          subtitle: Text(l10n.settingsVersion(appVersion)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
          ),
        ),
      ],
    );
  }

  static String _promptLabel(AppLocalizations l10n, CollectionPrompt value) =>
      switch (value) {
        CollectionPrompt.ask => l10n.settingsCollectionPromptAsk,
        CollectionPrompt.always => l10n.settingsCollectionPromptAlways,
        CollectionPrompt.never => l10n.settingsCollectionPromptNever,
      };

  static String _themeLabel(AppLocalizations l10n, ThemeMode value) =>
      switch (value) {
        ThemeMode.system => l10n.settingsThemeSystem,
        ThemeMode.light => l10n.settingsThemeLight,
        ThemeMode.dark => l10n.settingsThemeDark,
      };

  static String _posterLabel(AppLocalizations l10n, PosterSize value) =>
      switch (value) {
        PosterSize.large => l10n.settingsPosterLarge,
        PosterSize.regular => l10n.settingsPosterRegular,
        PosterSize.small => l10n.settingsPosterSmall,
      };
}

/// One radio dialog, for every setting that is a choice rather than a switch.
Future<void> _pick<T>(
  BuildContext context, {
  required String title,
  required T value,
  required Map<T, String> options,
  required Future<void> Function(T) onChanged,
}) async {
  final chosen = await showDialog<T>(
    context: context,
    // `RadioGroup` rather than each tile carrying `groupValue`/`onChanged`,
    // which Flutter deprecated after 3.32: the group owns the selection, and a
    // tile that still declared its own would not compile clean.
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        RadioGroup<T>(
          groupValue: value,
          onChanged: (v) => Navigator.of(context).pop(v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in options.entries)
                RadioListTile<T>(
                  value: entry.key,
                  title: Text(entry.value),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (chosen != null) await onChanged(chosen);
}

/// Which child the Library opens on.
///
/// The options are the accounts Garfin can actually pick for — the same list
/// the Library's own row shows. A stored id whose account has gone reads as
/// Everyone rather than as an error, which is what [pickedChildProvider] does
/// with it too.
class _StartingChildTile extends ConsumerWidget {
  const _StartingChildTile({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final kids = ref.watch(kidsOverviewProvider(session)).asData?.value
            .shortlisted ??
        const <KidSummary>[];

    final options = <String?, String>{
      null: l10n.settingsStartingChildEveryone,
      for (final kid in kids) kid.user.id: kid.user.name,
    };

    return ListTile(
      leading: const Icon(Icons.face_outlined),
      title: Text(l10n.settingsStartingChild),
      subtitle: Text(
        options[settings.startingChildId] ?? l10n.settingsStartingChildEveryone,
      ),
      onTap: () => _pick<String?>(
        context,
        title: l10n.settingsStartingChild,
        value: settings.startingChildId,
        options: options,
        onChanged: ref.read(settingsProvider.notifier).setStartingChildId,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
