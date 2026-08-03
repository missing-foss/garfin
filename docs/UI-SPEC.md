<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# UI spec

Screen by screen. `docs/ui-mockup.jsx` is the clickable version — reference only, not source.

Bottom navigation, four destinations: **Library · Kids · Activity · Settings**.

## Unlock

Before anything else, on cold start and on resume after the idle timeout: biometric, falling back
to device PIN/pattern. Garfin holds an admin token on a phone that gets handed to children as its
normal mode of use, so device lock alone doesn't cover the case the app itself creates.

Below API 28 there is no `BiometricPrompt`, so 26–27 go straight to device credential. If the
device has no credential set at all, say so plainly and let the user continue — a lock Garfin
cannot enforce shouldn't become a lock-out.

## Sign in

Server URL (remembered), then Quick Connect (default) or password. Quick Connect shows a
six-digit code and an indeterminate progress bar while polling. Non-admin accounts are refused
with an explanation, not a generic error.

Backgrounding during Quick Connect is normal — authorising the code means opening a signed-in
Jellyfin session. If the process is killed, pairing restarts with a fresh code; the secret is
never persisted to survive it.

## Library — the landing screen

1. **"Picking for"** — a horizontal row of Jellyfin avatars for every label-controlled user, plus
   "Everyone". Selecting one filters the grid to what that child can't see yet, exposes their
   rating cap as a chip, and carries into the assign sheet.
2. **Filter bar** — one row: a tune button (opens all groups with Reset), then dropdown chips for
   Type, Genre, Decade, then the rating toggle when a child is selected. Chips show the filter
   name when unset, the value when set. Sticky on scroll.
3. **Result line** — "N things Emma hasn't got yet", with a Show/Hide shared text button.
4. **Poster grid** — 3 columns (2 under 400dp). Collections get a stacked cover and a count badge.
   Already-shared items carry a check badge. Each tile shows avatars of the children who have it.

## Assign sheet (modal bottom sheet)

Cover, title, metadata. For a collection: a note that labels land on all N films inside. For a
film in a collection: a softer note naming the set.

One row per label-controlled child, the selected one first. Rows above the child's rating cap are
flagged. Each row carries that child's **current** visible count — "Emma sees 24 of 400" —
fetched from the server, never computed here.

Toggling updates a **tag diff** — the exact additions and removals — which is the only place a
write is previewed. Apply, or Cancel.

The preview shows the count as it stands, not a prediction. Predicting the result would mean
simulating the server's policy evaluation, including the rating cap, which ground rule 4 forbids
precisely because it goes wrong silently.

**One case gets a hard warning, not a diff line.** If this removal would take the child's label
off the **last item still carrying it**, they will see *nothing* — not everything. Their
`AllowedTags` still lists the label; it just stops matching anything.

Garfin cannot empty `AllowedTags` itself — ground rule 8 means it never writes user policy — so
the trigger is a **count of items carrying the tag**, reached zero. That is a library query, not
a visibility computation, so ground rule 4 is not in play: no rating cap enters into it. It must
be impossible to apply without having read the warning.

If a single film belongs to a collection and labels were added, an **AlertDialog** asks whether to
keep the set together, listing the other members with their ratings. "Just this one" / "All N".

Result: a Snackbar with Undo, carrying the **re-fetched** count — "Emma now sees 25 of 400".
That is the server's answer after the write, so it is also what explains a share the rating cap
swallowed: the tag landed, the number didn't move, and the app says so rather than looking broken.

If a collection write partly fails, the sheet reports the exact state — "7 of 12 tagged" — and
offers *finish the rest* or *remove all*. It never silently undoes what succeeded; see ground
rule 5.

### How Undo works — everywhere it appears

**Undo is a new forward write, never a restore.** Fresh `GET /Users/{adminId}/Items/{itemId}`,
remove the specific tag Garfin added, post the full object back. It reverses the *effect*, not
the object. **Garfin never re-posts a previously captured item body.**

Restoring a snapshot is the intuitive reading and the dangerous one. Two reasons, and the second
is not recoverable:

- The item may have changed since — a Jellyfin metadata refresh, an edit in the web admin, a
  second Garfin session. Re-posting a stale body silently discards all of it.
- A body that isn't a faithful full single-item read is rejected with 400 **and leaves the item's
  detail endpoints returning 400 afterwards**, while list views keep showing correct data. The
  only known repair wipes every Garfin label on that item. See `docs/JELLYFIN-API.md`. Undo — the
  feature whose entire purpose is making a mistake recoverable — would become the one that makes
  it unrecoverable in place.

Consequences that follow from Undo being a forward write:

- **`Tags` is shared with the metadata provider**, so remove only the one label. Never restore a
  captured `Tags` array either: provider keywords may have changed underneath it.
- **It stays safe however long has passed**, which is what lets the Activity log offer Undo on
  old entries. A restore would grow more dangerous with age; a forward write does not.
- **It is idempotent.** If the label is already gone — removed by hand, or by a second session —
  Undo succeeds and says so, rather than erroring.
- **If the fresh `GET` fails, stop and surface it.** That is the signal the item is already in
  the broken state above, and pressing on would neither help nor be honest about it.

## Kids

Cards for label-controlled users: avatar, name, age, cap, an allow-list/block-list chip, the tags,
a progress bar, and "N of M things visible". Below, a plain list of users with no shortlist set,
including the admin.

## Kid detail

Hero block in the child's hue: avatar, the visible count as a large number, progress, and a
sentence explaining the mode in words. Then one row per library with its own visible/total, greyed
when access is denied — a missing library is usually a folder-permission mistake, not a tag one.
Extended FAB: "Add titles".

## Activity

Reverse-chronological list of every label write: item, "Handed to / Taken from {child}", relative
time, and the tag that changed. Recent entries offer Undo — a forward write, per the assign
sheet's *How Undo works* above, which is why an entry stays safely undoable however old it is.

## Settings

- **Unlock** — require biometric/PIN (on by default), and the idle timeout before Garfin asks
  again on resume. Default 2 minutes. Long enough not to nag while the parent is picking, short
  enough that handing the phone over expires the session in practice.
- **Server** — host, signed-in user, sign out, refresh cache
- **Labels** — prefix on/off, the prefix itself, cascade to episodes, cascade to collection
  members, collection prompt behaviour, refresh metadata after write
- **Picking** — starting child, hide shared, respect age cap, libraries to browse
- **Looks** — theme, dynamic colour, poster size
- **About** — version, GPL-3.0, non-affiliation, source, licences
