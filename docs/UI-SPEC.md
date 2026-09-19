<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# UI spec

Screen by screen. `docs/ui-mockup.jsx` is the clickable version — reference only, not source.

Bottom navigation, four destinations: **Kids · Library · Activity · Settings** — a
**navigation rail** on the left instead, from 600dp (see § Large screens).

**Back returns to Kids, and only from another tab.** Confirmed by the maintainer on the
issue, case by case. The app is one route with an internal tab switch, so back had no
meaning and went straight to the system from everywhere; Kids is where a face tap sends a
parent, so back is the way out of where it sent them. From Kids it leaves the app, which is
the one case that was already right.

Everything else that looks like navigation is a real route — a collection, the sheets, the
dialogs, About, Licences — so Flutter already pops those, and a route on top of the shell
receives the gesture before the shell does.

**Behind the lock the gesture is not intercepted.** The lock screen is an overlay in a
`Stack` rather than a route, so back there already means *leave the app* and cannot dismiss
the gate. Catching it would send a parent to a tab they cannot see and leave them with a
back gesture that does nothing behind a lock — worse than exiting.

**The app opens on Kids, and Kids is first in the navigation.** Both moved together: a
landing screen sitting second in its own navigation is a small lie about which screen the
app is built around, and it leaves the highlighted destination somewhere other than where
the app opened. This reverses the order that stood until 0.2.0 — see § Kids.

## Large screens

Garfin is a phone app that is handed a 1280dp window whether or not it is ready for one: nothing in
the manifest restricts orientation, aspect ratio or resizability, and for apps targeting API 36 the
platform ignores those restrictions anyway on any display 600dp or wider. So the tablet case is not
a migration, it is a layout that had no upper end.

Four widths, and every one of them is read off the **space a widget is handed** rather than off
`MediaQuery` — beside a rail or a panel those are different numbers, and it is the second that
decides whether a layout fits:

| from | measured on | what changes |
|---|---|---|
| any | the widget's own space | a column of rows stops widening at **640dp**, centred |
| 600dp | the **window** | the bottom bar becomes a **navigation rail** — the same four destinations, never both at once |
| 840dp | the space **beside the rail** | the Library and a collection show the **assign panel** beside the grid (360dp) instead of a modal sheet |
| 1240dp | the **window** | the rail **extends**: labels beside the icons rather than under them |

**The 840dp row is not a window width, and there is no window width to quote** — which matters,
because the next person to test this on a device will set one. The rail takes its share of the body
first, so the Library sees `window − rail − 1`, and the rail is as wide as its widest label: measured
**116.0dp in English and 153.5dp in French**, so the same layout gets the panel at **957dp** of window
in one locale and about **994dp** in the other, and text scale moves it again. So it is asserted as
the relationship it is — the panel appears when the pane beside the rail reaches 840 — in both
locales, rather than as a figure that would be wrong for half of them.

**640dp is a chosen number, not a fitted one.** At Nunito's body size it is roughly 70 characters —
near the top of the comfortable range for prose — and it keeps a switch within one glance of the
label it switches. Uncapped, a settings row on a tablet in landscape parks its trailing control a
hand's width from its own title.

**The cap is applied as the list's padding, never as a box around it.** The two look identical and
are different apps: narrowing the scrollable means a drag started in the margin of a tablet scrolls
nothing, and the scrollbar leaves the window's edge to come and meet the text. It also caps the
*content*, leaving each screen's own padding outside it, so every screen lands on the same column
width rather than one that varies with the insets it happens to declare.

The **poster grid is deliberately not capped** — it is the one thing on screen that gets better with
room, which is what the target-width rule in § Library is for. Both **modal bottom sheets** are
capped, because between 600dp and 840dp there is a rail but no panel yet and a sheet is still
allowed to be 839dp wide.

## Unlock

On cold start with a session already stored, and on resume after the idle timeout: biometric,
falling back to device PIN/pattern. Garfin holds an admin token on a phone that gets handed to
children as its normal mode of use, so device lock alone doesn't cover the case the app itself
creates.

**Not over sign-in.** The gate starts where the token does. Before a session there is nothing to
gate, and asking for biometrics before a server address has been typed protects an empty app.

**The question, once.** Straight after an interactive sign-in — and only then — a full-screen
choice: *Ask every time* (recommended, and what a fresh install does anyway) or *Not now*, with the
note that Settings can change it later. Answering "ask every time" drops straight to the lock
screen; answering "not now" opens the app. Either answer is remembered, and the screen never
appears again.

A **restored** session skips the question entirely and goes to the lock screen. The question is put
only to someone who has just proved they hold the Jellyfin credentials; anyone else holding the
phone is the reason the gate exists.

**Backgrounding ends it.** Leave the question unanswered and put the phone down, and the resume
lands on the lock screen rather than back on the offer — the same treatment a restored session
gets, because by then that is what it is. A notification shade or a system prompt does not count:
`paused`, never `inactive`. Nothing is recorded either way, so the next sign-in asks properly.

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

## Library

**Not the landing screen any more.** It opened the app until 0.2.0, on the reasoning that
the task which opens the app is *find something for a kid*, so the app should open on the
thing you act on. That is overruled: the first thing a parent wants is an answer about
their children — who they are, what each can see, and whether anyone is watching something
right now — and a grid of films is where they go once they have it. The Library is second
in the navigation and unchanged in every other respect.

