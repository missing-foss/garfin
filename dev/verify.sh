#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Pre-push verification gate for garfin. Run from the repo root:
#   dev/verify.sh
# Needs flutter on PATH.
#
# The gate that blocks a merge is .forgejo/workflows/ci.yml. TWO checks run
# ONLY here: the leak scan, which needs a pattern list supplied through the
# environment and deliberately absent from the repository, so a hosted runner
# has nothing to give it; and "Toolchain pin agrees with CI", which compares
# .tool-versions against the workflow files. The forge gate has a toolchain
# step of its own, but it is a different check -- it confirms the flutter it
# is running matches the pin, not that the pinned versions agree with each
# other.
#
# One check runs in both places but NOT identically: the hardcoded-UI-string
# check. The forge gate allows Text() literals naming a language in a picker;
# this script has no such allowlist and is therefore stricter. Nothing in lib/
# triggers the difference today. If you add one, this goes red while the gate
# stays green.
#
# .github/workflows/ci.yml is the mirror's inherited workflow, not this
# repository's gate: no tracker-reference check, no vendored-guard check, no
# hardcoded-string check, no toolchain confirmation. Do not read it as "CI"
# when deciding what a change has been checked by.
#
# Everything else here runs in the forge gate too, with the same invocation.
#
# This paragraph previously named the mirror's workflow as "CI" and claimed
# four local-only checks. Three of those had moved into the forge gate and the
# sentence did not move with them -- the same drift the tracker-reference and
# vendored-guard steps below exist to catch, in the file that describes them.
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

