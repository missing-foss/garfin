// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import 'device_sign_in_sheet.dart';
import 'user_avatar.dart';
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
                UserAvatar(name: kid.user.name, avatarUrl: kid.avatarUrl),
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
                // Flexible for the same measured reason as the heading row
                // below, and this one is **older than this change**: the
                // status has always been an inflexible child beside an
                // `Expanded`, and at 296dp/200% the header row overflowed
                // too. Found while measuring the row the review asked about.
                Flexible(child: _ModeLabel(mode: kid.mode)),
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

            // **Whose settings these are, said before what they say** (#74).
            // The two lines below sit directly under the age — which the
            // parent has just been able to edit, and which Garfin keeps on
            // this phone — so three lines from three different places read as
            // one list of Garfin's. The heading is the whole fix: one label
            // above two existing lines, no new data.
            Row(
              children: [
                // `Flexible`, and it is not decoration: measured at a 296dp
                // card with Android's 200% text scale, this row overflowed by
                // 15px in English. Raised in review as probably-unreachable
                // arithmetic; it is reachable.
                Flexible(
                  child: Text(
                    l10n.kidsServerSection,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                // The tap the mode label used to promise and not have. One
                // explanation for all three server-owned facts, next to the
                // two that are hardest to place.
                //
                // **No `visualDensity: compact` here.** It measured 40x40,
                // under the 48dp interactive minimum — on the one control
                // that explains the card to a parent who could not work out
                // what it was telling them, which is the worst place to save
                // eight pixels.
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 18),
                  tooltip: l10n.kidsServerExplainAction,
                  onPressed: () =>
                      _explain(context, l10n, kid.user.name),
                ),
              ],
            ),

            Text(_capLabel(l10n), style: theme.textTheme.bodySmall),

            // The other half of what the server enforces. A card that shows the
            // rating cap and not the hours summarises half a parental control
            // and reads as the whole of one.
            const SizedBox(height: 4),
            Text(_scheduleLabel(context, l10n), style: theme.textTheme.bodySmall),

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

            // Signing this child in on one of their devices (#40). On their own
            // card on purpose: the child is then chosen by construction, and
            // approving for the wrong child — the failure that matters here,
            // and a silent one — has no list to happen in.
            //
            // Absent for a conflicting account, which Garfin refuses to
            // interpret at all (ground rule 3). Minting a session for an
            // account it cannot describe would be acting past the point where
            // it stopped understanding.
            if (!conflicting) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.phonelink_lock_outlined, size: 18),
                  label: Text(l10n.deviceSignInAction),
                  onPressed: () => showDeviceSignInSheet(
                    context,
                    session: session,
                    child: kid.user,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The hours the account may be used, or that there is no restriction.
  ///
  /// **An absent schedule is stated, not left blank.** No schedule means
  /// unrestricted hours, and an empty line where the other children have times
  /// reads as the opposite — as though this child were the restricted one and
  /// Garfin had failed to say when.
  ///
  /// **Server time, said out loud.** Measured for #49: the API exposes the
  /// server's UTC instant and nothing about its offset, so Garfin cannot
  /// convert 20:00-on-the-server into a time on this phone. Rendering it as if
  /// it were local would be the quiet kind of wrong this project keeps
  /// catching.
  String _scheduleLabel(BuildContext context, AppLocalizations l10n) {
    final schedules = kid.user.policy.accessSchedules;
    if (schedules.isEmpty) return l10n.kidsScheduleNone;

    final lines = schedules
        .map((s) => l10n.kidsScheduleWindow(
              _dayLabel(context, l10n, s.dayOfWeek),
              formatScheduleHour(s.startHour),
              formatScheduleHour(s.endHour),
            ))
        .join('  ·  ');
    return l10n.kidsScheduleServerTime(lines);
  }

  /// `Everyday`, `Weekday` and `Weekend` are Jellyfin's own convenience values,
  /// beside the seven days — ten in total, and the three are what a parent
  /// most often picks. The seven come from `intl` rather than the catalogue,
  /// so they are named the way the reader's locale names them.
  static String _dayLabel(
    BuildContext context,
    AppLocalizations l10n,
    String day,
  ) {
    switch (day) {
      case 'Everyday':
        return l10n.kidsScheduleEveryday;
      case 'Weekday':
        return l10n.kidsScheduleWeekday;
      case 'Weekend':
        return l10n.kidsScheduleWeekend;
    }
    const weekdays = <String, int>{
      'Monday': DateTime.monday,
      'Tuesday': DateTime.tuesday,
      'Wednesday': DateTime.wednesday,
      'Thursday': DateTime.thursday,
      'Friday': DateTime.friday,
      'Saturday': DateTime.saturday,
      'Sunday': DateTime.sunday,
    };
    final weekday = weekdays[day];
    // A value from a later server version renders as itself rather than
    // throwing or disappearing — the same reason `LibraryItem.type` stays a
    // string.
    if (weekday == null) return day;
    final locale = Localizations.localeOf(context).toString();
    // 2026-08-03 is a Monday, so this maps a weekday number to a date whose
    // name `intl` can give in the reader's locale.
    return DateFormat.EEEE(locale).format(DateTime(2026, 8, 2 + weekday));
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

/// What the parent is looking at, and where it lives (#74, #76).
///
/// One sheet for all three server-owned facts rather than a tooltip each: the
/// question they provoke is the same question — *whose setting is this and can
/// I change it here* — and answering it three times in three places is how the
/// answers drift apart.
///
/// It states the read-only boundary plainly. Ground rule 8 is a deliberate
/// design commitment, and a limit nobody explains reads as a missing feature.
void _explain(BuildContext context, AppLocalizations l10n, String name) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        // **Scrollable, not a bare `Column`.** Four paragraphs of explanation
        // overflow a modal sheet on a short screen — caught by a test on an
        // 800x600 surface, and a large text scale would do the same on any
        // phone. An explanation that clips is worse than none, because the
        // part it cuts is the part nobody has read yet.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.kidsServerSection, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(l10n.kidsServerExplainMode(name),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(l10n.kidsServerExplainPolicy(name),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              // The path is Jellyfin's own menu names, read out of the
              // 10.11.11 web client's strings rather than remembered: the
              // issue that asked for this line flagged that a wrong path is
              // worse than none, and it is the kind of claim that reads as
              // verified whether or not it was.
              Text(l10n.kidsServerExplainWhere(name),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                l10n.kidsServerExplainBirthYear,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel({required this.mode});

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

    // **A label, not a `Chip`** (#76). This reports which kind of list the
    // child's Jellyfin account uses; it has never done anything on tap. The
    // app's chips *are* tappable — `FilterChip` and `ChoiceChip` on the
    // library filter bar — so a pill here taught the parent it was a button
    // and then ignored them. It was reported as "a 'select' button that
    // doesn't seem to work", which is exactly what the widget promised.
    //
    // The explanation it provoked now lives beside the two lines below,
    // where the same question is asked about the rating limit and the hours.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colour ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
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