1. **Who this is about — one avatar in the app bar, right-aligned.** It shows the current child,
   or the app's own mark for Everyone. One tap moves to the next child and past the last one back
   to Everyone; with no managed children it is not a control at all, because a control whose only
   move is back to where it already is teaches a parent that taps there do nothing.

   It replaced a row of avatar chips above the filters. That row was the first thing on the screen
   and was not the library, and the selection is one fact — it belongs where the screen says what
   it is showing. A cycle rather than a menu: two or three children is the shape this app is for,
   and a menu is a second surface to open for a choice with three answers. Everyone is the mark
   rather than a group of faces, because at 32dp a shoal is a smudge.

   **The same avatar is on the collection screen**, where switching child without leaving the set
   was the picker row's job and would otherwise have gone with it.

   Selecting a child still does everything it did: filters the grid, exposes the rating cap as a
   switch in the tune sheet, and carries into the assign sheet.
2. **Filter bar** — one row, and it does not scroll: a **search field** taking the width, then a
   tune button (opens all groups with Reset) carrying a badge with the number of active filters.
   Sticky on scroll.

   It used to carry a chip per filter after the tune button — Type, Genre, Decade, and the rating
   toggle when a child was selected — which made the row wider than the screen and left the search
   field a fixed 300dp. Every one of those filters is in the tune sheet, so the chips added reach
   rather than capability. What went with them is reading each filter's *value* at a glance; the
   badge's count remains. Measured at 412dp: the search field goes 300 → 324dp.

 **Search finds; the tune sheet narrows.** The grid is the administrator's whole library — that
   is what makes "not given yet" answerable — so it is as long as the library gets, and no
   category filter answers *the one film they asked for at dinner*. The server does the matching:
 `searchTerm` on the same request, never a filter applied to a page after it arrives, because
   the match is usually not in the first page of rows.

   It matches the **title only** — measured, not the overview, cast, tags or genres — any
   substring, case- and accent-insensitively, and it combines with the other filters rather than
   replacing them. Typing is debounced at 350ms: every keystroke would otherwise be a
   library-sized query, which was measured at up to half a second. Whitespace is not a search, and
   an active search counts toward the filter badge like anything else.

**The share sits in the collection's own badge, on the poster.** One badge rather than two,
because all four corners of a poster are already spoken for — state top-left, faces top-right, age
hint bottom-left, this one bottom-right — and the share is the same subject as the count, which is
not lost but becomes the denominator.

**That corner has four states, not two**, and the three that are not the ordinary one are what a
reader is most likely to get wrong:

| what is known | what the badge reads |
|---|---|
| a child is picked and the set's membership has arrived | `3/6` beside the ring |
| nobody is picked | "6 titles" |
| a child is picked, membership still in flight or failed | "6 titles" |
| the server sent no `ChildCount` and there is no share to show | nothing |

The third row is the one that costs something to get right. The share is one membership request per
visible collection tile, so *every* collection tile passes through it, and a tile whose request
fails stays there. The count is the fallback rather than the ring's companion: it stands in the
share's place until the share can speak, so the corner never goes blank while the answer is merely
unknown.

The fourth row is a corner deliberately left empty. A missing `ChildCount` means the field was not
asked for, never that the set is empty — those collections stay on the grid — so nothing there
invents a size. The share itself needs no count, and does not wait for one.

It began as a bare ring under the title, sized to *fit* an 83dp tile, and was reported
unnoticeable on a phone. Fitting was the wrong target: it had to be **seen** at arm's length. The
numerals came back with the move — a ring alone is a proportion to interpret, a ring beside `3/6`
is one to read.

**How much of a collection is a child's is a ring, not a sentence.** "Les 5 partagés avec Emma" was
the longest thing on a tile and named a child the app bar already names. The ring fills clockwise
from the top; **a closed ring is *all***, which is the shape's own answer to the distinction six
strings used to carry — "8 of 8 reads like a coincidence" was the argument, and a full circle is
read as *all* without counting.

**Direction is carried by tone**, in the two colours this screen already uses for state. Ground
rule 3 makes an allow list and a block list opposite verbs and a proportion reads the same either
way, so tone is doing real work — and it is a weaker carrier than a word. That is a deliberate
trade, made on the owner's reasoning that a set whose ring is ambiguous is one tap from the
sentence: the collection screen shows it in full, and the ring carries it as its spoken label.

**A plain share is said by the child's face, not by a badge.** They are a holder of the item, so
their picture is already on the poster; a "Given" badge beside it was the same fact twice. The
selected child sorts **first** in that row, which is load-bearing rather than tidy — the row
collapses its overflow into a `+N`, so whoever is first is whoever survives a narrow tile.

Two states keep their badge, because a face cannot express either. **Held back** is the opposite of
what a face implies — the label is there and the server is still not showing the title. **Blocked**
belongs to a block-list child, and a block-list child is never collected as a holder at all, so
there is no face that could carry it.

A side effect worth knowing: with no badge on a plain share the row has the whole top edge back, so
more faces fit on a narrow tile than before.

**A collection with nothing in it is not drawn at all.** There is nothing in it to give or
withhold, its assign sheet would have no members to write to, and its share ring is already
suppressed — so the tile could only ever be a row a parent cannot act on.

It saves requests rather than only a row, in two places. The grid asks for one membership per
*visible* collection tile; the collection index asks for one per collection **on the server**, at
`1 + N`. An empty set's answer can only ever be "nothing", so both skip it. Measured on 10.11.11 — an
empty `BoxSet` reports `ChildCount: 0`, the field present rather than absent, and `/Items` offers
no server-side way to exclude them, so this is a client-side drop like hide-shared. **A missing
count is not zero**: it means the server was not asked, and those are kept.

**A refresh keeps your place.** Applying a share rebuilds the grid — the write has to be reflected,
and the grid and the count that describes it are refreshed as one unit so they cannot disagree. That
rebuild used to start again at the first page, which threw away every page the parent had scrolled
to: not the scroll offset, the *rows*. Eight pages down, applying one share handed back one page,
and scrolling could not get back to where it had been because there was nothing there yet.

