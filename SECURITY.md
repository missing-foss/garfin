<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Security

This documents Garfin's privacy posture and its at-rest protection of the Jellyfin
access token.

**Status: partially verified.** Garfin is pre-alpha and has no network code yet.
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

**Not yet verified:** the runtime half. A `tcpdump` capture against an idle
install, confirming no unexpected outbound connections, is **outstanding** and
must be done once there is a running app to capture. Until then this section
documents an audited dependency tree, not observed network silence.

Note for contributors: Flutter's *tooling* reports usage analytics to Google by
default. That is the `flutter` command on a developer's machine, not anything
shipped in the APK, and the two must not be conflated. Disable it locally with
`flutter --disable-analytics`.

## What Garfin talks to

**Exactly one host: the Jellyfin server the user signs in to.** There is no
Garfin backend, no account system, and no third-party service. Server URL,
credentials and library data never leave the user's own device and their own
server.

**Verified (2026-08-02):** trivially, by absence — there is no HTTP call in the
codebase yet. This claim needs re-verifying, by packet capture, once the
Jellyfin client lands.

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

**Verified (2026-08-02):** `flutter_secure_storage` is a declared dependency and
`shared_preferences` is present for settings only.

**Not yet verified:** there is no storage code at all yet, so the separation
above is a design commitment rather than an audited fact. It needs confirming
against the real implementation — including that no token reaches
`shared_preferences`, a logger, or a crash path — before release.

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
- **The recents thumbnail is not covered, and screenshots are not restricted.** `FLAG_SECURE` is
  not set. The gate locks on *resume*, never on the way out, so Android captures its task snapshot
  while Garfin is still showing unlocked content — someone who is handed the phone can read the
  last screen off the task switcher without ever meeting the lock screen. Today that screen is a
  placeholder, but the Kids screen, the library grid and per-child policy are the screens this
  gate exists for, and they arrive at steps 3–5. **Decide this before they do.** Setting
  `FLAG_SECURE` is the usual answer and costs the parent their own screenshots and casting;
  covering on `paused` is racy against when the snapshot is taken. Argued from documented Android
  behaviour, not measured — there is no device here to measure it on.

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
