<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Contributing

Public issues and PRs live here on GitHub.

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

It mirrors CI exactly: `flutter analyze`, `flutter test`, a debug APK build,
FR translation parity, the hardcoded-string check, the copy rules, the
no-`print` check, the leak scan, gitleaks and REUSE lint. CI runs the same
gates, so a green `verify.sh` means a green PR.

`gitleaks` and `reuse` are skipped locally if not installed — CI still runs
them, so install them if you'd rather not find out on the PR:

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
  not — see the licence table in [`CLAUDE.md`](CLAUDE.md).

## Cutting a release (maintainers)

Garfin uses bare `vX.Y.Z` tags — not the `<short>-vX.Y.Z` prefix the Trobar
client repos use, because Garfin is a standalone product rather than a client.

```bash
# 1. bump pubspec.yaml: version: X.Y.Z+BUILD   (BUILD becomes versionCode)
# 2. commit that through a PR like anything else
# 3. tag and push
git tag vX.Y.Z && git push origin vX.Y.Z
```

The tag triggers `release.yml`, which checks the tag matches `pubspec.yaml`,
runs the same ten gates a PR runs, and opens a **draft** release. It attaches
no artifact, deliberately.

Then build and sign locally — the signing key never exists in CI:

```bash
export GARFIN_KEYSTORE=~/keys/garfin/garfin-release.jks
export GARFIN_KEY_ALIAS=garfin
export GARFIN_KEYSTORE_PASSWORD='<the store password>'

# Clear stale artifacts first — see below, this is not housekeeping.
rm -f build/app/outputs/flutter-apk/*.apk
flutter build apk --release --split-per-abi

# Verify before uploading. Every APK must print the published digest:
for apk in build/app/outputs/flutter-apk/*-release.apk; do
  apksigner verify --print-certs "$apk" | grep 'SHA-256 digest' || echo "NOT SIGNED: $apk"
done
# 2e815848c120b612589a5999a43e0c30555b0f2a1c7d46abae2fc181c1819f95

# The same glob that was verified — never a wider one.
gh release upload vX.Y.Z build/app/outputs/flutter-apk/*-release.apk
gh release edit vX.Y.Z --draft=false
```

**Those exports are the whole of it, and their absence is silent.** The guard in
`android/app/build.gradle.kts` refuses to build with a keystore whose
fingerprint is not the pinned one — but with no password exported there is no
keystore to check, so it is skipped rather than triggered and the build happily
produces an **unsigned** APK. The guard cannot catch its own absence, which is
why the verify step above is part of the procedure rather than a precaution.

**Why the `rm` and why the globs match.** `--split-per-abi` writes
`app-arm64-v8a-release.apk` and two siblings; it does **not** write or overwrite
`app-release.apk`. A plain `flutter build apk --release` — which `dev/verify.sh`
runs, with no keystore, on every pre-push check — leaves exactly that file
sitting there **unsigned**. Uploading `*.apk` would then attach it to the
release beside the three signed ones. Found by running this procedure rather
than reading it: the verify loop printed `NOT SIGNED: …/app-release.apk` against
a directory that looked fine.

So the build starts from an empty output directory, and the glob that is
uploaded is the glob that was verified. Checking one list and shipping another
is how a check stops meaning anything.

Nothing is public until you publish the draft.

**Don't remove `protect-release-tags`' bypass while tidying rulesets.** The
ruleset restricts tag *creation*, and carries `Repository admin → Always allow`
so releases are possible at all. Without it no tag could be pushed, including
the first one — the bypass is what makes the release process work, not an
oversight left over from bring-up.

## Licensing of contributions

Code is **GPL-3.0-or-later**, like the app. Brand artwork under `brand/` is
CC BY-SA 4.0 — see [`BRANDING.md`](BRANDING.md). By opening a PR you agree
your contribution ships under those terms.
