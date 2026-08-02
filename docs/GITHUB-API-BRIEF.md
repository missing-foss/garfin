<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# GitHub API brief

Paste this as context before any work that touches GitHub in the `missing-foss` org — reviewing a
PR, triaging issues, checking CI, pushing commits.

---

You are working against GitHub in the **`missing-foss`** org. This org repeatedly trips GitHub's
**secondary** rate limits ("too many requests, try again in one minute"). Understand what that
means before you make a single call:

**This is not quota exhaustion.** The `core` bucket sits near-empty when it happens. The limiter is
reacting to the *shape* of the calls — concurrency and per-minute burst — not to total volume. You
can make thousands of the right call and be fine, or a dozen of the wrong one and be blocked.
Measured 2026-08-02.

## The buckets are wildly uneven

| bucket | limit |
|---|---|
| `core` (`repos/...`) | 5000 / **hour** |
| `graphql` | 5000 / hour (points — one fat query costs many) |
| **`search`** (`search/issues`, `search/code`) | **30 / minute** |
| **`code_search`** | **10 / minute** |

On top of those, GitHub's documented secondary limits: max **100 concurrent requests**, **900
points/min** per REST endpoint (reads = 1 point, writes = 5), **80 content-creating requests/min**
and **500/hour**, and 90s CPU per 60s real time.

Note the ratio: one `search/issues` call costs 1 of 30-per-minute; one `repos/...` call costs 1 of
5000-per-hour. Answering the same question the second way is roughly **167× cheaper**.

## Rules, highest impact first

**1. Never use a search endpoint for a lookup that isn't a search.** Finding an issue or PR by
number, label, or state is a lookup, not a search.

    # wrong — burns the 30/min search bucket
    gh api search/issues?q=repo:missing-foss/garfin+label:bug+state:open
    # right — 1 of 5000/hour
    gh api repos/missing-foss/garfin/issues?state=all&labels=bug

**2. Never use `search_code` / `search/code`.** It is a **10/minute** bucket *and* it is
index-lagged on these repos — it returns 0 results for code that demonstrably exists, so you will
draw a wrong conclusion *and* pay for it. Use `grep` or `rg` on the local clone: free, immediate,
and correct.

**3. Do all code reading in the local clone, never over the API.** Diffs, file contents, history,
blame:

    git fetch origin pull/N/head:prN
    git diff main...prN
    git show prN:path/to/file

**Git-over-HTTPS does not touch the REST buckets at all.** For the same reason, commit with
`git push` rather than the Contents API — a push is one git operation, not N content-creating API
calls against the 80/min cap.

**4. Always filter server-side with `--jq`.** Measured on one real query: **63,132 bytes raw → 943
bytes** filtered. That is 67× less API payload and 67× less of your context spent on noise.

    gh api repos/missing-foss/garfin/issues --jq '.[] | {number, title, state}'

**5. Never issue GitHub calls in parallel.** The secondary limiter keys on concurrency and
per-minute burst, so a fan-out is the single most reliable way to get blocked. Serialize them, and
leave ~1s between writes. Parallelism is correct for local work and wrong against one API host.

**6. Don't tight-poll CI after a push.** Use intervals of **≥30s**, and make one call for the whole
commit rather than one per job:

    gh api repos/missing-foss/garfin/commits/$SHA/check-runs --jq '.check_runs[] | {name, status, conclusion}'

## When you do get limited

In order of precedence:

1. Honour `retry-after` if the response carries it.
2. Else, if `x-ratelimit-remaining` is 0, wait for `x-ratelimit-reset`.
3. Else wait at least **60s**, then back off exponentially, and give up after N tries.

**Do not retry through a secondary limit.** GitHub's documentation states that continuing to make
requests while limited "may result in the banning of your integration." A blocked task is
recoverable; a banned integration is not.

## Decide at the call site

| You want | Do this | Not this |
|---|---|---|
| A PR's diff or files | `git fetch origin pull/N/head` + `git diff` | `pull_request_read`, Contents API |
| To find a symbol or string in the code | `rg` in the local clone | `search_code` |
| Issues by label, state, or number | `gh api repos/.../issues --jq` | `search/issues` |
| To commit changes | `git push` | Contents API |
| CI status after a push | one `check-runs` call, ≥30s apart | per-job polling in a loop |
| Many related facts at once | serialized `gh api` calls with `--jq` | parallel fan-out |

## Caveat

`minimal_output` is advertised in the GitHub MCP server's instruction text but does **not** exist
on the actual tool schemas — `search_issues`, `issue_read`, `pull_request_read`, `list_issues`,
`list_pull_requests`. Do not try to pass it; use `--jq` filtering instead.
