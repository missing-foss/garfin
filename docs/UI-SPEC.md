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
2. **Filter bar** — one row: a **search field** first, then a tune button (opens all groups with
   Reset), then dropdown chips for Type, Genre, Decade, then the rating toggle when a child is
   selected. Chips show the filter name when unset, the value when set. Sticky on scroll.

   **Search finds; the chips narrow (#73).** The grid is the administrator's whole library — that
   is what makes "not given yet" answerable — so it is as long as the library gets, and no
   category filter answers *the one film they asked for at dinner*. The server does the matching:
   `searchTerm` on the same request, never a filter applied to a page after it arrives, because
   the match is usually not in the first 24 rows.

   It matches the **title only** — measured, not the overview, cast, tags or genres — any
   substring, case- and accent-insensitively, and it combines with the other filters rather than
   replacing them. Typing is debounced at 350ms: every keystroke would otherwise be a
   library-sized query, which #68 measured at up to half a second. Whitespace is not a search, and
   an active search counts toward the filter badge like anything else.
3. **Result line** — "N things Emma hasn't got yet", with a Show/Hide shared text button.
4. **Poster grid** — 3 columns (2 under 400dp). Collections get a stacked cover and a count badge.
   Already-shared items carry a check badge. Each tile shows avatars of the children who have it.

## Assign sheet (modal bottom sheet)

Cover, title, metadata. For a collection: a note that labels land on all N titles inside **and on
the collection itself** — measured, a set whose members alone are labelled hands the child the
films without the set, and browsing it answers 401. For a film in a collection: a softer note
naming the set, **one per set**, because a film can belong to several.

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

If a collection write partly fails, the sheet reports the exact state — "7 of 12" — and offers
*finish the rest* or *remove all*, in place of Apply and without closing over the top of it. It
never silently undoes what succeeded; see ground rule 5. *Finish the rest* is the same write again,
which is safe because tag writes are idempotent.

If the **pre-flight** fails instead, the sheet says so in different words — nothing was written at
all, and the difference between "untouched" and "half done" is the whole reason the pre-flight
exists.

**That report is written per direction, and it has to be.** A removal reaches it too — the
container's label comes off first, so a container write that fails while every title succeeds ends
there. Labels left *on* the container mean the child keeps a collection that is now empty; labels
left *off* it mean they have the films and no set to find them in. Those are opposite sentences,
and the reversing button is "remove all" after an addition and "put it all back" after a removal —
naming the other one would name the opposite of what pressing it does.

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

**The toast's Undo expires after eight seconds; Activity's does not (#65).** The toast used to
stay on screen indefinitely — `SnackBar.persist` defaults to `action != null`, so the app's only
action-bearing toast was also its only permanent one. It now behaves like the other five.

That expiry is deliberate and it is not a loss of function, precisely *because* Undo is a forward
write: the same act is available from Activity for as long as the entry exists. What expires is
the shortcut, not the ability. And a shortcut that outlives the moment it belonged to is the
worse option — an Undo button still sitting on the grid an hour later performs a real write
against a list the parent may have changed since, which is the one thing the button's placement
implies it will not do.

Eight seconds is the long end of Material's 4–10s: this message names a child, a count and a
total, and only then asks for a decision.

## Kids

Cards for label-controlled users: avatar, name, age, cap, **the access hours**, an
allow-list/block-list chip, the tags, a progress bar, and "N of M things visible".

The hours are the other half of what Jellyfin enforces, and the card shows both or summarises
neither honestly. They are **the server's hours, said so** — measured, the API exposes no offset, so
they cannot be converted — and a child with no schedule is told they can watch at any time rather
than being left blank, which would read as the opposite. Below, a plain list of users with no shortlist set,
including the admin.

### The users with no shortlist need an explanation, not just a listing

Garfin cannot give a child their first label. A child is only under shortlist control because
`Policy.AllowedTags` already contains one, and adding the first one is a **policy** write, which
ground rule 8 forbids. So this list is a boundary, not a to-do list — and without a word of
explanation it reads as a dead end someone will file a bug about.

Give the section a short line of copy and leave the rows **non-interactive**. A row that looks
tappable and does nothing is worse than one that plainly isn't.

The copy stays plain and short — a parent does not need to know why:

> Set their shortlist up in Jellyfin first, then come back here.

The *reason* belongs in this document and in `docs/DECISIONS.md`, not on screen. Explaining
full-object replaces to a parent would be technical detail dressed as reassurance, and the Voice
rules exist to stop that.

Once a label exists on the account, everything after it happens in Garfin — which is the split
worth being deliberate about: the one-time setup is in Jellyfin, the repeated work of tagging
hundreds of titles is here. That is the product's premise, not a retreat from it.

### Signed in now

Above the cards when anyone is: who, on which device, and what they are watching with how far in.
Absent entirely when nobody is signed in, and absent while it loads or if it fails — a sessions
list that cannot be fetched is not news a parent can act on, and it must not displace the cards.

Three actions, in the order a parent reaches for them: **send a message** (which costs the child
nothing and so needs no confirmation), **stop playback**, and **end session**. The last two are
confirmed, per ground rule 6.

**The copy says what was sent, not what happened.** Measured: the message and stop commands answer
204 against a device that cannot act on either, so only ending a session — which really does revoke
the token — is reported as done. A device that says it cannot be remote-controlled says so on the
card, rather than letting a parent believe a message arrived.

**Garfin's own session is never in this list.** Ending it is a 204 followed by an immediate 401:
the app signing the parent out of itself.

## Kid detail

Hero block in the child's hue: avatar, the visible count as a large number, progress, and a
sentence explaining the mode in words. Then one row per library with its own visible/total, greyed
when access is denied — a missing library is usually a folder-permission mistake, not a tag one.
Extended FAB: "Add titles".

## Activity

Reverse-chronological list of every label write: item, "Handed to / Taken from {child}", relative
time, and the tag that changed. Entries offer Undo — a forward write, per the assign sheet's
*How Undo works* above, which is why an entry stays safely undoable however old it is. That is also
why the offer is not limited to recent ones: age was the only reason to withhold it, and a forward
write removes that reason.

**This is Garfin's own record, and the screen says so.** Measured for #57: Jellyfin logs nothing
when an item's metadata is written, so there is no server history to read back — a label added in
the web admin, or from a second phone, cannot appear here. The list carries that caveat at its foot
and on its empty state.

**One entry per action, not per write.** Handing over a twelve-film collection is one thing a
parent did; twelve rows would bury it. A part-written set records nothing at all — it is not
something they did yet, it is a state the sheet is still offering to finish or reverse.

**An entry per child**, because a single Apply can hand a film to one child and take it from
another, and "Handed to Emma" cannot say both.

**Undoing a collection re-resolves its membership** rather than replaying the titles it wrote to:
a set can gain or lose films in between, and a captured list is the same mistake as a captured
item body.

**An undo is itself an action, and appears as one.** Undoing an entry appends a new entry pointing
the other way; the original row stays exactly as it was, still offering Undo — which is safe,
because a forward write that removes an absent label changes nothing. The log is an append-only
record of *what Garfin did*, not a view of what is currently true, and the difference matters here
more than it usually would: marking a row "undone" would be a claim Garfin cannot back. The label
can be changed in the web admin or from a second phone, which this screen already admits it cannot
see, so an "undone" badge would quietly become a lie in exactly the case the caveat exists for.

The log is bounded — the oldest entries fall off the end — and lives in `shared_preferences`, so it
does not survive an uninstall and does not leave the phone.

## Settings

- **Unlock** — require biometric/PIN (on by default), and the idle timeout before Garfin asks
  again on resume. Default 2 minutes. Long enough not to nag while the parent is picking, short
  enough that handing the phone over expires the session in practice.
- **Server** — host, signed-in user, sign out, refresh cache
- **Labels** — collection prompt behaviour (ask each time / the whole set / just the one title),
  refresh metadata after write
- **Picking** — starting child, hide shared
- **Looks** — theme, dynamic colour, poster size
- **About** — version, GPL-3.0, non-affiliation, source, licences

### Three switches this list used to carry, and why they are gone

Each was written before the rule that rules it out was settled. A switch that controls nothing
reads as a promise, so they are recorded here rather than left on the screen (#52).

- **Tag prefix, on/off and the prefix itself.** Garfin never composes a label: it reads the child's
  existing one out of `Policy.AllowedTags` and writes that string back in the policy's own casing.
  There is nothing to prefix. Giving a child their *first* label is a policy write, which ground
  rule 8 forbids — the same consequence as the Kids screen's "set their shortlist up in Jellyfin
  first".
- **Cascade to collection members.** `docs/DECISIONS.md` § Collections: a collection **always**
  writes to its members, and #50 measured what the alternative does — the child gets a visible,
  empty collection. Off is not a preference, it is a broken write.
- **Cascade to episodes.** Not a gap after all, which #53 established by measuring it: the policy
  filter inherits from the series, so a label on a series is already enough for the child to see
  every season and episode inside it — they inherit the label, report it, and are matched by
  `tags=`. There is nothing for a switch to turn on, and the old note was wrong rather than
  half-right.

**Respect age cap** is the filter bar's rating toggle (#44), not a setting, and **libraries to
browse** waits on the same grid work — `/Items` takes one `parentId`, so more than one library is
a pagination question rather than a preference.
