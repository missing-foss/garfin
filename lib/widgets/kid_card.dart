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
import '../models/library_filters.dart';
import '../providers/app_providers.dart';
import '../providers/home_tab_providers.dart';
import '../providers/kids_providers.dart';
import '../providers/library_providers.dart';
import '../repositories/jellyfin_exception.dart';
import 'error_notice.dart';
import '../repositories/birth_year_store.dart';

/// One child's card: avatar, name, age, cap, the mode chip, the tags, progress
/// and the count.
/// How big a child's face is, given how many there are.
///
/// **Fewer children, bigger faces** — they are the subject of this screen, and
/// a household with two of them has the room to say so.
///
/// **Capped at 36 rather than sized to the space available.** Measured on
/// 10.11.11 and recorded in `docs/JELLYFIN-API.md`: a user's avatar arrives at
/// whatever resolution it was uploaded, and Jellyfin accepts every request to
/// resize it and ignores them all. Nothing in the user DTO reports the source
/// dimensions either, so the app cannot know that a picture is small until it
/// has already drawn it too large. A conservative ceiling is the only version
/// of this that cannot make somebody's photograph look worse.
double kidAvatarRadius(int children) => switch (children) {
  <= 2 => 36,
  <= 4 => 30,
  _ => 24,
};

class KidCard extends ConsumerStatefulWidget {
  const KidCard({
    super.key,
    required this.kid,
    required this.session,
    this.avatarRadius = 24,
  });

  final KidSummary kid;
  final AuthSession session;

  /// From [kidAvatarRadius]. Defaulted so a caller that does not care gets the
  /// size this card always had.
  final double avatarRadius;

  @override
  ConsumerState<KidCard> createState() => _KidCardState();
}

class _KidCardState extends ConsumerState<KidCard> {
  /// Whether the per-library breakdown is showing.
  ///
  /// **Local, and that is the design.** Nothing asks the server for a
  /// per-library count until this is true for a row, so a screen of six
  /// children costs nothing extra until a parent asks about one of them.
  bool _expanded = false;

  KidSummary get kid => widget.kid;
  AuthSession get session => widget.session;

