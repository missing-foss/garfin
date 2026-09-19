<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

<p align="center">
  <img src="brand/svg/garfin-lockup-v.svg" width="260" alt="Garfin">
</p>

<p align="center">
  <b>Hand-pick what your kids can watch.</b><br>
  An Android app for managing Jellyfin parental controls through tags.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/licence-GPL--3.0-blue" alt="GPL-3.0">
  <img src="https://img.shields.io/badge/platform-Android-3ddc84" alt="Android">
  <img src="https://img.shields.io/badge/built%20with-Flutter-42a5f5" alt="Flutter">
</p>

---

Jellyfin can restrict what a user sees by tag, but tagging hundreds of items one at a time in the
web admin is miserable. Garfin puts the whole thing on your phone: pick a child, browse what they
can't see yet, and hand them a film, a series, or a whole collection in one tap.

**You sign in as a Jellyfin administrator**, and that is Jellyfin's requirement rather than
Garfin's: the server has no lesser permission that can manage parental controls. Measured — an
account with every other permission switched on still cannot edit a policy or write a tag. So a
second parent who wants to use Garfin needs administrator access too, and there is no reduced
mode that does less and still does something useful. What that leaves them is below.

## What it does

- Connects to your server with **Quick Connect** or a password (admin account required)
- Lists every user and shows which ones are actually under tag-based control
- Per child: which libraries they reach, and how many items they can see **in each one** —
  counted by the server, not guessed
- Browse the library as posters, with a title search, and filters for type, genre, decade and
  the child's rating cap
- Assign a title to one or more children; the tag is written back to Jellyfin so it appears
  on their next refresh
- **Collections**: tag a set and every film inside gets it; tag one film from a set and Garfin
  asks whether to keep the set together
- Every write is previewed as a tag diff before it happens, and undoable after

## Install

Android 8.0 or newer. The APK is published on the project's Releases page, so
Android will ask you to allow installing from wherever you downloaded it.

**Check what you downloaded before installing it.** The signing fingerprint is
not a secret and is published in [`SECURITY.md`](SECURITY.md):

```sh
apksigner verify --print-certs garfin-<version>.apk
```

The `Signer #1 certificate SHA-256 digest` it prints must equal the fingerprint
recorded there. If it does not, do not install it — that is the whole point of
checking, and there is no second signal that would tell you.

**v0.1.0 carries a different fingerprint from the releases after it**, because
this app's signing key was changed early on. `SECURITY.md` records both values
and the reason, so v0.1.0 stays verifiable. An update cannot cross a key change,
so anyone holding v0.1.0 installs the newer one fresh rather than updating over
it.

## First run

1. **Type your server's address.** It is remembered, so this is a one-time step.
2. **Sign in with Quick Connect or a password.** Quick Connect shows a six-digit code
   and polls while you authorise it from an already signed-in Jellyfin session.
   Leaving Garfin to go and do that is expected. If the app is killed mid-pairing,
   you get a fresh code next time -- the pairing secret is never stored to survive it.
3. **A non-admin account is refused here**, with the reason, rather than failing later
   on the first write.
4. **Once, straight after signing in**, Garfin asks whether to require your
   fingerprint or PIN each time it opens. "Ask every time" is the recommendation and
   is what a fresh install does anyway. Either answer is remembered and the question
   never comes back; Settings can change it later.

That gate exists because of what this app is: it holds an administrator token on a
phone that gets handed to children as its normal mode of use. Your device's own lock
does not cover the case Garfin itself creates. On Android 8.0 and 8.1 there is no
biometric prompt, so it goes straight to the device credential -- and if the device has
no PIN or pattern set at all, Garfin says so and lets you carry on rather than locking
you out of a lock it cannot enforce.

## How sharing works

Jellyfin decides what a child can see from a **tag list on their account**, and Garfin
edits which titles carry those tags. It does not invent the label: it reads the one
already on the child's account and writes that same string back, in the server's own
casing.

- **Pick a child, then browse.** The grid shows what is in the library, filtered by
  type, genre, decade, and optionally the child's own rating cap.
- **Hand over a title in one tap.** The tag is written to the item, so it appears for
  the child on their next refresh.
- **Collections carry their members.** Tag a set and every film inside gets the tag.
  Tag one film out of a set and Garfin asks once whether to keep the set together.
- **A series carries its episodes**, with nothing to switch on: the filter inherits
  down from the series, so labelling the series is enough for every season and episode
  inside it.
- **Every write is previewed first** as an exact list of tags added and removed. Nothing
  is written on a toggle, and the preview carries the child's current item count as the
  *server* computed it rather than a number Garfin worked out.
- **Undo is available afterwards**, and removing a title never cascades the way adding
  one does.

## A second parent

Jellyfin has no role between ordinary user and administrator, so a second parent who
wants to hand titles over needs an administrator account too. Three ways to arrange
that, and only the first is a recommendation.

