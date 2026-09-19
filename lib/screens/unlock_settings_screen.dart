// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/app_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/unlock_providers.dart';
import '../repositories/unlock_settings_store.dart';
import '../widgets/adaptive_layout.dart';

/// Settings → Unlock (`docs/UI-SPEC.md`).
///
/// A screen of its own for now. The full Settings screen is build order step 7
/// and will absorb this as its first section — but the idle timeout is part of
/// what issue #18 asks for, and a setting with no way to reach it is not a
/// setting.
class UnlockSettingsScreen extends ConsumerStatefulWidget {
  const UnlockSettingsScreen({super.key});

  @override
  ConsumerState<UnlockSettingsScreen> createState() =>
      _UnlockSettingsScreenState();
}

class _UnlockSettingsScreenState extends ConsumerState<UnlockSettingsScreen> {
  LockController get _controller =>
      ref.read(lockControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final required = _controller.isRequired;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsUnlockTitle)),
      body: ReadableList(
        children: [
          SwitchListTile(
            value: required,
            title: Text(l10n.settingsUnlockRequire),
            subtitle: Text(l10n.settingsUnlockRequireSubtitle),
            onChanged: (value) async {
              await _controller.setRequired(value);
              if (mounted) setState(() {});
            },
          ),
          const Divider(),
          // **Here rather than under Looks**, because it is not an appearance
          // choice: it moves the window flag that the lock's own recents cover
          // used to depend on, and a parent deciding about it is deciding
          // about the same thing the switch above is about.
          Consumer(
            builder: (context, ref, _) {
              // **What it costs, where it costs it.** Below Android 13 the
              // recents thumbnail is covered by this flag and nothing else, so
              // allowing capture gives that snapshot back — the half a parent
              // cannot infer from "screenshots are blocked". Unknown counts as
              // uncovered: a warning shown where it was not needed is the
              // cheaper mistake.
              final covered =
                  ref.watch(recentsCoveredProvider).asData?.value ?? false;
              return SwitchListTile(
                value: ref.watch(settingsProvider).allowScreenshots,
                isThreeLine: !covered,
                title: Text(l10n.settingsAllowScreenshots),
                subtitle: Text(
                  covered
                      ? l10n.settingsAllowScreenshotsSubtitle
                      : '${l10n.settingsAllowScreenshotsSubtitle}\n'
                          '${l10n.settingsAllowScreenshotsCost}',
                ),
                onChanged:
                    ref.read(settingsProvider.notifier).setAllowScreenshots,
              );
            },
          ),
          const Divider(),
          ListTile(
            enabled: required,
            title: Text(l10n.settingsUnlockTimeout),
            subtitle: Text(l10n.settingsUnlockTimeoutSubtitle),
          ),
          // RadioGroup rather than per-tile groupValue/onChanged, which are
          // deprecated as of Flutter 3.32.
          RadioGroup<Duration>(
            groupValue: _controller.idleTimeout,
            onChanged: required
                ? (value) async {
                    if (value == null) return;
                    await _controller.setIdleTimeout(value);
                    if (mounted) setState(() {});
                  }
                : (_) {},
            child: Column(
              children: [
                for (final choice in UnlockSettingsStore.idleTimeoutChoices)
                  RadioListTile<Duration>(
                    value: choice,
                    enabled: required,
                    title: Text(_timeoutLabel(l10n, choice)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _timeoutLabel(AppLocalizations l10n, Duration value) =>
    value == Duration.zero
        ? l10n.unlockTimeoutImmediate
        : l10n.unlockTimeoutMinutes(value.inMinutes);
