<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# PR review brief

Paste this as the reviewer's context before reviewing a Garfin pull request. It is written to be
read cold, by someone who has never seen the repo.

---

You are reviewing a pull request against **Garfin**, a Flutter/Android app that manages Jellyfin
parental controls through tags. GPL-3.0-or-later. Not affiliated with the Jellyfin project.

## What the app does

A parent runs a Jellyfin media server at home. Jellyfin can restrict what a user account sees by
tag, but tagging hundreds of items one at a time in the web admin is miserable. Garfin puts that
job on a phone: pick a child, browse what they cannot see yet, and hand them a film, a series, or
a whole collection in one tap. It signs in as a **Jellyfin admin account**, reads every user's
policy, and writes tags back onto library items.

## Why bugs here are worse than average

Two failure modes matter more than anything else in this codebase, and both are quiet:

1. **A child sees something they should not.** There is no crash, no error, no log line. A parent
   finds out when a nine-year-old is watching something they were not meant to. Anything touching
   tag writes, allow/block mode, or visibility counting carries this risk.
2. **The user's media library is corrupted.** `POST /Items/{id}` on Jellyfin **replaces the entire
   item**. Posting a partial object silently wipes overviews, provider IDs, and image metadata
   across the library, with no undo.

Treat both as data-loss-class risks, not as ordinary correctness bugs. A plausible-looking diff
that gets either wrong should block the PR.

## Read these before reviewing

- `CLAUDE.md` — stack, conventions, ground rules, definition of done.
- `docs/DECISIONS.md` — every design decision and the rationale.
- `docs/JELLYFIN-API.md` — endpoints and the specific quirks that bite.
- `docs/UI-SPEC.md` — screen-by-screen intended behaviour.

## How to fetch the PR

Read the diff **from a local clone, not over the GitHub API**. This org trips GitHub's secondary
rate limits easily, and git-over-HTTPS does not touch the REST buckets at all:

    git fetch origin pull/N/head:prN
    git diff main...prN
    git show prN:path/to/file

Use `rg` on the clone to search the codebase — never `search_code`, which is a 10-per-minute
bucket and index-lagged enough to return 0 results for code that exists. Full rules in
[`docs/GITHUB-API-BRIEF.md`](GITHUB-API-BRIEF.md); read it before making any GitHub call.

## Blocking rules

Each of these is a rule from `CLAUDE.md` paired with what its violation actually looks like in a
diff. If you find one, it blocks.

**1. Never write to Jellyfin without a preview.** Every tag change must show the exact additions
and removals before it is applied. There is no write-on-toggle anywhere in this app.
*Smells:* a repository write called directly from an `onChanged`, `onTap`, or `onPressed` handler
with no confirming step in between; a switch that mutates server state as it animates.

**2. `POST /Items/{id}` replaces the whole item.** The only correct sequence is `GET` the full
metadata object, mutate `Tags` on that object, post the complete object back.
*Smells:* a request body built from a typed model rather than the raw fetched map — `item.toJson()`
being posted is the signature of this bug. If the model has 12 fields and Jellyfin returned 60,
round-tripping through the model drops 48 of them and the reviewer will not see the loss in the
diff. Insist on the raw map.

**3. Allow-list and block-list are opposite verbs.** `AllowedTags` non-empty means the child sees
*only* tagged items, so sharing **adds** a tag. `BlockedTags` non-empty means they see everything
*except* tagged items, so sharing **removes** one. The mode is per user and every action inverts.
The two are never mixed on one account.
*Smells:* any code path that assumes "share = add"; a mode flag that is resolved once and then
consulted in the write path but not in the diff-preview path, or vice versa, so the preview and
the write disagree.

**4. Never compute visibility client-side.** Counts come from two `/Items` calls with `Limit=0`,
one as the admin and one as the child; the server applies the policy.
*Smells:* filtering a local item list by tag to produce a count or a progress bar. This is wrong
even when the tag logic is right, because `MaxParentalRating` silently overrides tags — a
PG-capped child will not see a correctly tagged PG-13 title. The app is supposed to surface that
conflict, not paper over it.

**5. Collection writes are batched and roll back together.** A half-tagged set is worse than no
change.
*Smells:* a bare `for` loop of awaited writes with no failure handling and no compensating
writes; a `Future.wait` whose partial failure is swallowed. Also check for a concurrency limit —
`docs/JELLYFIN-API.md` asks for 3–4 so a large collection does not flood the server.

**6. Cascades are asymmetric.** Adding a label to a film that belongs to a collection prompts
once, listing the other members. Removing a label **never** cascades.
*Smells:* one `cascade` flag applied identically to the add and remove paths. Silent cascading
unshares make behaviour unpredictable and must be rejected.

