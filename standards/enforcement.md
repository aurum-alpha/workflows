# Enforcement ledger

Every rule in every Aurum Alpha standard, the mechanism that enforces it, and
the tier that mechanism actually reaches today. One table, across all standards,
because the question "is this rule real?" has to have one answer and one place
to look it up.

The tiers — **gated**, **audit only**, **review only** — and the law they serve
are defined in [`../STANDARDS.md`](../STANDARDS.md). Read that first; this
document is the register, not the argument.

**Proposed gate** is a commitment, not a wish. A rule landing review-only names
the mechanism it is eventually getting, and promoting it is a change that moves
its row. A rule that genuinely resists automation says so there instead, and
stays review-only honestly.

This ledger claims what a mechanism *can* do, not what every repository has
taken up. Adoption is tracked in each repository's own issue tracker.

## CI standard

Rules from [`ci.md`](ci.md). `tools/check-ci-conformance` runs two ways from one
source — `--repo-root` inside a repo's own CI via `job-ci-conformance.yml`, and
`--fleet` for sweeps — because an audit and a gate that can disagree eventually
will.

| # | Principle | Enforced by | Status |
|---|---|---|---|
| 1 | One source of truth per pin | — | **review only** |
| 2 | Local = CI | — | **review only** |
| 3 | Fail closed | `check-ci-conformance` P3 | gated |
| 4 | Standard runner line | `check-ci-conformance` P4 | gated |
| 5 | Ephemeral-runner assumptions | — | **review only** |
| 6 | Concurrency everywhere | `check-ci-conformance` P6 | gated |
| 7 | BUILD ONCE | — | **review only** |
| 8 | No multi-stage prod Dockerfiles | — | **review only** |
| 9 | Canonical script names | `check-ci-conformance` | gated¹ |
| 10 | Lint output through standard channels | — | **review only** |
| 11 | Registry auth in user-level npmrc | — | **review only** |
| 12 | One way per capability | `check-ci-conformance` | gated¹ |
| 13 | Provenance in every artifact | — | **review only** |
| 14 | A version is a commit, not a tag | — | **review only** |
| 15 | The repo is versioned, not the artifact | — | **review only** |
| 16 | A version exists only where consumed | — | **review only** |
| 17 | Release is promotion, not production | `check-ci-conformance` D4, D5 | gated |
| 18 | One workflow per repo | `check-ci-conformance` P18 | gated |
| — | Standard job DAG (build first) | `check-ci-conformance` D1–D3 | gated |
| — | Every job blocks something | `check-ci-conformance` D6 | gated |
| — | Something runs the image | `check-ci-conformance` D7 | gated |
| — | `needs.<id>` expressions resolve | `check-ci-conformance` D8 | gated |
| — | `workdir` names a shape, not a path | `check-ci-conformance` WD | gated |
| — | Per-stack DAG in multi-codebase repos | — | **review only** |
| — | SHA pinning | `check-ci-conformance` PIN | gated |
| — | `ci-ok` is the only required check | branch protection | gated |
| — | Fleet pnpm version | `check-fleet-versions` | gated¹ |
| — | Caller `with:` matches the shared job's inputs | `check-ci-conformance` IN | gated |
| — | One shared `ci-ok` rollup, not eleven copies | `check-ci-conformance` RU | gated |
| — | Caller permissions cover shared jobs | `check-caller-permissions` | gated¹ |

¹ Gated in every repo whose `ci.yml` calls `job-ci-conformance`, which runs
these three checkers alongside `check-ci-conformance`. Issue #79 tracks the
per-repo rollout; until a repo adopts the job, these rules are unenforced
**in that repo** and nothing there will say so. The row claims what the
mechanism can do, not what every repo has taken up — check the rollout, not
this table, before believing a given repo is covered.

Where a CI rule reads **review only** above, `ci.md` explains why: BUILD ONCE
needs to know what an artifact is, and the per-stack DAG needs to know which
stack a job belongs to. Those resist a checker honestly. The rest are candidates
for the gate.

## Agent standard

Rules from [`../AGENTS.md`](../AGENTS.md). The whole standard lands review only,
per the charter's sequence. The proposed gate is `tools/check-agent-docs`, run
from `job-ci-conformance.yml` alongside the existing checkers, so adopting it is
a checker change rather than a per-repo workflow change.

| # | Rule | Enforced by | Status | Proposed gate |
|---|---|---|---|---|
| A1 | Every repository has an `AGENTS.md` at its root | — | **review only** | `check-agent-docs` — file exists |
| A2 | It answers all six required sections | — | **review only** | `check-agent-docs` — headings present |
| A3 | It references the fleet standard, or vendors it | — | **review only** | `check-agent-docs` — reference or vendored copy present |
| A4 | One source of agent guidance; no parallel per-tool rule trees | — | **review only** | `check-agent-docs` — no unlisted rule directories |
| A5 | Per-tool files are pointers, never second copies | — | **review only** | `check-agent-docs` — pointer files under a line budget |
| A6 | The named work queue is the only work queue | — | **review only** | resists a checker; review question |
| A7 | Gates pass before commit; hooks are never skipped | — | **review only** | partially reachable: `--no-verify` in history is detectable |
| A8 | The human approval gate is honoured | — | **review only** | resists a checker; review question |
| A9 | Docs win over code, and a correction lands in the docs | — | **review only** | resists a checker; review question |

A4 and A5 are the two that most need the gate, because they fail silently and
by accumulation: nothing announces that a second rule tree has appeared, and by
the time anyone notices, the copies disagree and no one knows which one the
agents read.