**Give them an administrator account of their own.** The one that works. It is a full
administrator on the server, so it is a real trust decision rather than a formality --
though in practice they use Garfin rather than the dashboard, and the account being an
administrator is the reason the app asks for a fingerprint or PIN when it opens.

**Share one administrator account across both phones.** This works, and it does not
cost you a record of who changed what -- because there is no such record either way.
Garfin's Activity screen is kept on the phone that did the writing and never names who
was holding it, and Jellyfin's own activity log gains no entry at all when an item's
tags change. Separate accounts are still better, for a different reason: each phone
holds its own token, so one parent can be signed out without disturbing the other.

**Neither.** A non-administrator can browse and watch, and cannot change what the
children see. Nothing in Garfin lifts that, and it does not pretend to.

## What Garfin does not do

Some of these are deliberate limits rather than missing features, and they are the ones
worth knowing before you rely on it.

- **It never changes a child's account settings.** Garfin only writes tags onto library
  items. It does not touch the rating cap, which library folders a child can reach, or
  any other permission -- the Jellyfin call that would do that replaces the account's
  entire permission set at once, and a single omitted field silently resets. So the
  actual safety control stays where you set it, in Jellyfin.
- **It cannot give a child their first tag.** Because of the above, a child who has no
  tag list yet has to be set up in Jellyfin once. After that, Garfin manages the
  contents.
- **It never guesses what a child can see.** Counts come from the server, asked twice --
  once as you, once as them. A rating cap can override tags, and guessing gets it wrong.
- **It is not a media player**, and it does not stream, download, or transcode anything.
- **It does not work around Jellyfin's permissions.** There is no lesser account than
  administrator that can manage parental controls, which is the requirement described
  above.

## Troubleshooting

**Sign-in says the account isn't an administrator.** That is the whole reason, and it
is refused there rather than later: Jellyfin has no lesser role that can manage
parental controls, so there is no reduced mode Garfin could offer instead.

**Your server address lost its username and password.** If you typed an address with
credentials in it, Garfin strips them and tells you so rather than storing them. It
cannot sign in through a server sitting behind its own separate login, because the
header it would need is already taken.

**A child is missing from the Kids screen.** Only accounts already under a tag list appear
there -- the screen shows the children Garfin can act on, and says nothing about the rest,
so an account with no list is simply absent rather than listed as unmanageable. Set a list
up for them in Jellyfin once; Garfin manages it from then on.

**The child still cannot see something you handed over.** Two usual causes. Their
**rating cap** may exclude it -- the cap overrides tags, and Garfin will not change a cap.
Or their client has not refreshed yet. The count shown in the preview is the server's,
so if that has gone up, the write landed.

**A collection appeared for the child but is empty.** That is what happens when a set is
labelled without its members, which is why Garfin always writes to both and does not
offer it as a choice.

**A title search returns titles that do not contain what you typed**, and a crowd of
collections marked *Contains a match* comes first. Check whether your server runs a search
plugin, such as Meilisearch. Jellyfin's own title search matches the typed text anywhere in a
title and nothing else. A search plugin replaces it for every client, Garfin included, and can
match single words or plot summaries instead. Garfin adds each collection holding a film the
server returned, so every loose match brings its collection with it. The fix is on the
server: have the plugin match all the words, and have its index search titles only. Some
plugin versions reset the searched fields when they reconnect, so if search goes wrong again
after a server restart, check them first.

**Quick Connect never completes.** Authorising the code needs a Jellyfin session that is
already signed in elsewhere. If Garfin was killed while waiting, start again -- the code
will be a new one, by design.

**It asks for a fingerprint every time and you would rather it did not.** Settings.
The question is only put once, right after signing in, so afterwards that is where it
lives.

## Status

**v0.1.0 is released.** Early, and `docs/ENGINEERING.md` records the build order
it followed.

It is signed with a different key from the releases after it — see **Install**
above, and [`SECURITY.md`](SECURITY.md) for both fingerprints and the reason.

## Documentation

| File | What's in it |
|---|---|
| [`docs/ENGINEERING.md`](docs/ENGINEERING.md) | Stack, conventions, ground rules |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Every design decision and why |
| [`docs/UI-SPEC.md`](docs/UI-SPEC.md) | Screen-by-screen behaviour |
| [`docs/JELLYFIN-API.md`](docs/JELLYFIN-API.md) | Endpoints and the things that bite |
| [`BRANDING.md`](BRANDING.md) | Logo, colours, type, licences |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | What the APK redistributes, and under what terms |

`docs/ui-mockup.jsx` is a clickable React mockup of the whole app — a visual reference, not source.
Open `brand/garfin-design-pack.html` in a browser for the full identity system.

## Licence

Source is **GPL-3.0-or-later**. Brand artwork is **CC BY-SA 4.0** — see `BRANDING.md`.

Garfin is not affiliated with, endorsed by, or connected to the Jellyfin project.
Jellyfin is a trademark of Jellyfin, Inc.
