<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Contributing

Public issues and PRs live here on GitHub.

Pull requests opened here are reviewed and then shipped by the maintainers
rather than merged in place, so your commits may arrive under a release
commit rather than your own. Your pull request is closed with a note
crediting you when the change lands. Keep changes focused — a small pull
request with a clear rationale is much easier to take than a large one.

Security issues: not in the public tracker — missing_foss@etik.com. See
[`SECURITY.md`](SECURITY.md).

## Before a large PR

Open an issue first. [`docs/DECISIONS.md`](docs/DECISIONS.md) records the
alternatives already considered and rejected, with reasons — reading it saves
proposing something that was ruled out for a reason that still holds.

## Before you push

```bash
dev/verify.sh
```

It runs fourteen steps: `flutter analyze`, `flutter test`, debug **and**
release APK builds, FR translation parity, the hardcoded-string check, the copy
rules, the no-`print` check, the leak scan, gitleaks, REUSE lint, the
vendored-guard version check, a tracker-reference check and a toolchain-pin
check.

**There are two CIs and they are not the same gate.** A repository carrying
`.forgejo/workflows/` is served by that directory alone, so the development
forge runs `.forgejo/workflows/ci.yml` and the published mirror runs
`.github/workflows/ci.yml`. Both run analyze, the tests, both APK builds, FR
parity, the copy rules, the no-`print` check, gitleaks and REUSE. The forge
**also** runs the hardcoded-string check, the tracker-reference check and the
vendored-guard check; the mirror runs none of those three.

Neither runs the leak scan — it needs a pattern list that exists only on a
development machine, and CI says so rather than passing silently — and neither
runs the toolchain-pin check. So a green `verify.sh` covers every gate either
CI will run, plus **two** things neither does.

It is not a superset, though, and the difference is deliberate. CI additionally
confirms the runner's toolchain is the pinned one, which a local run cannot do,
and it **fails a release APK that is signed** — the signing key must never exist
in CI. `verify.sh` reports the artifact's signing state without failing on it,
because a maintainer holding the keystore should get a signed build and must not
be told that is wrong.

The two of these that come from outside the repo behave **differently** when
they are missing, and the difference is deliberate. `gitleaks` is skipped with
a note — a local run would not have matched what CI matches anyway. `reuse` is
not skipped: it **fails** the run, because an unlicensed file is something a
local run can and should catch before it reaches a PR. Install both:

```bash
pipx install reuse
# gitleaks: https://github.com/gitleaks/gitleaks/releases
```

## What the gates expect

- **Every file needs SPDX licensing.** An inline header on source, or an entry
 in [`REUSE.toml`](REUSE.toml) for binaries and generated files. A new file
 without either fails `reuse lint`.
- **No hardcoded UI strings.** Text shown to a user goes through
 `AppLocalizations`, with a key in `lib/l10n/app_en.arb` *and* its French
 counterpart in `app_fr.arb`. A missing translation fails the build rather
  than shipping English inside a French UI. Note the check is a line-based
 grep, so a `Text()` call split across lines can slip past it — don't rely on
  it to catch what review should.
- **Copy style** is plain and warm, never cute about permissions. Never
  "safe", "protected" or "secure" — Garfin manages a shortlist and guarantees
 nothing. Never surveillance framing. See `docs/DECISIONS.md` § Voice.
 **This is enforced**, per-locale, by `dev/check-copy.py`: adding a new
  language means adding its banned-term list there, or the check fails loudly
  rather than silently passing untested copy.
- **No `print`.** Use the logger, and never log tokens, passwords or Quick
  Connect secrets.
- **New dependencies need their licence checked and stated in the PR.** MIT,
  BSD and Apache-2.0 are fine. Anything proprietary or GPL-incompatible is
 not — see the licence table in [`docs/ENGINEERING.md`](docs/ENGINEERING.md).

## Cutting a release (maintainers)

Releases are tagged `vX.Y.Z`.

```bash
# 1. bump pubspec.yaml: version: X.Y.Z+BUILD   (BUILD becomes versionCode)
# 2. commit that through a PR like anything else
# 3. tag and push
git tag vX.Y.Z && git push origin vX.Y.Z
```

Tagging on the published mirror triggers `release.yml`, which checks the tag
matches `pubspec.yaml`, calls the mirror's own `ci.yml` so a release runs the
same ten gates a mirror pull request runs, and opens a **draft** release. It
attaches no artifact, deliberately.

The development forge does not run it, by the same rule that gives the two CIs
different contents: `release.yml` lives in `.github/workflows/`, so the release
path exists on the mirror and nowhere else.

Then build and sign locally — the signing key never exists in CI:

```bash
flutter build apk --release --split-per-abi
gh release upload vX.Y.Z build/app/outputs/flutter-apk/*.apk
gh release edit vX.Y.Z --draft=false
```

The guard in `android/app/build.gradle.kts` verifies the keystore fingerprint
during that build and refuses to proceed if it doesn't match the pinned value.
Nothing is public until you publish the draft.

## Licensing of contributions

Code is **GPL-3.0-or-later**, like the app. Brand artwork under `brand/` is
CC BY-SA 4.0 — see [`BRANDING.md`](BRANDING.md). By opening a PR you agree
your contribution ships under those terms.
