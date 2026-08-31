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
these checkers alongside `check-ci-conformance`. The per-repo rollout is
tracked in this repository's issues; until a repo adopts the job, these rules are unenforced
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

Rules from [`platform.md`](platform.md) — the
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

Rules from [`identifiers.md`](identifiers.md) —
the first per-capability standard under the platform contract, and the first
`contracts/` tree, so the PC3–PC6 mechanisms above now have something to run
against.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| IP1 | Internal integer keys never leave the service; addressable rows carry a separate opaque public id | schema-level column check, buildable once the [data-layer standard](platform.md#the-capability-roster) defines a readable schema; until then the stated review question | **review only** |
| IP2 | Public ids use an admitted format from the table (UUIDv7, nanoid profile, prefixed handle); UUIDv4-in-an-index needs a written defence | `job-contract-conformance` running `contracts/identifiers/corpus.json` (proposed) | **review only** |
| IP3 | Ids are opaque — equality only, no parsing meaning out of them | — resists honestly; review question on consumers | **review only** |
| IP4 | Instants are RFC 3339 UTC `Z` at one pinned fractional precision (default three digits, extendable to six or nine, never fewer); calendar dates are `full-date`; MySQL profile `DATETIME(3)` | corpus validity + canonical cases (proposed, same job) | **review only** |
| IP5 | Money is integer minor units + ISO 4217 code, together; floats never | corpus validity cases (proposed, same job) | **review only** |

IP2, IP4 and IP5 are exactly what a corpus can hold: their gate is the
platform contract's own `job-contract-conformance`, and the corpus already
exists, so promoting them is building the job, not writing the cases. IP1's
mechanical gate is named but waits on the [data-layer
standard](platform.md#the-capability-roster). IP3 resists a checker — what a
consumer does with an id after receiving it is not a fact on disk — and the
document states the review question instead.

## Observability standard

Rules from [`observability.md`](observability.md) —
the propagation and telemetry-transport profile the service baseline's log
fields and the async envelope both build on.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| OC1 | W3C trace context on every boundary — HTTP calls and the job envelope; continue valid inbound context, start fresh otherwise; no parallel correlation scheme | propagation corpus under `job-contract-conformance` (proposed) | **review only** |
| OC2 | One id vocabulary: `trace_id`, `span_id`, `request_id`, `tenant_id` — same snake_case names and formats in every log line and audit event, every language | corpus validity cases (same job, proposed) | **review only** |
| OC3 | Traces and metrics leave as OTLP to an endpoint from the OTel env vars; no vendor exporter in application code; logs stay stdout per the service baseline | env presence checkable; wire half proven where the corpus runs live; vendor-exporter half a review question | **review only** |
| OC4 | The context block is present on lines and events emitted within request context | startup-line assertion in `job-image-starts` (proposed) + propagation corpus | **review only** |

OC1, OC2 and OC4 are exactly corpus-shaped: inject a `traceparent`, read
emitted lines, black-box in any language — the same `job-contract-conformance`
the identifiers rows wait on, so building that job promotes seven rows at
once. OC3 splits honestly: config presence is a fact on disk, the wire
protocol is proven live, and "no vendor exporter in app code" is judgment and
stays a review question.

## Charter: document conventions

Rules from [`../STANDARDS.md`](../STANDARDS.md)'s "How these documents are
written" and "The foundation: twelve-factor".

| # | Rule | Enforced by | Status |
|---|---|---|---|
| D1 | No document carries a status header; a merged document is binding | `check-standards-docs` (proposed): no `Status:` line in a standard | **review only** |
| D2 | Documents reference documents by working relative link — never a tracker number, never a bare name; a standard not yet written is linked at its roster row | `check-standards-docs` (proposed): no issue or pull-request reference in a standard's prose, and every relative link resolves | **review only** |
| D3 | A rule restating a twelve-factor factor cites it; a rule departing from one says so, in the rule, with the reason | — resists honestly: whether a citation is apt, or a departure argued, is judgment | **review only** |

D1 and D2 are the cheapest gates in this ledger — a grep each, no false
positives — and they are the kind of rule that regresses silently, because a
status line looks like diligence and a tracker reference looks like a
citation. The checker is worth writing before the next standard lands rather
than after.
D3 resists a checker: a grep can find the word "twelve-factor" but not
whether the citation is apt or the departure argued, so it stays a review
question, stated in the charter's *The foundation: twelve-factor*.
One carve-out is unsettled and left visible rather than assumed: the CI
standard's decisions log cites the change that settled each row, which is
history rather than a live reference, and whether D2 admits that is a review
question until someone rules on it.

## Service standard

Rules from [`service.md`](service.md) — what a running service exposes. This
section carries the ledger's strongest promotion candidate: `job-image-starts`
already accepts an `http` probe and already reads startup output, so SC1 and
SC5 need an extension of a job every repository calls, not a new one.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SC1 | `/healthz` and `/readyz`: fixed paths, fixed shapes, unauthenticated, uncached; readiness checks dependencies and `503`s when one fails | `job-image-starts` with an `http` probe on `/readyz`, asserting the schema (proposed); `check-service-contract` (proposed) for route registration | **review only** |
| SC2 | One JSON log line per event to stdout, with the pinned field vocabulary; a failure line states its reason, its subject and its cause, never the fact of failure alone | corpus validity cases against captured stdout, incl. the `error` object required on error and fatal lines and the insufficient-message list (proposed) | **review only** |
| SC3 | Config from the environment; a missing required variable fails startup naming all of them; no environment detection in code | `check-service-contract` (proposed) for declared variables; the fail-loud behaviour is a lifecycle corpus case | **review only** |
| SC4 | SIGTERM flips readiness, drains, then exits; the deadline is stated and what it abandons is logged | lifecycle corpus case under a live harness (proposed) | **review only** |
| SC5 | The running service reports its service, version, commit and build timestamp | `job-image-starts` asserting the startup line (proposed) | **review only** |
| SC6 | Endpoints up first; no dependency blocks startup; misconfiguration blocks serving but not observability; never crashloop | `job-image-starts` with every dependency absent — the image must answer `/healthz` and stay running (proposed) | **review only** |

SC6 is gateable by the job the fleet already runs, and cheaply: start the
image with **no** dependencies reachable — which is exactly what
`job-image-starts` does today, since it starts a container in isolation — and
assert that `/healthz` answers and the process is still running. A service
that refuses to start without its database fails that, by name, in the job it
already calls. The crashloop half is the same observation over time: a
container that exits and restarts is not a container that stayed up.

SC1 and SC5 are the cheapest real gates the fleet can build: no new job, no new
infrastructure, and adoptable per-repository as each grows the endpoint, so
there is no flag day. Today `job-image-starts` can claim only that a process
did not exit within its timeout — a service that starts, fails to reach its
database and answers nothing passes. These two rows are what turn that claim
into "it came up, reached its dependencies, and said what it was."

SC2's reason-giving half is enforceable further than it first looks. That a
failure line carries an `error` object is a schema fact, and the corpus
carries a list of **failure classes that are insufficient as a whole
message** — `error occurred`, `operation failed`, `invalid input` and their
relatives. The match is **equality, never containment**: those words are
fine opening a message and useless as the whole of one, so `invalid input:
expiry_date must be RFC 3339 full-date` passes and bare `invalid input`
does not. The list is deliberately conservative — it catches the shapes
people actually type, and no list can enumerate vagueness, so "does this
message answer what kind, which operation, which input, and what exactly
went wrong" stays a review question on every diff that logs.

SC3's "no environment detection in code" half resists a checker honestly: a
grep for `NODE_ENV` finds the common case and misses a hostname test or a
path-existence check, and the rule is about the act rather than the spelling.
It stays a review question on every diff that reads its surroundings.