So the window that was open is asked for again. **The condition is that nothing else changed**: a
different child, a different view or a different filter still comes back at page one, because that
is a different list rather than the same list seen again. Both directions are load-bearing and both
are tested.

The window is restored in **one request** where nothing is being filtered out client-side — `/Items`
accepts a large `limit` — and the fetch budget grows with the window asked for. That second part is
not housekeeping: the budget is one page plus five refills, and a ten-page restore under it would
return a third of the rows and report success, which is worse than the original bug because it is
intermittent.

**A page is 240 rows, not one screenful.** Measured on a 412dp phone at the regular poster size —
`maxCrossAxisExtent: 175` gives three columns and about three rows on screen, so nine tiles are
visible and a page is roughly **27 screens** of scrolling. At 24 it was under three, so the grid
went back to the server every couple of flicks.

Ten times the rows costs about 1.3 times the request: `Limit=24` answers in 26 ms and `Limit=240`
in 34 ms, because the per-request constant dominates at the small size. It also crosses a threshold
that has nothing to do with Jellyfin — `dio` decodes a body off the main isolate only above 50 KB,
and a 24-row page is 11.9 KB while a 240-row page is 118.9 KB. So the larger page moves the parse
off the thread that draws.

**What that does not establish is that scrolling feels smooth.** These are request timings. Turning
240 rows into tiles happens on the main isolate and is unmeasured, as is any of it on a real device.
The claim here is about how often the grid must go back to the server, which is ten times less
often; the frames are not measured.

The filtering window is the same 240. It used to be four times the page — a multiple that bought a
single round trip when a quarter of the rows survived, which was the right trade against 24. At 240
it inverts: most of a library is not given to any one child, so survival is usually high, and asking
for 960 to keep 240 would over-fetch fourfold on the common path to save a refill on the rare one.

**A series says how many episodes it holds**, in the same bottom-right corner and the same badge
as a collection's size — asked for on the strength of that one. It reads "5 episodes", never
"5 titles": the noun is not interchangeable, and the number comes from `RecursiveItemCount` rather
than `ChildCount`, which for a series counts the **seasons**. A two-season, five-episode show
reports 2 for the latter, so the obvious reuse would have printed a count of something the tile
never mentions.

There is no share badge on a show. A series is one item to give and its label reaches every episode
inside, so there is no partial state for a ring to describe — the collection's `3/6` exists
precisely because a set can be half given.

**A collection is outlined**, in a 2dp line in the tertiary tone, drawn over the artwork rather
than behind it — the poster fills the whole rect, so a border in the background is a border nobody
can see.

Two earlier answers were tried and lost on a phone. Rounding separates nothing: every poster
already clips at 8, so collections would need a *different* radius, and a few pixels of curvature
is a difference a parent has to look for. A stack of two dimmer sheets behind the top-right corner
replaced it, read clearly on a development machine and was reported as too subtle from a phone.
Both failed the same way — an unsaturated difference, in one corner, on a tile that is ~83dp wide
at four columns. The line is the whole silhouette, so no size leaves it in the part of the tile the
eye is not on, and colour does most of the work.

Gold was the other suggestion and was set aside: the palette has none, and a colour outside it for
one marker spreads. Tertiary is already this screen's "worth a second look" tone.

It does not replace the "{count} titles" badge. The line says *a set*; the badge says *how big*.
The state badge and the faces are pinned to the tile's own corners — they carried an offset for as
long as the poster was inset for the sheets behind it, and with the line drawn *on* the poster
there is no inset.

**A collection stands in for its members, and only when nothing narrows the grid.** With no filter
and no child picked, a film that belongs to a `BoxSet` on the same grid is not drawn; the set is.
Any filter, a search or a picked child switches this off — a set can fail a filter its members
pass, most obviously a search, which matches a film's title and not the set's name. Hiding a film
behind a set that is not on the grid would show the parent nothing for a title that exists.

**A search finds a set through the film inside it, and the set comes first.** `searchTerm` matches
substrings of an item's **own** title, so the server returns a set when its name shares the term —
*Paddington* finds *Paddington Collection* — and misses one that does not, such as *Bear Films*
holding *Paddington*. The app adds the missing sets from the collection index, ahead of the films,
with *Contains a match* under the title, and never adds one the server already returned. Nothing the
parent typed is removed — the film they searched for is still there — and the label is what stops a
row nobody asked for reading as the app answering a different question.

**Known limit: ordering.** A set sorts by its own name, so it can land on a later page than the
films it stands for. Until that page loads those films are on no page and the set is not there
either — the grid is short by design, briefly. Searching *through* a collection, so that a member's
title finds the set, is a separate question and is not built.

**And the order is now a setting, which widens that limit rather than creating it.** Under *date
added* a set carries the date the collection itself was made, which can be nowhere near its films';
under *release date* a set has no date at all, so every collection groups with the other undated
titles — at the top ascending, at the bottom descending, alphabetically within the group. Measured,
not assumed: a server sets a year from the file name and a collection gets none. Sets are
deliberately **not** given a date computed from their members — an order a parent cannot see the
rule for is worse than one they can.

3. **Result line** — "N things Emma hasn't got yet", with a text button that leaves whichever
   slice is on screen. There are **three**: what is left to give (the default, from Settings),
   everything, and what the child can already see. The third is where a tap on a face lands and is
   not otherwise reachable from the button, whose job there is to get back to the giving grid.
   All three run the same query and differ only in which classified entries are kept — the grid is
   the administrator's view in every one of them, which is what keeps "not given yet" answerable.

   **It subtracts collapsed members only when the collapse is on** (above). Elsewhere it is the
   server's own count and may read higher than the number of tiles: the collection index knows
   membership, not which members a genre, a decade or a search would have kept, so subtracting
   them all would report fewer titles than the grid holds.
   Show/Hide shared text button. **N is
 `total − tagged`, both counted by the server under the active filters** — never the number of
   tiles loaded, which climbs as the parent scrolls, and never the grid's contents, which include
   already-shared titles whenever Show shared is on. A block-list child reads the other way round —
   "N things kept from Sam", the tagged count itself — and a conflicting account gets the library's
   own count with no claim about them (ground rule 3). Until the count arrives, and if it fails,
   the line says what the library holds: true either way, and better than a spinner over a number.
