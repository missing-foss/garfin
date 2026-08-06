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

> **Superseded 2026-08-05 (#52).** The *concern* was right and is now met by construction: Garfin
> never invents a label, so it cannot force `kids-` on anybody. It reads the child's existing label
> out of `Policy.AllowedTags` and writes that string back, casing included. Which means the
> **setting itself cannot exist** — there is nothing to prefix, and no migration to offer, because
> Garfin does not own the naming. That follows from ground rule 8 (a first label is a policy write)
> exactly as "a child's first label is set up in Jellyfin" does. Removed from `UI-SPEC.md`
> § Settings, where the reasoning is repeated for anyone reading the spec rather than this file.

**The filter bar filters the administrator's view, and says so.** Type, Genre and Decade are
server-side parameters, and so is the rating chip — it goes out as `maxOfficialRating`, so nothing
compares a rating on the phone. But it is *not* a prediction of what the child sees: measured, an
unrated title passes every cap in that filter while a child whose policy sets `BlockUnratedItems`
cannot see it. Two mechanisms, one of them invisible from here. Hence "within Emma's limit" rather
than "what Emma can see" — the same distinction the result line already draws between *hasn't got
yet* and *can't see*.

**Two independent cascades.** "Cascade to episodes" walks down a series; "cascade to collection
members" walks across a set. Separate switches, separate concerns.

> **Corrected 2026-08-06 (#53). There is only one cascade, and this was right about which.** The
> collection one is real and is built (#50). The episode one is not needed at all: measured on
> 10.11.11, a label on a series **is inherited by its seasons and episodes** — they report it,
> `tags=` matches them, and the child sees every one of them, including a direct fetch of a single
> episode, with an untagged second show as the control answering 404. What this project had
> recorded — that the tag "does not propagate" — was wrong in both halves.
>
> "Separate switches, separate concerns" still holds as reasoning — a set and a series are different
> shapes, which is exactly why one needs a cascade and the other does not: a series **is** an
> ancestor of its episodes, and a BoxSet is not an ancestor of anything. See `JELLYFIN-API.md`
> § Series, seasons and episodes.

---

## Collections

**Tagging a collection always writes to its members.** A Jellyfin BoxSet is a container; the
policy filters the films inside. Tagging the container alone appears to work and does nothing.

> **Amended 2026-08-05 (#50), from measurement.** The first sentence stands and is still the
> load-bearing half. The second understates it, and the amendment is that **the write covers the
> container too**. Measured on 10.11.11 for an allow-list child: tagging only the container is not
> inert — the child gets the collection on their screen and it is **empty**; tagging only the
> members hands over the films while the set itself is absent from their library and browsing it
> answers **401**. To hand over a collection *as a collection*, both.
>
> That gives the container's label a job: written **last** on an addition and **first** on a
> removal, it is an accurate marker of "the whole set landed". A fix-forward partial therefore
> leaves it off and the half-tagged set stays in the to-do list below — which that decision asks
> for, and now costs the grid no extra query. Full matrix in `JELLYFIN-API.md` § Collections.

**Collections are browsable in their own right** — stacked cover, count badge, and the strictest
rating found among members.

**A collection counts as shared only when every member is** — and, per the amendment above, only
when the container carries the label too, because without it the child cannot reach the set at all.
Half-shared sets stay in the to-do list rather than looking finished.

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

> **Update, 2026-08-03.** The font choice stands, but that last clause no longer holds and
> should not be cited. GPLv2 compatibility is not maintained: `dynamic_color` is Apache-2.0 and
> already ships, and a downward relicence would need every contributor's consent, which
> `CONTRIBUTING.md` does not collect. Avoiding Roboto keeps the *font stack* unconstraining — a
> smaller and true claim. See `CLAUDE.md` § Licence.
>
> **Amended 2026-08-04 (#28).** This originally cited `material_symbols_icons` alongside
> `dynamic_color`. That package has been removed — nothing imported it and it was adding 33 MB of
> icon fonts to every APK. The conclusion is unchanged, and deliberately never rested on it:
> `dynamic_color` carries the Apache-2.0 exposure on its own, and the contributor-consent point
> is independent of the dependency tree entirely.

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

## Safety model (settled 2026-08-03, from issue #1)

**The app gates itself behind device auth.** Garfin holds a Jellyfin *admin* token, and the phone
running it is the phone handed to a child — that is the product's normal interaction. Device lock
protects a phone left on a table; it does nothing about one deliberately passed to the person the
app restricts. Biometric/PIN on cold start and on resume after an idle timeout. Rejected: gating
every write, which would cost the one-tap promise the product is built on while still leaving
every child's policy readable.

**Previews show the current count, never a predicted one.** A `− Frozen` line does not tell a
parent that the library is about to go dark. But predicting the resulting count means simulating
the server's policy evaluation locally, which is the one thing "never compute visibility
client-side" exists to forbid — the rating cap overrides tags silently, and a wrong prediction is
worse than none. So: current server-computed count in the preview, a hard warning when the removal
would take the label off the **last item carrying it**, and the real count re-fetched afterwards.
The after-count is also what explains a share the rating cap swallowed, which is otherwise
indistinguishable from the app being broken.

> **Correction, 2026-08-03.** This originally said the warning fires when the diff would "empty
> `AllowedTags`", justified as following from the policy's shape. Both halves were wrong, and
> review caught it: `AllowedTags` lives on the user policy, which ground rule 8 forbids Garfin
> from writing, so no diff the app can produce could empty it — the rule warned about an event
> another rule made impossible. The reachable case is the tag ceasing to match any item, which is
> a *count of tagged items*, not the policy's shape. Still a library query rather than a
> visibility computation, so rule 4 remains untouched — but the stated reason was wrong for the
> case that can actually happen.

**Collection writes fix forward. They do not roll back.** This reverses the earlier intent, and
the reason is arithmetic: undoing 7 successful writes of 12 means 7 more full-object replaces —
seven fresh chances to trigger the metadata wipe — on items that were fine. Tag writes are
idempotent, so retrying a failure is safe and repeatable while undoing a success is neither.
"A half-tagged set is worse than no change" is true about the product and false about the data.
Pre-flighting every member with a `GET` first costs nothing and catches most failures before any
write exists to regret.

**Garfin never writes a user policy.** The tempting fix for tag-casing mismatches is to normalise
the policy too, but `POST /Users/{id}/Policy` replaces the child's whole permission set including
`MaxParentalRating`. A dropped field there does not corrupt metadata, it removes a child's
restrictions. Instead the policy is the source of truth for casing — read `Kids-Emma`, write
`Kids-Emma` — which avoids the endpoint entirely.

**A child's first label is set up in Jellyfin, not Garfin — and that is a consequence, not an
oversight.** A child is only under shortlist control because `Policy.AllowedTags` already contains
a label; adding the first one is a policy write, so the rule above rules it out. Garfin manages an
existing shortlist, it does not create one.

This is a deliberate split rather than a gap: setting a child up is a **one-time** action, while
tagging hundreds of titles is the repeated one Garfin exists to replace. Sending the one-time
action to the web admin costs a parent very little, and it keeps the dangerous endpoint out of the
app entirely. The Kids screen says so in one plain line rather than listing those users with
nothing attached — see `docs/UI-SPEC.md`.

**The narrow exception is rejected, and will be proposed again.** Someone will suggest reading the
policy, changing only `AllowedTags`, and writing it back. That is still `POST /Users/{id}/Policy`
and still a full-object replace: the read-modify-write shape does not make it safe, it makes it
*look* safe, which is worse. The risk is not that we would mean to change something else — it is
that a field absent from the DTO we read, or added by a later Jellyfin version, silently vanishes
on the way back. `MaxParentalRating` disappearing that way removes a child's rating cap while
every screen still reports success. Treat this as settled.

**The Quick Connect secret is never persisted.** It lives for one exchange and is inert once
traded for the access token. Writing it to secure storage would only add a
stale-credential-after-crash case. Accepted cost: a process kill mid-pairing means a fresh code.

**No `SCORECARD_TOKEN`.** Adding a classic PAT with `repo` scope to a public repo's secrets, to
raise a security score, is a net loss. See `SECURITY.md`.

## The age hint advises; it never enforces (settled 2026-08-05, from issue #43)

**Jellyfin enforces the rating cap. Garfin suggests.** `MaxParentalRating` is applied server-side
and silently overrides tags — measured — but only if the parent set one, and on a self-hosted
server most accounts have no cap at all. The hint exists for that case: nothing is enforcing, the
parent is choosing, and a rating on the item plus a birth year they typed is enough to flag the
obvious mismatches.

It compares the item's `OfficialRating`, resolved through the server's own ladder, to the child's
age. It never filters, and `test/library_tile_test.dart` asserts the tile survives every value of
the enum.

**Ground rule 4 is untouched, and the distinction is worth keeping straight.** Rule 4 forbids
computing what a child can *see*, because that is the server's answer — tags and cap together. The
hint predicts nothing about the server; it compares two numbers and offers a sentence. It is the
same distinction rule 1 draws for the tagged-item count. The child's `MaxParentalRating` is
deliberately **not** an input, so the hint cannot drift into being a visibility prediction.

**"Not known" is a first-class answer, and it carries the weight.** Four situations produce it: the
item has no `OfficialRating`; its rating is not on the ladder (`Rated PG`, or a French certificate
on a US server); no birth year is set; or the ladder value is a sentinel rather than an age. Each
must read as *don't know* and look different from *suitable* — a helper that quietly reported
absence as suitability would be wrong exactly where a parent is trusting it, and unrated files are
arguably the majority case in a self-hosted library.

Rejected — treating an unrated item as suitable, on the grounds that most unrated files in a
family library are innocuous. Probably true and entirely beside the point: the cost of being
wrong is asymmetric, and the parent can see the answer is missing and decide for themselves.

**The age it compares against is the one the child is *guaranteed* to have reached.** Only a year
is stored, so a child is either `today.year - birthYear` or one less depending on whether their
birthday has passed. The hint takes the lower.

Taking the higher — the obvious arithmetic, and what this first shipped as — biases every hint
toward *suitable* for roughly half of children at any moment: born 2013, on 2026-08-05 the sum
says 13 while a November birthday means 12, and a 13-rated title reads as suiting them. Systematic,
invisible, and pointed the wrong way. Erring low means the hint appears slightly too often and a
parent who knows the birthday dismisses it, which is the failure worth having. Same asymmetry as
the unrated case above, and it gives the same answer.

This is deliberately **different from the age on the Kids card**, which is a best estimate that
nothing branches on. A number that decides something and a number that is merely displayed can
honestly differ by a year for part of the year.

**The ladder's values are an ordering, not ages.** They align with ages in the low range on the
measured US ladder — 7, 10, 13, 14, 17, 18, 21 — and then jump to 1000 (`XXX`) and 1001
(`Banned`), which are sentinels. Values outside 0–21 answer *not known*. The mapping is read from
the ladder rather than hardcoded, because the ladder is locale-dependent, and `PG = 10` never
meant "suitable at ten" in the first place.

## The Library grid's two filters (settled 2026-08-05, from issue #44)

**Hide-shared filters client-side, over an enlarged fetch window.** `/Items` takes 86 parameters
and **none of them excludes by tag** — measured on 10.11.11. So "what this child hasn't got yet"
has no direct server query, and the grid asks for more than a screenful while hiding is on, then
keeps fetching until the visible rows fill.

Rejected — `excludeItemIds`, the obvious server-side answer. It is a comma-delimited query string,
so the URL grows with the *shared* set, and the shared set is precisely what grows as the app is
used. Around 240 ids is roughly 8 KB, the default request-line limit in Kestrel, which Jellyfin
runs behind. A parent who has shared 300 titles with a child would get a 414 — and 300 shared
titles is ordinary use, not an edge case. The client-side cost is a variable number of requests
once nearly everything is shared, which lands exactly when the grid is nearly empty and resolves
quickly.

Rejected — dropping hide-by-default. § Product shape already settled that hiding turns the grid
into a to-do list rather than an inventory, and the paging mechanics do not bear on that.

**The visibility diff decorates; it never filters.** An item the server does not show to the
selected child stays on the grid, marked. Two reasons, the second stronger than the first: it
leaves exactly one filtering axis, so ragged-page handling stays in one place; and hiding a
given-but-invisible film would hide the one case the feature exists to explain. A parent tags
something, the count does not move, and the tile is what tells them why — remove the tile and the
confusion comes back.

So the rule is: **hide-shared may remove tiles. The cap diff may only change how they look.**

**Visibility is asked, never computed.** The state comes from `GET /Items?userId={child}&ids=…`
against the ids on screen — the server applying tags and cap together — and not from comparing the
item's `OfficialRating` to the child's `MaxParentalRating`. That comparison is ground rule 4
verbatim and fails silently on unrated items, on a non-US ladder, and on anything hidden for a
reason that is not the cap at all. A folder permission is indistinguishable from a rating cap from
here, which is also why the screen *offers* a reason rather than asserting one.

## Nothing syncs to a cloud account (settled 2026-08-05, from issue #35)

**Garfin is a tool for self-hosters, and nothing it stores leaves the device for anyone's cloud.**
This is a standing principle, not a manifest attribute. It is the same instinct as the app having
no backend, no account system and no telemetry: someone who runs their own media server did that
on purpose, and an app for them should not quietly post their household's shape to Google.

Implemented as `android:allowBackup="false"` **plus** a `dataExtractionRules` file excluding
everything from both `<cloud-backup>` and `<device-transfer>`. Both are required —
`allowBackup="false"` alone leaves device-to-device transfer enabled on some manufacturers'
devices for apps targeting API 31+, per Android's own documentation, which is a gap that would
hold on whichever handset it was tested on and not on someone else's.

Rejected — **excluding selectively**, keeping the server URL and unlock settings while dropping
`device_id` and the account fields. It is the most precise option and the least durable: at
`minSdk 26` it needs two files saying the same thing, and worse, it creates a **standing
obligation that fails silently**. Every key added later becomes "did anyone remember to exclude
it?", and the first one due is the child's birth year in step 3. Blanket exclusion is correct by
default for keys nobody has written yet.

Rejected — **leaving it on**, on the grounds that it is the user's own account and Android
encrypts the backup with a key derived from their device credential. Both true, and the reason
this needed deciding rather than assuming. What decided it: the restore is *already* incomplete,
because `flutter_secure_storage`'s master key lives in the Keystore and is not backed up, so the
token cannot come back and the user signs in again regardless. Backup was therefore buying a
pre-filled hostname and two settings — and restoring `device_id` alongside them, which is
actively wrong, since Jellyfin keys a session on it and a restored phone would present the same
`DeviceId` as the old one.

Accepted cost, and it is real: a reinstall or a new phone loses the server address and the unlock
preferences. For an app whose job is being convenient about a fiddly task that is not nothing —
but it lands on a path that already requires signing in again.

One consequence worth keeping: an undecryptable secure-storage blob makes `TokenStore.read()`
throw rather than return null. `allowBackup="false"` removes the restore path that would cause
it, but not the others — changing the device credential or re-enrolling biometrics can invalidate
the Keystore key the same way. `app_root.dart` renders that `AsyncError` as the sign-in screen,
deliberately, and `test/widget_test.dart` now pins it.

**`FLAG_SECURE` is set, blanket, on the one window (settled 2026-08-05, from issue #26).** The
issue deliberately refused to pick an option until the exposure had been *measured*, because
`FLAG_SECURE` costs a legitimate user something real and the case for it had been argued from
documented Android behaviour rather than observed. Measured 2026-08-05; numbers in `SECURITY.md`.

What the measurement changed: the exposure is not a live thumbnail, it is a **file on disk** at
`/data/system_ce/0/snapshots/<taskId>.jpg` that outlives the idle timeout byte-identical. So
resuming demands authentication while the switcher still shows what was on screen before the app
relocked. The gate locks on resume and the snapshot is taken on the way out, which means no
amount of work on the gate can reach it.

Rejected — **cover on `paused`**: it avoids the screenshot cost, but its correctness depends on a
lock scrim rasterising before WindowManager takes the snapshot, and nothing in the app controls
that ordering. `FLAG_SECURE` is refused by the system rather than beaten by timing; there is no
race to lose. Rejected — **toggle the flag around the lifecycle**: narrower in principle, but it
reintroduces the same race plus window-flag churn as a fresh bug source. Rejected — **accept and
document it**: defensible while the only gated screen was a placeholder, but step 3 puts the Kids
screen behind the gate, so accepting would mean reopening this immediately.

Accepted cost, and it is a real one: the parent cannot screenshot Garfin or mirror it to another
screen. Garfin is not a media player, so casting it was never the point; screenshots for a bug
report are the genuine loss. Weighed against an admin token on a phone handed to children by
design — ground rule 9's whole premise — the trade is worth making.

Implemented natively in `MainActivity.onCreate`, not via a plugin. The usual plugin suggestion,
`flutter_windowmanager`, is not an option here at all: latest is 0.2.0, published 2021-08-26, and
its constraint is `sdk: >=2.12.0 <3.0.0` — it excludes Dart 3, and this project is on 3.12.2
(checked 2026-08-05 against pub.dev's API). Even were it current, it would be a dependency and a
licence review bought for a one-line platform call.

---

## Open questions

- Whether to offer a migration when the tag prefix changes, or just document it
- Whether the Activity log persists across sessions or is session-only
- Music: albums and artists are taggable but the value is unclear — currently in scope, untested
- Whether to support multiple servers, or one at a time
