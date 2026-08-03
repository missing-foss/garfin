// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../providers/unlock_providers.dart';
import '../repositories/unlock_settings_store.dart';

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
      body: ListView(
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
