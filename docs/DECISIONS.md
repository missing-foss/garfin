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

## Access schedules

**Shown on the Kids card, never written.** `AccessSchedules` lives inside `Policy`, so writing one
is the full-object replace ground rule 8 forbids — the same reason the rating cap is displayed and
not set. Scheduling stays in Jellyfin; summarising it honestly is Garfin's job.

**The hours are labelled as the server's, because they cannot be converted.** Measured: the API
gives the server's UTC instant and nothing about its offset, and a container running UTC+10 was
indistinguishable from one running UTC in every response Garfin makes. Rendering "8pm" as though it
were the reader's 8pm would be exactly the quiet wrongness this project keeps catching.

**No live "outside their hours right now".** It would be the most useful line on the card — it is
the answer to "why won't it let me in" — and Garfin cannot compute it without the offset above. A
status that is wrong for half the world is worse than no status.

**An absent schedule is stated rather than left blank.** No schedule means unrestricted hours; a
blank line where other children show times reads as the opposite.

---

## Signing a child in, on their behalf

**A child never learns their own password.** The parent creates the account, and onboards each of
the child's devices by approving the Quick Connect code that device shows. The child cannot sign in
anywhere without the parent, and every new device becomes an explicit parental decision.

**This is a supported use, not a trick.** Quick Connect exists so *you* can sign yourself in on a
television without typing a password on a remote — but `POST /QuickConnect/Authorize` takes an
optional, admin-only `userId`, first-class in the server's own OpenAPI, and a non-admin pointing it
at an administrator is refused with 403. The privilege boundary is enforced by the server, which is
why Garfin does not re-implement it.

**An id Garfin did not mean to send is refused before the request.** `Authorize` answers 200 to an
empty, absent or all-zero `userId` and signs the device in as the **approving administrator** — on a
child's device, the inversion of the product's purpose, with no error on either side. The server's
own privilege check (the 403) stays the server's; this is a different thing, and the distinction is
worth keeping: Garfin does not second-guess what the server permits, it declines to ask questions it
does not mean.

**Garfin cannot show what is being approved, and this is accepted rather than pending.** No endpoint
turns a code into device details — only the requesting device holds the secret that would. So the
confirmation names the child, reads the code back, and says plainly that the device was not checked.
The same is true of approving in Jellyfin's own web UI. Anything warmer would be implying a
verification that did not happen.

**The child is chosen by construction, not from a list.** The action lives on that child's own card,
so the silent failure — approving for the wrong child, which no screen would report — has no list to
happen in.

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

