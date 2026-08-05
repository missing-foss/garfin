// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_session.dart';
import '../models/jellyfin_user.dart';
import '../models/kid_summary.dart';
import '../providers/app_providers.dart';
import '../providers/kids_providers.dart';
import '../repositories/birth_year_store.dart';

/// One child's card: avatar, name, age, cap, the mode chip, the tags, progress
/// and the count.
class KidCard extends ConsumerWidget {
  const KidCard({super.key, required this.kid, required this.session});

  final KidSummary kid;
  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final conflicting = kid.mode == ShortlistMode.conflicting;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(kid: kid),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kid.user.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      _AgeLine(kid: kid, session: session),
                    ],
                  ),
                ),
                _ModeChip(mode: kid.mode),
              ],
            ),
            const SizedBox(height: 12),

            // The conflicting case is stated, not resolved. Ground rule 3 says
            // the two verbs are never mixed; the server permits it anyway, and
            // picking one here would be a guess that silently reverses what
            // every later action does.
            if (conflicting) ...[
              Text(
                l10n.kidsModeConflictingDetail,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],

            Text(_capLabel(l10n), style: theme.textTheme.bodySmall),

            if (kid.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in kid.tags)
                    Chip(
                      label: Text(tag, style: theme.textTheme.labelSmall),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            // Both numbers came back from the server (ground rule 4). The bar
            // is a rendering of them, not a second opinion about them.
            LinearProgressIndicator(value: kid.progress),
            const SizedBox(height: 6),
            Text(
              l10n.kidsVisibleOfTotal(kid.visibleCount, kid.libraryTotal),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  /// The cap, named where the server's ladder can name it.
  ///
  /// Three distinct answers, and they are not interchangeable: no cap at all,
  /// a cap the ladder knows, and a cap it does not. The last one shows the raw
  /// number — see [ParentalRatingLadder.nameFor] for why guessing a nearby rung
  /// on a safety control is the wrong kind of helpful.
  String _capLabel(AppLocalizations l10n) {
    final value = kid.user.policy.maxParentalRating;
    if (value == null) return l10n.kidsRatingCapNone;
    final name = kid.ratingCapName;
    return name == null
        ? l10n.kidsRatingCapValue(value)
        : l10n.kidsRatingCap(name);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.kid});

  final KidSummary kid;

  @override
  Widget build(BuildContext context) {
    final initial = kid.user.name.trim().isEmpty
        ? '?'
        : kid.user.name.trim().characters.first.toUpperCase();

    // No URL means the user has no avatar — measured as key-absence rather than
    // a null, so this is not a guess. Asking anyway would put a 404 behind
    // every initial.
    if (kid.avatarUrl == null) {
      return CircleAvatar(radius: 24, child: Text(initial));
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: kid.avatarUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (_, _) => CircleAvatar(radius: 24, child: Text(initial)),
        errorWidget: (_, _, _) =>
            CircleAvatar(radius: 24, child: Text(initial)),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final ShortlistMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final (label, colour) = switch (mode) {
      ShortlistMode.allow => (l10n.kidsModeAllowList, null),
      ShortlistMode.block => (l10n.kidsModeBlockList, null),
      ShortlistMode.conflicting =>
        (l10n.kidsModeConflicting, theme.colorScheme.errorContainer),
      // Cards are only built for users who have a shortlist, so this arm is
      // unreachable today. It exists because the alternative is a non-exhaustive
      // switch that would fail to compile the day a fourth mode is added, which
      // is precisely when someone should be made to think about this screen.
      ShortlistMode.none => (l10n.kidsModeAllowList, null),
    };

    return Chip(
      label: Text(label, style: theme.textTheme.labelSmall),
      backgroundColor: colour,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// The age, or an invitation to supply one.
///
/// Tappable in both states, because a year typed wrongly needs correcting as
/// much as a missing one needs adding.
class _AgeLine extends ConsumerWidget {
  const _AgeLine({required this.kid, required this.session});

  final KidSummary kid;
  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final age = kid.ageIn(DateTime.now().year);

    return InkWell(
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          age == null ? l10n.kidsAgeUnknown : l10n.kidsAgeYears(age),
          style: theme.textTheme.bodySmall?.copyWith(
            color: age == null
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_BirthYearResult>(
      context: context,
      builder: (_) => _BirthYearDialog(initial: kid.birthYear),
    );
    if (result == null) return;

    await ref.read(birthYearStoreProvider).write(kid.user.id, result.year);
    ref.invalidate(kidsOverviewProvider(session));
  }
}

class _BirthYearResult {
  const _BirthYearResult(this.year);

  /// Null means the parent chose to forget it.
  final int? year;
}

class _BirthYearDialog extends StatefulWidget {
  const _BirthYearDialog({this.initial});

  final int? initial;

  @override
  State<_BirthYearDialog> createState() => _BirthYearDialogState();
}

class _BirthYearDialogState extends State<_BirthYearDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.kidsBirthYearTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.kidsBirthYearHelp),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.kidsBirthYearTitle,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _BirthYearResult(null)),
            child: Text(l10n.kidsBirthYearClear),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: () => _save(context),
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }

  void _save(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = _controller.text.trim();

    // Empty means the same as Remove. A parent who clears the field and taps
    // Save has said what they meant as plainly as one who tapped Remove.
    if (text.isEmpty) {
      Navigator.of(context).pop(const _BirthYearResult(null));
      return;
    }

    final year = int.tryParse(text);
    if (year == null || !BirthYearStore.isPlausible(year)) {
      setState(() => _error = l10n.kidsBirthYearInvalid(
            BirthYearStore.minYear,
            BirthYearStore.maxYear,
          ));
      return;
    }
    Navigator.of(context).pop(_BirthYearResult(year));
  }
}