4. **The order** — *date added*, *release date* or *name*, ascending or descending, from Settings.
   The default is name ascending, which is what the app did before the setting existed, so nobody's
   grid changes until they change it. One Settings row for the field with the direction as an arrow
   beside it; the arrow states its meaning in words through a tooltip, which is also what a screen
   reader announces, because it is the one control in that group whose meaning is a shape.

   **Both tile screens follow it** — the library grid and a collection's members, since browsing a
   set is the library narrowed to one container. The decade menu and the collections list are not
   tile grids and keep their own name order.

   **Changing it starts the grid at the top.** A refresh restores the window that was open; a new
   order is a different list, and restoring a window into it would hand back the first N entries of
   a list whose start the parent has never seen.

5. **Poster grid** — **the poster size setting is a target width, and the column count falls out
 of the window**: 175dp at regular, 360 at large, 112 at small. **This is the first thing
   written down here about large screens**, and the reason is that the old fixed count had no upper
   end: the same three columns were used at 412dp and at 1280dp, so a 10" tablet in landscape drew
   posters 3.4× wider than the phone they were meant for, ~703dp tall against a ~800dp viewport —
   not one complete row visible, and at the large setting a single poster taller than the screen.

   **The old "2 columns under 400dp" now reads "under about 406dp".** That rule was a hard cliff and
   a continuous target cannot reproduce one — forcing the crossover onto 400 exactly pins the small
   size into a ~0.3dp window, which is a fitted constant rather than a chosen number. So the
   crossover lands where the arithmetic puts it, and the targets are chosen to decide *which* band
   moves: every phone width below 400dp behaves exactly as before, including 393dp — a Pixel 4a/5/5a
   — and 400–406dp gets one column fewer than it used to. That direction is deliberate: posters get
   bigger there, never smaller, which is what the old rule cared about when it called three columns
   on a small phone "stamps".

   The width read is the one the grid is *given*, not the display, so a narrow parent inside a wide
   window — split-screen, a folded foldable — gets the narrow answer. Collections get an
   outlined poster and a count badge. **Both edges of a poster lay their markers out against each
   other rather than pinning them to opposite corners** — the state badge against the avatars at
   the top, the age hint against the collection count at the bottom. Opposite corners collide on
   anything narrower than a two-column tile, and it is a silent collision: everything stays inside
 the tile, so nothing errors. The top edge shrinks (three faces, then one and a `+N`, then
 nothing) because a `+N` can stand for a face; the bottom edge **wraps** instead, the count
   taking the line below, because neither of those is a picture and nothing stands for a word. A
   lone count — no child selected, so no hint — keeps the bottom-right corner it has always had.
   Already-shared items carry a check badge. Each tile shows avatars of the children who have it —
   **"have" meaning the label is on the item, never "can watch it"** (ground rule 4). Allow-list
   children only: for a block-list child the same tag means the title is *withheld*, and a
   conflicting account has no verb at all (ground rule 3), so neither appears. Three overlapped
 22dp circles at most, then a `+N` circle for the rest; a child with no picture falls back to
   their initial. They share the poster's top edge with the state badge and **shrink to whatever
 the badge leaves** — three faces and a `+N`, then two, then one, then nothing. The badge is the
 answer about the child the parent picked, so it keeps its width. A `+N` is never drawn alone:
   beside faces it means "N more than these", and on its own it would mean "N in total" — the same
   glyph with two meanings, on the smallest tile. The faces are in the tile's spoken label at every
   width, in full, minus the selected child, whom the badge has just named. The held-back nuance
   stays with the selected child's badge —
   knowing it for everyone would cost a query per child per title. The faces show with no child
   selected, which is the case they exist for, and no badge exists then, so the whole edge is
   theirs.

   A tile's spoken label names the **kind** as well as the title when it is a set — "Collection,
 7 titles". The count badge is a picture, and without this a box set and a film were the
   same sentence to a screen reader, on the one tile whose tap goes somewhere different. It comes
   second, straight after the name, because it is what the thing *is* rather than what has been
   done with it; it is spoken whatever the selection is, unlike the state badge, because it is not
   a claim about a child; and it falls back to "Collection" alone when the server sent no
 `ChildCount`, rather than inventing "0 titles".

6. **The assign panel**, from 840dp — the write preview beside the grid rather than a sheet over
   it. "Pick a child, pick a film" is a comparison, and on a tablet there is room to keep the thing
   being compared against on screen: the tiles stay visible and stay tappable while a preview is
   open. Below 840dp the same tap opens the modal sheet, and the two are never both live — a sheet
   over a panel would be two previews of one write, either of which could be applied.

   The panel is on screen **whether or not anything is picked**, showing a line about what the
   space is for. Appearing only on demand would re-flow the grid on every selection, moving the
   poster that was just tapped out from under the finger that tapped it.

   It is **keyed by the item**, which is not a detail: the panel's state is the pending toggles, and
   reused across a selection it would let a parent flick *give to Emma* on one film, change their
   mind, tap another, and write the second film to Emma from a switch they set for the first —
   with the switch on screen agreeing, because it is the switch they flicked. Opening a collection
   empties the panel for the same reason.

## Collection screen

**Tapping a collection opens it. It asks nothing.** Before this, a collection tile behaved like a
film — one tap opened the assign sheet for the whole set, whose Apply writes to every member *and*
the container. A parent tapping a box set is looking, and "give all eight to Emma?" is an answer to
a question they did not ask.