> **Amendment, 2026-08-05 (issue #69).** The gate sat *above* the whole app, so it also guarded
> sign-in — where Garfin holds no token, no server address and no children. It demanded biometrics
> from someone who had not yet typed a server address, to protect an empty app. The premise of the
> rule is "Garfin holds an admin token", and that becomes true the instant a session exists, which
> is now where the gate starts: inside the signed-in branch of `AppRoot`, never over sign-in.
>
> The same change puts the choice to a new parent once, on first sign-in: keep asking, or not now.
> **It is only ever offered to someone who has just signed in interactively.** A *restored* session
> is gated with no question asked — whoever picked the phone up has proved nothing, and offering
> them "not now" would be offering to skip the gate to exactly the person it exists for. That
> asymmetry is the whole point of the screen and is the case `test/unlock_start_test.dart` guards
> hardest.
>
> Answering "keep asking" leaves the app **locked**, not open behind the answered question: the
> gate has not run this session, so it stands exactly as a cold start would leave it.
>
> **And the offer expires with the moment it belonged to.** Provenance was the only thing gating
> the question, and provenance does not expire on its own: signing in, leaving it unanswered and
> putting the phone down left that screen up — with "Not now" on it — for whoever picked the phone
> up next, which is the person the gate exists for. Backgrounding now drops `justSignedIn`, so the
> next frame routes through the gated branch and the lock screen stands in front of the app.
> Nothing is recorded by that: an interruption is not an answer, and the next interactive sign-in
> asks properly.
>
> Rejected: wrapping the question in `UnlockGate` instead, which looks cheaper. The gate's
> controller starts locked whenever unlock is required, and it is required by default — so a
> parent who had just typed their Jellyfin password would be asked for a fingerprint *before*
> being asked whether they wanted one. The question must be reachable at the moment it is asked;
> what it must not do is outlive that moment.
>
> Found in review rather than by a test, and the reason is worth keeping: the suite covered
> provenance exhaustively — restored versus just-signed-in, answered versus not, both answers, a
> live gate — and never once sent the app to the background. A mutation table only catches what
> the harness can express.

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

## The About screen, and two reversals it forced (settled 2026-08-06, from issue #66)

Garfin had no About screen — it had four tiles at the bottom of Settings. The screen is now
the trobar-android shape: the mark, the wordmark in Fredoka, the version, a manual update
check, four links, and the licences. Two things that had been settled the other way had to
change for it, and both are recorded here rather than left in a diff.

**Links open now, and that reverses a deliberate decision.** The old code *showed* the source
address, with a comment saying why: launching a browser meant another dependency and another
licence review for one address. That reasoning was sound and it aged badly — a URL you cannot
tap on a phone is close to no link at all, and there are four of them now rather than one.
`url_launcher` **6.3.2** is taken; read from the package's own shipped `LICENSE`, as § Licence
in `CLAUDE.md` requires, it is **BSD-3-Clause, Copyright 2013 The Flutter Authors** — the same
text `local_auth` ships, byte-identical in the `url_launcher_android` case. `externalApplication`
mode, deliberately: an in-app web view would put a browser inside an app holding an admin token,
which is more surface than four static links are worth.

**The update check contacts a host that is not the user's server**, which SECURITY.md's "exactly
one host" sentence had to be rewritten for. The shape is what makes it acceptable: one request,
on a button press, never automatic; anonymous, with no token and no cookie; and on a *separate*
`Dio` with no interceptors, because Garfin's Jellyfin client attaches an admin token to
everything it sends and reusing it here would post that token to GitHub. GitHub learns the IP
address of whoever presses the button. That is the entire cost, it is not recoverable by design,
and it is why this is a button and not a poll.

**`/releases`, not `/releases/latest` — measured, not assumed.** The obvious endpoint answers
**404** for this repository: it excludes pre-releases, and every Garfin release so far is one. A
check built on it would have told every beta user "no releases published yet", forever, while
looking like a working feature. `/releases?per_page=1` sees them, newest first.

**The version comparison is three integers and nothing else.** Pre-release suffixes are ignored,
so `v0.2.0-beta.1` and `v0.2.0` compare equal. The asymmetry is deliberate: it can say "up to
date" a day early, and it cannot invent an update that does not exist. The tag is read with a
regex rather than by stripping a leading `v`, because the sibling project tags releases
`android-v2.14.0` and a parser that only survives its own repository's convention fails silently
— by reporting that everything is fine.

**Kept:** Flutter's built-in `showLicensePage`, rather than rendering a bundled
`THIRD_PARTY_NOTICES.md` the way trobar does. The built-in already knows every package compiled
in and cannot go stale; shipping a second list means shipping a list that can disagree with the
first.

**Deferred:** the tap-the-mark Easter egg. trobar's five-tap tic-tac-toe transfers as a
mechanism, but Garfin's mark is a fish and the game should not be a copy. It is a follow-up
rather than a stub, because a tap counter that opens nothing is dead code no test can cover.

---

## The verified count arrives after the sheet closes (settled 2026-08-06, from issue #68)

Ground rule 1 says report the **verified** count — the server's, re-read after the write, never
predicted. That is unchanged and not negotiable: it is what explains a share the rating cap
swallowed, where the tag landed and the number did not move.

What changed is who waits for it. The write is two round trips and costs ~18 ms, flat. The
verification is one query whose cost tracks **what the child can already see**, and worse than
linearly: 19 ms at one title, 214 ms at a thousand, 538 ms at two thousand — and 8.7 seconds at
six thousand, on a settled library with a 0.7 ms control alongside. So the sheet was holding a spinner
over work that had already finished, for a duration that grows the more successfully the app is
used.

The sheet now closes when the write succeeds. The toast appears immediately saying what is true —
*Shared with Emma*, or *Taken back from Emma*, direction-aware because both reach it — and the
sentence is replaced by the counted one when the server answers. Rule 1 holds: the number is still
the server's, still after the write, still never guessed.

**The pending sentence is not a placeholder.** If the count fails, or is slower than the eight
seconds the toast lives for (#65), it simply stays — it was a complete true statement on its own,
and the Kids screen carries the verified count regardless. A design where the first sentence is a
lie without the second would not be acceptable here.

Two related things fell out of the same measurement:

- **Undo asked for counts nobody read.** It routed through `apply`, which verifies; the sheet's
  Undo takes a `Future<void>` and the toast after it names no number. On a large library that was
  half a second of the server's time requested and discarded after every Undo. It no longer asks.
- **Two serial loops of that query became bounded-parallel** — the per-child counts after a write,
  and the Kids screen's own load. Both were `for` loops with an `await` inside, and `mapBounded`
  (limit 4) was already the house pattern a few dozen lines away in one of the same files.

Rejected: `/Items/Counts`, which does answer the same question — verified in four cases that could
have told them apart — but is roughly flat where `/Items` scales, so it would make the common case
four times slower to make the extreme case twice as fast.

---

## Open questions

- Whether to offer a migration when the tag prefix changes, or just document it
- Whether the Activity log persists across sessions or is session-only
- Music: albums and artists are taggable but the value is unclear — currently in scope, untested
- Whether to support multiple servers, or one at a time
