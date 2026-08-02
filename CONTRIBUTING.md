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
FR translation parity, the hardcoded-string check, the leak scan, gitleaks and
REUSE lint. CI runs the same gates, so a green `verify.sh` means a green PR.

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
- **New dependencies need their licence checked and stated in the PR.** MIT,
  BSD and Apache-2.0 are fine. Anything proprietary or GPL-incompatible is
  not — see the licence table in [`CLAUDE.md`](CLAUDE.md).

## Licensing of contributions

Code is **GPL-3.0-or-later**, like the app. Brand artwork under `brand/` is
CC BY-SA 4.0 — see [`BRANDING.md`](BRANDING.md). By opening a PR you agree
your contribution ships under those terms.