- The members, as ordinary library tiles — same badges, same age hints, same faces, because a title
  has to mean the same thing inside a set as it does on the grid. They are classified by the same
  code the grid uses, not a second copy of it.
- **"Give the whole set"** is a button on this screen, not the tap. It opens exactly the sheet the
  tap used to, so nothing is lost from the old flow except that it stops happening by accident. It
  is always enabled, with a child picked or not: the sheet asks who gets this and lists every
  shortlisted child with a switch, so the question a gate here would ask is answered one screen
  later and better. It was gated once, on the grounds that the preview is a preview *for a child*;
  that was wrong about the sheet, which takes the child rows from the shortlist rather than from
  the selection — the library grid has always opened the same sheet with nobody picked.
- The child chips stay on screen, and the selection carries in and back out — deciding about a set
  is when a parent is most likely to want to check it against a second child.
- Tapping a member opens the ordinary assign sheet for that member. Members arrive from
 `GET /Items?parentId=` with 16 fields against the write path's 41, so nothing on this screen
  posts one back: the sheet re-reads its own body (ground rule 2).

**What this screen deliberately does not change:** giving some members and not others still leaves
the container unlabelled, so the child reaches those films by search while the collection itself
answers 401. That is today's behaviour, not something browsing introduced — it is simply much
easier to reach now. Tracked separately rather than decided here.

### How much of the set is theirs

Under the title count, whenever a child is picked: **"Nothing here is Emma's yet"**, **"4 of 6 given
to Emma"**, or **"All 6 given to Emma"** — and the same three inverted for a block-list child, who is
*kept from* rather than *given* (ground rule 3). Nobody picked, or an account ground rule 3 refuses
to interpret, and the line is absent rather than guessed.

The same sentence appears on **each child's row of a set's write preview**, where it answers a
different question from the row above it: *"Emma sees 24 of 400"* is what the server shows her across
the library, and this is what has been handed over inside this set.

**It counts labels, not visibility**, and the two never share a line. A rating cap can hide a
labelled title, so "4 of 6 given" and "sees 4 of 6" are different facts — computing the second here
is what ground rule 4 forbids.

Free on both screens: the members are already fetched and already classified, so this is a count of
what is on screen rather than a question for the server. **The grid's collection tile does not carry
it yet** — the grid has no membership to count without building the collection index, which is 1 + N
requests, and that cost wants measuring before it goes on the landing screen.

## Assign sheet (modal bottom sheet — or a side panel, from 840dp)

Cover, title, metadata. For a collection: a note that labels land on all N titles inside **and on
the collection itself** — measured, a set whose members alone are labelled hands the child the
films without the set, and browsing it answers 401. For a film in a collection: a softer note
naming the set, **one per set**, because a film can belong to several.

One row per label-controlled child, the selected one first. Rows above the child's rating cap are
flagged. Each row carries that child's **current** visible count — "Emma sees 24 of 400" —
fetched from the server, never computed here.

Toggling updates a **tag diff** — the exact additions and removals — which is the only place a
write is previewed. Apply, or Cancel.

**The preview and the surface it appears on are separate things.** The same view is the sheet
on a phone and the panel on a tablet; what a surface owns is how it is dismissed, and it hands that
in. Nothing else about the preview changes with the width — the rows, the diff, the last-item
warning, the cascade question and Apply are the same code on both.

The preview shows the count as it stands, not a prediction. Predicting the result would mean
simulating the server's policy evaluation, including the rating cap, which ground rule 4 forbids
precisely because it goes wrong silently.

**Apply closes the sheet as soon as the write lands, not when the count does.** The write is
two round trips and does not get slower; re-reading the child's verified count costs what their
visible library is large — measured from 19 ms to 538 ms — so the spinner was covering work that
had already finished. The toast appears immediately with what is true — *Shared with Emma*, or
*Taken back from Emma* — and the counted sentence, *Emma now sees 24 of 400*, replaces it when the
server answers. If the count never arrives, the first sentence stays; it was complete on its own.

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

**The toast's Undo expires after eight seconds; Activity's does not.** The toast used to
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

## Kids — the landing screen

**The app opens here**, and Kids is first in the navigation. Both moved together in 0.2.0;
the reasoning and what it reverses are in § Library.

What it already carries is most of what a welcome screen was asked for: the children's
pictures, each child's total in their own verb, and the live sessions above them. The
This section describes what ships today.

**Nobody to look after yet.** When the server has accounts but none of them has a shortlist —
the ordinary first run — the screen invites the parent to set one up in Jellyfin and links to
Jellyfin's own documentation. An invitation rather than an empty state: they have a server and
accounts, and the one step left is the one Garfin is not allowed to take for them (ground rule
8). The link goes to Jellyfin's words because the setting names are theirs and a summary here
would go stale the first time they moved one. It disappears as soon as there is a child.

**The faces are sized to how many there are** — 36 for one or two, 30 for three or four, 24
beyond that. Capped rather than sized to the space: measured, a user's avatar arrives at
whatever resolution it was uploaded and Jellyfin ignores every request to resize it, so
drawing one larger risks upscaling a picture the app has no way to know is small.

**The sessions block is absent entirely when nothing is playing** — not an empty panel, and
not a heading with nothing under it.

