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
| 14 | A version is a commit, not a tag | `job-version-gate` + `job-version-release` (partly) | mixed² |
| 15 | The repo is versioned, not the artifact | — | **review only** |
| 16 | A version exists only where consumed | — | **review only** |
| 17 | Release is promotion, not production | `check-ci-conformance` D4, D5 | gated |
| 18 | One workflow per repo | `check-ci-conformance` P18 | gated |
| — | Standard job DAG (build first) | `check-ci-conformance` D1–D3 | gated |
| — | Every job blocks something | `check-ci-conformance` D6 | gated |
| — | Something runs the image | `check-ci-conformance` D7 | gated |
| — | `needs.<id>` expressions resolve | `check-ci-conformance` D8 | gated |
| — | `workdir` names a shape, not a path | `check-ci-conformance` WD | gated |
| — | Every upload declares `retention-days` | `check-ci-conformance` RET | gated³ |
| — | Per-stack DAG in multi-codebase repos | — | **review only** |
| — | SHA pinning | `check-ci-conformance` PIN | gated |
| — | `ci-ok` is the only required check | branch protection | gated |
| — | Branches up to date before merging | branch protection | gated |
| — | The `ci-ok` body is the one the pull request ships | — | **review only** |
| — | Fleet pnpm version | `check-fleet-versions` | gated¹ |
| — | Shared lint config unedited (`.oxlintrc.json`) | `check-eslint-config` | gated¹ |
| — | Caller `with:` matches the shared job's inputs | `check-ci-conformance` IN | gated |
| — | One shared `ci-ok` rollup, not eleven copies | `check-ci-conformance` RU | gated |
| — | The version moves forward, or not at all | `job-version-gate` | gated² |
| — | A release pull request changes only the version file and prose | `job-version-gate` | gated² |
| — | The version file is never deleted | `job-version-gate` | gated² |
| — | Only a version change mints the tag and the GitHub release | `job-version-release` | gated³ |
| — | Only a version change mints a `v<version>` image tag or package version | — | **review only** |
| — | Caller permissions cover shared jobs | `check-caller-permissions` | gated¹ |

¹ Gated in every repo whose `ci.yml` calls `job-ci-conformance`, which runs
these checkers alongside `check-ci-conformance`. Issue #79 tracks the
per-repo rollout; until a repo adopts the job, these rules are unenforced
**in that repo** and nothing there will say so. The row claims what the
mechanism can do, not what every repo has taken up — check the rollout, not
this table, before believing a given repo is covered.

³ Gated in every repo whose `ci.yml` calls `job-version-release`. It covers
the two emissions the job itself produces and nothing else: a `v<version>`
image tag comes from an `enable=` expression in the caller's own
`job-image-publish` stub, and a package version from whatever renders it, so
both stay review questions. `gha-runner-controller` is the reason that
distinction is drawn rather than assumed — its `v<version>` tag was applied on
`is_default_branch` alone, so every merge re-pointed it at new bytes, and no
release job anywhere would have caught it.

² Gated in every repo whose `ci.yml` calls `job-version-gate`, and in no
other. Unlike the ¹ checkers this one is not carried by
`job-ci-conformance` — it needs the pull request's base commit and its own
`pull-requests: write` grant, so it is a job a repo adds deliberately. A repo
with no version file passes it trivially and is right to call it anyway: the
job is what makes adding one later safe.

Row 14 reads **mixed** because the principle is two claims and only one of them
has a mechanism. That the version moves forward, alone, and in a pull request
of its own is gated. That the direction is file → build → tag — that no tag,
release or versioned artifact is minted except by a commit which changed the
file — is enforced in each repo's own `ci.yml`, and nothing checks that a repo
did it. That is the next checker worth writing, and until it exists this row
does not claim it.

³ Presence only. `RET` proves an upload states a retention, never that the
number is the right one — one day is correct for a hand-off between jobs and
ninety is correct for firmware that has no other durable home, and no checker
can tell those apart. Whether a long retention is earned stays a review
question, and so does whether the deliverable should have a release instead.

Where a CI rule reads **review only** above, `ci.md` explains why: BUILD ONCE
needs to know what an artifact is, and the per-stack DAG needs to know which
stack a job belongs to. Those resist a checker honestly. The rest are candidates
for the gate.

## Agent standard

