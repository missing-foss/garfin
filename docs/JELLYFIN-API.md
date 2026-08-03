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

    GET  /Users/{adminId}/Items/{itemId}   -> the FULL metadata object
    POST /Items/{itemId}                   -> the same object, Tags modified

`POST /Items/{id}` **replaces the entire item**. If you post a partial object you will wipe
fields — overviews, provider IDs, images metadata. Always round-trip the full object.

### "The full object" is not one thing — and this list is not yet derived

The DTO Jellyfin returns varies **by endpoint and by the `Fields` query parameter**. A `GET` that
does not request everything returns a trimmed object, and posting *that* back is precisely the
wipe described above — with no error, no undo, and success reported.

> **⚠️ The exact endpoint and `Fields` list are deliberately not written here yet.** They are
> being derived empirically against a real Jellyfin instance, not from documentation or memory.
> A plausible-but-wrong list in this file is the worst available outcome: this is the document
> people trust *instead of* checking, and the failure mode is silent library-wide data loss.
> Until the experiment lands, treat the write path as unimplementable.

**Standing review gate.** Every PR that touches the write path must demonstrate a round-trip
against a live server: stand up Jellyfin in Docker, snapshot the item's full JSON, write one tag
through the code under review, and diff. Prove it, don't assert it. This method has caught silent
no-ops-reporting-success before.

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
- Deleting a user's last allowed tag makes them see nothing, not everything. Warn.
