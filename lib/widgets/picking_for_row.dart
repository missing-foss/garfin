// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';

/// The avatars along the top. Everyone, then one per label-controlled child.
///
/// Public since #83: a collection is browsed on its own screen, and the parent
/// has to be able to switch child without leaving the set to do it. The
/// selection itself lives in `pickingForProvider`, so it carries across the
/// push and back on its own — this is only the control.
class PickingForRow extends ConsumerWidget {
  const PickingForRow({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(kidsOverviewProvider(session));
    final selected = ref.watch(pickingForProvider);

    final kids = overview.asData?.value.shortlisted ?? const <KidSummary>[];
    if (kids.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.libraryPickingFor,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PickChip(
                  label: l10n.libraryEveryone,
                  selected: selected == null,
                  onTap: () =>
                      ref.read(pickingForProvider.notifier).select(null),
                ),
                for (final kid in kids)
                  _PickChip(
                    label: kid.user.name,
                    selected: selected == kid.user.id,
                    onTap: () =>
                        ref.read(pickingForProvider.notifier).select(kid.user.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