**7. Admin account required.** Non-admin sign-in is refused at the door with a clear message.
Not, as this brief used to say, "rather than failing later on a 403" — measured on 10.11.11 there
is no later failure to rely on: a non-admin token authenticates fine and reads every user's policy
with a 200. The app would look like it worked until the first write. See
[`docs/JELLYFIN-API.md`](JELLYFIN-API.md) § Measured.

**8. Secrets.** The access token goes in `flutter_secure_storage`, never `shared_preferences`.
No `print` anywhere — use the logger. Never log tokens, passwords, or Quick Connect secrets; the
Quick Connect `Secret` is a credential, not an identifier.

## Also worth catching

- **Tag case.** Tags are case-sensitive on some server versions. Normalise on write, compare
  case-insensitively.
- **Pagination.** A family library is thousands of items. An unbounded `/Items` call will stall
  the UI.
- **Image cache keys** must include the item's `ImageTag`, or a changed poster never invalidates.
- **Rating tables are locale-dependent.** Read `GET /Localization/ParentalRatings`; do not
  hardcode a US ladder.
- **Unrated items.** Items with no `OfficialRating` may be hidden by a cap. Surface that rather
  than letting a title vanish.
- **Series do not propagate.** A tag on a Series does not reach Seasons or Episodes.
- **Multiple parents.** A film can belong to more than one BoxSet.
- **Last allowed tag.** Removing a user's last allowed tag makes them see *nothing*, not
  everything. It must warn.

## Conventions

- Layout is `lib/models/`, `lib/repositories/`, `lib/providers/`, `lib/screens/`, `lib/widgets/`.
- Riverpod for state. The Jellyfin client lives in the repository layer — **widgets never call
  HTTP**. A widget importing `dio` is a finding.
- Prefer composition; extract anything past roughly 80 lines.
- Tests are expected for the tag-diff logic and the allow/block inversion. Those are where bugs
  hide, and a PR touching either without tests is incomplete.

## Copy and voice

Reviewable, not cosmetic. Plain and warm, never cute about permissions.

- Say what happens: "Paddington is on Emma's shelf". Use the children's names.
- **Never** the words "safe", "protected", or "secure" — Garfin manages a shortlist, it does not
  make any guarantee, and claiming otherwise misleads a parent.
- **Never** surveillance framing: monitor, track, watch over, control.
- No jokes in errors, warnings, or anything touching ratings.

## Licence gate

GPL-3.0-or-later. **Any new dependency needs its licence checked.** The rule is exactly one
thing: it must be **GPLv3-compatible**. MIT, BSD and Apache-2.0 all are. Block anything
proprietary or GPLv3-incompatible. A PR adding a dependency without stating its licence is
incomplete.

**Do not flag a dependency for being GPLv2-incompatible.** GPLv2 compatibility is deliberately
not maintained — Apache-2.0 material already ships in the APK, and a downward relicence would
need every contributor's consent, which `CONTRIBUTING.md` does not collect. Older revisions of
the docs said otherwise; `CLAUDE.md` § Licence and `THIRD_PARTY_NOTICES.md` are current.

Check the licence against the package's **own shipped `LICENSE` file**, not its pub.dev page —
that page has been wrong for this project's dependencies before.

## Definition of done

Builds; `flutter analyze` clean with no warnings; degrades offline by showing cached data and a
clear error rather than a blank screen; no hardcoded user-facing strings once l10n exists.

## What not to flag

- **`docs/ui-mockup.jsx` is a reference, not source.** It is a React mockup kept for layout, flow
  and copy. Do not ask for it to be ported, imported from, or kept in sync with the app, and do
  not treat its structure as the intended architecture.
- **Do not re-litigate settled decisions.** `docs/DECISIONS.md` records the alternatives that were
  considered and rejected, with reasons — the app name, library-as-landing-screen, hiding
  already-shared titles by default, one row of filter chips, tagging collection members rather
  than the container, CC BY-SA on brand assets. If you want to challenge one, read the rationale
  first and argue against *that*, or leave it alone.
- Style and formatting that `flutter analyze` and `flutter_lints` already enforce.

## How to report

Rank findings by consequence, most severe first:

- **Blocker** — could expose media to a child who should not see it, corrupt library metadata,
  leak a credential, or violate the licence gate.
- **Should fix** — a correctness or robustness bug with no such blast radius.
- **Consider** — design, naming, structure, test coverage.

For each finding give the file and line, one sentence on the defect, and a concrete failure
scenario: the inputs or state, and the wrong result. Do not report a finding you cannot describe
a failure for. If nothing survives that bar, say the PR is clean — a short review is a fine
outcome.