Rules from [`../AGENTS.md`](../AGENTS.md). `tools/check-agent-docs` runs from
`job-ci-conformance.yml` alongside the other caller-side checkers, so adopting
it was a checker change rather than twelve workflow changes.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| A1 | Every repository has an `AGENTS.md` at its root | `check-agent-docs` A1 | gated¹ |
| A2 | It answers all six required sections | `check-agent-docs` A2 | gated¹ |
| A3 | It references the fleet standard, or vendors it | `check-agent-docs` A3 | gated¹ |
| A4 | No rule tree outside the two supported tools | `check-agent-docs` A4 | gated¹ |
| A5 | `CLAUDE.md` opens by importing `AGENTS.md` | `check-agent-docs` A5 | gated¹ |
| A6 | The named work queue is the only work queue | — | **review only** |
| A7 | Gates pass before commit; hooks are never skipped | — | **review only** |
| A8 | The human approval gate is honoured | — | **review only** |
| A9 | Docs win over code, and a correction lands in the docs | — | **review only** |

¹ Gated in repos named in the checker's `ADOPTED` list. Elsewhere the findings
are printed on every run without failing it — the same contract
`check-ci-conformance` gives an `UNCONVERTED` repo, and for the same reason: a
gap someone has looked at and a gap nobody has looked at should not read the
same. Adoption is moving a name into that list.

A4 and A5 are the two that earn the gate. A4 fails by accumulation — a tree
appears, nothing announces it, and the copies drift until nobody knows which one
an agent read. A5 fails by looking correct: `AGENTS.md` prescribed a markdown
link until it was checked against the tool, and Claude Code would have loaded a
file whose whole content told it to read something it then would not read.

A6 to A9 resist a checker honestly. Whether a correction reached the docs, or an
agent stopped at the approval gate, is not a fact on disk.

## Platform standard

Rules from [`platform.md`](platform.md), **proposed (issue #185)** — the
doctrine the per-capability application standards are written under. The
per-capability rules themselves register here as each standard lands; these
rows govern the doctrine.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| PC1 | An opinion is a contract, never a tool | — resists honestly | **review only** |
| PC2 | Standard protocol first, profile second, internal contract last | — resists honestly | **review only** |
| PC3 | An agreed contract carries its artifacts (schemas, corpus) | `check-contract-artifacts` (proposed) | **review only** |
| PC4 | Gates run the corpus at the boundary, never check the implementation | `job-contract-conformance` (proposed) | **review only** |
| PC5 | A package conforms to the spec, never the reverse; no fleet package depends on another | corpus run + manifest check in package CI (proposed) | **review only** |
| PC6 | Contracts evolve additively, versioned, with deprecation windows | `check-contract-evolution` (proposed) | **review only** |

PC1 and PC2 are judgment — what "a tool the lifecycle depends on" or "a
standard that suffices" means is not a fact on disk — so they stay review
questions, stated as such in the document. PC3 through PC6 name real
mechanisms and are commitments: each becomes buildable the moment the first
`contracts/<capability>/` tree lands, and promoting each is its own change
that moves its row.

## Identifiers standard

Rules from [`identifiers.md`](identifiers.md), **proposed (issue #188)** —
the first per-capability standard under the platform contract, and the first
`contracts/` tree, so the PC3–PC6 mechanisms above now have something to run
against.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| IP1 | Internal integer keys never leave the service; addressable rows carry a separate opaque public id | schema-level column check, buildable once the data-layer standard (#147) defines a readable schema; until then the stated review question | **review only** |
| IP2 | Public ids use an admitted format from the table (UUIDv7, nanoid profile, prefixed handle); UUIDv4-in-an-index needs a written defence | `job-contract-conformance` running `contracts/identifiers/corpus.json` (proposed) | **review only** |
| IP3 | Ids are opaque — equality only, no parsing meaning out of them | — resists honestly; review question on consumers | **review only** |
| IP4 | Instants are RFC 3339 UTC `Z` at one pinned fractional precision (default three digits, extendable to six or nine, never fewer); calendar dates are `full-date`; MySQL profile `DATETIME(3)` | corpus validity + canonical cases (proposed, same job) | **review only** |
| IP5 | Money is integer minor units + ISO 4217 code, together; floats never | corpus validity cases (proposed, same job) | **review only** |

IP2, IP4 and IP5 are exactly what a corpus can hold: their gate is the
platform contract's own `job-contract-conformance`, and the corpus already
exists, so promoting them is building the job, not writing the cases. IP1's
mechanical gate is named but blocked on #147. IP3 resists a checker — what a
consumer does with an id after receiving it is not a fact on disk — and the
document states the review question instead.