  /// Pick this child and go to the Library, in that order.
  ///
  /// Two writes rather than a route with an argument: the selection is the
  /// Library's own, so the screen arrives already filtered instead of being
  /// handed a child it would have to apply itself — and there is no second
  /// path to keep in step with the first.
  /// Pick this child, and land on what they can already see.
  ///
  /// **Both halves of "has access to", not one.** A label is what Garfin gives;
  /// the rating cap silently overrides it, so a grid filtered to the labels
  /// alone would show a child titles their own account refuses them. The cap
  /// filter is the server's, applied to the administrator's view, and it is
  /// what the per-library counts on the card use too — so the screen a face
  /// opens agrees with the number the face was sitting next to.
  ///
  /// The full grid is one tap away, and the giving workflow lives there:
  /// `library_repository.dart` builds every view from the administrator's, so
  /// nothing is lost by arriving narrowed. Provisional by the owner's decision
  /// on the issue — whether this should be permanent is parked until it has
  /// been used.
  void _pick(WidgetRef ref) {
    ref.read(pickingForProvider.notifier).select(kid.user.id);
    ref.read(libraryViewProvider.notifier).set(LibraryView.given);
    ref.read(libraryFiltersProvider.notifier).set(
          ref.read(libraryFiltersProvider).copyWith(withinCap: true),
        );
    ref.read(homeTabProvider.notifier).go(HomeTab.library);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final conflicting = kid.mode == ShortlistMode.conflicting;

    // **A column of cards, not one card with headings.** What the tap reveals
    // is two unrelated things: what Jellyfin enforces on the account, and what
    // the child can see library by library. Stacked together they were one run
    // of lines that a label had to keep apart; separate cards say it in the
    // shape instead, which is what a card is for.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // **The picture is its own target.** Tapping it means *pick
                    // this child* — the same act as choosing them in the Library's
                    // "Picking for" row, and it sets the same selection rather
                    // than a lookalike, so the grid, the rating-cap chip and what
                    // carries into the assign sheet are the state that row
                    // produces and not a second version of it.
                    //
                    // Sized to the avatar and no larger: this is the one place on
                    // this screen where a mistap takes a parent somewhere they did
                    // not ask to go, so the target is the picture rather than the
                    // padding around it.
                    Semantics(
                      button: true,
                      label: l10n.kidsPickThisChild(kid.user.name),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _pick(ref),
                        child: UserAvatar(
                          name: kid.user.name,
                          avatarUrl: kid.avatarUrl,
                          radius: widget.avatarRadius,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // **The rest of the row is the expander**, and it is a
                    // separate target from the picture beside it on purpose: the
                    // picture leaves this screen, this does not. Revealing in
                    // place rather than pushing a route is what keeps the two
                    // meanings apart — one goes somewhere, one shows more here.
                    Expanded(
                      child: Semantics(
                        button: true,
                        expanded: _expanded,
                        child: InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      kid.user.name,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    _AgeLine(kid: kid, session: session),
                                  ],
                                ),
                              ),
                              // **The affordance.** A card whose detail is hidden
                              // behind a tap has to say so, or the tap is a thing
                              // only whoever built it knows about. Inside the same
                              // `InkWell` rather than beside it, so it is a hint
                              // and not a second control with its own meaning —
                              // the whole row does one thing.
                              Icon(
                                _expanded ? Icons.expand_less : Icons.expand_more,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

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
        ),

        // Everything else waits for the tap. The resting card is the picture,
        // the name, the age and the way in — what a parent needs to recognise a
        // child and act on them. The rest is reference, read when a question is
        // asked.
        //
        // The mode label comes down here with the rest. It reports which kind
        // of list the account uses, which is a fact about the account rather
        // than about the child, and it never did anything on tap.
        if (_expanded) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **Whose settings these are, said before what they say.**
                  // The two lines below are read from the child's Jellyfin account
                  // and never written; the age above is Garfin's own, kept on this
                  // phone. Stacked without a word they read as one list, and the
                  // birth year sounds like it drives the limit beneath it.
                  //
                  // The heading mattered more when all three sat in one column at
                  // rest. It still earns its place: revealing them together is the
                  // same stack, one tap later.
                  Row(
                    children: [
                      // `Flexible`, and it is not decoration: measured at a 296dp
                      // card with Android's 200% text scale, this row overflowed by
                      // 15px in English. Raised in review as probably-unreachable
                      // arithmetic; it is reachable.
                      Flexible(
                        child: Text(
                          l10n.kidsServerSection(kid.user.name),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
                        onPressed: () => _explain(context, l10n, kid.user.name),
                      ),
                    ],
                  ),

                  Text(_capLabel(l10n), style: theme.textTheme.bodySmall),

                  // The other half of what the server enforces. A card that shows the
                  // rating cap and not the hours summarises half a parental control
                  // and reads as the whole of one.
                  const SizedBox(height: 4),
                  Text(
                    _scheduleLabel(context, l10n),
                    style: theme.textTheme.bodySmall,
                  ),

                  // **The labels, said rather than shown bare.** A row of
                  // chips under two sentences was a list with no verb: it
                  // never said whether carrying one of these is what lets the
                  // child see a thing or what stops them. Ground rule 3 — for
                  // a block-list account those are opposites — so the sentence
                  // is chosen by the mode rather than assumed.
                  //
                  // A conflicting account gets neither sentence. Both lists
                  // are set, the red line above already says Garfin will not
                  // guess which was meant, and picking a verb here is exactly
                  // the guess that rule forbids.
                  if (kid.tags.isNotEmpty && !conflicting) ...[
                    const SizedBox(height: 8),
                    Text(
                      kid.mode == ShortlistMode.allow
                          ? l10n.kidsLabelsAllow
                          : l10n.kidsLabelsBlock,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in kid.tags)
                          Chip(
                            label: Text(tag, style: theme.textTheme.labelSmall),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                  ],

                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // The second card, and the reason the total above it is gone: these
          // numbers answer "how much can they see" per library, which is the
          // same question with more resolution. Keeping both meant a headline
          // that could disagree with the breakdown beneath it — and the
          // headline was the most expensive thing the card computed.
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.kidsLibrariesSection(kid.user.name),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  _PerLibrary(session: session, kid: kid),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The hours the account may be used, or that there is no restriction.
  ///
  /// **An absent schedule is stated, not left blank.** No schedule means
  /// unrestricted hours, and an empty line where the other children have times
  /// reads as the opposite — as though this child were the restricted one and
  /// Garfin had failed to say when.
  ///
  /// **Server time, said out loud.** Measured: the API exposes the
  /// server's UTC instant and nothing about its offset, so Garfin cannot
  /// convert 20:00-on-the-server into a time on this phone. Rendering it as if
  /// it were local would be the quiet kind of wrong this project keeps
  /// catching.
  String _scheduleLabel(BuildContext context, AppLocalizations l10n) {
    final schedules = kid.user.policy.accessSchedules;
    if (schedules.isEmpty) return l10n.kidsScheduleNone;

    final lines = schedules
        .map(
          (s) => l10n.kidsScheduleWindow(
            _dayLabel(context, l10n, s.dayOfWeek),
            formatScheduleHour(s.startHour),
            formatScheduleHour(s.endHour),
          ),
        )
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
  /// Four distinct answers, and they are not interchangeable: no cap at all, a
  /// cap the ladder knows, and a cap it does not — which splits again on
  /// whether the sub-level carries meaning.
  ///
  /// The unnameable case shows the raw numbers rather than a nearby rung; see
  /// [ParentalRatingLadder.nameFor] for why guessing on a safety control is the
  /// wrong kind of helpful. It prints the sub-level **only when it is
  /// non-zero**: 0 and absent both behave as the strictest sub-level, so the
  /// score alone is then the whole cap, while 10/0 and 10/1 are genuinely
  /// different caps and one number for both would render them identically. The
  /// measurement is at [UserPolicy.maxParentalSubRating].
  String _capLabel(AppLocalizations l10n) {
    final value = kid.user.policy.maxParentalRating;
    if (value == null) return l10n.kidsRatingCapNone;
    final name = kid.ratingCapName;
    if (name != null) return l10n.kidsRatingCap(name);
    final sub = kid.user.policy.maxParentalSubRating ?? 0;
    return sub == 0
        ? l10n.kidsRatingCapValue(value)
        : l10n.kidsRatingCapPair(value, sub);
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
              Text(l10n.kidsServerSection(name), style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                l10n.kidsServerExplainMode(name),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.kidsServerExplainPolicy(name),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              // The path is Jellyfin's own menu names, read out of the
              // 10.11.11 web client's strings rather than remembered: the
              // issue that asked for this line flagged that a wrong path is
              // worse than none, and it is the kind of claim that reads as
              // verified whether or not it was.
              Text(
                l10n.kidsServerExplainWhere(name),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.kidsServerExplainBirthYear,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial?.toString() ?? '',
  );
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
      setState(
        () => _error = l10n.kidsBirthYearInvalid(
          BirthYearStore.minYear,
          BirthYearStore.maxYear,
        ),
      );
      return;
    }
    Navigator.of(context).pop(_BirthYearResult(year));
  }
}

/// One child's counts, library by library.
///
/// **Visibility only, and one number per row.** `UI-SPEC.md` is explicit that
/// labels and visibility never share a line, and this is the child's own
/// visible count per library — the same question the headline asks, narrowed.
/// A label count could join it later; it would be a second row, not a second
/// number on this one.
class _PerLibrary extends ConsumerWidget {
  const _PerLibrary({required this.session, required this.kid});

  final AuthSession session;
  final KidSummary kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final counts = ref.watch(
      childLibraryCountsProvider(
        ChildLibrariesRequest(session: session, childId: kid.user.id),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: counts.when(
        // Small and in place: the row has already opened, so a full-width
        // spinner would push the card around for something that is about to
        // be four lines of text.
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: LinearProgressIndicator(),
        ),
        // The card keeps everything else it was saying. A breakdown that could
        // not be fetched is not a reason to lose the numbers above it.
        error: (error, _) => Text(
          jellyfinErrorText(
            l10n,
            error is JellyfinException
                ? error
                : const JellyfinException(JellyfinErrorKind.server),
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        // **Most-seen first.** Sorted here rather than by the server: the
        // rows come from one `/Items` count per library, so there is no single
        // query whose order could be asked for. Ties keep the server's own
        // order, which is `/UserViews`' — a stable arrangement a parent may
        // recognise from Jellyfin, rather than one this screen invented.
        data: (rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in [...rows]..sort(
                (a, b) => b.visible.compareTo(a.visible)))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.library.name,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      l10n.libraryItemCount(row.visible),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
