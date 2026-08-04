// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The first sign-in step: where the Jellyfin server lives.
///
/// Presentation only — the controller owns normalisation and the reachability
/// probe. Widgets never call HTTP (`CLAUDE.md` § Conventions).
class ServerAddressForm extends StatelessWidget {
  const ServerAddressForm({
    super.key,
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.serverStepTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          enabled: !busy,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: busy ? null : onSubmit,
          decoration: InputDecoration(
            labelText: l10n.serverAddressLabel,
            hintText: l10n.serverAddressHint,
            helperText: l10n.serverAddressHelp,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => onSubmit(controller.text),
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.continueLabel),
        ),
      ],
    );
  }
}
