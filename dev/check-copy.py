#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

"""Enforce Garfin's copy rules against the ARB catalogues.

docs/DECISIONS.md § Voice bans two families of wording in user-facing copy:

  - "safe" / "protected" / "secure" — Garfin manages a shortlist and guarantees
    nothing. Claiming otherwise misleads a parent about what the app does.
  - surveillance framing — "monitor", "track", "watch over". The app hands a
    child a film; it does not watch them.

These were style notes that nothing enforced. This makes them a gate.

Scope is deliberately `lib/l10n/*.arb` and nothing else. Every user-facing
string goes through AppLocalizations (dev/verify.sh enforces that separately),
so the catalogues are the complete surface. Grepping the whole tree instead
would drown in false positives: SECURITY.md is *about* security, and
`flutter_secure_storage` is a package name.

Only translatable values are checked — ARB metadata keys (`@foo`) hold
descriptions written for translators, which legitimately discuss the banned
words when explaining the rule.

Each locale carries its own list. A rule written only in English survives
exactly one language, which is the point issue #1 raised about translator
guidance.
"""

import json
import pathlib
import re
import sys

# Whole-word matches unless the entry is a stem (marked by a trailing '-'),
# which matches any inflection: "protég-" covers protégé/protéger/protégeant.
BANNED = {
    "en": [
        "safe", "safety", "secure", "securely", "security",
        "protect", "protects", "protected", "protection",
        "monitor", "monitors", "monitoring",
        "track", "tracks", "tracking",
        "watch over", "watching over",
    ],
    "fr": [
        "sûr", "sûre", "sûres", "sécuris-", "sécurité",
        "protég-", "protection",
        "surveill-",
        "piste-", "traqu-",
    ],
}


def offending_terms(text: str, locale: str) -> list[str]:
    found = []
    lowered = text.lower()
    for term in BANNED.get(locale, []):
        if term.endswith("-"):
            if term[:-1] in lowered:
                found.append(term)
        elif re.search(rf"(?<!\w){re.escape(term)}(?!\w)", lowered):
            found.append(term)
    return found


def main() -> int:
    arb_dir = pathlib.Path("lib/l10n")
    files = sorted(arb_dir.glob("*.arb"))
    if not files:
        print(f"no ARB catalogues found in {arb_dir} — did the l10n setup move?")
        return 1

    violations = 0
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        locale = data.get("@@locale") or path.stem.rsplit("_", 1)[-1]
        if locale not in BANNED:
            print(f"{path}: locale '{locale}' has no banned-term list — add one to {__file__}")
            violations += 1
            continue
        for key, value in data.items():
            # Skip ARB metadata: @@locale, and the @key description blocks.
            if key.startswith("@") or not isinstance(value, str):
                continue
            for term in offending_terms(value, locale):
                print(f"{path}:{key}: banned term {term!r} in: {value!r}")
                violations += 1

    if violations:
        print(
            f"\n{violations} copy-rule violation(s). See docs/DECISIONS.md "
            "§ Voice — Garfin manages a shortlist, it does not make guarantees, "
            "and it does not watch anyone."
        )
        return 1

    checked = ", ".join(p.name for p in files)
    print(f"ok ({checked})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
