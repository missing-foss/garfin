// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../providers/support_providers.dart';
import '../repositories/support_card_store.dart';
import 'open_external.dart';

/// The one-time thank-you card, on the Kids screen after the 50th action.
///
/// **Parent-side by where it sits.** Kids is past the unlock, like everything
/// signed in; the sign-in and lock screens never show it.
///
/// **It stays for the visit it appears in.** The flag is written as soon as
/// the card is first drawn, so the provider stops calling it due at once; the
/// card holds itself on screen until it is answered or the screen is left.
class SupportCard extends ConsumerStatefulWidget {
  const SupportCard({super.key});

  @override
  ConsumerState<SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends ConsumerState<SupportCard> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    if (!_showing && ref.watch(supportCardDueProvider)) {
      _showing = true;
      final store = ref.read(supportCardStoreProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(store.markShown());
        // The provider does not watch the flag; without this it would go on
        // saying "due" — after Not now, and on the next visit to Kids.
        if (mounted) ref.invalidate(supportCardDueProvider);
      });
    }
    if (!_showing) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    void close() => setState(() => _showing = false);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.coffee_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.supportCardBody(SupportCardStore.milestone),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: close,
                  child: Text(l10n.supportCardLater),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    close();
                    unawaited(openExternal(context, supportUrl));
                  },
                  child: Text(l10n.aboutSupport),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
