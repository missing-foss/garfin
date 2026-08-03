<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Jellyfin API notes

Everything Garfin needs, plus the parts that will bite. Verify against the server's own
`/api-docs/swagger` — the API moves between versions.

## Auth

    GET  /QuickConnect/Initiate                  -> { Code, Secret }
    GET  /QuickConnect/Connect?secret={Secret}   -> poll until Authenticated == true
    POST /Users/AuthenticateWithQuickConnect     { Secret }  -> AccessToken, User
    POST /Users/AuthenticateByName               { Username, Pw }   (fallback)

Every subsequent request carries:

    Authorization: MediaBrowser Token="...", Client="Garfin", Device="...", DeviceId="...", Version="..."

Quick Connect must be enabled server-side; if `GET /QuickConnect/Enabled` is false, hide the tab
rather than failing on Initiate. Poll with a backoff and a timeout — do not hammer.

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

**Admin check:** the authenticated user's `Policy.IsAdministrator` must be true. Reading other
users' policies and writing item metadata both require it. Refuse at sign-in with a clear message.

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

`POST /Items/{id}` **replaces the entire item**. If you post a partial object you will wipe
fields — overviews, provider IDs, images metadata. Always round-trip the full object.

### "The full object" is not one thing — and this list is not yet derived

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