step "build release APK (#30)"
# Not redundant with the debug build. INTERNET is declared only in Flutter's
# debug/profile manifests, so a release build once shipped with no network
# access while every gate was green. Debug and release also differ in manifest
# merging, signing, minification and icon tree-shaking.
if flutter build apk --release; then
  apk=build/app/outputs/flutter-apk/app-release.apk
  aapt2=$(ls "${ANDROID_HOME:-$HOME/sdk/android}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
  if [ -z "$apk" ] || [ ! -f "$apk" ]; then
    echo "RELEASE: no APK produced"; fail=1
  elif [ -z "$aapt2" ]; then
    # Unlike CI, a contributor may genuinely not have build-tools on PATH.
    echo "SKIP (aapt2 not found) — CI still checks the APK's permissions"
  # No pipe. This script sets `pipefail`, and `grep -q` exits at its first
  # match, so whatever is still writing takes SIGPIPE and the pipeline reports
  # failure on a *successful* match. Capturing first does NOT fix that — it
  # only raises the threshold to the pipe buffer, measured at ~64 KB. It is
  # safe here today solely because aapt2's output is ~4 KB, which is a property
  # of the tool rather than of this code. A bash `==` test has no subprocess
  # and so nothing to break. See the longer note in .github/workflows/ci.yml.
  elif [[ $("$aapt2" dump badging "$apk" 2>/dev/null) \
          == *"uses-permission: name='android.permission.INTERNET'"* ]]; then
    echo ok
  else
    echo "RELEASE: the APK declares no INTERNET permission"; fail=1
  fi
  # Neither signed nor unsigned is a failure here, and that is exactly why it
  # has to be SAID. "Must be unsigned" is a property of CI, where the key must
  # never exist; a maintainer with the real keystore should get a signed APK
  # and must not be told that is wrong. But a release build with no signing
  # environment in the shell succeeds, exits 0, and produces an APK whose name
  # says nothing either way -- Flutter copies the artifact onward and drops
  # Gradle's `-unsigned` suffix -- which is how an unsigned APK once reached a
  # review. So report the artifact's real state.
  #
  # Assert on the ARTIFACT, never on the build's exit code. Same habit as the
  # INTERNET check above: the build exiting 0 is what was already believed and
  # was already wrong.
  if [ -f "$apk" ]; then
    apksigner=$(ls "${ANDROID_HOME:-$HOME/sdk/android}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
    if [ -z "$apksigner" ]; then
      echo "SIGNING: unknown (apksigner not found) — the forge gate checks this too"
    elif "$apksigner" verify "$apk" >/dev/null 2>&1; then
      # A pipe is safe here where it is not above: `sed -n s///p` reads its
      # input to EOF, so nothing takes SIGPIPE and `pipefail` has nothing to
      # report. The check above uses `grep -q`, which exits at first match.
      fp=$("$apksigner" verify --print-certs "$apk" 2>/dev/null \
           | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
      echo "SIGNING: signed, sha256 ${fp:-unknown}"
    else
      echo "SIGNING: UNSIGNED — installable nowhere, publishable nowhere"
      # Opt-in strictness, so "this one is meant to ship" can be stated once
      # and enforced without breaking CI or a contributor, both of which build
      # release unsigned on purpose.
      if [ -n "${GARFIN_REQUIRE_SIGNED:-}" ]; then
        echo "RELEASE: GARFIN_REQUIRE_SIGNED is set but the APK is unsigned"; fail=1
      fi
    fi
  fi
else
  echo "RELEASE: build failed"; fail=1
fi

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
# regardless of locale.
#
# There is no allowlist here, and there never was. This comment used to say
# "adjust the allowlist below", pointing at something absent -- while the forge
# gate carried a real one this script did not. Two call sites, both green,
# checking different things: the gate had the exemption and no comment, this
# had the comment and no exemption. The gate's is gone; so is the sentence.
#
# Must stay identical to .forgejo/workflows/ci.yml's copy. When a language
# picker arrives this goes red: do not reinstate a literal allowlist -- exact
# match permits those strings anywhere in lib/, not just the picker, and covers
# exactly two languages until the third silently isn't. Prefer a structural
# exemption, decided with the picker in front of you.
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

step "leak scan (strings that must never ship)"
# #404: `grep -f` on a missing terms file exits 2 (swallowed by 2>/dev/null
# below), the `if` is then false, and this printed "ok" having scanned
# nothing — fail-open, not fail-safe. `-s` catches missing AND empty in one
# test, skipping the grep entirely so this doesn't ALSO scan (and pass)
# against a pattern file with nothing in it.
# The pattern list is NOT in this repository. A denylist that ships the terms
# it exists to exclude publishes exactly what it is protecting -- which is what
# used to happen here. Supply one via LEAK_PATTERNS to run it; with no
# list configured this reports that it did not run rather than passing.
#
# STRIP FIRST. A `-f` list has no comment or blank-line syntax: every line in
# the file is a pattern. The list is hand-maintained prose-and-groups, so it
# carries both, and handing it over unmodified made a clean tree report tens of
# thousands of hits — a gate that is red on every commit regardless of content
# gets routed around exactly like one that never runs. Strip anything not
# intended as a pattern before grep sees it. This is a property of the `-f`
# interface, not of any particular grep.
#
# An empty result after stripping is a malformed list, not a clean scan: the
# #404 lesson one level up. That fix caught a missing or empty file; this
# catches one that is non-empty and still has nothing usable in it.
#
# The count is printed on success because a list that silently shrinks to three
# patterns still reports "ok" — "ok (3 patterns)" does not.
#
# THE FILTERED LIST NEVER LANDS ON DISK. It used to be written to `mktemp` and
# removed on EXIT; that is still a copy of a file whose one handling rule is
# that it is never copied, and EXIT does not run on SIGKILL, on a full disk, or
# when a CI container is torn down mid-step. Process substitution removes the
# question instead of managing it.
#
# NO `xargs` HERE, AND THAT IS THE WHOLE POINT. A process substitution is a
# pipe and a pipe can be read once. `xargs` may invoke grep several times on a
# long file list: the first invocation drains the patterns and every later one
# scans against an empty set, matches nothing and says nothing. That is a
# silent under-scan with an unchanged exit status -- strictly worse than the
# temp file it replaced. One grep invocation, file list as an argv array, so
# the pipe is read exactly once. `--` guards a path beginning with `-`, and the
# array (not word-splitting) guards a path containing spaces.
#
# The count re-reads the list rather than measuring a file. Two cheap reads,
# nothing written. If the argument list ever exceeded ARG_MAX this dies with
# E2BIG -- loudly, which is the right direction.
#
# BRANCH ON THE STATUS, NOT ON TRUTHINESS. grep exits 0 found, 1 none, 2 ERROR,
# and `if grep ...` reads 1 and 2 alike. A tracked file missing from the working
# tree makes grep exit 2 -- so the old form PRINTED a real match and then
# reported "ok", because the run as a whole had errored. That is the #404
# fail-open again, in the statement rewritten to fix a different one, and it is
# the reason grep's stderr is no longer discarded: the message says which file.
#
# An empty file list is its own trap: grep with no file operands reads STDIN and
# blocks, so an empty tracked tree would hang rather than fail. Guarded.
if [ -n "${LEAK_PATTERNS:-}" ] && [ -s "${LEAK_PATTERNS}" ]; then
  leak_n=$(grep -cvE '^[[:space:]]*(#|$)' "${LEAK_PATTERNS}")
  if [ "$leak_n" -eq 0 ]; then
    echo "FAIL: pattern list has no usable patterns (comments and blanks only)"; fail=1
  else
    mapfile -t leak_files < <(git ls-files)
    if [ "${#leak_files[@]}" -eq 0 ]; then
      echo "FAIL: no tracked files to scan -- refusing to report a clean scan of nothing"; fail=1
    else
      grep -InE -f <(grep -vE '^[[:space:]]*(#|$)' "${LEAK_PATTERNS}") -- "${leak_files[@]}"
      leak_rc=$?
      case "$leak_rc" in
        0) echo "LEAK: forbidden term(s) above"; fail=1 ;;
        1) echo "ok ($leak_n patterns)" ;;
        *) echo "FAIL: leak scan errored (grep exit $leak_rc); a scan that could not run is not a clean scan"; fail=1 ;;
      esac
    fi
  fi
