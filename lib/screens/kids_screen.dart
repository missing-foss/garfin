// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../models/auth_session.dart';
import '../models/kid_summary.dart';
import '../providers/kids_providers.dart';
import '../repositories/jellyfin_exception.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/error_notice.dart';
import '../widgets/user_avatar.dart';
import '../models/active_session.dart';
import '../providers/session_providers.dart';
import '../models/label_collision.dart';
import '../widgets/kid_card.dart';
import '../widgets/label_clash_notice.dart';
import '../widgets/session_card.dart';

/// Build order step 3. The first screen that reads a child's policy.
///
/// Three ground rules are live here at once: allow-list and block-list are
/// opposite verbs (3), visible counts come from the server (4), and Garfin
/// never writes a user policy (8) — which is why the section at the bottom is a
/// boundary rather than a to-do list.
class KidsScreen extends ConsumerWidget {
  const KidsScreen({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(kidsOverviewProvider(session));

    // Wraps everything, including the loading and error states: the sessions
    // block is worth refreshing whether or not the children loaded, and a
    // timer that only started once the overview succeeded would be a second
    // condition to keep in step with this screen's own states.
    return _SessionPoller(
      session: session,
      child: overview.when(
        // **The faces first.** The roster is one cheap request; the counts
        // beside them are the most expensive thing the app does, and on a
        // large library that is seconds of spinner on the first screen anyone
        // sees. If the roster has landed, the children are drawn now and the
        // numbers fill in underneath them.
        loading: () => ref.watch(kidsRosterProvider(session)).maybeWhen(
              data: (roster) => roster.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _FacesWhileCounting(roster: roster),
              orElse: () => const Center(child: CircularProgressIndicator()),
            ),
        // Offline-degraded, per the definition of done: a plain explanation and a
        // way out, never a blank screen.
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reuses sign-in's mapping so a parent gets the same sentence for
                // the same cause wherever it happens. A non-Jellyfin error means
                // the failure was local rather than the server's, and `server`
                // is the honest bucket for "it did not work and Garfin cannot
                // tell you more" — there is deliberately no generic catch-all
                // string to reach for.
                ErrorNotice(
                  message: jellyfinErrorText(
                    l10n,
                    error is JellyfinException
                        ? error
                        : const JellyfinException(JellyfinErrorKind.server),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(kidsOverviewProvider(session)),
                  child: Text(l10n.kidsRetry),
                ),
              ],
            ),
          ),
        ),
        data: (data) => _KidsList(session: session, overview: data),
      ),
    );
  }
}

/// Re-reads `/Sessions` on a timer, and only that.
///
/// **Never the overview.** The two are one dependency chain —
/// `childSessionsProvider` watches `kidsOverviewProvider` to learn which users
/// are children — so invalidating the wrong one puts the expensive per-child
/// counts on a ten-second loop. Invalidating the sessions alone re-reads the
/// cheap half and takes the children from cache.
///
/// **Mounted is visible.** The shell builds one destination at a time, so
/// leaving this screen disposes this widget and stops the timer; there is no
/// separate visibility check to keep in step with the navigation.
///
/// **Stops when the app is not in front, and catches up on return.** A timer
/// running in the background is requests nobody is looking at, and coming back
/// to a screen that waits up to ten seconds before telling the truth is the
/// thing a poll is supposed to prevent, so resuming refreshes once immediately
/// and then resumes the interval.
class _SessionPoller extends ConsumerStatefulWidget {
  const _SessionPoller({required this.session, required this.child});

  final AuthSession session;
  final Widget child;

  @override
  ConsumerState<_SessionPoller> createState() => _SessionPollerState();
}

