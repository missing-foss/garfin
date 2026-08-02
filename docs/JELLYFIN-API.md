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

Writing a policy (only if the app ever sets tags up): `POST /Users/{id}/Policy` with the full
policy object.

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

Optional, slower, makes the change visible immediately:

    POST /Items/{itemId}/Refresh?metadataRefreshMode=FullRefresh

For collections and episode cascades: batch the writes, and if one fails, roll the others back.
A half-tagged set is worse than no change. Consider a small concurrency limit (3–4) so a big
collection doesn't flood the server.

## Gotchas

- Tags are case-sensitive in some server versions. Normalise on write, compare case-insensitively.
- A tag added to a Series does not propagate to Seasons or Episodes. If a client browses episodes
  directly, cascade or the child hits gaps.
- `MaxParentalRating` uses the server's rating table, which is locale-dependent. Don't hardcode a
  US ladder; read `GET /Localization/ParentalRatings`.
- Items with no `OfficialRating` are treated as unrated and may be hidden by a cap. Surface that
  rather than letting a title vanish mysteriously.
- Deleting a user's last allowed tag makes them see nothing, not everything. Warn.
