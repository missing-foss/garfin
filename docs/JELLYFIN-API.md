<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Jellyfin API notes

Everything Garfin needs, plus the parts that will bite. Verify against the server's own
`/api-docs/swagger` — the API moves between versions.

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

    GET /Items?IncludeItemTypes=BoxSet&Recursive=true&Fields=Tags
    GET /Items?parentId={boxsetId}    -> members

An item can belong to several BoxSets. Do not assume one parent.

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
symmetric** — taking the label back out returns 52 fields and 18 tags. This is
the diff every write-path change has to be able to show.

The film arrived carrying **eighteen** provider tags before Garfin touched it —
`bear`, `taxidermist`, `cliché`, `harsh`. The label is the nineteenth, and the
diff above is what proves the other eighteen survive.

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

## Gotchas

- Tags are case-sensitive in some server versions. Compare case-insensitively — but **do not
  impose our own casing on write. Adopt whatever casing the user's policy already uses.** The
  policy is the source of truth: read `AllowedTags`, see `Kids-Emma`, write `Kids-Emma` onto the
  item. Normalising the item to `kids-emma` while the policy says `Kids-Emma` matches nothing on
  a case-sensitive server — the write succeeds, the app reports success, and the child sees
  nothing. That is indistinguishable from a rating-cap swallow, so even the support answer comes
  out wrong. Fixing it from the other end would mean writing the policy, which ground rule 8
  forbids for good reason.
- A tag added to a Series does not propagate to Seasons or Episodes. If a client browses episodes
  directly, cascade or the child hits gaps.
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
