<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Security

This documents Garfin's privacy posture and its at-rest protection of the Jellyfin
access token.

**Status: partially verified.** Garfin is pre-alpha.
Each claim below states what has actually been checked and what has not. Nothing
here is inherited by analogy from a sibling project — where verification is
outstanding it says so, and it must be completed before the first release.

## Reporting a vulnerability

Preferred: GitHub's **private vulnerability reporting** — "Report a
vulnerability" under this repository's Security tab. Or email
**missing_foss@etik.com** with details and, if possible, a way to reproduce.
Please don't open a public issue for anything exploitable until it's been
addressed.

## No telemetry

Garfin collects nothing, reports nothing, and has no analytics, crash-reporting
or tracking dependency.

**Verified (2026-08-02):** a static audit of the *full transitive* dependency
tree in `pubspec.lock` — 110 packages, not just the direct dependencies in
`pubspec.yaml` — found no analytics, telemetry, crash-reporting or attribution
SDK.

**Verified (2026-08-05), at runtime:** the release APK on an emulator —
Android 16, API 36, `sdk_gphone64_x86_64`.

Attribution is **per-UID, not per-packet**. A capture of the whole device
cannot separate Garfin's traffic from the system's, and this image talks to
Google constantly; Garfin ran as uid 10216, so network activity is read from
`dumpsys netstats detail` and `/proc/net/{tcp,tcp6,udp,udp6}` filtered to that
uid.

- **Idle, not signed in.** From install through launch, unlock, the sign-in
  screen, two minutes backgrounded and a resume: **zero** netstats entries and
  **zero** sockets for uid 10216. In the same window 23 other UIDs recorded
  traffic, which is what makes that zero evidence rather than a mis-aimed
  query.
- **Signed in.** Against a throwaway Jellyfin 10.11.11 over Quick Connect, 35
  socket samples across 60s and two cold restarts with session restore
  resolved to exactly **one** remote endpoint — the server signed in to — and
  no UDP. This doubles as the positive control for the bullet above: the same
  query goes from zero to non-zero the moment there is a server to talk to.

**What that does not cover:** the test server was addressed by IP over plain
HTTP, so no name resolution happened. A deployment addressed by hostname
resolves through the system resolver under a different uid, which a per-UID
method cannot see. This says Garfin opens no socket to anywhere but its
server; it does not say Garfin never causes a DNS lookup.

Note for contributors: Flutter's *tooling* reports usage analytics to Google by
default. That is the `flutter` command on a developer's machine, not anything
shipped in the APK, and the two must not be conflated. Disable it locally with
`flutter --disable-analytics`.

## What Garfin talks to

**Exactly one host: the Jellyfin server the user signs in to.** There is no
Garfin backend, no account system, and no third-party service. Nothing Garfin
*sends* goes anywhere but that server.

**One qualification, and it is the platform's rather than the app's.** Nothing
in `android/` declares `allowBackup`, `dataExtractionRules`,
`fullBackupContent` or a `backupAgent`, so Android's default `allowBackup="true"`
applies and `shared_preferences` is eligible for **Auto Backup** and
**device-to-device transfer**. That means the server URL, the signed-in user's
id and name, the unlock settings and `device_id` can be uploaded to the user's
own cloud account and restored onto a different phone. It is their account and
recent Android encrypts those backups with a key derived from the device
credential — so this is a qualification, not a refutation. But it is
platform-mediated egress, and the verification below cannot see it: that reading
is scoped to the app's own HTTP. See #35 for the decision about whether to turn
it off.

**Verified statically (2026-08-04).** The earlier version of this line said the
claim held "trivially, by absence — there is no HTTP call in the codebase yet",
which stopped being true when the client landed in #24.

Every HTTP call goes through one place. `JellyfinApiFactory.create` holds the
only `Dio(` constructor in `lib/`, its `baseUrl` is the address the user typed,
and every request path is relative to it. There is no second client, and **no
URL literal anywhere in `lib/` names a destination**:

- `server_settings_store.dart` has two occurrences of `'http://$text'`, which
  prefix a scheme onto what the user entered.
- `lib/l10n/app_en.arb`, `app_fr.arb` and their generated output contain
  `http://jellyfin.local:8096` as the hint text under the address field and as
  ARB placeholder examples. It is shown to the user and never contacted.

`cached_network_image` is a declared dependency and is not yet used by any
screen — zero references.