class _SessionPollerState extends ConsumerState<_SessionPoller>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
      _start();
      return;
    }
    _timer?.cancel();
    _timer = null;
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(sessionPollInterval, (_) => _tick());
  }

  /// Skipped, not queued, while a command is waiting on its read-back: the
  /// verifier is about to say what actually happened, and a poll landing first
  /// would redraw the card with the state the command has not reached yet.
  void _tick() {
    if (!mounted) return;
    if (ref.read(sessionCommandsInFlightProvider) > 0) return;
    ref.invalidate(childSessionsProvider(widget.session));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _KidsList extends ConsumerWidget {
  const _KidsList({required this.session, required this.overview});

  final AuthSession session;
  final KidsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (overview.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.kidsEmpty, style: theme.textTheme.bodyLarge),
        ),
      );
    }

    // Live sessions (#41), above the cards: it is the thing happening *now*,
    // and the cards are the standing picture. Absent entirely when nobody is
    // signed in, rather than showing an empty heading — and absent while it
    // loads or if it fails, because a sessions list that cannot be fetched is
    // not news a parent can act on and must not displace the cards.
    final sessions =
        ref.watch(childSessionsProvider(session)).asData?.value ??
        const <ActiveSession>[];

    return RefreshIndicator(
      // **Sessions only, deliberately.** Pulling used to re-read the overview
      // too, which is where the per-child visible counts come from — and that
      // query scales worse than linearly with what a child can already see
      // (19 ms at one title, 8.7 s at six thousand). A gesture a parent can
      // repeat freely must not be attached to it. The counts change when
      // Garfin writes a label, and the write path already invalidates them.
      onRefresh: () async => ref.invalidate(childSessionsProvider(session)),
      // Capped rather than full-bleed (#95): a kid card stretched across a
      // 1280dp window puts the avatar and the count at opposite ends of the
      // screen. The cap lives in the list's own padding, so the pull-to-refresh
      // gesture and the scrollbar still reach the window's edge.
      child: ReadableList(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Above the sessions and the cards, because it is about the shape of
          // the whole screen rather than about any one child on it — and
          // because a parent who reads nothing else should read this.
          LabelClashNotice(
            collisions: findLabelCollisions(
              overview.shortlisted.map((kid) => kid.user),
              normalize: foldLabelLikeJellyfin,
            ),
          ),
          if (sessions.isNotEmpty) ...[
            Text(l10n.sessionsHeading, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final active in sessions)
              SessionCard(session: session, active: active),
            const SizedBox(height: 20),
          ],
          // Accounts exist but none of them is managed — the ordinary first
          // run. Not an error and not something Garfin can finish for them:
          // giving a child their first label is a policy write, and ground
          // rule 8 forbids it. So this says where the work happens and points
          // at Jellyfin's own words for how.
          if (overview.shortlisted.isEmpty) _NobodyYet(),
          for (final kid in overview.shortlisted) ...[
            KidCard(
              kid: kid,
              session: session,
              // Fewer children, bigger faces — they are the subject of this
              // screen. Capped rather than filling the space: measured, a
              // user's avatar arrives at whatever size it was uploaded and
              // Jellyfin ignores every request to resize it, so anything
              // larger risks upscaling a small picture the app cannot know
              // is small. See `docs/JELLYFIN-API.md`.
              avatarRadius: kidAvatarRadius(overview.shortlisted.length),
            ),
            const SizedBox(height: 12),
          ],
          // Accounts Garfin cannot manage are deliberately absent from here —
          // not listed, not counted, not named. The screen is the children
          // under a rule, and the space belongs to them.
          //
          // They are still *known*: the roster keeps them, because "this
          // server has no accounts at all" and "it has accounts and none of
          // them is managed" are different sentences and only the second one
          // gets [_NobodyYet]. Dropping the data would collapse that.
          //
          // What this costs, so it is not rediscovered as a bug: the listing
          // was the only answer to "why is this child not here?", and ground
          // rule 8 means Garfin cannot fix that absence anyway. The invitation
          // above is now the whole of what the screen says about it.
        ],
      ),
    );
  }
}


/// The children, drawn before their counts have arrived.
///
/// **Not a skeleton and not a spinner**: these are the real names and the real
/// pictures, which is everything the screen can honestly show yet. The numbers
/// appear beneath them when [kidsOverviewProvider] lands, and nothing here
/// moves when they do — the cards take the same place in the same order.
///
/// Deliberately without a placeholder bar or shimmer where the count will be.
/// A shape that implies a number is coming is a promise about a request that
/// may fail, and the honest version of "not known yet" on this screen is the
/// absence of a sentence rather than a grey rectangle pretending to be one.
class _FacesWhileCounting extends StatelessWidget {
  const _FacesWhileCounting({required this.roster});

  final KidsRoster roster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReadableList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        for (final face in roster.shortlisted)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  UserAvatar(name: face.user.name, avatarUrl: face.avatarUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(face.user.name,
                        style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}


/// The landing screen when there is nobody to look after yet.
///
/// An invitation rather than an empty state: the parent has a server and
/// accounts, and the one step left is one Garfin is not allowed to take for
/// them. The link goes to Jellyfin's own documentation because the setting
/// names are theirs and a summary here would go stale the first time they
/// moved one.
class _NobodyYet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.kidsWelcomeNoneHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.kidsWelcomeNoneBody,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.kidsWelcomeNoneLink),
              onPressed: () => launchUrl(
                Uri.parse(jellyfinUsersDocsUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
