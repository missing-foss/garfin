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
resume after an idle timeout (default 2 minutes, configurable in Settings). Below API 28 there is
no `BiometricPrompt`, so 26–27 use device credential directly.

Limits worth stating plainly:

- This raises the cost of picking up an unlocked phone. It is **not** a defence against someone
  who has the device *and* its PIN.
- A device with no credential set cannot be gated at all. Garfin says so rather than locking the
  user out of their own app.
- The token remains in `flutter_secure_storage` either way; the gate protects the *session*, not
  the storage.

**Not yet verified:** none of this is implemented. It is a design commitment recorded here, and
it needs testing against a real device — including that backgrounding actually triggers re-auth,
which is the case that matters.

## Repository security posture

Branch protection is implemented as **rulesets** (`protect-main`, `protect-release-tags`), with
required status checks and no bypass, rather than classic branch protection.

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
