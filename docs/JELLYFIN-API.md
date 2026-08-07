<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Jellyfin API notes

Everything Garfin needs, plus the parts that will bite. Verify against the server's own
`/api-docs/swagger` — the API moves between versions.

## Measuring this without measuring your own harness

Everything in this file was measured against a throwaway server, and the measurements that were
*wrong* were never wrong about the status code. They were wrong because the harness answered a
different question, confidently, with no error to notice.

**That is the species worth naming: a harness that answers confidently and wrongly rather than
erroring.** The ordinary defence — read the error — never fires. Five instances so far, all caught,
each by a different accident:

| The trap | What it looked like | Why nothing errored |
|---|---|---|
| **The container that never bound** | a health check reporting a healthy server | it *was* healthy — it was the **live** server on the same port |
| **A spent single-use value** | "an absent `userId` answers 500" | the code had been used by an earlier step; the 500 was the code's (#40) |
| **A shared `DeviceId`** | every call after the second answering 401 | the "device" client authenticated as the admin and invalidated the admin's own token (#40) |
| **A query that fetched nothing** | "0 items, so the claim holds" | a wrong `parentId` and a true claim are the same empty list (#55) |
| **Observing a state you wrote** | "descendants carry no tags" | the harness had written `Tags: []` to them itself (#55) |
| **A fixture the scanner renamed** | `KeyError: 'Bravo'` — and, one step later, a fixture silently written to the wrong film | an empty `Bravo.mkv` is still matched by the metadata provider and the item comes back called **`Rio Bravo`**; `Charlie.mkv` became *Charlie and the Chocolate Factory* and `Delta.mkv` *The Delta Force* (#81). Key a fixture on **`Path`**, never on `Name` |

The checks are cheap and none of them is clever:

1. **Assert the target is the throwaway before writing**, per the protocol in § Writing tags —
   `"StartupWizardCompleted": false`. It fails closed against every way of ending up on the wrong
   server, including the one nobody predicted.
2. **One fresh single-use value per case.** Quick Connect codes are spent by the first `Authorize`;
   reusing one measures the code rather than the variable you meant to vary.
3. **One `DeviceId` per client.** Jellyfin retires a device's previous token when a new session
   claims the same id, so a probe sharing an id with the admin client kills the run halfway and the
   rest of it measures a dead session. **Measured on 10.11.11, with a control** — because in a
   section about not mistaking a conclusion for a measurement, this was the one line that was an
   inference about the server's rule rather than an observation of the harness:

       token1 (DeviceId=shared-id), before token2 exists   -> 200
       token1 (DeviceId=shared-id), after token2 claims it -> 401
       token3 / token4 (distinct ids), both after          -> 200, 200

   `GET /Sessions` corroborates it from the other side: one session for the shared id — the newer
   client — and both distinct ids still present. Caught and closed in review of #60.
4. **Require `n > 0` before believing a negative.** A "nothing found" result and a query that asked
   the wrong thing are indistinguishable, and a false confirmation is worse than a false alarm —
   nobody goes back to check it.
5. **Never observe a state your harness created.** If the setup writes it, the measurement is of the
   setup. Read the fixture back through a *different* path than the one that wrote it.
6. **Keep a control in every sweep.** A second show that is never tagged, a genre filter with a
   known answer, an untouched sibling item: the row that proves the query can still say no.

Both #40 and #55 were caught in review rather than by the person running the sweep, and in both
cases the reviewer's own run had avoided the trap by accident rather than by design — a loop that
happened to generate a fresh value each time, distinct device ids chosen for unrelated reasons. A
confound you dodge by luck is one that returns when the loop is written differently. Which is the
argument for **independent reproduction** rather than for care: a second harness fails in different
places, and one person running one sweep twice is not a substitute for that.

### The harder case: a claim that was never measured at all

Every trap above is a measurement that answered the wrong question. There is a second failure in
this file's history, and it is worse in one specific way — **nothing ran**:

| #60 | "Jellyfin retires a device's previous token when a new session claims the same id" — a rule about the server, inferred from a 401 cascade that several mechanisms would explain |
| #41 | "passing the wrong id answers 204 and ends nothing" — only the *correct* id had ever been sent |

Both were stated in the same voice as the measurements around them, and **a prose claim sitting
between two code blocks inherits their authority**. No control catches this, because there is no
confound to find: the checks above defend against measuring the wrong thing, and this is not
measuring at all.

The only defence is marking which lines are observations and which are inferences — which is what
**"measured on 10.11.11"** is for, and why it appears as often as it does.

**That marker is a convention from here on, not a property of the file today.** Counted at the time
of writing: 42 sections, 22 carrying a marker and 20 not, and fifteen of the unmarked ones state
hard facts in code blocks — several of which two people have independently re-measured. So an
unmarked line means **unaudited, not doubtful**, and a rule that told you to distrust half the
document would simply be ignored. The marker is applied as sections are revisited, and accumulates.

What it buys, from here on: **a line that states a server behaviour and carries no marker is the
line to check first** — including, and especially, your own.

## Auth

    POST /QuickConnect/Initiate                  -> { Code, Secret }
    GET  /QuickConnect/Connect?secret={Secret}   -> poll until Authenticated == true
    POST /Users/AuthenticateWithQuickConnect     { Secret }  -> AccessToken, User
    POST /Users/AuthenticateByName               { Username, Pw }   (fallback)

Every subsequent request carries:

    Authorization: MediaBrowser Token="...", Client="Garfin", Device="...", DeviceId="...", Version="..."

Quick Connect must be enabled server-side; if `GET /QuickConnect/Enabled` is false, hide the tab
rather than failing on Initiate. Poll with a backoff and a timeout — do not hammer.

### Measured against 10.11.11, 2026-08-03

Same protocol as the write-path experiment below: throwaway container, loopback-only,
`StartupWizardCompleted: false` asserted before anything was written, torn down with its volumes.

**`Initiate` is a POST.** This file used to say `GET`, and the GET *does* still answer 200 on
10.11.11 — but the server's own `/api-docs/openapi.json` lists only `post` for that route. The GET
is an undocumented survivor, so it is the one that can vanish in a point release. Use POST.

**The `Authorization` header is required on the anonymous calls.** `Initiate` echoes `DeviceId`,
`DeviceName`, `AppName` and `AppVersion` straight back out of it, and that is what the user sees
when asked to approve the code. A missing header there is not a 401, it is a nameless approval
prompt.

**And there is no second way to send it — so Garfin cannot sit behind a reverse proxy that does
HTTP basic auth.** The proxy wants `Authorization: Basic …`, Jellyfin wants
`Authorization: MediaBrowser …`, and one header cannot be both. Every alternative was tried:

| Route for the device identity | 10.11.11 |
|---|---|
| `X-Emby-Authorization: MediaBrowser …` + `Authorization: Basic` | **400** on `AuthenticateByName`, **401** on `/Users/Me` |
| Split `X-Emby-Client` / `X-Emby-Device-Name` / `X-Emby-Device-Id` / `X-Emby-Client-Version` | **400** |
| No identity at all | **400** |
| `X-Emby-Token: <token>` + `Authorization: Basic` | **200** |

Only the last one works, and it is no help: it carries a token, and a token is the thing you can
only get by signing in first — which is the call that fails. `X-Emby-Authorization` and the split
`X-Emby-*` identity headers have been removed from this version.

Consequence, and it is a *cannot* rather than a *have not*: a `user:password@` in the server
address is dropped rather than used. It is also dropped because keeping it would write a password
to `shared_preferences` in clear and put it on screen — but even if that were solved, sign-in
would still fail. The address step says so instead of discarding it silently. Re-test this on a
version bump; if an identity header returns, so does the feature.

**Status codes, and what each one means to a user:**

| Call | Condition | Answer |
|---|---|---|
| `POST /Users/AuthenticateByName` | wrong password | `401` |
| `GET /Users/Me` | token no longer valid | `401` |
| `GET /QuickConnect/Connect` | unknown or aged-out secret | `404 "Unknown secret"` |
| `POST /Users/AuthenticateWithQuickConnect` | secret not approved yet | `404` |
| any `/QuickConnect/*` | feature switched off | `401 "Quick connect is disabled"` |

That last row is the trap: a 401 from a Quick Connect route means *the feature is off*, not *your
credentials are wrong*. Mapping it to a credentials message sends the user off fixing a password
that was never the problem. Quick Connect is **on by default** on 10.11.11
(`QuickConnectAvailable: true`), so the off-path is easy to never see in testing.

**`AuthenticationResult` carries exactly `AccessToken`, `ServerId`, `SessionInfo`, `User`.**

**A non-admin is not stopped by the server.** Signing in as a non-administrator succeeds and
returns a working token, and `GET /Users` with that token answers **200 with every user's `Policy`
populated** — including `IsAdministrator` and the shortlist fields. There is no 403 waiting to
catch the mistake: Garfin would build the entire Kids screen from a child's token and only fail at
the first write. Ground rule 7's check at sign-in is therefore not a nicety that saves a confusing
error later, it is the *only* thing standing between a wrong account and a working-looking app.

**Casing is content-negotiated, and it is not stable during startup.** `Accept: application/json`
gets PascalCase; `application/json; profile="CamelCase"` gets camelCase. But polling
`/System/Info/Public` across a container restart returned **camelCase with HTTP 200** for roughly
the first second, then a `503` loading page, then PascalCase steady state. A parser keyed on exact
field names reads that early reply as an object with everything missing — for
`AuthenticationResult` that is an empty token and a `Policy` that looks like "not an
administrator", i.e. a sign-in refused for the wrong reason on a server that had just rebooted.
Read DTO fields case-insensitively (`lib/models/dto_json.dart`).

**The server answers `503` while it is loading**, sometimes as an HTML page and sometimes as the
plain text `Jellyfin Server is loading. Please try again shortly.` — so a JSON parser has to
survive a non-JSON body on a failed call.

**The `Secret` lives in memory only. It is never written to disk** — not to
`flutter_secure_storage`, not anywhere. It is a credential for the length of one exchange and is
inert once traded for the `AccessToken`, so persisting it only creates a stale-credential-after-
crash case that memory-only cannot have. Clear it on success, on timeout, and on dispose.

Consequence to accept: the user will normally background Garfin mid-pairing, because authorising
the code means opening an already-signed-in Jellyfin session. If Android kills the process, the
Secret is gone and pairing restarts with a fresh code. That is the intended behaviour, not a bug
to work around.

The `AccessToken` is the opposite case — long-lived, must survive restarts, and belongs in
`flutter_secure_storage`.

**Admin check:** the authenticated user's `Policy.IsAdministrator` must be true. Refuse at sign-in
with a clear message. Note the measured correction above: on 10.11.11 reading other users'
policies does **not** require it — a non-admin token reads them all with a 200 — so nothing
downstream will catch a wrong account for you.

## Users and policy

    GET /Users

Per user, the fields that matter:

- `Policy.AllowedTags` — non-empty means allow-list mode
- `Policy.BlockedTags` — non-empty means block-list mode
- `Policy.MaxParentalRating` — **silently overrides tags**
- `Policy.EnabledFolders` / `EnableAllFolders` — library access
- `Policy.IsAdministrator`, `Policy.IsDisabled`
- `PrimaryImageTag` — for the avatar

Avatar: `GET /Users/{id}/Images/Primary?tag={PrimaryImageTag}`. Absent tag = no avatar set;
fall back to an initial.

**Garfin never writes a policy.** `POST /Users/{id}/Policy` takes the full policy object and
replaces it, exactly like `POST /Items/{id}` — but the blast radius is the child's entire
permission set. Dropping `MaxParentalRating` on a round-trip does not corrupt metadata, it
silently removes the rating cap, which is the one control that still holds when tagging is wrong.
Read policy, write items. See ground rule 8.

## Counting what a user can see

    GET /Items?userId={admin}&Recursive=true&Limit=0   -> TotalRecordCount
    GET /Items?userId={child}&Recursive=true&Limit=0   -> TotalRecordCount

The server applies the policy. Never compute this client-side. Per library, add
`parentId={libraryId}`.

### Measured, 2026-08-06 — what this call costs, and what it scales with (#68)

`Limit=0` keeps the *payload* empty. It does not make the server's work small,
and the doc comment in `jellyfin_api.dart` used to claim this was therefore
"cheap enough to do per child". That claim was never measured. It is wrong.

A throwaway 10.11.11, films generated with ffmpeg, no metadata fetchers, medians
of seven calls after a discarded warm-up, with `/System/Info/Public` timed
alongside at every size as a control (0.6–1.2 ms throughout, so none of the
below is the harness or the machine):

| library | GET full item | POST full item | count, child sees 1 | count, admin sees all |
|---|---|---|---|---|
| 100 | 10.1 ms | 9.4 ms | 15.9 ms | 15.0 ms |
| 500 | 8.7 ms | 7.5 ms | 13.9 ms | 28.7 ms |
| 2000 | 9.4 ms | 8.9 ms | 17.4 ms | **525.8 ms** |
| 6000 | 9.4 ms | 8.3 ms | — | **7613.6 ms** |

**The write is flat. The count is not.** And the first reading of that table is
wrong: it looks like the child's query is cheap and the admin's is expensive,
but those two differ in the size of the *result set* as much as in whose policy
applies. Holding the library at 2000 and growing what the child can see:

| child can see | count | library |
|---|---|---|
| 1 | 18.8 ms | 2000 |
| 250 | 27.2 ms | 2000 |
| 1000 | 214.3 ms | 2000 |
| 2000 | 538.3 ms | 2000 |
| 4646 | 5363.8 ms | 6000 |
| 6000 | 8726.2 ms | 6000 |

The 6000 rows were measured on a **settled** library — the item count held at
6000 across five consecutive thirty-second checks before anything was timed —
with `/System/Info/Public` at 0.7 ms alongside. An earlier attempt at these
timed while the scan was still ingesting (4499 items, then 4617, *during* the
run) and reported 5.2 s for the admin total; that is the harness competing with
the thing it measures, and the number is not usable. Three stable readings were
not enough to detect it either, because a Jellyfin scan pauses. Five were.

**The cost tracks the result set, not the library.** A child who can see
everything costs exactly what the admin costs. So this call gets slower as a
parent shares more, which is the app being used successfully — the worst shape a
cost curve can have.

**And it is worse than linear.** 100 → 2000 items is 20× the library for 35× the
time; 2000 → 6000 is 3× for **14×**. At 6000 titles one verified count is
between five and nine seconds, and the write it verifies is still nine
milliseconds.

Consequences, both now in the code: the verified count is not something to block
a UI on, and a loop of them must not be serial.

#### `/Items/Counts` is not the way out

It answers the same question — checked in four cases that could tell them apart,
not just the easy one:

| case | `/Items` | `/Items/Counts` | agree |
|---|---|---|---|
| child sees a subset (250 of 2000) | 250 | 250 | yes |
| child sees nothing | 0 | 0 | yes |
| child blocked by `BlockUnratedItems` | 0 | 0 | yes |
| the admin | 2000 | 2000 | yes |

**The first version of this test proved nothing**: every film was tagged for
that child, so all six candidates returned 2000 and a query ignoring the policy
entirely would have "agreed" too. Two numbers matching under a condition that
cannot tell them apart is the harness answering its own question.

But it is the wrong trade. `/Items/Counts` is roughly flat where `/Items`
scales — 122 ms against 30 ms for a child seeing 250, and 221 ms against 492 ms
for the admin. Swapping would make the common case four times slower to make the
extreme case twice as fast.

Also measured and rejected: `enableTotalRecordCount=false` (returns 0 — it is
the number, not an extra), and `Limit=1` instead of `Limit=0` (**slower**, 1041
ms against 540 ms).

### Measured, 2026-08-05 — the admin token honours `userId`

This was asserted here for two days before anyone checked it, and it is the
assumption the whole Kids screen rests on: if an admin token *ignored* the
`userId` parameter, every child would show the administrator's total and every
test would still pass, because the tests can only confirm Garfin sends what it
means to send.

Four movies, two tagged `kids`, a child holding `AllowedTags: ["kids"]`:

    GET /Items?userId={id}&Recursive=true&Limit=0&IncludeItemTypes=Movie,Series

    admin token, admin userId   -> TotalRecordCount 4
    admin token, child userId   -> TotalRecordCount 2      policy applied
    child's OWN token           -> TotalRecordCount 2      control, agrees exactly

**The control is the part that matters.** Without it, a smaller number is
equally consistent with "the server filtered by `userId`" and with "the number
happened to be smaller". Asking as the child, with the child's own token, is
what distinguishes them — and the two agree exactly.

### Measured, 2026-08-05 — the rating cap really does override a correct tag

The justification for ground rule 4, demonstrated rather than argued. Starting
from the child's count of 2 above, setting `OfficialRating=R` on one of the two
**correctly tagged** items and `MaxParentalRating=7` on the child:

    admin token, child userId   -> TotalRecordCount 2 -> 0

A properly tagged title disappears. This is why a count derived from the tag
list would be confidently wrong for exactly the children who have a cap, and
why `SECURITY.md` and the Kids screen both show the cap next to the tags — so a
parent can see the reason rather than concluding Garfin is broken.

### Measured, 2026-08-05 — an unrated item is not a low-rated one

Three movies, two labelled for a child with `AllowedTags`. Setting
`OfficialRating=R` on one of the labelled pair and `MaxParentalRating=7` on the
child, then asking which of them the child can see:

    before the cap  -> both labelled items
    after  the cap  -> only one of them

The item that stayed visible has **no `OfficialRating` at all** — the key is
absent, not set to something low.

That is the concrete case behind ground rule 4. Locally there is no way to tell
*"unrated, therefore fine"* from *"rated above the cap"* without reimplementing
the server's policy evaluation, and the two land on opposite sides of the
answer. It is why the Library grid asks the server which items a child can see
rather than comparing an item's rating to a child's cap.

**`ids=` needs no `Recursive=true`.** It is its own lookup. Measured against
items nested inside a library, the answer is identical with and without the
flag — three ids in, three back for the administrator and two for a child
restricted **by tags** either way, only two of the three being labelled. Every other `/Items` call here passes `Recursive`, so the
omission looks like an oversight and is not.

    GET /Users/{id}/Views     -> libraries this user can reach

### Approving a code on someone else's behalf (#40)

    POST /QuickConnect/Authorize?code={code}&userId={childId}    -> 200 true

**Measured on 10.11.11**, re-run 2026-08-06. `userId` is an optional, admin-only parameter on the
server's own OpenAPI, and it is the whole of this feature: the parent approves, the **child's**
device exchanges its own secret, and the session that comes out is the child's with
`IsAdministrator: false`. No password is typed on the child's device — one the child need never be
told.

| attempt | result |
|---|---|
| admin approves with `userId=<child>` | 200, the child's device gets a child session |
| **non-admin approves with `userId=<admin>`** | **403** |
| non-admin approves for themselves, no `userId` | 200 — ordinary Quick Connect |
| a code nobody asked for | 404 |
| a well-formed `userId` that does not exist | **400** |
| the same code twice | **500** |

The 403 is load-bearing: **the privilege boundary is the server's**, so Garfin does not re-implement
it — a check it implemented would be the one that could be wrong.

> **An earlier version of this table said the last two both answered 500.** That was a confounded
> measurement: the absent-user case reused a code an earlier step had already spent, so the 500 came
> from the code rather than from the id. Re-run with **a fresh code per case**, they are 400 and 500
> and the server tells them apart perfectly well. Caught in review of #40. The lesson is the cheap
> one — a sweep that reuses a single-use value measures the value, not the variable.

### `Authorize` fails open to the approving administrator

**The finding that shapes the code.** Measured, each case on its own fresh code, following the
device through to the session it actually receives:

| `userId` sent | approve | the session the device gets |
|---|---|---|
| `<child>` | 200 `true` | **the child**, `IsAdministrator: false` |
| the all-zero GUID | 200 `true` | **the administrator**, `IsAdministrator: true` |
| omitted entirely | 200 `true` | **the administrator** |
| the empty string | 200 `true` | **the administrator** |

No error anywhere in that. The device shows a code, the parent approves it on a child's card, and
the tablet receives an **administrator** session while the app reports the child was signed in —
the exact inversion of what this app is for, silent in both directions.

`JellyfinUser.fromJson` defaults a missing `Id` to `''`, so one malformed `/Users` row is all it
would take. `approveQuickConnect` therefore refuses an empty or all-zero `userId` **before** the
request. That is not re-implementing the server's privilege check — that check is the 403, and it
stays the server's — it is declining to send a request whose meaning Garfin does not intend. It is
the same family as `fullItem` comparing the id it got back with the one it asked for: the all-zero
GUID again, on a route that mints sessions rather than returning a folder.

**Nothing can be shown about the device being approved.** Only `Authorize` takes a code; the one
route carrying `DeviceName`, `AppName` and `AppVersion` is `GET /QuickConnect/Connect`, which needs
the **secret** — held solely by the requesting device. Asking it for a code answers 404. The five
Quick Connect routes and their parameters are the whole surface:

    POST /QuickConnect/Authorize   code, userId
    GET  /QuickConnect/Connect     secret
    GET  /QuickConnect/Enabled     —
    POST /QuickConnect/Initiate    —
    POST /Users/AuthenticateWithQuickConnect

This is the same blindness as approving in Jellyfin's own web UI, so it is not a regression — but a
parent can be talked into approving a code that is not their child's device, and the confirmation
says so rather than implying anything was checked.

**This is not a policy write.** `Authorize` mints a session; ground rule 8 is about
`POST /Users/{id}/Policy` and its full-object replace, and none of that risk is in play.

## Access schedules — the other half of the parental controls

`Policy.AccessSchedules` is a list of `{ Id, UserId, DayOfWeek, StartHour, EndHour }`.
**Measured on 10.11.11 (#49)**, on a container deliberately running `TZ=Australia/Sydney` so a
local-clock leak would be obvious.

    read back: [{"Id":1,"UserId":"…","DayOfWeek":"Everyday","StartHour":8.5,"EndHour":20.25}]

- **The hours are floats.** `8.5` is 08:30, `20.25` is 20:15. An int-typed reader turns half past
  into the hour, in the direction of *more* access.
- **`DayOfWeek` has ten values, not seven**: the days plus `Everyday`, `Weekday` and `Weekend`.
  `Everyday` is what the server writes for the commonest configuration. An unknown value is
  rejected with **400** and the previous schedule is kept.

### What a schedule gates — and it is not visibility

    inside the window : password auth 200, items the child can see 1
    outside          : password auth 403, items the child can see 1   <- unchanged

And it is not only sign-in. A token obtained **inside** the window stops working when the window
closes:

    inside : /Users/Me 200, /Items 200
    outside: /Users/Me 403, /Items 403

So the schedule gates **every request**, session and all, while the set of items the account would
see is identical either way. Nothing in the Library grid moves with the clock.

### Quick Connect is not gated by it — the sign-in succeeds and the session cannot be used

    outside the window: Authorize 200, exchange 200 (a session for the child)
                        the same account's password auth, same moment: 403
    that session, used outside the window: /Users/Me 403, /Items 403
    the same session once the window opens: /Users/Me 200, /Items 200

`AuthenticateWithQuickConnect` does not apply the access schedule that `AuthenticateByName` does.
It is **not a way past the control** — the token it issues is refused on every request until the
hours begin — but it is a confusing approval, so the sign-in sheet says so when the child has a
schedule at all.

### Whose clock? The server's, and it will not say which one

This is the decision #49 could not make without measuring, and the answer is that conversion is
impossible:

    GET /GetUtcTime        -> {"RequestReceptionTime":"…Z","ResponseTransmissionTime":"…Z"}
    HTTP Date header       -> GMT, by specification
    /System/Info           -> no time or zone field of any kind
    /System/Configuration  -> none either

The server's **UTC instant** is available; its **offset** is not, and the offset is the only thing
that would let a phone turn "20:00 on the server" into a time for its reader. With the container on
UTC+10 nothing in any response differed from the UTC case.

So Garfin renders the hours as the server wrote them and **says whose hours they are**. It also
does not show a live "outside their hours right now" — it cannot compute one, and a wrong live
status is worse than none.

## Browsing

    GET /Items?userId={admin}&Recursive=true
        &IncludeItemTypes=Movie,Series,MusicAlbum,Video
        &Fields=Tags,Genres,OfficialRating,ProductionYear,ParentId
        &SortBy=SortName&SortOrder=Ascending
        &StartIndex=0&Limit=100

Paginate. A family library is thousands of items; loading it in one call will stall the UI.

    GET /Genres?userId={admin}
    GET /Years
    GET /Items/{id}/Images/Primary?maxWidth=300&tag={ImageTag}

Cache images aggressively; include the tag in the cache key so a changed poster invalidates.

## Collections

    GET /Items?IncludeItemTypes=BoxSet&Recursive=true&Fields=Tags,ChildCount
    GET /Items?parentId={boxsetId}&Fields=Tags    -> members

An item can belong to several BoxSets. Do not assume one parent.

**Measured on 10.11.11, 2026-08-05**, throwaway container per the protocol below — six films,
three BoxSets, one allow-list child.

`userId` and `Recursive=true` change nothing on the `parentId` query; `Fields=Tags` is required
exactly as it is everywhere else, and without it the `Tags` key is **absent** rather than empty —
which reads as "no member is labelled". Member rows carry `Name`, `ProductionYear` and
`OfficialRating` (when the item has one) unasked, which is enough for the cascade dialog's list.

**`ChildCount` is absent unless asked for.** `Fields=Tags` alone returns no `ChildCount` at all;
`Fields=Tags,ChildCount` returns it. The grid's count badge is guarded on that field being
non-null, so it never rendered until this was fixed.

### There is no way to ask which collections contain a film

Every plausible route gives a **wrong answer rather than an error**:

| Attempt | Result |
|---|---|
| `Fields=ParentId` on the film | the **library folder** — the same id for every film in the library |
| `GET /Items/{id}/Ancestors` | that same folder chain. The BoxSet is not in it |
| recursing the Collections folder for `IncludeItemTypes=Movie` | **0 items** |
| `IncludeItemTypes=BoxSet&ancestorIds={filmId}` | **every** BoxSet on the server, including ones that do not contain the film |

The last row is the trap worth remembering: `ancestorIds` is **not one of `/Items`' 86
parameters**, and an unknown parameter is **silently ignored rather than rejected** — confirmed
directly, `totalNonsense=42` answers 200. On a test library with one collection, that wrong answer
and the right answer are the same string.

So the reverse map is built the only way that exists — list the BoxSets, then one `parentId` query
each, 1 + N calls — and cached for the session. Nothing Garfin does changes membership.

### Tagging the container and tagging the members do different things

Allow-list child, tag `kids-emma`, every combination measured:

| container tagged | members tagged | films the child sees | BoxSets they see | browsing the set |
|---|---|---|---|---|
| no | no | 0 | — | 401 |
| no | **yes** | **3** | — | **401** |
| **yes** | no | 0 | Back to the Future | **0 items** |
| yes | yes | 3 | Back to the Future | 3 |

Tagging the container alone is not inert — it hands the child an **empty collection**. Tagging
only the members is not the whole job either: the films arrive and the set does not.

**So a collection write covers both.** Write the container **last** on an addition and **first** on
a removal, and its label becomes an accurate marker of "the whole set landed": a fix-forward
partial leaves it off, and the half-tagged set stays in the to-do list on the grid at no extra
query. See `DECISIONS.md` § Collections and `AssignRepository.applyToCollection`.

### The BoxSet round-trip is a film's, with different numbers

    BoxSet single-item GET : 41 fields      BoxSet list row : 14 fields
    POST /Items/{boxSetId} : 204            LOST none  GAINED none  CHANGED ['Etag', 'Tags']

Read the claim, not the number: the count is item-dependent here too.

### `tags=` takes `|`, not `,`

    tags=kids-emma                  -> 3
    tags=family-films               -> 1
    tags=kids-emma|family-films     -> 3     <- OR
    tags=kids-emma,family-films     -> 0

That 0 is not "AND". Writing a tag *literally named* `kids-emma,family-films` onto one film makes
`tags=kids-emma,family-films` return exactly **1** — that film. The comma was never a separator;
the whole string is one tag. Meanwhile `IncludeItemTypes=Movie,Series` in the same query string
uses commas correctly, so the conventions really are per parameter.

It matters because a child may hold **several** shortlist tags and the server matches any of them:
a member-counting query built with a comma returns 0, and a fully-shared set reads as untouched.

### `tags=` ANDs with every other filter — measured, because #81 subtracts across them

The Library's result line is `total − tagged` (§ *The result line is a subtraction*, `DECISIONS.md`),
and that is only a number if both queries describe the **same population**. So each filter was
checked against `tags=` directly rather than inferred from the `searchTerm` composition above.

Six films, written through the full-object round-trip: `Alpha` (`kids-emma`, Family, 1991, G),
`Rio Bravo` (`kids-emma`, Drama, 2001, PG-13), `Charlie…` (`family-films`, Family, 1991, G),
`The Delta Force` (untagged, Family, 1991, G), `Echo` (`kids-emma`, Family, 2015, PG-13),
`Foxtrot` (untagged, Drama, 2001, PG-13). All counts `Limit=0`, `IncludeItemTypes=Movie`:

    (no filter)                                 -> 6
    tags=kids-emma                              -> 3
    genres=Family                               -> 4
    tags=kids-emma&genres=Family                -> 2     <- AND
    tags=kids-emma&genres=Drama                 -> 1     <- the other direction
    tags=kids-emma&genres=Horror                -> 0     <- the control that can still say no
    years=1991                                  -> 3
    tags=kids-emma&years=1991                   -> 1
    tags=kids-emma&years=1991,1992,1993         -> 1     <- a decade span, as the grid sends it
    tags=kids-emma|family-films                 -> 4     <- OR, still an OR under a filter
    tags=kids-emma|family-films&genres=Family   -> 3
    tags=kids-emma&searchTerm=alpha             -> 1
    tags=kids-emma&searchTerm=charlie           -> 0
    maxOfficialRating=0                         -> 3
    tags=kids-emma&maxOfficialRating=0          -> 1

And the subtraction itself, per filter set — the numbers the result line puts on screen:

    no filter        total=6  tagged=4  outstanding=2
    genres=Family    total=4  tagged=3  outstanding=1
    years=1991       total=3  tagged=2  outstanding=1

**`PG-13` has no numeric value in this ladder** (`G=0`, `PG-13=null`), which is the same shape as the
five names sharing value 0 recorded below: a cap is only ever sent as the number the child's policy
holds, never as a name.

<sub>Measured 2026-08-07 on 10.11.11 in a disposable container — port tested free and bound to
127.0.0.1, `StartupWizardCompleted: false` asserted before any write, container and volumes removed
after. Two harness traps hit on the way, both now in the table at the top of this file: the
**camelCase-on-boot** reply that `dto_json.dart` already documents (the wait loop broke on the first
200 and read an object whose every field looked absent), and the **scanner renaming the fixture**.</sub>

### A well-formed GUID that does not exist answers 404 — except the all-zero one

    GET /Users/{admin}/Items/deadbeefdeadbeefdeadbeefdeadbeef  -> 404
    GET /Users/{admin}/Items/00000000000000000000000000000000  -> 200  Name="Media Folders"
    GET /Users/{admin}/Items/not-a-guid                        -> 400

The empty GUID resolves to the **root media folder**, whose `Id` is not the one asked for. A caller
that trusts the status — or trusts that a JSON object came back — would hand the write path the
root folder's body to post to `/Items/000…`. So `fullItem` compares the returned `Id` with the
requested one and refuses the mismatch. The check is one line; the failure it prevents is the class
the whole of ground rule 2 exists for.

### Batching

Five member writes at a concurrency of four: **0.2s, all 204**. Failures are per item — a bogus id
in the middle 404s at pre-flight while both its neighbours land, which is the fix-forward state
exactly.

## Series, seasons and episodes

**Measured 2026-08-06 for #53**, throwaway container per the protocol below, two shows — one of
them a control that is never tagged. Bluey: 1 series, 2 seasons, 6 episodes. Allow-list child
holding `kids-emma`, and **every combination tried**:

| series tagged | seasons | episodes | episodes the child sees | series visible | browsing the series |
|---|---|---|---|---|---|
| no | no | no | 0 | — | 0 |
| no | no | **yes** | 6 | — | **0** |
| no | **yes** | no | **0** | — | 0 |
| no | yes | yes | 6 | — | 6 |
| **yes** | no | no | **6** | Bluey | **6** |
| yes | * | * | 6 | Bluey | 6 |

**Tagging the series is the whole job.** With the label on the series and nothing written below it,
the child sees all six episodes, both seasons, can browse the series, and a direct
`GET /Users/{kid}/Items/{episodeId}` answers **200**. The control makes it the tag rather than
something ambient: the same call for an episode of the untagged second show answers **404**.

So **there is no episode cascade to build**, and building one would have written hundreds of
full-object replaces per series — the operation this whole file is a warning about — for no gain.

### The inheritance is visible in the item, not only in the filter

Descendants **report the series' tag as their own**. Same episode, three read paths, with the label
written only to the series:

| read | `Tags` |
|---|---|
| `GET /Users/{uid}/Items/{episodeId}` | `['kids-emma']` |
| `GET /Items?ids=…` — no `Fields` | **key absent** |
| `GET /Items?ids=…&Fields=Tags` | `['kids-emma']` |

Unchanged at t+0, t+5s, t+30s and t+60s, so it is not a scan catching up.

**An explicit write to a descendant pins it and stops the inheritance being reported.** Post one
episode back with `Tags: []` and that episode reads `[]` and drops out of `tags=` while its
untouched siblings still carry the label. **Visibility is unaffected** — the pinned episode still
answers 200 for the child, who still sees 6 of 6. So the filter that decides what a child may see
inherits from the series regardless; only the *reported field* and the `tags=` query follow the
explicit write.

> The matrix above was produced by writing `Tags: []` to every season and episode for the rows
> where they are "not tagged" — which is the *harder* test, not a weaker one: it shows the child
> still sees everything even when each descendant carries an explicit empty array. The earlier
> draft of this section read that harness state as "the tag does not propagate", which was the
> harness observing a condition it had itself created. Review of #55 caught it.

### What this costs, and where it would bite: `taggedItemCount`

One write to one series, then `tags=kids-emma`:

    IncludeItemTypes=Movie,Series,BoxSet   -> 1     <- what taggedItemCount asks for
    IncludeItemTypes=Series                -> 1
    IncludeItemTypes=Season                -> 2
    IncludeItemTypes=Episode               -> 6
    no type filter at all                  -> 9

**`taggedItemCount`'s item types are load-bearing, not incidental.** It is what ground rule 1's
last-item hard warning counts with — the warning that stops a parent taking a label off the last
item carrying it and blanking the child's view. Widen that list to include `Episode` or `Season`
and a single series contributes nine instead of one, `count <= 1` stops being reachable in any
library with a series in it, and **the warning silently never fires again**. There is a test
pinning the item types for exactly this reason.

### Why a series behaves unlike a BoxSet

    GET /Items/{episodeId}/Ancestors
      -> Season 1 (Season), Bluey (Series), Shows (CollectionFolder), Media Folders (UserRootFolder)

The series **is** an ancestor of its episodes. A BoxSet is not an ancestor of its films — measured
in #50, where a film's ancestors are the library folder chain and the set is nowhere in it. One
rule explains both: **the filter inherits down the library hierarchy, and a collection is a link
rather than a place.**

### Two edges worth knowing, neither of which Garfin can produce

- **A season's tag does not reach its episodes.** Tag only Season 1 and the season is visible while
  every list query returns 0 episodes — yet a direct `GET` of one of its episodes answers 200. The
  list filter inherits from the *series*; the single-item access check is more permissive than the
  filter. Garfin never tags a season (the grid offers `Movie`, `Series`, `BoxSet`), so it cannot
  create that state.
- **Episodes tagged with an untagged series** are reachable and countable but the series is
  invisible and `/Shows/{id}/Episodes` returns 0 — findable only by a client that already has the
  id.

### Block mode inherits identically

    series blocked=false -> episodes visible: 8, series visible: both, one episode direct: 200
    series blocked=true  -> episodes visible: 2, series visible: the other one, direct: 404

Blocking a series takes its episodes with it. Ground rule 3's inversion holds at every level, which
means neither verb needs a cascade.

## Searching by title — measured before it was built (#73)

`searchTerm` is a parameter on the same `/Items` call as every other filter. All
of the below is from a throwaway 10.11.11 with five films built to be
*confusable* — one whose overview says "Nothing like Paddington at all" and
which carries the tag `paddington`, and an actor named `Sam London` in a
different film from the one whose overview mentions London.

**Title only.**

    searchTerm=Paddington  -> 1   ['Paddington']       not the film whose overview and tag say it
    searchTerm=Anatolia    -> 0   []                   an overview word
    searchTerm=Tautou      -> 0   []                   an actor
    searchTerm=London      -> 0   []                   an actor, and another film's overview
    searchTerm=wildlife    -> 0   []                   a tag
    searchTerm=Comedy      -> 0   []                   a genre

The trap film is the point: without it, "Paddington returns Paddington" is
equally consistent with a search that reads overviews and tags.

**Substring, anywhere in the title — not a word prefix.**

    add    -> Paddington        ington -> Paddington
    eep    -> Winter Sleep      inter  -> Winter Sleep

**Case- and accent-insensitive.** `Amelie`, `amelie`, `AMELIE` and `Amélie` all
return `Amélie`.

**It ANDs with the other filters**, checked in both directions so that "it
composes" is not read off a single agreeing case:

    searchTerm=bear                        -> 1  ['The Bear']
    searchTerm=bear&genres=Family          -> 1  ['The Bear']
    searchTerm=bear&genres=Drama           -> 0  []
    searchTerm=bear&years=1988             -> 1  ['The Bear']
    searchTerm=bear&years=2014             -> 0  []
    searchTerm=bear&tags=kids-emma         -> 0  []      (it is tagged wildlife)

**`Recursive=true` is required**, and this is the silent one:

    /Items?searchTerm=bear&Recursive=true   -> 1  ['The Bear']
    /Items?searchTerm=bear                  -> 2  ['Movies', 'Playlists']

Without it the query answers with *folders*, not films — a 200, a plausible
count, and nothing a parent searched for.

**An empty or whitespace term is not a filter.** `searchTerm=` and
`searchTerm=%20` both return the whole library, so Garfin omits the parameter
rather than sending it blank.

### A caution about `maxOfficialRating` that this exercise nearly got wrong

While checking composition, `searchTerm=bear&maxOfficialRating=0` returned
nothing and looked like it contradicted the recorded finding that an unrated
title passes every cap. It did not. The films had been given `GB-PG` and `GB-15`
by the scan, so they were never unrated, and the genuinely unrated ones behave
exactly as recorded:

    Winter Sleep (OfficialRating: null)   cap=0 -> visible   cap=1000 -> visible
    whole library                          cap=0 -> 2 items (both unrated)
                                           cap=10 -> 4 items
                                           cap=1000 -> 5 items

The recorded claim stands. Check what the fixture actually holds before
reporting that a measurement disagrees with one.

## Filtering the grid — and the delimiters, which are not a house style

**Measured 2026-08-06 for #44**, six films with genres, years and certificates written onto them.

| parameter | delimiter | a wrong delimiter |
|---|---|---|
| `IncludeItemTypes` | comma | — |
| `genres` | **`|`** | `genres=Family,Comedy` -> **0**, silently |
| `tags` | **`|`** | `tags=a,b` -> **0**, silently (§ Collections) |
| `years` | **comma** | `years=1985|1989` -> **HTTP 400** |

So one wrong delimiter fails loudly and the other quietly, in the same query string, and the quiet
one is the dangerous shape: a filter that matches nothing looks exactly like a library that has
nothing. Each is pinned by a test rather than remembered.

    genres=Adventure|Comedy  -> 6    genres=Family|Comedy -> 4    genres=Nonexistent -> 0
    years=1985,1989          -> 2    years=nineteen       -> 400

**`/Genres` is an index, not a scan.** After writing genres directly onto items it answered empty;
`POST /Library/Refresh` populated it within five seconds. An empty answer therefore means "nothing
indexed", which is not "no genres" — the filter chip hides rather than claiming either.
`/Years` needs no such coaxing and lists the distinct production years.

### `maxOfficialRating` filters the admin's view. It does not predict the child's

    maxOfficialRating=G      -> 2    (1 G + the unrated one)
    maxOfficialRating=PG     -> 5    (3 PG + G + the unrated one)
    maxOfficialRating=8      -> 5    <- the numeric value works, and this ladder has
    maxOfficialRating=PG     -> 5       five names sharing value 0
    maxOfficialRating=junk   -> 6    <- unparseable filters NOTHING, silently

Two things follow. **The cap goes out as the number** from the child's policy, because a name would
mean choosing arbitrarily among `0+`, `All`, `E`, `G` and `U` — and because an unparseable value
fails open rather than closed.

And **an unrated title passes every cap in this filter**, while the same title is invisible to a
child whose policy sets `BlockUnratedItems: ['Movie']` — measured both ways on one library:

    child capped at PG, BlockUnratedItems []        -> sees the unrated film
    child capped at PG, BlockUnratedItems ['Movie'] -> does not
    admin + maxOfficialRating=PG                    -> includes it either way

`MaxParentalRating` and `BlockUnratedItems` are **two independent mechanisms**, and only the server
knows the second. This is exactly ground rule 4's line: filtering the administrator's view is a
library query, predicting what a child sees is not. The chip says "within Emma's limit" and never
"what Emma can see".

## Writing tags — the dangerous part

    GET  /Users/{adminId}/Items/{itemId}   -> the FULL metadata object (52 fields, verified)
    POST /Items/{itemId}                   -> the same object, Tags modified   -> 204

Verified round-trip on 10.11.11: posting the full 52-field object back with one tag added returns
204 and changes exactly two fields — `Tags` and `Etag`. `Overview`, `ProviderIds`, `ImageTags`,
`Genres`, `Studios` and `People` all survive untouched.

**Every write starts with its own fresh `GET`. Never re-post a body captured earlier** — not from
the grid, not from a cache, and not from a snapshot taken so a user-facing Undo could restore it.
Undo is a forward write: fresh `GET`, remove the tag, post back. See `docs/UI-SPEC.md` §
*How Undo works*, and ground rule 5.

`POST /Items/{id}` **replaces the entire item**. If you post a partial object you will wipe
fields — overviews, provider IDs, images metadata. Always round-trip the full object.

### "The full object" is not one thing — derived 2026-08-03, round-tripped 2026-08-05

The DTO Jellyfin returns varies **by endpoint and by the `Fields` query parameter**. A `GET` that
does not request everything returns a trimmed object, and posting *that* back is precisely the
wipe described above — with no error, no undo, and success reported.

**Derived empirically against Jellyfin 10.11.11**, 2026-08-03 — a throwaway instance in Docker
with one TMDB-matched film. Numbers below are measured, not inferred, and independently
reproduced on a second instance. Re-run on a version bump.

> **Which of these are contract, and which are just what 10.11.11 happens to do.** The field
> counts and the safe full-object round-trip are stable behaviour to build on. The **400 rather
> than a silent accept**, and the **bricked detail endpoint** that follows it, are *observed*
> behaviour, not documented API contract — a future version could revert to silently accepting a
> trimmed object and wiping fields, which is what this file assumed before the experiment.
> **Design so that either behaviour is survivable:** never post an object that did not come from
> a single-item `GET`, regardless of what the server does when you get it wrong. The guarantee to
> rely on is the one you enforce, not the one the server currently happens to provide.

| Read strategy | Fields returned |
|---|---|
| `GET /Users/{uid}/Items/{id}` | **52** |
| `GET /Items/{id}` | 52 |
| `GET /Users/{uid}/Items/{id}?Fields=<every field>` | 52 |
| `GET /Items?ids=..&userId=..&Fields=<every field>` | 51 |
| `GET /Items?ids=..&userId=..` — **a list query, no `Fields`** | **19** |

**So: no `Fields` parameter is needed.** `GET /Users/{uid}/Items/{id}` already returns everything;
asking for every field explicitly adds nothing. The spec's original instruction was right.

#### The round-trip, performed 2026-08-05

`GET /Users/{uid}/Items/{id}` → add one tag → `POST /Items/{id}` → re-`GET`:

    POST /Items/{id}: 204
    fields before: 52   after: 52
    fields LOST : none
    fields GAINED: none
    fields CHANGED: ['Etag', 'Tags']
       Tags: 18 -> 19   added=['kids-emma'] removed=[]

Nothing but the intended change and the server's own `Etag`. **Removal is
symmetric** — the label comes back out and the field set is unchanged. This is
the diff every write-path change has to be able to show.

**Read the claim, not the number.** An independent run on a different film
measured **53** fields rather than 52; the count is item-dependent, so a bare
number invites the next person to read a mismatch as a regression. What holds
is *the same set of fields before and after, with only `Tags` and `Etag`
differing* — which is also what the test asserts.

The film arrived carrying **eighteen** provider tags before Garfin touched it —
`bear`, `taxidermist`, `cliché`, `harsh`. The label is the nineteenth, and the
diff above is what proves the other eighteen survive.

#### Posting a list row does not merely fail — it bricks the item

Measured 2026-08-05, deliberately, to find out what the rule is worth:

    a list row carries 21 fields against 53 from the single-item GET
    POST /Items/{id} with the list row      -> 400
    GET  /Users/{uid}/Items/{id} afterwards -> 400   <- the ITEM, not the request

**The damage outlives the request.** The item's detail endpoint keeps answering
400 while the item still appears in list queries with its tags intact — so it
looks fine on a grid and can never be edited again through the only path Garfin
has. `POST /Items/{id}/Refresh` did not recover it within 60 seconds; a full
`POST /Library/Refresh` did.

This retires "probably just a 400" as an intuition, and it is why
`AssignRepository` takes an item **id** rather than an item: the guarantee has
to be structural, because the failure is not recoverable from inside the app.

#### Tag casing is stored verbatim, and the filter does not care

    write  [..., 'KIDS-EMMA']  -> 204
    stored ['KIDS-EMMA']        <- not folded to the policy's casing

    tags=kids-emma -> 1    tags=KIDS-EMMA -> 1    tags=Kids-Emma -> 1

**So ground rule 3's casing instruction is about the data, not about matching.**
Writing the wrong casing breaks nothing Garfin does — the filter matches either
way — it just leaves `KIDS-EMMA` beside `kids-emma` in the parent's own tag
list in Jellyfin. Adopt the casing from the child's policy; never invent one.
Remove case-insensitively, so a label written wrongly in the past still comes
off cleanly.

**The danger is not a missing `Fields` value — it is round-tripping a *list* result.** A list
query returns 19 of 52 fields, dropping `Overview`, `ProviderIds`, `Genres`, `People`, `Studios`,
`Tags`, `Path`, `SortName` and 25 others. Fetch the item singly for a write. Never reuse the
object you already have from the grid.

### What actually happens when you post a trimmed object

Not what this file previously assumed. Measured:

```
POST /Items/{id}  with the 19-field list object   ->  HTTP 400 "Error processing request"
```

It is **rejected, not silently accepted** — so the "silent wipe" this section warned about is not
the failure mode on 10.11.11. The real one is worse in a different way. After that rejected POST:

```
GET /Items/{id}                 -> 400   System.ArgumentNullException: Value cannot be null
GET /Users/{uid}/Items/{id}     -> 400   (Parameter 'source')
GET /Items?ids={id}&userId=..   -> 200   metadata intact
```

**The write is refused and the item's detail endpoint is bricked anyway.** The data survives and
still looks correct in every list and grid view — but the endpoint you need in order to read the
item back, including to repair it, is the one that now throws. A failed write leaves the item
unreadable by the exact path the write path depends on.

**Recovery, and what it costs:**

```
POST /Items/{id}/Refresh?metadataRefreshMode=FullRefresh&imageRefreshMode=FullRefresh&replaceAllMetadata=true
```

restores the endpoint to 200 — **and wipes every Garfin tag on that item**, because
`replaceAllMetadata=true` replaces provider-owned fields including `Tags`. So the only known
repair destroys precisely the data Garfin manages. Treat a trimmed POST as unrecoverable-in-place
and design so it cannot happen.

### `Tags` is shared with the metadata provider

Measured on a TMDB match: Jellyfin populated `Tags` with provider keywords before Garfin touched
it — `["squirrel", "bunny", "repayment", "mobbing", "revenge", "open source", "blender", …]`.

Garfin's labels live in the same array. Consequences:

- **Never set `Tags` wholesale.** Read, add or remove the one label, write the whole array back.
- The tag diff shown to the user must not present provider keywords as things they chose.
- "Remove the child's label" is a surgical removal from a shared list, not a clear.

### Refresh after write: safe only without `replaceAllMetadata`

`UI-SPEC.md` offers *refresh metadata after write* as a Settings option. Measured on a tagged item:

| Call | Garfin's tag |
|---|---|
| `Refresh?metadataRefreshMode=FullRefresh` | **survives** |
| `Refresh?metadataRefreshMode=FullRefresh&replaceAllMetadata=true` | **wiped** |

The setting must never pass `replaceAllMetadata=true`. Doing so would delete the label the write
just created — the app undoing its own work, silently.

**Re-measured 2026-08-05 for #52, watching it settle**, because a refresh is queued work and an
immediate re-read proves nothing about what the scan does when it gets there:

    FullRefresh                        t+2s ['kids-emma']  … t+30s ['kids-emma']
    FullRefresh + replaceAllMetadata   t+5s []             … t+30s []

The wipe lands within five seconds and stays. The safe call is still safe half a minute later. In
the app the dangerous parameter is not a flag, a default, or a caller's choice — `refreshItem`
does not have one.

**Standing review gate.** Every PR that touches the write path must demonstrate a round-trip
against a live server: stand up Jellyfin in Docker, snapshot the item's full JSON, write one tag
through the code under review, and diff. Prove it, don't assert it. This method has caught silent
no-ops-reporting-success before.

> **Protocol — follow this exactly, it is not boilerplate.** A developer machine may already be
> running a real Jellyfin, and Jellyfin's default port is the first thing a container tries to
> bind. During the original experiment the test container failed to bind, and the health check
> that followed silently answered from the **live server instead** — an experiment about
> destructive writes, one wrong URL away from a real family library.
>
> 1. Pick a port by *testing* that it is free, don't assume one. Bind it to `127.0.0.1` only.
> 2. Before writing anything, assert the target is a fresh throwaway:
>    `GET /System/Info/Public` must report `"StartupWizardCompleted": false`.
> 3. Tear the container **and its volumes** down afterwards.
>
> Step 2 is the one that actually saves you: it fails closed against every way of ending up
> pointed at the wrong server, including the one nobody predicted.
>
> The port trap is one of five in the same family — see § *Measuring this without measuring your
> own harness* at the top of this file for the rest, and for the checks that catch them.

Optional, slower, makes the change visible immediately:

    POST /Items/{itemId}/Refresh?metadataRefreshMode=FullRefresh

### Collections and cascades: pre-flight, then fix forward

`GET` every member first and abort before writing anything if any read fails. Reads are free and
catch most failure modes — missing item, permission problem, unreachable server — before a single
write exists to regret.

If a write still fails mid-batch, **retry that item. Do not undo the ones that succeeded.** Tag
writes are idempotent, so a retry is safe and repeatable; an undo is another full-object replace
on an item that was fine, which is the dangerous operation this whole section is about. Rolling
back 7 of 12 doubles the exposure to fix something cosmetic.

Surface the exact state instead — "7 of 12 tagged" — and offer *finish the rest* or *remove all*.
Both are idempotent and both are the user's choice. See ground rule 5.

Keep a small concurrency limit (3–4) so a big collection doesn't flood the server.

**The pre-flight reads and keeps nothing.** Handing a pre-flight body to the write would be
re-posting a captured object — the thing the Undo rule above forbids — and it would be stale by
however long the batch takes. Every write does its own fresh `GET`. In the code that is structural:
`_preflight` returns ids, so there is no body to be tempted by.

**And "the read succeeded" is not the check.** It is "the item that came back is the item asked
for" — see the all-zero GUID answering 200 with the root folder, in § Collections above.

## Writing user policy — measured, and still not done

Ground rule 8 forbids `POST /Users/{id}/Policy`. These measurements are recorded because the
endpoint is a live hazard for anything that ever touches it, and because the reasoning the rule
used to carry would have rejected the safe mechanism and accepted the unsafe one.

**Measured 2026-08-07 on 10.11.11**, disposable container, ~170 policy writes, port tested free and
bound to loopback, `StartupWizardCompleted: false` asserted before anything was written, torn down
with its volumes.

### A raw round-trip is lossless

`GET /Users/{id}` → `Policy` (43 keys) → `POST` that object back unchanged:

    status 204   keys before 43   after 43   fields changed: 1
      AccessSchedules[0].Id: 1 -> 2

The one difference is the schedule row's primary key: schedules are deleted and re-inserted on every
write, so the `Id` churns. **Writes are therefore not idempotent in that field** — anything keying
off a schedule row id would break. Content is otherwise identical.

Mutating exactly one key on the map as received, then posting the whole map:

    status 204   fields changed: 2
      MaxParentalRating: 7 -> 13          <- intended
      AccessSchedules[0].Id: 169 -> 170   <- the row-id churn again

    read-back: MaxParentalRating=13, AllowedTags=['garfin-kid-shortlist'],
               schedules=1, MaxActiveSessions=3

### An omitted key is reset to its default, silently, with a 204

One key at a time, each omitted from an otherwise complete object:

    MaxParentalRating          7        -> None      <- the rating cap, gone
    AccessSchedules            [Sun 9-19:30] -> []   <- the hours, gone
    AllowedTags                ['garfin-kid-shortlist'] -> []
    BlockedTags                ['horror'] -> []
    EnableLiveTvAccess         False    -> True      <- restriction lifted
    EnableContentDownloading   False    -> True      <- restriction lifted
    EnableLiveTvManagement     False    -> True
    LoginAttemptsBeforeLockout 5        -> -1
    RemoteClientBitrateLimit   3000000  -> 0
    SyncPlayAccess             'None'   -> 'CreateAndJoinGroups'

**The 31 keys that appeared unchanged are not protection.** Control — set three of them to
non-default values, then omit them:

    MaxActiveSessions   3     -> 0      RESET
    EnableRemoteAccess  False -> True   RESET
    IsHidden            True  -> True   kept (True is its default)

### The 400 that looks like the server protecting itself is a coincidence

Writing only the eight fields `UserPolicy` models — exactly what a DTO-based write produces —
returns **400 and changes nothing**. Not because the server validates the set:

    required keys (omission -> 400): AuthenticationProviderId, PasswordResetProviderId

Two provider-id strings Garfin has no interest in. The trimmed write fails *only* because it happens
to omit those two.

### What a DTO write actually does once it gets past the 400

Add both required ids to the eight modelled fields — ten keys — and the write succeeds. **The
modelled fields survive and the unmodelled ones reset**, which is the opposite of what this section
first claimed and is worth stating in the strong form: *a typed model protects exactly what it
models and silently resets everything else.*

    POST /Users/{id}/Policy with 10 keys -> 204

    modelled, and unchanged      MaxParentalRating 7, AllowedTags ['kids-emma'],
                                 BlockedTags ['horror'], EnabledFolders, EnableAllFolders
    modelled, content unchanged  AccessSchedules — only the row Id churns, 1 -> 2

    NOT modelled, and reset      EnableContentDownloading    False -> True
                                 EnableLiveTvAccess          False -> True
                                 EnableLiveTvManagement      False -> True
                                 EnableRemoteAccess          False -> True
                                 LoginAttemptsBeforeLockout      5 -> -1
                                 MaxActiveSessions               3 -> 0
                                 SyncPlayAccess             'None' -> 'CreateAndJoinGroups'

Four restrictions lifted, two limits removed, one capability granted — silently, with a 204. The
fields that survive are the ones somebody thought to model; the ones that revert are the ones nobody
did, which is the shape of every DTO ever written.

**Measured twice, independently, after the first write-up got it backwards** — it said the cap would
be stripped, which cannot happen through a body that contains the cap. The claim that survived the
correction is the mechanism, not the field list.

### `MaxParentalRating` is absent, not null, until a cap is set

    a child with no cap:  42 keys, no MaxParentalRating key at all
    the same child capped: 43 keys

So a round-trip check written as "all 43 keys" fails on the ordinary starting state. **Assert that
every key that came back goes back**, and compare schedule *content* rather than the whole object,
since the row `Id` churns on every write and a naive diff reports it as a loss — which it did here,
in the harness that produced the table above.

**An unknown extra key is accepted and ignored (204)**, which is why a raw map is more
forward-compatible than a typed model: a field a later Jellyfin adds rides through a round-trip
untouched, and is exactly what a DTO drops.

### What this does not change

The rule. See `docs/DECISIONS.md` § Tagging model for why the ban is kept as a product decision, and
`CLAUDE.md` rule 8 for the discipline any future policy write would have to follow.

## Sessions — seeing them, commanding them, ending them

**Measured on 10.11.11 (#41).** `GET /Sessions` carries `UserName`, `DeviceId`, `DeviceName`,
`Client`, `SupportsRemoteControl`, `PlayState` and — **only while something is playing** —
`NowPlayingItem` with its `RunTimeTicks`. Not playing is the ordinary case and the key is simply
absent rather than null.

### `userId` is accepted and ignored

    /Sessions                                    -> ['emma', 'admin']
    /Sessions?userId=<the child>                 -> ['emma', 'admin']   <- unfiltered
    /Sessions?activeWithinSeconds=1              -> ['emma']            <- this one works
    /Sessions?controllableByUserId=<the admin>   -> []

Another parameter in the family of `ancestorIds`: taken, ignored, no error. **Filter by `UserId`
in the client**, or a screen puts somebody else's device under a child's name.
`activeWithinSeconds` is a recency filter and does work — at one second the idle admin session
drops out while the child's remains.

### A 204 from a command is acceptance, not compliance

    POST /Sessions/{id}/Message         -> 204
    POST /Sessions/{id}/Playing/Stop    -> 204
    POST /Sessions/{id}/Playing/Pause   -> 204

All three against a session whose `SupportsRemoteControl` is **false** and which cannot act on any
of them. So the server accepting a command says nothing about the child's device obeying it, and
the copy says what Garfin *sent* — "Sent to", "Asked to stop" — rather than what happened. Only the
revoke below is reported as done, because it is the one the server really performs.

### Ending a session, and the foot-gun in it

    the child's token before        -> 200
    DELETE /Devices?id={deviceId}   -> 204
    the child's token after         -> 401
    /Sessions afterwards            -> the session is gone

Keyed on the **device**, not the session — the session carries both ids:

    DELETE /Devices?id=<the session id>   -> 404   child's token: still 200
    DELETE /Devices?id=nonsense           -> 404   child's token: still 200
    DELETE /Devices?id=<the device id>    -> 204   child's token: 401

So passing the wrong one **answers 404 and ends nothing** — loud rather than silent, but still the
wrong call, and still worth a test at the call site where the choice is made.

> An earlier draft of this said it answered **204** and ended nothing, which would have meant a
> parent being told their child was signed out while they carried on watching. That was never
> measured — only the correct id had been — and it is the failure mode this file's opening section
> warns about, asserted in the file that warns about it. Caught in review of #41.

**It works on Garfin's own device too**: an admin deleting its own device id gets 204 and its very
next request answers **401** — the app signing the parent out of itself. Garfin's own session is
therefore excluded from the list outright rather than shown with the button disabled.

Not a policy write, so ground rule 8 is untouched — same as the Quick Connect approval in #40.

## The server keeps no history of a metadata write

**Measured 2026-08-06 for #57.** The obvious source for an Activity screen is Jellyfin's own log.
It does not contain what that screen needs:

    GET /System/ActivityLog/Entries    -> 3 entries
       AuthenticationSucceeded · SessionStarted · UserPasswordChanged
    POST /Items/{id}  with a tag added -> 204
    GET /System/ActivityLog/Entries    -> 3 entries      <- unchanged

Sessions, authentication and playback; **nothing for a library write**. Its filters are
`startIndex`, `limit`, `minDate` and `hasUserId`, and it requires elevation.

So Garfin's Activity log is **its own, on the device**, and the consequence is a product one rather
than a technical one: it records what *this app* did, and a label added from the web admin or from
a second phone can never appear in it. The screen says so — a log that looked complete and was not
would be worse than no log at all, and it is the same class of honesty as the grid's *hasn't got
yet* versus *can't see*.

## Gotchas

- Tags are case-sensitive in some server versions. Compare case-insensitively — but **do not
  impose our own casing on write. Adopt whatever casing the user's policy already uses.** The
  policy is the source of truth: read `AllowedTags`, see `Kids-Emma`, write `Kids-Emma` onto the
  item. Normalising the item to `kids-emma` while the policy says `Kids-Emma` matches nothing on
  a case-sensitive server — the write succeeds, the app reports success, and the child sees
  nothing. That is indistinguishable from a rating-cap swallow, so even the support answer comes
  out wrong. Fixing it from the other end would mean writing the policy, which ground rule 8
  forbids for good reason.
- A tag on a Series **is inherited by its Seasons and Episodes** — they report it, `tags=` matches
  them, and the child sees them. Measured on 10.11.11; this file said the opposite until #53, and
  the correction has teeth: see § Series, seasons and episodes for what it means for
  `taggedItemCount` and ground rule 1.
- `MaxParentalRating` uses the server's rating table, which is locale-dependent. Don't hardcode a
  US ladder; read `GET /Localization/ParentalRatings`.
- Items with no `OfficialRating` are treated as unrated and may be hidden by a cap. Surface that
  rather than letting a title vanish mysteriously.
- A user whose `AllowedTags` matches nothing sees **nothing**, not everything. Two distinct routes
  reach that state, and only one is Garfin's:
  - Deleting the tag from `Policy.AllowedTags` — a policy write, which **Garfin never does**
    (ground rule 8). This is the Jellyfin behaviour to be aware of, not an action to guard.
  - Removing the tag from the **last item carrying it**. `AllowedTags` is untouched and still
    lists the label; it simply matches zero items. This one Garfin *can* cause, and it is the
    case rule 1 must warn about. Detecting it is a count of tagged items — a library query, not
    a visibility computation, so rule 4 does not apply.