else
  echo "SKIP (no LEAK_PATTERNS configured)"
fi

step "gitleaks (secrets)"
# TWO scans, and the second is the one that matches CI.
#
# `gitleaks git` walks history. Locally that is a full clone, so it sees each
# commit's diff. In CI `actions/checkout` fetches depth 1, so the same command
# sees a single commit containing the whole tree — meaning CI effectively scans
# every file while a local run scans only what changed. That divergence let a
# secret-shaped test fixture reach CI green locally and red there (#34).
#
# `gitleaks dir` scans the working tree, which reproduces CI's coverage. It also
# walks build/ when one exists, which is a bonus rather than a cost: a
# credential baked into an APK is exactly the thing worth catching.
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --no-banner . && gitleaks dir --no-banner . && echo ok || fail=1
else
  echo "SKIP (gitleaks not installed) — CI still runs it, and see above: a"
  echo "     local run would not have matched it anyway. Install it:"
  echo "     https://github.com/gitleaks/gitleaks/releases"
fi

step "REUSE (per-file SPDX licensing)"
# Every file must declare copyright + license (inline SPDX header, or via
# REUSE.toml for binaries / generated / Flutter-scaffolding). A new unlicensed
# file then fails here rather than shipping unattributed.
if command -v reuse >/dev/null 2>&1; then
  if reuse lint >/dev/null 2>&1; then echo ok; else reuse lint | tail -20; fail=1; fi
else
  echo "FAIL: reuse is not installed (pipx install reuse) — the licensing check cannot run"; fail=1
fi

step "vendored guards match their declared versions"
# Runs BEFORE the guard it covers: a drifted guard's verdict is not worth
# reading until you know it is the guard you think it is. Prints what it
# checked rather than a bare ok -- a silent pass and a step that never ran are
# the same text.
dev/guards/verify-vendored.sh || fail=1

step "Tracker references in published prose"
# Public docs must stand alone: an issue number that outlives the tracker it
# points at is worse than no citation. Excludes fenced blocks, inline code, hex
# colours and heading anchors -- a guard that false-positives gets switched
# off, and then protects nothing.
#
# NO PATH ARGUMENTS. The guard defaults to the whole tree, minus vendored and
# generated directories. It used to be handed four paths here, and prose added
# outside them was never checked -- THIRD_PARTY_NOTICES.md sat unscanned while
# carrying four citations. If you add an argument list back, the forge workflow
# has to change with it or the two gates check different things.
if python3 dev/guards/check-tracker-refs.py; then
  echo ok
else
  fail=1
fi

echo
step "Toolchain pin agrees with CI"
# .tool-versions is the source of truth; CI must not drift from it. Deliberately
# a consistency check rather than making CI read the exact string: setup-java's
# acceptance of a "17.0.20+8" style version is not something this repo can test,
# and a check that both agree catches the drift either way.
if [ -f .tool-versions ]; then
  tv_java=$(awk '/^java /{print $2}' .tool-versions | sed 's/^temurin-//; s/\..*//')
  ci_java=$(grep -hoE 'java-version: *"?[0-9]+' .github/workflows/*.yml 2>/dev/null | grep -oE '[0-9]+' | sort -u)
  if [ -n "$tv_java" ] && [ -n "$ci_java" ] && [ "$tv_java" != "$ci_java" ]; then
    echo "PIN DRIFT: .tool-versions says java $tv_java, CI says $ci_java"; fail=1
  else
    echo ok
  fi
else
  echo "SKIP (no .tool-versions in this repo)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fail"