**The faces arrive before the counts.** Listing the children is one cheap request; the
counts beside them are the most expensive thing the app does (19 ms at one title, 8.7 s at
six thousand, and 7.6 s for the administrator's total on the same library). So the children
are drawn as soon as they are known and the numbers fill in underneath, rather than a
spinner standing in for both.

There is deliberately **no placeholder where the number will be** — no bar, no shimmer. A
shape that implies a number is coming is a promise about a request that can fail, and the
honest rendering of *not known yet* is the absence of a sentence.

**A child's picture is its own tap target, and means *pick this child*.** It sets the same
selection the Library's app-bar avatar sets and then goes there, so the grid, the rating-cap switch
and what carries into the assign sheet are that one state rather than a second version of it — one
meaning for a face everywhere in the app.

**Arriving from the navigation shows Everyone instead.** Coming from a face means *this child*;
coming from the navigation means *the library*. There is no remembered starting child any more —
the stored setting is gone, because it answered a question the parent had not asked on every visit
but the first.

The target is the picture and not the row around it. This is the one place on this screen
where a mistap takes a parent somewhere they did not ask to go, so the rest of the row is
deliberately not a near-miss on it.

**The rest of the row opens the per-library breakdown, in place.** No route and no
navigation: one target leaves the screen, the other shows more of it, and keeping them
apart is what makes a mistap harmless. Each library is listed with what that child can see
in it — visibility only, since labels and visibility never share a line, and a label count
would be a second row rather than a second number on this one.

**Nothing per-library is requested until a row is opened**, and then only for that child.
The counts query tracks the result set (19 ms at one title, 8.7 s at six thousand), so
asking it per child per library on every open would make this the slowest screen in the
app. The requests fan out at the house limit of four. Opening a row twice does not ask
twice; the answer is cached per child.

**The sessions block polls; nothing else does.** `/Sessions` is re-read every ten seconds
while this screen is the one on show and the app is in front, and once immediately on
resume so returning does not wait out an interval. Pull-to-refresh does the same thing on
demand.

It re-reads **only** the sessions. The per-child visible counts come from the same
dependency chain and are the expensive half — that query scales worse than linearly with
what a child can already see, 19 ms at one title against 8.7 s at six thousand — so it is
never on the timer and no longer on the pull either. Labels change through a write, and the
write path invalidates the counts itself.

A poll is **skipped**, not queued, while a Stop or End is waiting on its read-back: those
commands answer 204 whether or not the client obeyed, and re-read `/Sessions` a few seconds
later to say what actually happened. A tick landing in between would ask the server before
it can reflect the command and redraw the card as though nothing had.

Cards for label-controlled users, **at rest**: the picture, the name, the age, and a way to
sign the child in on a device. Nothing else, and a chevron saying there is more.

Everything else waits behind the tap, and arrives as **two cards, not one run of lines**: what
Jellyfin enforces on the account — the cap, **the access hours**, and the labels — under *Parental
controls for {name}*, and what the child can see library by library, under *{name} has access to*.
Two unrelated kinds of fact were sharing a column with a heading holding them apart; a card does
that in the shape instead.

**Both headings name the child**, because a card that opens from a face should keep saying whose
face it was. The per-library rows are sorted **most-seen first**, so the answer to "where can they
see the most" is the first line rather than a scan.

**The labels are introduced by a sentence, not shown bare.** A row of chips under two sentences was
a list with no verb: it never said whether carrying one of these is what lets the child see
something or what stops them. Ground rule 3 makes those opposites, so the sentence is chosen by the
account's mode — and a **conflicting** account gets neither, because picking a verb there is exactly
the guess the rule forbids. The standalone mode pill is gone with it: the sentence already says
which list this is, and the pill had been reported as a button that does not work.

**There is no headline count.** "N of M things visible" is gone rather than moved. The per-library
rows answer the same question with more resolution, and keeping both meant a total that could
disagree with the breakdown directly beneath it — the total counts `Movie,Series` across the whole
server, the rows count each library's own types within what the child can open. It was also the
most expensive single thing the card computed: measured, a child's count is 19 ms at one title and
8.7 s at six thousand. The progress bar that used to render it went earlier, for the same reason.

**And the request went with it.** Once nothing drew the number, the Kids screen stopped asking for
it: one `visibleItemCount` for the administrator plus one per child, gone from every load and every
invalidation after a write. What is left on that path is the ratings ladder, which is a property of
the server and is fetched once for everyone. The per-library counts are asked when a card is
opened, and not before.

The tap target is the row beside the picture, not the picture itself — the picture picks the
child and leaves for the Library, and the two meanings stay apart.

The hours are the other half of what Jellyfin enforces, and the card shows both or summarises
neither honestly. They are **the server's hours, said so** — measured, the API exposes no offset, so
they cannot be converted — and a child with no schedule is told they can watch at any time rather
than being left blank, which would read as the opposite.

**Only children under a rule appear.** Accounts Garfin cannot manage are not listed, not counted
and not named anywhere on this screen.

### Whose settings are on a kid's card, and where they live

Three lines sit in one column and come from three different places: the **age**, from a birth year
the parent enters and Garfin keeps on this phone; the **rating limit** and the **hours**, both read
from the child's Jellyfin account and never written (ground rule 8). Stacked without a word they
read as one list of Garfin's, and the birth year sounds like it drives the limit beneath it. It does
not — it only shapes the Library's age hints.

So the two server-owned lines sit under a **"Set in Jellyfin"** heading, with a help button beside
it opening one explanation for all three facts: what Garfin does to the child's list, that it reads
the limit and the hours and never writes them, where to change them — *Dashboard → Users → {name} →
Parental Control*, which are Jellyfin's own menu names — and what the birth year is actually for.

**The mode label is a label, not a chip.** It reports which kind of list the account uses and has
never done anything on tap; drawn as a `Chip` it imitated the tappable `FilterChip`s the library
filter bar carried at the time, and was duly reported as a button that does not work. Those chips
have since gone (§ Library, item 2); the reasoning stands without the comparison. In French the pair reads as two
values of one setting — *Liste de sélection* / *Liste d'exclusion* — rather than a bare noun that is
also a verb.

### Accounts Garfin cannot manage are absent, not explained

The screen used to list them: a non-interactive section, with pictures and a line of copy, for
every account with no shortlist or with both lists set. It is gone. They are not shown, not
counted and not named.

The reasoning that put it there was sound, and is kept here because it is what makes the absence a
decision rather than an oversight. Garfin cannot give a child their first label — that is a policy
write and ground rule 8 forbids it — so the section was a boundary rather than a to-do list, and it
carried copy precisely so it would not read as a dead end.

What replaced it is the judgement that this screen is *the children under a rule*, and that the
space belongs to them. A household's unmanaged accounts are usually the adults, so the old section
spent the top of the landing screen listing Mum, Dad and a guest under a heading explaining that
Garfin will not act on any of them.

**What this costs, recorded so it is not rediscovered as a bug.** That section was the only answer
to "why is this child not here?". The answer is now silence — and ground rule 8 means Garfin could
not have fixed the absence anyway. The invitation shown when nobody is managed becomes the whole of
what the screen says on the subject, which makes it load-bearing rather than decorative: it must
keep firing in the case where the server has accounts and none of them is managed.

**They are still known, just not drawn.** The roster keeps them, because "this server has no
accounts at all" and "it has accounts and none of them is managed" are different sentences wanting
different screens. Dropping the data would collapse the two and take the invitation with it.

### Labels Jellyfin can read as one

Above everything else on the screen, when it applies: the children whose labels the server can
fold into a single one, and what to do about it.

Jellyfin does not compare a tag literally. It strips accents and folds case before matching, and
on 12.0 it also reduces punctuation to spaces and collapses the runs — so `kids-emma`,
`kids_emma`, `Kids Emma` and `kids--emma` are one label, and so are `kids-chloé` and
`kids-chloe`. Two children whose labels differ only that much end up sharing one list, and
nothing else in the picture tells the parent. **Garfin cannot prevent it** — it never invents a
label and never writes a policy — but it already reads every managed child's policy to build this
screen, so it is the one thing that can notice.

Four things this pins down:

- **It says Jellyfin *can* read the labels as one, never that it does.** The folding differs by
  server version: a pair differing only by punctuation collides on 12.0 and on *neither* path of
  10.11.11. Asserting the consequence outright would be false on current stable, which is the
  class of claim this project treats as a defect. The conditional carries it — *while it does* —
  and the advice is identical on every version, which is the half worth acting on anyway.
- **Warning early is deliberate.** The rule applied is 12.0's, whatever the server is. It is not
  one of two rules to choose between: 12.0's folding is 10.11.11's with a further step applied to
  its output, so every collision the older rule finds the newer one finds too, and applying the
  newer one alone is exactly the union of both. It can therefore never miss a clash; it can only
  name one that a 10.11.11 server has not started making yet.
- **Two sentences, because there are two events.** Two allow-lists folding together means what one
  child is given reaches the other. An allow-list folding into a *block*-list is the opposite —
  one tag doing both jobs, so giving one child a title takes it away from the other. A single
  sentence general enough for both stops being worth reading, and one that fits either would be
  false of the other.
- **Sharing on purpose is not a clash.** Two children deliberately holding one identical label are
  not warned about, nor is a single child holding two labels that fold together. The first is an
  ordinary household setup and the second is merely redundant. A warning that fires on those
  teaches a parent to ignore the one that matters.

Renaming anybody's label stays out of scope, for the same reason Garfin never invents one: see
`docs/DECISIONS.md`. Detect and explain; the parent chooses the fix, in Jellyfin.

The diacritic folding is a dependency rather than a hand-rolled table, and it folds a few letters
that have no Unicode decomposition. Two of those have now been measured against a running 12.0
server: **`œ` agrees** — the case that matters most here, since `œ` is ordinary French — and **`ß`
does not**, the server leaving it alone where the dependency folds it to a single `s`. `æ`, `ø` and
the rest of that family are still unmeasured and are not predicted by `œ`.

Where they disagree, Garfin folds *more* than the server, so it can name a pair the server keeps
apart and cannot miss one the server folds — the same direction it already errs in above, and the
reason the copy is conditional rather than assertive.

### Signed in now

Above the cards when anyone is: who, on which device, and what they are watching with how far in.
Absent entirely when nobody is signed in, and absent while it loads or if it fails — a sessions
list that cannot be fetched is not news a parent can act on, and it must not displace the cards.

**What is playing is named by the show, not by the episode.** Reported from family use: an
episode's own name is frequently not something a parent can place — "Chapter 3", "The One
Where…" — so a card carrying only that answers the question with a riddle. An episode therefore
shows the **series** as its title, with the episode name secondary underneath; a film, which was
always self-describing, keeps the single line it had.

Beside both, the **artwork**: the show's poster for an episode, the film's own for a film. It is
the glance-level answer where the words are a reading one, at a poster's proportions and small
enough to sit beside a sentence rather than compete with it.

Three things this pins down:

- **An episode's own image is never used**, even where the server sends one. It is a still from the
  episode — measured `PrimaryImageAspectRatio` ≈ **1.78** against a film poster's ≈ **0.67** — so
  cropping it into a 2:3 poster box gives a parent a rectangle they can place even less than the
  title they started with. Rejected first on reasoning, now on a number.

  **Which picture is chosen follows the item's `Type`, not which fields arrived.** The series
  fields are absent on a film rather than empty, so asking "is there a `SeriesId`?" happens to
  give the right answer for both kinds that were measured — and that is not the same as being
  what was measured.
- **No artwork is a supported state, drawn as no artwork.** Not a grey box holding space, and not a
  tagless image URL: without the version tag the picture would be asked for by name alone, and a
  cached poster would outlive the artwork it shows. Where there is no tag there is no picture, and
  the row is the plain sentence.
- **The fields this reads were inferred from the item DTO and have since been measured.** Read off
  a live server, one episode and one film; the inference held exactly, and `docs/JELLYFIN-API.md`
  now carries the fields rather than the absence of them. They stay optional in the model all the
  same — that is one server and one version, not a survey — so an absent field still costs the
  artwork and nothing else.

Three actions, in the order a parent reaches for them: **send a message** (which costs the child
nothing and so needs no confirmation), **stop playback**, and **end session**. The last two are
confirmed, per ground rule 6.

**The copy says what was sent, not what happened.** Measured: the message and stop commands answer
204 against a device that cannot act on either, so only ending a session — which really does revoke
the token — is reported as done. A device that says it cannot be remote-controlled says so on the
card, rather than letting a parent believe a message arrived.

**And then it says what happened, because "sent" was being read as "done".** Reported from
use: Stop doesn't stop the film and End session has no visible effect, both reporting success. The
requests were correct — the bug was that a 204 is all Garfin waited for. So the two disruptive
commands now read `/Sessions` back three seconds later and replace the sentence:

| | while waiting | read back |
|---|---|---|
| Stop | "Asked *device* to stop." | "*device* stopped playing." / "Asked *device* to stop, but it's still playing." |
| End | "*device* is signed out." | unchanged, or "*device* signed out, then signed straight back in." |

Four things this pins down:

- **The outcome arrives *into* the toast, never gating it** — the same shape, and its reasoning: the
  command has already finished, and a spinner over finished work is what was removed from the
  assign path. A read-back that fails leaves the first sentence up. It was true when it was said.
- **The card refreshes after the read-back, not before.** Invalidating the sessions list on the way
 out re-read `/Sessions` before the server could reflect anything, so the card redrew identical —
  half of why "nothing happened" was the obvious reading.
- **Ending is matched on the device, and on the device alone.** Measured on 10.11.11:
 `DELETE /Devices?id=` is **device-wide** — one revoke put both users signed in on a shared device
 onto 401 — and `/Sessions` holds at most one row per device id, a second user's sign-in taking
 that row over rather than adding to it. So there is no per-user session for a `userId` clause to
 exclude, and no sibling session to mistake for the child's. Comparing `userId` would also make
  the sentence less true, since the copy names the device.
- **Stop stays enabled when `SupportsRemoteControl` is false.** That flag is the client's own claim
  and the commands answer 204 either way, so disabling on it withdraws a control that may work, on
  the strength of a self-report. What was dishonest was the copy, and the copy now reads back.

**Three seconds is a choice, not a measurement** — the one number here that is neither. It errs
long on purpose: too short accuses a client that was about to comply, too long costs a few seconds
of a toast that already said something true.

**Not covered: whether a film already playing survives its own token being revoked.** An ended
session is not in `/Sessions` to be asked, so this route is invisible to the read-back and remains
unmeasured. Nothing in the copy claims either way.

**The message command does not read back**, and that is a decision rather than an oversight: no
endpoint was looked for that would report whether a line of text was displayed, and none was
measured. "Sent" stays the whole of what that command claims.

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

**This is Garfin's own record, and the screen says so.** Measured: Jellyfin logs nothing
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
- **Picking** — hide shared
- **Looks** — theme, dynamic colour, poster size, library order
- **About** — one tile, showing the version, opening the About screen below

## About

Reached from Settings → About. Top bar with a back button, centred scrolling column:

- **The mark**, 84dp, from `assets/brand/` — output of `brand/make-app-assets.sh`, whose source
  is the same SVG the launcher icon comes from.
- **Garfin** in Fredoka, semi-bold, `headlineSmall`. The product name, not a translated string.
- **Version**, in `colorScheme.outline`.
- **Check for updates** — one call to GitHub *per press*, never automatic. The answer appears in
  place and stays there rather than in a snackbar that slides away: someone opened this screen in
  order to read something. Six outcomes, each with its own sentence — a newer release (named by
  its tag, with an Open button), up to date, nothing published yet, rate-limited, unreachable,
  unreadable. "Nothing published yet" is not phrased as a failure, because it is true of Garfin
  itself until the first release ships.
- **Links** — Documentation, Source code, Report an issue, Releases. Each shows its address as
  the subtitle: the tile leaves the app, and someone handing a phone around should be able to see
  where a tap goes before taking it.
- **Licences** — the GPL line, then Flutter's own licence page, then the non-affiliation note.

The mark takes five taps, and nothing before the fifth. It is not announced anywhere and
carries no affordance — no ripple, no button semantics — which is the point of it.

### Three switches this list used to carry, and why they are gone

Each was written before the rule that rules it out was settled. A switch that controls nothing
reads as a promise, so they are recorded here rather than left on the screen.

- **Tag prefix, on/off and the prefix itself.** Garfin never composes a label: it reads the child's
 existing one out of `Policy.AllowedTags` and writes that string back in the policy's own casing.
  There is nothing to prefix. Giving a child their *first* label is a policy write, which ground
  rule 8 forbids — the same consequence as the Kids screen's "set their shortlist up in Jellyfin
  first".
- **Cascade to collection members.** `docs/DECISIONS.md` § Collections: a collection **always**
  writes to its members, and measurement showed what the alternative does — the child gets a visible,
  empty collection. Off is not a preference, it is a broken write.
- **Cascade to episodes.** Not a gap after all, which was established by measuring it: the policy
  filter inherits from the series, so a label on a series is already enough for the child to see
  every season and episode inside it — they inherit the label, report it, and are matched by
 `tags=`. There is nothing for a switch to turn on, and the old note was wrong rather than
  half-right.

**Respect age cap** is the filter bar's rating toggle, not a setting, and **libraries to
browse** waits on the same grid work — `/Items` takes one `parentId`, so more than one library is
a pagination question rather than a preference.
