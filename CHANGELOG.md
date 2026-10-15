<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Changelog

What changed for someone using Garfin, release by release. Changes to the
build, the tests and the documentation are left out unless they change what
you get.

## Unreleased

## 0.3.0 — 2026-10-15

### Giving and taking back

- The assign sheet scrolls as one, poster and title included, and the child
  you are picking for is the first row.
- Apply waits for a collection's titles to arrive instead of calling a tap made
  too early a server error, and shows it is working while it waits.
- Removing a set, or pressing Undo, warns first when it would leave a child
  with nothing.
- Undo on the toast still works after the sheet has closed, says so when it
  fails, and names every child the write touched.
- Activity shows which label each entry wrote.
- Counts read "1 title", not "1 titles", in English and in French.

### The library

- Collections and their titles are read whole, page by page. A listing whose
  total changes between pages is refused rather than shown with gaps, and a
  page that comes back short asks for the next one.
- Picking a child's face carries that child's view and rating filter with it.
- Posters are fetched at the size they are drawn.
- The Library no longer reloads every time the Kids screen refreshes.

### Signing in and out

- The session is checked again when you come back to the app, when you press
  Try again, and whenever the server no longer recognises the session.
- Signing out asks first, then revokes the session on the server.
- A server that redirects is not followed. Garfin reports the address to use
  instead.
- An untrusted certificate is named, so you can tell it from a server that is
  down.
- Approving the code in Jellyfin is noticed at once when you switch back.

### Everything else

- Every empty or failed screen says what happened and offers a way out.
- Stop stays available whatever a playing device says about remote control,
  and the note about a device that cannot be stopped is worded as that device's
  own claim.
- Screen readers: the password field's show button has a label, a child's age
  line is a full-size button, library tiles say what a tap does, and the
  five-tap mark is hidden.
- Updated libraries: Material components, dynamic colour, credential storage and
  image caching.

## 0.2.0 — 2026-09-20

**Signed with a new key.** v0.1.0 used a different one, so it can't be updated
in place: install 0.2.0 fresh. `SECURITY.md` records both fingerprints.

Published as one APK per ABI: `arm64-v8a`, `armeabi-v7a` and `x86_64`.

### Kids

- The app opens on Kids, and Kids comes first in the navigation.
- The Kids screen shows only the children under a rule, each as a card with a
  face, a name, an age and a way in, drawn before their counts arrive.
- A child's card opens what they can see in each library, counted by the
  server.
- Tapping a child's picture picks that child and opens the library on what
  they can already see.
- With no child set up yet, Garfin invites you to set up the first one.
- Two children whose labels are the same label on the server are flagged.

### Giving a title

- Giving a film from inside a collection gives the collection too, so the child
  can find it, unless you have turned that off in Settings.
- A whole collection can be given with nobody picked.
- Applying keeps your place in the grid.
- A rating cap is read in both halves, and the second half is shown when it
  changes the cap.

### The library

- Collections show their share in a badge on an outlined poster, stand in for
  their titles on the grid, and are hidden when empty.
- A child's face on a poster says the title is shared with them, and the
  current child is in the app bar.
- A series says how many episodes it holds.
- The grid can be sorted.
- Search by title, by cast and crew, or by studio. A search finds a collection
  through a film inside it, and the result line says "sorted by relevance".
- The detail sheet shows the rating and whose certification it is, the year and
  duration, the country as flags, scores, genres and studios, for series too.

### Sessions and settings

- Now Playing names the show and draws its artwork.
- Ending a session stops the film first, then revokes the session, and says
  that a film already playing may not stop.
- **Allow screenshots** can be switched on in Settings. The recent-apps preview
  stays hidden either way.
- A warning explains that this app will stop installing on certified Android
  devices.
- The licence list puts the packages Garfin chose first.
- Five taps on the mark open a small game.

## 0.1.0 — 2026-08-23

The first public release.
