#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Pre-push verification gate for garfin. Run from the repo root:
#   dev/verify.sh
# CI (.github/workflows/ci.yml) runs the same checks. Needs flutter on PATH.
set -uo pipefail
fail=0
step() { echo; echo "== $1 =="; }

step "flutter analyze"
flutter analyze && echo ok || fail=1

step "flutter test"
flutter test && echo ok || fail=1

step "build debug APK"
# See ci.yml's own comment on why this is here (not in trobar-desktop's own
# verify.sh) — analyze+test alone won't catch every real Android compile
# break. Delete if this stops being a mobile target.
flutter build apk --debug && echo ok || fail=1

step "translations (FR ARB complete, #32)"
# gen-l10n validates placeholder/ICU parity (it errors on a mismatch) and writes
# every untranslated key to the untranslated-messages-file set in l10n.yaml. The
# file is "{}" when complete and "{\"fr\": [...]}" when a key lacks its FR value,
# so a "[" means a gap — a new string then fails the build instead of shipping an
# English fallback in French. Delete this step (and l10n.yaml) if not translating.
if flutter gen-l10n; then
  if grep -q "\[" lib/l10n/untranslated.txt 2>/dev/null; then
    echo "UNTRANSLATED FR messages:"; cat lib/l10n/untranslated.txt; fail=1
  else
    echo ok
  fi
else
  echo "flutter gen-l10n failed (placeholder/ICU mismatch?)"; fail=1
fi

step "no hardcoded UI strings (must go through AppLocalizations)"
# A Text() built from a string literal bypasses l10n and renders in English
# regardless of locale. Adjust the allowlist below for your own legitimate
# exceptions (e.g. native language names in a language picker).
if grep -rnE "Text\(\s*(const\s+)?['\"]" lib/ --include='*.dart' \
     | grep -v 'l10n/gen'; then
  echo "HARDCODED: localize the Text() string(s) above via AppLocalizations"; fail=1
else
  echo "ok"
fi

step "copy rules (docs/DECISIONS.md § Voice)"
# Bans "safe"/"protected"/"secure" and surveillance framing in user-facing copy,
# in both catalogues. Stated-but-unenforced rules erode; this makes it a gate.
python3 dev/check-copy.py && echo ok || fail=1

step "no print() in app code"
# flutter_lints' avoid_print covers this today, but a lint rule can be turned
# off in analysis_options.yaml and this grep survives that. Excludes generated
# l10n output, which we don't author.
if grep -rnE '(^|[^.\w])print\s*\(' lib/ --include='*.dart' | grep -v 'lib/l10n/gen'; then
  echo "PRINT: use the logger — and never log tokens, passwords or Quick Connect secrets"; fail=1
else
  echo "ok"
fi

step "leak scan (household infra must never ship)"
# #404: `grep -f` on a missing terms file exits 2 (swallowed by 2>/dev/null
# below), the `if` is then false, and this printed "ok" having scanned
# nothing — fail-open, not fail-safe. `-s` catches missing AND empty in one
# test, skipping the grep entirely so this doesn't ALSO scan (and pass)
# against a pattern file with nothing in it.
if [ ! -s dev/forbidden-terms.txt ]; then
  echo "LEAK: dev/forbidden-terms.txt missing or empty — scan did not run"; fail=1
elif git ls-files | xargs grep -InE -f dev/forbidden-terms.txt 2>/dev/null \
     | grep -viE "\.lock$|^dev/forbidden-terms\.txt:"; then
  echo "LEAK: forbidden term(s) above"; fail=1
else
  echo "ok"
fi

step "gitleaks (secrets)"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --no-banner . && echo ok || fail=1
else
  echo "SKIP (gitleaks not installed) — CI still runs it"
fi

step "REUSE (per-file SPDX licensing)"
# Every file must declare copyright + license (inline SPDX header, or via
# REUSE.toml for binaries / generated / Flutter-scaffolding). A new unlicensed
# file then fails here rather than shipping unattributed.
if command -v reuse >/dev/null 2>&1; then
  if reuse lint >/dev/null 2>&1; then echo ok; else reuse lint | tail -20; fail=1; fi
else
  echo "SKIP (reuse not installed — pipx install reuse) — CI still runs it"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fail"
