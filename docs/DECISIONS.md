<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Decisions

Why things are the way they are. If you want to change one of these, that's fine — but read the
rationale first, because the obvious alternative is usually what was rejected.

---

## Naming

**The app is called Garfin.** Chosen after checking eleven candidates against GitHub, app stores,
and trademark registers.

Rejected, with reasons worth remembering:

| Candidate | Why not |
|---|---|
| Guppy | Legally clear, but the namespace is saturated — Oxford Nanopore's basecaller, Quantinuum's quantum language, J&J's Android loggers, a Spanish EV rental app |
| Tidepool | Registered trademark of the Tidepool Project, a diabetes-software nonprofit shipping open-source mobile apps. Real conflict |
| Kidfin | Clear, but reads as a children's *banking* app to everyone outside the selfhosted world |
| Dalfin | Dalfin AI ships a no-code builder on Play and the App Store |
| Gardafin / Gardfin | `-fin` is the standard suffix for an Italian *finanziaria*; four Gardafin holding companies exist. `gardfin` is also listed as a typo of `gardin` |
| Espiafin | Namespace free, but *espiar* = "to spy". Searches return nothing but stalkerware. Wrong category entirely |
| Serafin | Serafin Asset Management ships a funds app in Germany and Switzerland |
| Baratze (Basque) | No software conflict, but Euskaltzaindia's corpus notes an ancient sense of "burial place" |
| Opari (Basque) | Every Opari sells gifts — brands in France, Switzerland, Spain, Kuwait |
| Kimu (Basque) | An active OSS front-end framework and an AI video-editing desktop app |
| Wardfin | Genuinely empty namespace, but rejected on feel |

**Standing lesson:** short, pretty, two-syllable names in any language are taken. `-fin` reads as
*finance* in most European markets. If a rename is ever needed, check the string against app
stores and company registers before falling in love with it.

**Jellyfin's trademark policy** permits the name as an affix showing compatibility — "X for
Jellyfin" is fine. It does not permit implying endorsement, and forks must use a different name
and logo. Hence the standing "not affiliated" line and the deliberate absence of any fin
silhouette in the mark.

---

## Product shape

**Library is the landing screen, not the user list.** The task that opens the app is "find
something for a kid", so the app opens on the thing you act on. The Kids screen is a settings
and overview surface, second in the nav.

**A child selector sits at the top of the Library.** Selecting a child does four things at once:
filters the grid to what that child can't see yet, exposes their rating cap as a one-tap chip,
badges already-shared titles, and sorts them to the top of the assign sheet. "Everyone" clears it.

**Avatars come from Jellyfin**, so the faces match what the children see on their own login
screen. This is worth the extra request.

**Already-shared titles are hidden by default.** Turns the grid into a to-do list rather than an
inventory. Cost: unsharing needs one extra tap to find the item. Accepted; the toggle is one tap
and the default is in Settings.

**Filters are one row of dropdown chips.** Each chip shows its filter name when unset and the
chosen value when set, so state is readable without opening anything. Stacked chip rows were tried
and ate ~120dp of poster space. The rating filter stays a plain toggle — it's binary, and burying
a safety control inside a menu would be wrong.

**The age filter is a filter, not a recommendation engine.** It hides anything above the child's
cap. No scoring, no suggestions. Keeps it honest about why a title appears.

---

## Tagging model

**Allow-list and block-list are opposite verbs.** `AllowedTags` set means the child sees *only*
tagged items, so sharing = adding a tag. `BlockedTags` set means they see everything *except*
tagged items, so sharing = removing one. The app detects the mode per user and inverts every
action. The two are never mixed on one account — that's the fastest route to an incomprehensible
library.

**Visible counts are fetched, never computed.** Two `/Items` calls with `Limit=0`, one as the
admin and one as the child. The server applies the policy, including the rating cap, which
silently overrides tags. A PG-capped child will not see a PG-13 title even when correctly tagged
— so the app flags that case rather than pretending tagging solved it.

**The tag prefix is optional and off-able.** Some servers already use bare account names as tags;
forcing `kids-` would orphan every label they have. The setting rewrites what the assign sheet
previews, so what you see is what gets written. Changing the prefix does not retag the library —
offer a one-off migration instead of silently rewriting thousands of items.

**Two independent cascades.** "Cascade to episodes" walks down a series; "cascade to collection
members" walks across a set. Separate switches, separate concerns.

---

## Collections

**Tagging a collection always writes to its members.** A Jellyfin BoxSet is a container; the
policy filters the films inside. Tagging the container alone appears to work and does nothing.

**Collections are browsable in their own right** — stacked cover, count badge, and the strictest
rating found among members.

**A collection counts as shared only when every member is.** Half-shared sets stay in the to-do
list rather than looking finished.

**Tagging one film in a set asks once**, listing the other members and their ratings, then either
keeps the set together or writes just the one. Default is *ask each time*, because "Jurassic Park"
and "Jurassic Park III" are not the same decision.

**The question only fires on additions.** Removing a label from one film never strips the rest —
silent cascading unshares would make the behaviour unpredictable.

**A film can belong to more than one BoxSet.** Handle multiple parents.

---

## Visual identity

**Material 3, dark-first,** generated from one seed (`#7C5CD6`) so Material You dynamic colour
drops in without redesign. Per-child colours are generated from a hue, same reason.

**Fredoka + Nunito, both SIL OFL 1.1** — free and GPL-compatible per the FSF. Roboto was avoided
on purpose: Apache 2.0 is fine with GPLv3 but incompatible with GPLv2, which would close off
relicensing later.

**The mark is a cartoon gar,** drawn as inline vector paths so it carries the project's licence
and no third-party asset terms. No fin silhouette anywhere near Jellyfin's trademarked one.

**Wordmark is the "eye-dot" construction** — the tittle on the *i* is the fish's eye. Chosen over
four alternatives because it's the only one that keeps character at 16px. The mono version knocks
the eye out as a ring; a solid dot just looks like a normal tittle.

**Brand assets are CC BY-SA 4.0, not GPL.** Copyleft on a logo means anyone can ship a modified
app under your mark. Forks are welcome; they should rename.

---

## Voice

Plain, warm, never cute about permissions.

- Say what happens: "Paddington is on Emma's shelf"
- Use the children's names — the app knows them
- Concrete verbs: pick, hand, share, take back
- **Never** "safe", "protected", or "secure" — it's a shortlist, not a guarantee
- **Never** surveillance words: monitor, track, watch over, control
- No jokes in errors, warnings, or anything about ratings
- The licence and non-affiliation lines stay plain

---

## Open questions

- Whether to offer a migration when the tag prefix changes, or just document it
- Whether the Activity log persists across sessions or is session-only
- Music: albums and artists are taggable but the value is unclear — currently in scope, untested
- Whether to support multiple servers, or one at a time