The scoping matters more than it looks. An earlier draft said "the only URL
literals in `lib/` are two occurrences…", which was written specifically to
avoid overclaiming and still didn't survive its own grep, because the l10n
files were never in it. Claim what is true — nothing names a destination — not
what is merely tidy.

**Still not verified:** that this is what happens on the wire. A packet capture
is outstanding (#19) and is the only thing that can close it, since "no other
host is contacted" is a runtime claim and everything above is a reading of the
source. Note for whoever runs it: capture a **release** build. Debug and release
differ in ways that have already bitten this project once — see § Release
signing and #30.

### Cleartext HTTP needs no exemption, and must not be given one

Garfin talks to a Jellyfin on the user's own LAN, which usually has no
certificate, so the address step resolves a scheme-less entry to `http://`. The
obvious worry is Android's cleartext policy: since API 28 the default is
`cleartextTrafficPermitted="false"`, and `targetSdk` is 36.

**It does not apply. Measured on GrapheneOS / Android 17, 2026-08-04**, with a
control build: `http://192.168.x.x:8096` connects and Quick Connect completes
with **no** `usesCleartextTraffic` and **no** `networkSecurityConfig` anywhere
in the manifest. The policy is enforced by the Java HTTP stacks — `libcore`,
OkHttp, WebView, Cronet — and dio talks over `dart:io` sockets, which never
consult it.

This is recorded because the wrong version is more intuitive than the right one.
A cleartext exemption was added during that same diagnosis, on the assumption it
was the cause, and the control build is what proved it inert. It permits
unencrypted traffic app-wide and buys nothing, so it was removed. There is a
comment in `AndroidManifest.xml` saying so, because the next person hitting an
unreachable server will reach for it first.

None of which changes the underlying exposure, which is about accepting `http://`
addresses at all rather than about any manifest setting:

- Traffic to a server the user gave as `http://` is **unencrypted on their
  network**, including the access token in the `Authorization` header of every
  request. On a home LAN that is the same exposure as using Jellyfin's own web
  UI over HTTP, which is how most self-hosted installs are already reached.
- A user whose server is on HTTPS still gets HTTPS. Nothing downgrades an
  `https://` address.

The alternative — refusing HTTP — would mean Garfin does not work for most of
the people it is for, so this is a deliberate trade rather than an oversight.
The point of the section above is only that the trade costs nothing *extra*: the
app does not have to weaken a platform default to make it.

## Data at rest

The Jellyfin **access token goes in `flutter_secure_storage`**, which wraps
Android Keystore — the Flutter analogue of a hand-rolled Keystore wrapper. It is
**never** written to `shared_preferences`, which is plaintext on disk and is used
only for non-sensitive settings.

The Quick Connect `Secret` is a credential for the duration of the pairing
exchange, not an identifier, and is held in memory only.

Nothing is logged that could carry a credential: no `print` anywhere, and the
logger must never receive tokens, passwords or Quick Connect secrets.

**Verified against the implementation (2026-08-04, #19).** Two ways, because a
static reading and a behavioural one fail differently.

*Statically*, every write in `lib/` was enumerated — **eight `shared_preferences`
call sites across three files**, which is the complete list:

| File | Sites | Stored |
|---|---|---|
| `server_settings_store.dart` | 5 | server URL, user id, user name (and their removal on sign-out) |
| `unlock_settings_store.dart` | 2 | whether the unlock gate is required (bool), the idle timeout (int seconds) |
| `device_identity.dart` | 1 | `device_id` — see below |

`flutter_secure_storage` is written at exactly one site, `token_store.dart`,
under one key, with the access token. The logger is called at seven sites, and
every one interpolates an enum name, a runtime type or a duration — never a
value from a credential-bearing object.

**`device_id` is a persistent random identifier, and belongs in this list.** It
is 128 bits of `Random.secure()`, generated on first launch and stored in
plaintext preferences. It is deliberately *not* a credential — it authenticates
nothing — but "not a credential" and "not worth disclosing in a privacy
posture" are different claims, and this is the one stored value that is a stable
handle for an installation. What it does: Jellyfin keys a session on `DeviceId`,
so a stable one is what stops every launch registering a new device on the
user's own dashboard. Where it goes: the `Authorization` header, to that server
and nowhere else. It is not derived from any hardware identifier, is not shared
between apps. It is **not** reliably per-installation, though: preferences are
covered by Android's default backup (above), so a restore can carry the same id
onto a reinstall or onto a new phone. An earlier version of this paragraph said
it "does not survive an uninstall", which is what preferences do in the absence
of backup and not what happens by default.

An earlier version of this paragraph said "seven call sites, all in
`server_settings_store.dart` and `unlock_settings_store.dart`" and omitted
`device_identity.dart`. The count came from grepping one field name rather than
the API, which is exactly the way an enumeration stops being exhaustive while
still reading as one. The behavioural test was never affected — it sweeps
`prefs.getKeys()`, so it already covered `device_id`.

*Behaviourally*, `test/credential_containment_test.dart` runs both real sign-in
paths — password and Quick Connect, including the tolerated-failure poll that
logs at `fine` — and then sweeps **everything they wrote or said** for three
sentinel credentials:

| | `shared_preferences` | `flutter_secure_storage` | the logger |
|---|---|---|---|
| Access token | absent | **present** (required) | absent |
| Password | absent | absent | absent |
| Quick Connect `Secret` | absent | absent | absent |

The `Secret` therefore never touches disk in either store, which is the claim
`docs/DECISIONS.md` makes about it. The log assertions read records **before**
`redactSecrets` runs: redaction is the backstop, and the property worth holding
is that nothing hands a credential to the logger at all. The crash path is
covered by asserting no model puts a credential in `toString()` — that is what
an uncaught error prints.

Mutation-tested, because a containment test that cannot fail is worse than
none: leaking the token into preferences fires 4 assertions, logging the token
fires 3, logging the `Secret` fires 2.

**Two limits on that, stated rather than glossed:**

- The test asserts what the app *writes*, through the same key-value API the
  real plugins implement, not what lands on disk. Confirming the bytes in
  `shared_prefs/*.xml` and the Keystore-backed store needs a device, and belongs
  with the packet capture below.
- `configureLogging` redacts a record's message and error but passes
  `stackTrace` through untouched. A Dart stack trace is frames, not values, so
  this is not currently a gap — but it is the one part of a log record nothing
  scrubs.

## Device access

Garfin signs in as a Jellyfin **admin** and holds that token on the device. The phone running it
is also the phone handed to a child to watch something — that is the product's normal
interaction, not an edge case, and it is exactly the situation device lock does not cover.

So the app gates itself: biometric, falling back to device PIN/pattern, on cold start and on
resume after an idle timeout (default 2 minutes, configurable in Settings).

On the API 26–27 case: the original wording here said those versions "use device credential
directly" because the platform's `BiometricPrompt` arrived in API 28. That is true of the platform
class but not of the mechanism — `local_auth_android` uses **androidx**'s `BiometricPrompt`, which
has its own compatibility path below 28. What Garfin actually does is ask the device what it can
do rather than what version it is: `biometricOnly: false`, and the plugin resolves that to a
device-credential prompt when there is no usable biometric. On a 26–27 phone with only a PIN the
outcome is the one described; the branch also covers a modern phone whose fingerprint reader is
broken or unenrolled, which a version check would miss.

Limits worth stating plainly:

- This raises the cost of picking up an unlocked phone. It is **not** a defence against someone
  who has the device *and* its PIN.
- A device with no credential set cannot be gated at all. Garfin says so rather than locking the
  user out of their own app.
- The token remains in `flutter_secure_storage` either way; the gate covers the *session*, not
  the storage.
- The app stays mounted behind the gate so a relock does not discard what the user was in the
  middle of. It is covered by an opaque screen, made untouchable, and hidden from screen readers,
  but it is not unmounted.
- **The recents thumbnail is covered: `MainActivity` sets `FLAG_SECURE`.** Measured first, then
  chosen — the reasoning and the rejected alternatives are in `docs/DECISIONS.md`.

  **Measured without the flag (2026-08-05, emulator, Android 16, release build).** The gate locks
  on *resume*, never on the way out, so Android snapshotted the window while Garfin was still
  showing unlocked content and wrote it to `/data/system_ce/0/snapshots/<taskId>.jpg`. The file
  held the full screen, including text typed into the sign-in field. It is worse than a live
  thumbnail: after more than the idle timeout it was **still on disk byte-identical**, while
  reopening the app raised a fresh authentication prompt. The app relocks; the snapshot does not.

  **Measured with the flag, same build and device otherwise unchanged.** The window reports
  `SECURE` in its `dumpsys window` flags. A snapshot file is **still written — it is blank, not
  absent**: 3 distinct colours and 94.7% white, against 6102 distinct colours for the same screen
  before. `screencap` of the foregrounded app comes back 99.8% pure black. Anyone re-checking this
  should test *what is in the file*, because "a snapshot exists" stays true either way.

  **The cost is real and accepted:** the parent cannot screenshot Garfin or mirror it to another
  screen. Weighed against an admin token on a phone handed to children by design, which is what
  ground rule 9 exists for, that trade is deliberate.

**Verified (2026-08-03), in tests:** cold start locks; a wrong attempt keeps the gate up and does
not retry on its own; resume after longer than the timeout relocks and resume inside it does not;
a device reporting no credential is told and let through rather than locked out; the gate is
absent when the setting is off. The lifecycle wiring is driven through the real
`inactive → hidden → paused` sequence, and the gate deliberately ignores `inactive`, because the
unlock prompt itself makes the app inactive.

**Verified on a real device (2026-08-04)** — GrapheneOS, Android 17, arm64, release build:
biometric unlock on cold start works; **backgrounding and resuming past the idle timeout re-locks**
— which is the case this file named as the one that matters, and the one no test here could
reach; and switching the timeout to *Straight away* in Settings → Unlock takes effect. Sign-in
over Quick Connect against a real Jellyfin succeeded on the same build.

**Still not verified:** API 26–27, where no such handset was available, so the device-credential
path is still argued from `local_auth_android`'s source rather than observed. The
no-credential-at-all case likewise — it needs a phone with no PIN, pattern or biometric set.

**A warning from how the above was reached.** The first two release builds could not reach any
server at all, because Flutter's scaffold declares `android.permission.INTERNET` **only in the
debug and profile manifests**, for hot reload. `dev/verify.sh` and CI both build a *debug* APK, so
every gate in this repo passed while the one build type users actually install had no network
access. Assertions on the main manifest now live in `test/android_config_test.dart`. The general
lesson is worth keeping: **a gate that only exercises the debug build cannot make claims about the
release build**, and several claims in this file are of exactly that kind.

## Repository security posture

Branch protection is implemented as **rulesets** (`protect-main`, `protect-release-tags`) rather
than classic branch protection. `protect-main` requires a pull request and two status checks
(`test`, `require-label`); `protect-release-tags` restricts tag creation, deletion and
force-update.

Both carry `Repository admin → Always allow` as a bypass. That is deliberate and load-bearing for
tags — without it no release tag could be created — but it should be read honestly: **a repository
admin can push past either ruleset.** The protection is against mistakes and against non-admin
contributors, not against a compromised admin account. Anyone modelling the threat here should
assume admin access defeats it.

**There is deliberately no `SCORECARD_TOKEN`.** The documented setup asks for a classic PAT with
`repo` scope — read *and write* over every repository its owner can reach — stored in a public
repo's secrets, in order to raise a security score. That trade is not worth making: if it leaked,
the blast radius is the whole organisation, and what it buys is a number. Scorecard runs and
publishes results without it; the Branch-Protection check scores low or unscored as a result.
The SAST check is capped regardless, because CodeQL does not support Dart — which is why
`flutter analyze` is treated as load-bearing static analysis here rather than a formality.

This is a considered decision, not an oversight.

## Release signing

Release builds are signed locally with Garfin's own canonical key; no keystore
exists in CI. `android/app/build.gradle.kts` pins the expected SHA-256
certificate fingerprint and refuses to build if the keystore doesn't match, so a
wrong or rotated key fails loudly instead of shipping an APK that can never be
updated.

The fingerprint is not a secret and will be published here once the first signed
release is cut, so anyone can verify a downloaded APK against it.

**Until #20 lands, a successful `flutter build apk --release` does not mean
"ready to publish."** Two things are not yet true of it:

- **The canonical key does not exist.** With no keystore the build now succeeds
  and produces an *unsigned* APK (#29) — deliberately, so CI and contributors
  can build release at all, which is what #30 needs. An unsigned APK cannot be
  installed as an update and must not be distributed.
- **The fingerprint guard is inert.** `expected` in `build.gradle.kts` is still
  `""`, so a wrong or rotated key only logs a warning rather than failing the
  build. The safeguard is wired up and untriggered, not enforcing.

Release builds became newly *easy* to produce in #29/#30, which is why this is
written down: the thing that used to stop an unpublishable artifact existing was
that the build refused to run at all. A misconfigured keystore — a password set
with no keystore behind it — does still fail loudly, by design.
