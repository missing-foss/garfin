<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# UI spec

Screen by screen. `docs/ui-mockup.jsx` is the clickable version — reference only, not source.

Bottom navigation, four destinations: **Library · Kids · Activity · Settings**.

## Sign in

Server URL (remembered), then Quick Connect (default) or password. Quick Connect shows a
six-digit code and an indeterminate progress bar while polling. Non-admin accounts are refused
with an explanation, not a generic error.

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
flagged. Toggling updates a **tag diff** — the exact additions and removals — which is the only
place a write is previewed. Apply, or Cancel.

If a single film belongs to a collection and labels were added, an **AlertDialog** asks whether to
keep the set together, listing the other members with their ratings. "Just this one" / "All N".

Result: a Snackbar with Undo.

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
time, and the tag that changed. Recent entries offer Undo.

## Settings

- **Server** — host, signed-in user, sign out, refresh cache
- **Labels** — prefix on/off, the prefix itself, cascade to episodes, cascade to collection
  members, collection prompt behaviour, refresh metadata after write
- **Picking** — starting child, hide shared, respect age cap, libraries to browse
- **Looks** — theme, dynamic colour, poster size
- **About** — version, GPL-3.0, non-affiliation, source, licences
