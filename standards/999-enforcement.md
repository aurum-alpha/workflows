# Enforcement ledger

Every rule in every Aurum Alpha standard, the mechanism that enforces it, and
the tier that mechanism actually reaches today. One table, across all standards,
because the question "is this rule real?" has to have one answer and one place
to look it up.

The tiers — **gated**, **audit only**, **review only** — and the law they serve
are defined in [`../README.md`](../README.md). Read that first; this
document is the register, not the argument.

**Proposed gate** is a commitment, not a wish. A rule landing review-only names
the mechanism it is eventually getting, and promoting it is a change that moves
its row. A rule that genuinely resists automation says so there instead, and
stays review-only honestly.

This ledger claims what a mechanism *can* do, not what every repository has
taken up. Adoption is tracked in each repository's own issue tracker.

## CI standard

Rules from [`010-ci.md`](010-ci.md). `tools/check-ci-conformance` runs two ways from one
source — `--repo-root` inside a repo's own CI via `job-ci-conformance.yml`, and
`--portfolio` for sweeps — because an audit and a gate that can disagree eventually
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
| 15 | The repo is versioned, not the artifact; images are cut on dependency closure, credential and configuration surface, and an image does one thing | the image set per repository is readable from the catalog calls; the three criteria are a review question | **review only** |
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
| — | Standard pnpm version | `check-dependency-versions` | gated¹ |
| — | Shared lint config unedited (`.oxlintrc.json`) | `check-lint-configs` | gated¹ |
| — | Caller `with:` matches the shared job's inputs | `check-ci-conformance` IN | gated |
| — | One shared `ci-ok` rollup, not eleven copies | `check-ci-conformance` RU | gated |
| — | The version moves forward, or not at all | `job-version-gate` | gated² |
| — | A release pull request changes only the version file and prose | `job-version-gate` | gated² |
| — | The version file is never deleted | `job-version-gate` | gated² |
| — | Only a version change mints the tag and the GitHub release | `job-version-release` | gated³ |
| — | Only a version change mints a `v<version>` image tag or package version | — | **review only** |
| — | Caller permissions cover shared jobs | `check-caller-permissions` | gated¹ |
| — | Overrides use pnpm's key alone, not npm's or yarn's | `check-overrides` | gated¹ |
| — | Every override carries a reason, and no reason outlives its override | `check-overrides` | gated¹ |
| — | The reason is true, still true, and names a real retirement condition | — | **review only** |

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

Where a CI rule reads **review only** above, `010-ci.md` explains why: BUILD ONCE
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
| A3 | It references the Aurum Alpha standard, or vendors it | `check-agent-docs` A3 | gated¹ |
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

Rules from [`000-platform.md`](000-platform.md) — the
doctrine the per-capability application standards are written under. The
per-capability rules themselves register here as each standard lands; these
rows govern the doctrine.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| PC1 | An opinion is a contract, never a tool | — resists honestly | **review only** |
| PC2 | Standard protocol first, profile second, internal contract last | — resists honestly | **review only** |
| PC3 | An agreed contract carries its artifacts (schemas, corpus) | `check-contract-artifacts` (proposed) | **review only** |
| PC4 | Gates run the corpus at the boundary, never check the implementation | `job-contract-conformance` (proposed) | **review only** |
| PC5 | A package conforms to the spec, never the reverse; no shared package depends on another | corpus run + manifest check in package CI (proposed) | **review only** |
| PC6 | Contracts evolve additively, versioned, with deprecation windows | `check-contract-evolution` (proposed) | **review only** |

PC1 and PC2 are judgment — what "a tool the lifecycle depends on" or "a
standard that suffices" means is not a fact on disk — so they stay review
questions, stated as such in the document. PC3 through PC6 name real
mechanisms and are commitments: each becomes buildable the moment the first
`contracts/<capability>/` tree lands, and promoting each is its own change
that moves its row.

## Identifiers standard

Rules from [`020-identifiers.md`](020-identifiers.md) —
the first per-capability standard under the platform contract, and the first
`contracts/` tree, so the PC3–PC6 mechanisms above now have something to run
against.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| IP1 | Internal integer keys never leave the service; addressable rows carry a separate opaque public id | schema-level column check, buildable once the [structured-data standard](025-structured-data.md) defines a readable schema; until then the stated review question | **review only** |
| IP2 | Public ids use an admitted format from the table (UUIDv7, nanoid profile, prefixed handle); UUIDv4-in-an-index needs a written defence | `job-contract-conformance` running `contracts/identifiers/corpus.json` (proposed) | **review only** |
| IP3 | Ids are opaque — equality only, no parsing meaning out of them | — resists honestly; review question on consumers | **review only** |
| IP4 | Instants are RFC 3339 UTC `Z` at one pinned fractional precision (default three digits, extendable to six or nine, never fewer); calendar dates are `full-date`; MySQL profile `DATETIME(3)` | corpus validity + canonical cases (proposed, same job) | **review only** |
| IP5 | Money is integer minor units + ISO 4217 code, together; floats never | corpus validity cases (proposed, same job) | **review only** |

IP2, IP4 and IP5 are exactly what a corpus can hold: their gate is the
platform contract's own `job-contract-conformance`, and the corpus already
exists, so promoting them is building the job, not writing the cases. IP1's
mechanical gate is named but waits on the [structured-data standard](025-structured-data.md). IP3 resists a checker — what a
consumer does with an id after receiving it is not a fact on disk — and the
document states the review question instead.

## Observability standard

Rules from [`040-observability.md`](040-observability.md) —
the propagation and telemetry-transport profile the service baseline's log
fields and the async envelope both build on.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| OC1 | W3C trace context on every boundary — HTTP calls and the job envelope; continue valid inbound context, start fresh otherwise; no parallel correlation scheme | propagation corpus under `job-contract-conformance` (proposed); the envelope half is met by the CloudEvents tracing extension, gated by [`055-messaging.md`](055-messaging.md)'s schema | **review only** |
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

Rules from [`../README.md`](../README.md)'s "How these documents are
written", "The foundation: twelve-factor" and "Acceptable solutions: the
register of what satisfies a standard". D5 to D9 govern the registers under
`solutions/`, which state no rules of their own and are therefore governed
entirely from here.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| D1 | No document carries a status header; a merged document is binding | `check-standards-docs` (proposed): no `Status:` line in a standard | **review only** |
| D2 | Documents reference documents by working relative link — never a tracker number, never a bare name; a standard not yet written is linked at its roster row | `check-standards-docs` (proposed): no issue or pull-request reference in a standard's prose, and every relative link resolves | **review only** |
| D3 | A rule restating a twelve-factor factor cites it; a rule departing from one says so, in the rule, with the reason | — resists honestly: whether a citation is apt, or a departure argued, is judgment | **review only** |
| D4 | A rule is argued from principle, never from precedent, and a standard is not an inventory: it names, counts and describes no repository; a failure mode is stated as the general property it is, so the text does not reveal which repository, if any, taught it | — resists honestly: a grep finds repository names and counting phrases, not the fallacy, and is still worth running. The review question on every rule and every Decisions entry: *would this reason hold if no current repository existed?* | **review only** |
| D5 | An acceptable solutions register states no rule: delete it and every rule still stands, with every repository still able to comply | the citation half is **static and decidable** — `check-solutions` (proposed): every rule id a register cites exists in the standard it shares a number with, which catches the drift that turns a claim into an orphan when a standard is renumbered. Whether a sentence is a claim or a rule in the wrong document resists honestly and is the review question on every register diff | **review only** |
| D6 | Absence from a register is not refusal; what is refused is refused by a rule in the standard, which the register cites | — resists honestly. The observable half: a register's refusals table cites a rule id for every row, checked with D5's citation pass | **review only** |
| D7 | A register entry is a technical claim on a date — never an endorsement, a price, a contract term or a vendor ranking | `check-solutions` (proposed): a currency symbol, or the pricing vocabulary, in a register is a finding. Close to no false positives, because the vocabulary has no other use on a page this class admits | **review only** |
| D8 | Every register carries the date its claims were last checked; the horizon is 180 days, lowerable and not raisable; an entry past it is a finding | **static and decidable, and the mechanism of the whole class** — `check-solutions` (proposed): parse the checked date, compare to the run date, fail past the horizon. The same shape as 038 FF3's date comparison, over a different committed file, and worth folding into that checker rather than writing twice | **review only** |
| D9 | A register may name at most one default route, argued, and says what would change it | — resists honestly: that an argument is good is judgment. That there is at most one is a review question a reader answers by reading the page | **review only** |

D1 and D2 are the cheapest gates in this ledger — a grep each, no false
positives — and they are the kind of rule that regresses silently, because a
status line looks like diligence and a tracker reference looks like a
citation. The checker is worth writing before the next standard lands rather
than after.
D3 resists a checker: a grep can find the word "twelve-factor" but not
whether the citation is apt or the departure argued, so it stays a review
question, stated in the charter's *The foundation: twelve-factor*.
D4 resists one the same way and is the convention most likely to be broken
in good faith, because copying a good answer feels like diligence. Two merged
standards carry passages written before it was stated; bringing them to it is
its own change.
One carve-out is unsettled and left visible rather than assumed: the CI
standard's decisions log cites the change that settled each row, which is
history rather than a live reference, and whether D2 admits that is a review
question until someone rules on it.

D5 to D9 land review-only under the charter's own sequence, and D8 is the row
to watch: **a register whose staleness nothing detects is the exact failure the
register class was created to prevent, one document further out.** The horizon
is a date in a file compared to the run date — the cheapest check in this
ledger after D1 — and until `check-solutions` exists, a register's freshness
rests on someone reading the date, which is what the class says is not good
enough. Writing it is the first follow-up this section is asking for, and it
belongs beside `check-flag-declarations`, whose date comparison is the same
comparison over a different file.
D5's citation pass is worth the same trip: it is what stops a register drifting
into an orphan after a standard is renumbered, and it is the only mechanical
grip on the boundary between a claim and a rule.

## Service standard

Rules from [`030-service.md`](030-service.md) — what a running service exposes. This
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

SC6 is gateable by the job already in the catalog, and cheaply: start the
image with **no** dependencies reachable — which is exactly what
`job-image-starts` does today, since it starts a container in isolation — and
assert that `/healthz` answers and the process is still running. A service
that refuses to start without its database fails that, by name, in the job it
already calls. The crashloop half is the same observation over time: a
container that exits and restarts is not a container that stayed up.

SC1 and SC5 are the cheapest real gates here: no new job, no new
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

## Service interfaces standard

Rules from [`050-http.md`](050-http.md) — which protocol an interaction uses, and the
conventions for the default answer.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| HA1 | HTTP is the default; gRPC is service-to-service only; SSE before WebSocket unless the client must push; HTTP/2 is a prerequisite for gRPC and for usable SSE and must reach the service, not just the edge; leaving HTTP never leaves the standards | — resists honestly: whether a reason is good is judgment. Two reviewable acts: a repository choosing a non-default protocol states why in its **Conventions**, and one serving gRPC or SSE states there where HTTP/2 terminates and that the backend hop carries it | **review only** |
| HA2 | A committed OpenAPI document describes the API and matches the running service; 3.1 is the floor, 3.2 where the service serves SSE | static and decidable: the document exists, lints, declares `openapi: 3.1.x` or later, and declares 3.2 if any response is `text/event-stream` (proposed). That it still *matches* resists a checker — see below | **review only** |
| HA3 | Every error is profiled RFC 9457 problem+json, with `type` stable, `detail` specific, `request_id` present | `job-image-starts` requesting an unroutable path and validating the body against the schema (proposed) | **review only** |
| HA4 | Collections paginate by opaque cursor; offset only for genuinely static collections, declared | corpus behaviour case under a live harness (proposed) | **review only** |
| HA5 | One major version in the path; change is additive until it cannot be | — resists honestly: whether a change is breaking is judgment | **review only** |
| HA6 | Mutating endpoints accept `Idempotency-Key`; a replay returns the original response, a reused key with a changed body is refused | corpus behaviour cases, two requests under a live harness (proposed) | **review only** |
| HA7 | `429` always carries `Retry-After`; clients retry only idempotent or keyed requests, with backoff and jitter | server half is a corpus behaviour case; the client half resists a checker | **review only** |
| HA8 | JSON body and query-parameter field names are snake_case; headers keep HTTP convention; the rule binds the wire, never source identifiers | **the one mechanically decidable rule here** — a checker walks the committed OpenAPI document's schema property names and parameter names and fails on any that is not `[a-z][a-z0-9_]*` (proposed `check-wire-naming`); the wire/code split needs no gate because a gate reading source would itself be the violation | **review only** |

HA3 is the cheapest live gate in this ledger after the service standard's own:
`job-image-starts` already talks to a running service, so one request to a path
that cannot exist, and one schema validation of what comes back, catches the
failure the portfolio actually has — a framework's default HTML error page escaping
to clients from the one route nobody wrote a handler for.

**HA8 is the cheapest gate of any kind here**, and static: the committed
OpenAPI document already lists every field name the API speaks, so checking
them against one character class needs no running service and has no false
positives. It is also the rule whose *other* half must never be gated —
verifying that source identifiers are idiomatic would mean reading the
implementation, which is exactly what PC4 forbids a gate to do.

Three rules resist a checker and say so. **HA1** is a judgment about fit: a
checker could detect that a repository opened a WebSocket, and could never
detect whether it should have. What is reviewable is the stated reason, so the
rule requires one. **HA2's second half** — that the document still describes
the service — is the important one: a checker can prove an OpenAPI file parses
and can never prove it is true, so the honest mechanism is a repository's own
contract tests and the review question is whether they exist. **HA5** needs to
know whether a change is breaking, which is a judgment about meaning rather
than a fact about a diff.

## Web client standard

Rules from [`090-web-client.md`](090-web-client.md) — the obligations of code running
in a browser.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| WC1 | The browser's only credential is a session cookie it cannot read: nothing in `localStorage`, `sessionStorage` or IndexedDB, no provider credential in the bundle, a `401` answered by navigating rather than exchanging | the storage half is a corpus behaviour case reading all three stores after a login (proposed). The central claim, that no token reaches JavaScript, **resists a checker entirely**: proving it means proving a negative about a running program, and a gate that read the source would be the PC4 violation. Review question: *what credential does this page hold, and what could read it* | **review only** |
| WC2 | The bundle is environment-agnostic; configuration is fetched at load from a document the server renders from its own environment; nothing secret is in it | **the cheapest gate in this standard and the one to build first** — a static grep of the build output for any environment's API origin or provider hostname, needing no browser and no running service (proposed `check-bundle-config`). The served document validates against its schema under `job-image-starts`. The no-secrets half is held by the schema's closed property set | **review only** |
| WC3 | One API client module, generated from the OpenAPI document, owning problem+json parsing, idempotency keys, bounded jittered retries, cursor paging and credentials mode | corpus behaviour case for key reuse across a retry (proposed). That the module is generated rather than hand-written correct **must not** be gated — a checker failing a build for a direct `fetch` would be enforcing an implementation choice, which PC4 forbids | **review only** |
| WC4 | Locale and zone come from the viewer, never inferred server-side; formatting uses `Intl`; currency exponents come from the currency; the server never sends a pre-formatted string | corpus behaviour cases for the two that are actually got wrong — a zero-exponent currency, and an instant whose calendar day differs by zone (proposed). The server half is reviewable in the OpenAPI document: a response field typed as a formatted string is visible there | **review only** |
| WC5 | The browser does not originate the server's trace; correlation is by the returned request id; the error report is a closed shape carrying build provenance and no session cookie, token or personal data | schema validation of emitted reports, and the conditional requirement that an `api_error` carries a `request_id` (proposed). What a report must *not* contain is held by `additionalProperties: false` rather than by a denylist, which is the only version of that rule that holds against a field nobody predicted | **review only** |

**WC2 is the one to build first**, and it is unusual in this repository for
being both cheap and high-value: the failure it catches — an API origin baked
into the bundle at build time — produces one artifact per environment, breaks
the build-once separation the [CI standard](010-ci.md) requires, and **nothing
fails today when it happens**. That is the exact profile of a rule that is a
preference until something enforces it.

This is the least gateable standard here so far, and the reason is structural
rather than an admission of laziness: its subject runs on someone else's
machine, under a browser we do not control, in a bundle that has been
minified. Two of the five rules have a genuinely observable boundary — the
cookie attributes of WC1 and the build output of WC2 — and those are where the
gates go. For the rest, the boundary a gate could legitimately check is the
wire, and the wire here is the two contracts under
[`contracts/web-client/`](../contracts/web-client/).

## Authentication standard

Rules from [`060-auth.md`](060-auth.md) — how a person is authenticated, what identity
reaches an application, and how a session ends. The authorization model is the
[RBAC standard](070-rbac.md)'s.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| AU1 | Authentication is a tier in front of the application; a reverse proxy is strongly preferred and application code is admitted with a stated reason; the application talks to the provider on the control plane only | — **resists a checker entirely**: whether authentication sits in a tier or in the application is an architecture question, and a gate reading source to answer it would be the PC4 violation. Review question: *which process is the OAuth client, and what holds the tokens* | **review only** |
| AU2 | One signed identity token crosses to the backend; (b) preferred, (a) admitted, (c) discouraged; the backend verifies rather than decodes; no authorization claim appears in it | **the strongest gate here** — the token is a wire shape, so the corpus validates it, and *verified rather than decoded* is testable by presenting a token signed with an untrusted key and requiring refusal (proposed) | **review only** |
| AU3 | An application stores `(issuer, subject)` as a link and keeps its own key; email is a matching key and never a foreign key; the subject identifier type is `public` | corpus rejects a subject without its issuer. That an application did not key its user table on the subject is a schema review question, not something a boundary shows | **review only** |
| AU4 | Users originate in the application, which creates the identity; four operations with stated semantics; creation idempotent and never owning; an application never disables an identity | two corpus behaviour cases — a second application reusing an identity, and revocation in one application leaving another unaffected (proposed). The rest governs who may change what, which no boundary reveals | **review only** |
| AU5 | Idle eight hours, absolute seven days; refresh invisible and rotated; back-channel logout for revocation with the short access token as backstop; logout is RP-initiated | live gates are available for the observable half — a session refusing service after its absolute cap, and logout ending the provider session too (proposed) | **review only** |
| AU6 | An authenticated subject with no local user gets `403` and the session ends, never `401`; `/me` carries advisory permissions the client renders from and never enforces on | **a clean live behaviour case**: authenticate as an unknown subject, require 403 with the session ended. That the server also enforces every permission resists a checker and is the review question | **review only** |
| AU7 | The topology is one of three, each with its stated cookie prefix and CORS posture; the split stays inside one registrable domain | **observable from outside**: a login response's `Set-Cookie` and a preflight's answer either carry what the tables require or they do not (proposed) | **review only** |

**AU2 is the one to build first.** It is the only rule here whose subject is a
wire shape rather than an arrangement of processes, and the property it protects
— that a backend verifies a signature rather than decoding a token — is both the
whole security value of the preferred variant and a thing that looks identical to
the broken version in every log and every test that only sends valid tokens.

The pattern across this ledger is worth naming rather than apologising for: **the
parts of authentication that live on a wire are gateable and the parts that are
architecture are not.** AU1, AU3, AU4 and half of AU5 govern where state lives
and who may change it, and neither appears at a boundary a gate can watch. Their
review questions are stated in the rows above so that unenforced is visibly
unenforced.

## Authorization standard

Rules from [`070-rbac.md`](070-rbac.md) — the model, its operations and its decision
corpus. Authentication is [`060-auth.md`](060-auth.md)'s; AU6 is the boundary.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| RB1 | Permissions are a closed set declared in code; a check against an undeclared permission is an error, not a denial | corpus rejection case for the error behaviour. That the declaration is genuinely complete is a judgment about content | **review only** |
| RB2 | A permission is `resource.action`: lowercase, snake_case segments, exactly two, the dot reserved for permissions and the colon for scopes | **static and decidable** — every declared permission matches `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`, which also catches the three-segment form (proposed `check-permission-names`) | **review only** |
| RB3 | A role is a named set; code-declared or data-stored, either admitted; every permission in it must be declared; a system role is not tenant-editable and a tenant role may not shadow its name; roles do not nest or inherit | three corpus rejection cases: an undeclared permission in a role, a tenant editing or deleting a system role, and a tenant role shadowing a system role's name | **review only** |
| RB4 | **Code never branches on a role name.** A role name appears in code only in a system role's seed definition and in display; every decision is `check(subject, permission, scope)` | **one corpus case is a mechanical detector**: a subject holding a tenant-defined role that carries exactly the permissions of a code-declared one. An implementation gating on the name refuses a subject the permission model allows, and fails that case while passing every other. A grep for role-name comparisons is a weak second gate with real false positives — display and seeding are legitimate | **review only** |
| RB5 | A grant binds subject to role within a scope; `global` or `type:id`; a containing scope satisfies a contained check | **decided entirely by the decision corpus** — five containment cases including the two an implementation gets wrong, upward and sibling | **review only** |
| RB6 | Deny by default; grants additive with no negative grants; **no wildcard anywhere** — declaration, stored role, check argument or authoring shorthand; no permission implying another | **decided entirely by the decision corpus**, plus a rejection case covering all four surfaces a wildcard could enter by | **review only** |
| RB7 | `check` is a pure function of subject, permission and scope; scope is an argument, never ambient state | the corpus is only writable *because* of this rule, so passing it is the evidence. Purity itself resists a checker — a gate reading source for it would be the PC4 violation | **review only** |
| RB8 | A decision carries its reason; the reason is logged and never returned to an unauthorised caller | the reason's presence and shape are corpus-checked; whether it is *informative* is a judgment, like SC2's | **review only** |
| RB9 | A cached decision is keyed by subject, permission and scope, and every path that changes a grant invalidates | **one corpus case catches the whole failure**: the same permission checked in two scopes, allowed in the first and denied in the second. A cache keyed without scope fails it | **review only** |

**This is the most gateable standard in the repository**, and that is the point
of writing authorization as an interface specification rather than as prose.
RB5, RB6 and RB9 are decided by data: an implementation loads the fixture, runs
seventeen checks, and either reproduces every decision or names the one it
failed. No running service, no browser, no network — which is what PC3 promised
a corpus would buy and the first place it fully pays.

The corpus is also the first real answer to *one contract judging three
languages*. A Go, a TypeScript and a PHP implementation each pass it or each
name their failure, and none of them can pass by importing anything.

`decisions.json` carries two cases that exist to catch a specific mistake rather
than to describe correct behaviour, and both were verified as detectors before
landing — a reference implementation passes them, and a deliberately broken one
fails each.

**The same permission checked in two scopes.** An implementation caching on
subject and permission alone returns allowed for both, which is a cross-tenant
authorization result produced by a cache key, and no test exercising one tenant
at a time will ever show it. This one is a defect found in production code rather
than imagined.

**A tenant-defined role carrying exactly a code-declared role's permissions.** An
implementation that gates on a role name refuses a subject the permission model
plainly allows, and fails only this case out of eighteen. It is the mechanical
detector for RB4, which is otherwise the easiest rule here to break by accident.

## Audit standard

Rules from [`080-audit.md`](080-audit.md) — the record of consequential acts. The event
reuses the identifiers contract's ids and timestamps and the observability
contract's correlation fields, so a violation of IP1, IP4, OC2 or OC4 inside an
audit event fails those contracts' rules too, from this file's schema.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| AE1 | An audit event is application data in the product's own durable, queryable, tenant-scoped store — never a log line, and the log stream is never the system of record | resists a checker honestly: whether a store is the system of record or a convenience is intent, not shape. The review question is whether a history screen could be built from it | **review only** |
| AE2 | One event shape, and **actor and target are separate required objects** — the failure the portfolio's one existing audit table demonstrates, plus `outcome`, an `impersonator` where one acted, and public ids never internal keys | **schema-decided** — `event.schema.json` under `job-contract-conformance`; sixteen validity cases already reach their stated verdict against it | **review only** |
| AE3 | `action` is `resource.verb`, and where a permission authorized the act the action string **is** that permission; `auth.*` is this standard's reserved namespace for acts with no permission behind them | the format half is schema-decided. The identity half gets **a static check worth writing early**: read the product's declared permission set, assert every emitted action is one of them or a reserved `auth.*` action (proposed `check-audit-actions`) | **review only** |
| AE4 | An event is self-contained, immutable and outlives its subject: display denormalized at write time, append-only, no cascade from the target's deletion, values not references, never a credential | the shape half is schema-decided. That the store is genuinely append-only and uncascaded is a schema fact once the [structured-data standard](025-structured-data.md) gives a checker a schema to read; that no credential reaches `changes` is SC2's judgment again | **review only** |
| AE5 | The floor of what must emit: authentication and session lifecycle, authorization changes, identity lifecycle, destructive writes, security-posture configuration, bulk personal-data export — and reads otherwise **not** audited | **the generative gate, and the one worth the most here** — enumerate the routes guarded by a destructive permission, exercise each, assert an event carrying that permission as its action. Fourteen `floor` cases in the corpus describe the acts; two of them are negative | **review only** |
| AE6 | Append-only discipline is required — `INSERT` and `SELECT`, retention deletion under a separate credential. Hash chaining is **not** required; tamper-evidence needs an anchor outside the writer's reach | the grant is a schema fact, readable against [`025-structured-data.md`](025-structured-data.md) SD3's credential split. That the request path holds no update is a review question | **review only** |
| AE7 | Retention has a floor of one year and a stated ceiling; audit rows are tenant-scoped data; erasure **redacts the event rather than deleting it**, keeping the act and losing the identification | the erasure half is corpus-decided by `redaction` cases; `erased_at` and `erased_subjects` travelling together is schema-decided. That a retention period was chosen rather than defaulted is a judgment | **review only** |
| AE8 | The event is written in the change's own transaction where they share a store; otherwise after the change, with a failed write logged at `error` with the payload inline, and never fire-and-forget | **resists a checker at the rule's own level** — whether a write shares a transaction is a fact about a call graph, and a gate reading source for it is the PC4 violation. The corpus reaches the observable half: a failed change produces no event, a successful one produces exactly one | **review only** |

The interesting split here is between what the schema decides and what it
cannot, and the corpus says which is which in the case rather than leaving a
reader to assume coverage.

**Two cases are recorded as passing precisely because the schema cannot catch
them.** `invoice.voided` is a well-formed event whose only defect is that the
product declares `invoice.void` — a second vocabulary, one action at a time,
which is what `check-audit-actions` is for. A credential change carrying the new
password would validate too; AE4 forbids it in prose and this ledger keeps it a
review question rather than claiming a gate.

**One redaction case is a verified detector**, in the pattern the authorization
corpus established. Erasure targets a *subject*, not a position: in the second
case the erased person is the target and the administrator who acted is a living
third party whose name must survive. An implementation that redacts by position —
"the actor is the person, redact the actor" — passes the first case and fails the
second twice over, stripping a living person's identity while leaving the erased
subject's in place. It was checked against exactly that broken implementation
before landing.

**AE5's generative gate is the one to build.** A list of routes that must audit
rots the day someone adds a route, which is how the portfolio's existing audit table
came to be a well-designed table nothing writes to. An enumeration over the
permission set cannot rot that way, and AE3's identity rule — the action string
*is* the permission string — exists largely to make that enumeration possible.

## Structured data standard

Rules from [`025-structured-data.md`](025-structured-data.md) — the query
language, migrations, isolation, and how the identifiers contract's primitives
are stored. This standard resolves three deferrals other rows above made to it:
IP1's schema check, IP4's non-MySQL storage profile, and AE4/AE6's append-only
grant as a schema fact.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SD1 | SQL is the query language: authored text, bound through native placeholders, no runtime generation from an object model or builder; codegen *from* SQL admitted | **resists a clean gate honestly** — checking imports is checking the implementation (PC4). The boundary gate is a driver-level capture in the conformance job asserting every executed statement matches committed text; it does not exist yet. Until then: *can I paste this into a console?* | **review only** |
| SD2 | A migration is an ordered `.sql` file, immutable once merged, never code; authoring unconstrained; every statement converges (guarded DDL, `ON CONFLICT` seeds) so a re-run against an applied or half-applied database exits zero; `db:push` absent from any deploy-reachable script | **three greps with no false positives**: only `*.sql` in the migrations directory, no merged file's bytes changed (from history), no push command reachable — plus a static, partial fourth for unguarded common forms. Ten corpus cases (proposed `check-migrations`); the live replay in SD3's gate is the proof of convergence | **review only** |
| SD3 | Migrations ship in their own image, built in the same run at the same version, run to completion as a discrete step before rollout, never at boot; idempotent at the command level (version record) and the file level (SD2); migration credential ≠ runtime credential | **live gate**: apply from empty, apply from the previous release's image, then replay every file against the migrated database bypassing the version record and require exit zero and an unchanged schema — as a sibling of `job-image-starts` (proposed `job-migrate`). Boot-time migration is a review question | **review only** |
| SD4 | Migrations expand; `DROP COLUMN`, `DROP TABLE`, `ALTER … TYPE` need `-- expand-only-ok: <release>`; down never trusted | a regex over each file's up section for the three statement kinds and the marker; the corpus covers the violation, the marker, and the marker with no release named (proposed `check-migrations`) | **review only** |
| SD5 | Isolation levels are declared and are the RB5 scope types; every scoped table carries the column for every containing level, denormalized; predicates are joinless | schema-decided by the isolation corpus; **one case is a verified detector** — a table carrying the inner column but not the outer one, which a suite checking only the innermost column passes wrongly | **review only** |
| SD6 | Isolation is a behaviour with three admitted mechanisms; a missing context denies; no bypass role on scoped tables; the gate enumerates scoped tables from the catalog | **the generative gate worth the most here** — discover scoped tables from `information_schema`, assert columns, types, keys and coverage; a table added tomorrow is covered the day it lands, and a table added without its columns is the finding | **review only** |
| SD7 | IP1's public-id column beside the internal key; per-engine storage profile from `storage-profiles.json`; session time zone UTC | **catalog check against the profile** (proposed `check-storage-profile`) — this is the check IP1's row has been waiting for | **review only** |
| SD8 | Seeds are idempotent SQL through the migrate path; fixtures are never production rows and no deploy path can load one | seeds: the from-previous-release run applies them twice, so a non-idempotent seed fails SD3's gate. Fixtures: reachability is a grep; that a fixture carries no real personal data is a judgment | **review only** |
| SD9 | Connection from the environment; least-privilege runtime role; TLS; bounded pool from config, exhaustion visible in readiness; SQL parameters never in telemetry | role privileges are a catalog fact once a checker connects as the runtime role and attempts `ALTER`; the rest is review | **review only** |
| SD10 | The schema carries its invariants: `NOT NULL` by default, foreign keys declared and indexed, `UNIQUE`/`CHECK` for domain rules, no native enums, JSON only for unqueried data, isolation columns leading composite indexes, `created_at`/`updated_at` on every table, `snake_case` identifiers, plural tables, `<singular>_id` keys | **catalog-decided by the `schema` corpus** for the mechanical half (unindexed FK, missing timestamps, native enum, non-snake identifier, isolation column not leading an index — proposed `check-schema`); `NOT NULL` intent and the JSON rule stay review questions | **review only** |
| SD11 | One request, one transaction; no transaction spans a network call or a human; `READ COMMITTED` default with `SERIALIZABLE` opted in per transaction plus retry; statement timeout on the runtime role; `migrate` holds an advisory lock | timeout and lock are configuration facts a checker reads; transaction span is a review question on every handler | **review only** |
| SD12 | Hard delete is the default; soft delete needs a domain reason in Conventions, and a soft-deleted row stays scoped, stays erasable, and is excluded in the query text | the Conventions declaration is a grep; the default is a review question on every delete path | **review only** |
| SD13 | The database is private to its service, in all of that service's processes, and every process holding its credential is built from the one repository that holds its migrations — one schema, one writer, no second credential; tests run against the engine the product runs, never a substitute | privacy is a credential fact (no second role on the database); the real-engine rule is a CI fact — the test job starts the real engine or data-access tests do not run | **review only** |

The corpus was run before landing. All ten migration cases, all six
isolation cases and all six schema cases reproduce their expected findings and visibility against a
reference implementation, and the SD5 detector was checked against a
deliberately weakened suite that inspects only the innermost isolation
column: it passes five of the six isolation cases and fails exactly the one
it exists to catch.

Three rows above are now buildable that were not: IP1 (a public id column in
an admitted format), AE4 and AE6 (the audit table's grant excludes `UPDATE`
and `DELETE`). Each of those rows says it was waiting on this standard, and
each now has a schema to read.

## Messaging standard

Rules from [`055-messaging.md`](055-messaging.md) — the envelope, delivery
semantics, and webhooks. The envelope is a CloudEvents profile, so AM1 is
gated by a schema over a standard rather than over an invention; the
delivery rules are the internal contract and are gated by running a consumer.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| AM1 | A message is a CloudEvents 1.0 event in JSON structured format under this profile: UUIDv7 `id`, logical `source`, past-tense `resource.event` `type`, public-id `subject`, IP4 `time`, `dataschema`, the tracing extension, `tenantid`, closed extension set | **schema-decided** — `envelope.schema.json` under `job-contract-conformance`; ten validity cases. Past tense is the one half the schema cannot tell and stays a review question | **review only** |
| AM2 | The transport is not the contract; a queue table belongs to one service; the transport is an attached resource | review question, and SD13's credential check covers the shared-table half | **review only** |
| AM3 | At-least-once; the inbox deduplicates the delivery on `(source, id)`, with the row in the effect's transaction, retained past the redelivery horizon; the effect's duplicate policy is the job's (057 JB2); ordering not relied on | **decided by the `delivery` corpus** — deliver the sequence, count the effects. **One case is a verified detector**: the same id from two sources, which a consumer keyed on id alone collapses to one effect | **review only** |
| AM4 | Produced in the transaction that caused it: the outbox, relayed by `outbox.relay`, a job the service's pool runs and the server never does | resists a boundary gate honestly — transaction sharing is a call-graph fact (PC4). The observable half (change without message, message without change, each provoked) is a live test | **review only** |
| AM5 | Bounded retries with backoff and jitter; dead-letter with envelope, attempts and last error; replayable; poison never blocks; failures logged with the OC4 context block | the dead-letter shape is schema-checkable; the rest is review | **review only** |
| AM6 | Work outside a request is a consumer in a worker — its own image, bound to the service by provenance (the build run) and by ownership (the credential), never by the repository alone — never a timer in the server; workers drain per SC4 | **static check with no false positives**: no `setInterval`/ticker/cron in the request-serving entrypoint (proposed `check-no-timers`); the worker image is built, started and published like any other image | **review only** |
| AM7 | A webhook leaving is the envelope in structured mode, signed per Standard Webhooks: `webhook-id` = event id, `webhook-timestamp` per attempt, `webhook-signature` `v1,<base64>` HMAC-SHA256 over `id.timestamp.body`; one secret per endpoint, rotated with two signatures; retried per AM5 with the spec's response semantics | **decided by the `signing` corpus** — computed signature values an implementation reproduces byte for byte | **review only** |
| AM8 | A webhook arriving is verified over the raw body, re-enveloped with the provider as `source` and the provider's event id as `id`, recorded in one transaction, and only then answered `2xx`; the work happens afterwards as a consumer | the rejections are `signing` corpus cases; the re-envelope dedupe is a `delivery` case; the order of the four steps is a review question | **review only** |

The corpus was run before landing: ten validity cases, six delivery cases and
six signing cases all reproduce their expected results against a reference
implementation, and the AM3 detector was checked against a consumer that
deduplicates on `id` alone — it passes five of the six delivery cases and
fails exactly the one it exists to catch. The signing values were computed,
not typed, so a verifier in any language proves its HMAC against them.

One row above changes as a result of this standard: OC1's envelope requirement
is now met by a standard extension rather than by a field the fleet named, and
OC1's row points here for the envelope half.

## Workers standard

Rules from [`035-workers.md`](035-workers.md) — the two worker models, how
their images are cut, the one-shot's command and exit codes, the runner
contract, and how a declaration reaches the runner. The runner is adopted
from existing schedulers rather than built, so WK5 states seven verbs and
[`../solutions/035-workers.md`](../solutions/035-workers.md) maps them onto the
settings a renderer emits and a checker can read back — the mapping being the
part that moves with an orchestrator release, and the verbs the part that does
not.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| WK1 | Two worker models, the pool and the one-shot, picked by the trigger; the outbox relay is a job the pool runs; the timer loop, the worker in the server, and work in the boot path are refused | the timer half is AM6's proposed `check-no-timers`; the relay's placement and the boot path are review questions | **review only** |
| WK2 | A worker is a container image built in the run at the repository's version; images split on dependency closure, credential and configuration surface and on nothing else; the migrate image stands alone; a repository is not a service and a service lives in exactly one repository; the escape hatch for runtimes that cannot run a separate image excludes migrations | the image set is read from the CI catalog calls (a migrate image and a jobs image where one-shot jobs exist, a pool image where per-event jobs exist); the one-repository rule is a credential fact — one database's credential in one repository's deployables — and is checkable once credentials are declared per image; the three-reasons rule is review | **review only** |
| WK3 | One pool per service by default; partitioning only after a measured reason, recorded in the repository's decisions | review question: the recorded reason | **review only** |
| WK4 | One command runs any one-shot; the worker constructs the invocation and derives the key by the trigger's rule; outcomes map to exit codes per `exit-codes.json`; long work is a blocking one-shot when a deployment waits and a self-continuing per-event job otherwise | **decided by the `one_shot` corpus** against the repository's one-shot image: nine cases, each an exit code and a run-record outcome | **review only** |
| WK5 | The runner satisfies seven verbs per `runner-contract.json`; the platform names and builds none; overlap and retry are configured to agree with the job's own lock and no-retry | the rendered runner configuration is compared to the contract's settings per runner; a runner that cannot satisfy a verb is a review finding | **review only** |
| WK6 | Declarations are rendered to the runner at deployment; the rendered form is an artifact and never hand-edited | every periodic declaration has a rendered counterpart in the deployment output and the two agree — a diff, once the renderer exists | **review only** |
| WK7 | A pool exposes queue depth and oldest-message age and the SC1 endpoints with readiness meaning connected; a one-shot exposes nothing but logs, the run record and its exit; both carry `job.name` and `job.run_id` | the metric names and the log fields are checkable against the 040 shape; the readiness meaning is review | **review only** |
| WK8 | A worker's configuration is the least its jobs declare; the pool and the jobs image carry the runtime credential, the migrate image the migration credential and no other; no image carries a credential to a database it does not own | a credential fact, checkable once credentials are declared per image; SD13's row covers the shared-database half | **review only** |

## Jobs standard

Rules from [`057-jobs.md`](057-jobs.md) — the job as an interface, its key
and duplicate policy, its declaration, its outcomes and run record, the lock,
cancellation, freshness, and backfills. The invoked input and the declaration
are schemas; the duplicate policies are decided by running a job runtime
against the corpus.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| JB1 | A job is `run(input, ctx) -> outcome`, named `resource.verb`; the per-event input is the 055 envelope and the invoked input is `invocation.schema.json`; input is validated against the declared schema before the body runs; a job ends and knows nothing of its trigger | **schema-decided** for the invoked input under `job-contract-conformance`; the name grammar is in `declaration.schema.json`; "knows nothing of its trigger" is a review question | **review only** |
| JB2 | Every job has a key derived by the trigger's rule, distinct from the delivery id, and one of three duplicate policies: `idempotent` (key and effect in one transaction, or a far-side dedup handle), `at_most_once` (claim, act, record; a crash between is `unknown`), `at_least_once` (act, record; the declaration is the consent); a key may carry `valid_for` and a late run is `expired` | **decided by the `keys` and `policies` corpus parts** — five key derivations, eight run sequences. **Two cases are verified detectors**: an implementation that acts before claiming fails `at-most-once-crash-between-act-and-record` and its sibling and passes everything else; an implementation that ignores `valid_for` fails exactly the two validity-window cases. Whether a declared `idempotent` job's effect really has a dedup handle stays a review question | **review only** |
| JB3 | Every job declares its class beside its code per `declaration.schema.json`, including the conditional fields; a job with no declaration does not run | **schema-decided**: twelve declaration cases, eight of them rejections each naming its rule; the worker's refusal to load an undeclared job is a `one_shot` corpus case | **review only** |
| JB4 | Five outcomes — `succeeded`, `failed`, `skipped`, `unknown`, `expired` — each with a named owner; `skipped` is a success exit; `unknown` is never aged out | the enumeration is in `run-record.json` and the exit mapping in `exit-codes.json`; that `unknown` rows are resolved is a review question | **review only** |
| JB5 | Every run leaves a row in `job_runs` per `run-record.json`, in the service's database, and the row is the authority over any runner history; logs and the span carry the job name and run id | the table shape is checkable against the storage profile; the log fields against the OC4 block; the authority claim is review | **review only** |
| JB6 | Single-flight and serial-per-key are enforced by an advisory lock in the job, whatever the runner or queue is configured to do | a held lock ending `skipped` is a `one_shot` corpus case; that the lock is taken before any work is review | **review only** |
| JB7 | Every job has a deadline and honours `SIGTERM` within `grace`; a long job checkpoints per unit of work and a rerun resumes; long work over a table is keyset batches, one transaction each | the checkpoint-and-resume behaviour is a `one_shot` corpus case; one-transaction-per-batch is a review question | **review only** |
| JB8 | For a periodic job absence is the failure: `stale_after` beside the schedule, default twice the cadence, alert when the newest `succeeded` row is older | the declaration requires `stale_after` on every periodic job (schema); the alert itself is platform configuration read from the declaration | **review only** |
| JB9 | A job produces through the outbox and reads only its own service's state | AM4's and SD13's rows | **review only** |
| JB10 | A backfill is a long, single-flight, on-demand, idempotent job with a rate bound, never inside a migration, run until it reports nothing left; very large backfills are self-continuing per-event jobs | SD4's expand-only gate keeps data movement out of `migrate`; the rest is review | **review only** |

The corpora were run before landing: twelve declaration cases, five key
derivations, eight policy sequences and nine one-shot cases all reproduce their
expected results against a reference runtime, and the two JB2 detectors were
checked against deliberately weakened runtimes — the act-first runtime fails
exactly the two claim cases, the dedup-only runtime fails exactly the two
validity-window cases, and both pass everything else.

Four rows above change as a result of these standards: AM3 now names the
delivery half as the inbox's and the effect half as the job's; AM4 names the
relay as a pool job; AM6 states the two bindings, provenance and ownership;
SD13 states its unit as the service in all its processes and the one-repository
rule that follows.

## Blob storage standard

Rules from [`026-blob-storage.md`](026-blob-storage.md) — the S3 profile, the
bucket as a backing service, the key, the object reference, reads served
through the server, the upload the server streams, the scan posture, deletion and purge, and tenancy. The
key, the reference and the upload policy are schemas; the upload and read
behaviours are decided by running a service against the corpus.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| BS1 | The S3 API is the storage protocol under the stated profile (SigV4 in headers and never a presigned URL, configured addressing, the named operation set, SHA-256 checksums, strong read-after-write); the client sits behind one boundary module per service that has no operation returning a URL, and no vendor type crosses into a domain signature | the profile's configuration half is readable (`BLOB_ENDPOINT`, `BLOB_REGION`, `BLOB_BUCKET` declared per SC3); the boundary-module half **resists a checker honestly** — a gate reading source for an SDK type would be the PC4 violation. Review question on every diff that imports the client | **review only** |
| BS2 | One bucket per service per environment; a backing service under the service's credential, in the server and pool images and never the migrate image; never shared between services; never public, and reachable from the service's processes alone | bucket configuration facts a checker reads from the platform: public-access block on, no anonymous ACL or policy, website hosting off, endpoint on the private network or under a policy admitting the service's credential alone (proposed `check-bucket-posture`); the one-credential rule is WK8's and SD13's credential check | **review only** |
| BS3 | The key is `<tenant public id>/<entity>/<object public id>` (or the unscoped two-segment form), object id UUIDv7, entity snake_case; no filename, extension, date path or personal data; the key never appears in an API | **schema-decided** — `key.schema.json` under `job-contract-conformance`; twelve `keys` corpus cases | **review only** |
| BS4 | The application stores an object reference (key, verified content type, size, checksum, status, scan, instants) in a row of its own database that owns the object; never a URL, bucket or endpoint; the row is the source of truth | **schema-decided** for the shape — `object-reference.schema.json`, closed, fourteen `references` cases — plus the two equalities the corpus states (key tail is the id, key head is the tenant); that the row genuinely owns the object is a schema review question once a checker reads foreign keys | **review only** |
| BS5 | Reads are served by the server, by object id, after the id resolves to a row, the tenant matches and the 070 check passes; the response is the bytes (`200`, or `206` for a range) and never a redirect, a location or any URL; the server streams and sets `Content-Type`, an RFC 6266/8187 `Content-Disposition` and `private, no-store` from the row | decided by the `reads` corpus against a live service (proposed, `job-contract-conformance`): every served case expects the bytes, so an implementation answering a redirect fails all six served cases; that the boundary module has no URL-returning operation is a grep and a review question on every diff touching it | **review only** |
| BS6 | Uploads are one request to the server, which checks the policy before the first byte, commits the pending row, streams the body to the store while hashing, counting and sniffing, and at the end verifies size, checksum and type against the declaration; a disagreement is a refusal that deletes the object and the row; a client never writes to the store; limits declared per entity in the upload policy | the policy is **schema-decided** (`upload-policy.schema.json`, ten `policies` cases, one of which refuses a read lifetime under any name); the sequence is decided by the `uploads` corpus against a live service. **One case is a verified detector**: a declared `image/png` over PDF bytes with size and checksum agreeing — an implementation that trusts the declared type, or sniffs and silently overwrites it, stores it and fails exactly that case | **review only** |
| BS7 | An entity whose audience is others declares `scan: true`; the scan is a per-event job that writes `clean` or `infected` on the row; nothing is served before `clean`; `infected` deletes the object and keeps the row; an absent scanner fails closed | the posture is **schema-decided** — `others` without `scan` does not validate; the gate is decided by the `reads` corpus. **One case is a verified detector**: a stored object with `scan: pending` for a permitted subject in the right tenant — an implementation treating the verdict as advisory serves it and fails exactly that case | **review only** |
| BS8 | Hard delete: the owning row's transaction writes `object.deleted` to the outbox and `object.delete` removes the bytes; retention past the row needs a declared reason and period; `object.purge` is a periodic single-flight job acting on pending rows past `upload_ttl`, objects with no row, and prefix/tenant disagreements; a lifecycle rule aborts incomplete multipart uploads | the outbox-and-delete sequence and the three purge findings are `uploads` corpus cases; the purge job's declaration is JB3's schema; the lifecycle rule is a bucket configuration fact. That the row delete and the outbox write share a transaction **resists a boundary gate**, exactly as AM4's does | **review only** |
| BS9 | Default encryption on at the bucket; TLS to the endpoint; versioning off by default and, where on, governed by the backup standard; the application reads only the current version | bucket configuration facts (default encryption, versioning state) readable by the same proposed `check-bucket-posture`; the version-id rule is a review question on the boundary module | **review only** |
| BS10 | The tenant boundary is the row's `tenant_id` against the request context plus the 070 check, proven by enumeration; the key prefix is a convenience and a prefix credential condition is a backstop, never the contract; missing context denies | decided by the `reads` corpus: another tenant's row with a valid grant, and a missing tenant context, are each refused; the enumeration form (every tenant's objects requested in every other tenant's context) is the proposed live gate in SD6's shape | **review only** |

The corpus was run before landing: twelve key cases, fourteen reference cases,
ten policy cases, fifteen upload sequences and thirteen read decisions all
reproduce their expected results against a reference server and storage, and
the two detectors were checked against deliberately weakened implementations —
a server that records the client's declared content type without sniffing
fails exactly `a-declared-type-that-disagrees-with-the-bytes-is-rejected` and
passes the other fourteen sequences, and a server that serves before the scan
verdict fails exactly `a-scan-pending-object-is-refused` and passes the other
twelve decisions. A third weakened server, one that answers a redirect to the
store instead of the bytes, fails every one of the six served decisions and
none of the refusals, which is the shape a posture rule should have.

## JSON document storage standard

Rules from [`027-json-document-storage.md`](027-json-document-storage.md) — JSON
documents, never files: when a document database is admitted beside the
relational store's JSON column, which engine class for which test, in which role, what
every document carries, how its shape changes without DDL, and what a copy
owes its source. Most rules are 025's carried across, and DS3 says which; the
admission and the envelope are schemas, the reader's version window and the
release sequence are decided by running a reader and a rollout against the
corpus.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| DS1 | The relational store is the system of record; the JSON column is the first answer; a document store is admitted only by a declaration naming which of three tests the column failed, and never for data a relational constraint governs | **schema-decided** for the declaration — `admission.schema.json` under `job-contract-conformance`, sixteen `admissions` cases; that a store exists without an admission is a credential fact (a document-store connection variable in a service's configuration with no admission beside it) checkable once credentials are declared per image (035 WK8); whether the stated reason is true is a review question | **review only** |
| DS2 | Two roles, derived and primary; a derived store names its rebuild and is not backed up; a primary store is a database in every sense; a derived store the rebuild cannot reproduce is a misdeclared primary | the role's conditional fields are schema-decided (four `admissions` rejections); the profile's admitted roles are a runner cross-check; **whether a derived store is genuinely rebuildable resists a checker** and is the first review question on every admission | **review only** |
| DS3 | Which 025 rules transfer: SD1's reasoning and keyset, SD5, SD6, SD7's form, SD8, SD9, SD12, SD13 verbatim; SD3 and SD4 in changed shape; SD2, SD10, SD11 do not | each transferred rule is gated by its own row above where a gate exists; the authored-query half **resists a clean gate for SD1's reason** — a gate reading source for a mapper is the PC4 violation — and stays the review question *can I paste this into the engine's shell?* | **review only** |
| DS4 | The document's id is the entity's public id or a minted UUIDv7, never the engine's; every scoped document carries every containing isolation field; every index on a scoped collection leads with the outermost; isolation proven by enumeration over the admission's collections | `id_source` is schema-decided; the leading-index rule is a runner check over the admission (one `admissions` case); the enumeration gate is SD6's, walking the admission instead of a catalog (proposed, same suite); that the engine's identifier is not in use is a sample of documents against the envelope plus the review question | **review only** |
| DS5 | Every document carries `id`, `tenant_id` where scoped, `schema_version`, `created_at`, `updated_at`; the envelope is open to the body | **schema-decided** — `document-envelope.schema.json` under `job-contract-conformance`, ten `envelopes` cases; the scoped-needs-tenant judgment is a runner check against the admission; one case is recorded as passing because a 24-hex engine identifier is a well-formed nanoid and no schema can tell them apart | **review only** |
| DS6 | Additive within a version; a version for a non-additive change; a reader accepts N and N-1, upgrades N-1 on read, refuses everything else by name; a bump is three releases | **decided by the `evolution` and `rollouts` corpus parts** — eight reader cases and four release sequences. **One case is a verified detector**: a current-version document carrying an unknown optional field, which a reader that closes its schema refuses while passing the other seven | **review only** |
| DS7 | A rewrite is a JB10 backfill, never a script; the collection and index declaration is applied by `documents.declare` at deployment, converging, under a declaration credential the runtime lacks, from the migrate image | the credential split is a runner check on the admission (two distinct names) and a credential fact per image once declared (WK8); that `documents.declare` runs as a deployment step is readable from the deployment's step order (035 WK6's renderer); that no script rewrites documents is a review question | **review only** |
| DS8 | A derived store is written only by its projection, rebuilt by `documents.rebuild`, proven fresh by `documents.reconcile` under JB8, and excluded from backup by declaration | the three job names and `backup: rebuild` are schema-decided; the reconcile job's `stale_after` is JB8's alert read from its own declaration; the drill is 028's row; **that the projection is the only writer resists a checker** and is a review question | **review only** |
| DS9 | An engine is admitted by a `storage-profiles.json` entry with every field filled; a search engine is derived only | the admission's engine enumeration and the profile's keys are asserted equal by the runner; the profile's admitted roles are a runner check (one `admissions` case); the native-type half is a catalog check per engine (proposed, alongside SD7's `check-storage-profile`) | **review only** |
| DS10 | A document over 256 KiB is a blob with a reference; the admission's ceiling is at or below it; a document store holds no encoded file content | the ceiling is schema-decided (`maximum: 262144`, one `admissions` rejection) and the over-ceiling document is a runner check (one `envelopes` case); that the writer refuses rather than truncates, and that no field carries base64 file content, are review questions | **review only** |

The corpus was run before landing. All sixteen admission cases, ten envelope
cases, eight evolution cases and four rollout sequences reproduce their
expected results against a reference reader and rollout simulation, the
admission's engine enumeration was asserted equal to the profile file's keys,
and the DS6 detector was checked against a deliberately closed reader — one
that validates a document against its version's field list with
`additionalProperties: false` — which passes seven of the eight evolution
cases and fails exactly the one it exists to catch.

Two rows above change as a result of this standard: 025's introduction says
its rules do not transfer to a document store by analogy, and DS3 now states
which transfer by argument; SD12's hard-delete default gains a document-store
half (a derived document is deleted when its source row is, by the
projection).

## Backup and recovery standard

Rules from [`028-backup-and-recovery.md`](028-backup-and-recovery.md) — the
recovery declaration, the mechanism per kind of store, the credential split,
the drill, retention, the erasure ledger, the restore as a deployment, and the
runbook. The declaration and the ledger entry are schemas; the drill's
freshness, its objectives and the restore's ordering are decided by running a
recovery implementation against the corpus.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| BR1 | Every stateful backing service a service owns carries a recovery declaration in the repository per `recovery-declaration.schema.json`; a store with no declaration is a store with no backup | **schema-decided** for the declaration's shape under `job-contract-conformance`, sixteen `declarations` cases; that every store the configuration attaches appears in it is a review question until a checker compares the declaration to the declared configuration variables (030 SC3) | **review only** |
| BR2 | The role decides whether there is a backup: a primary store is backed up by its engine's mechanism from the kind table, a derived store is rebuilt by a declared job or by reads and never backed up; a queue is not backed up; the service never performs its own backup | the role and kind rules are **schema-decided** — a derived store with retention or a drill, a primary store with a rebuild, a cache declared primary, a relational store under snapshot are all rejections in the `declarations` part; that a store declared derived is genuinely rebuildable, and that no job of the service dumps a table, are review questions | **review only** |
| BR3 | Three credentials — backup, restore, runtime — and no process holds more than its role's; the backup credential lives outside every service image; the destination refuses deletion under any credential the service's deployables hold | — resists a repository-side checker honestly: where a credential lives is a fact about the platform's configuration and the destination's policy, not about the repository. The recovery image standing alone is readable from the CI catalog calls (035 WK2's row); the rest is a review question on the deployment | **review only** |
| BR4 | Restore is exercised: `recovery.drill` is a periodic job that restores every primary store into a scratch environment, migrates, replays the ledger, rebuilds, verifies with the declared checks including readiness, measures the achieved RPO and RTO against the declaration, records the run and destroys the scratch; a drill older than `stale_after` alerts (057 JB8) and `recovery.assert_drilled` blocks the deployment | **decided by the `drills` corpus** — five `freshness` cases and three `objectives` cases; one freshness case separates an implementation reading the newest succeeded row from one reading the newest row of any outcome. The deployment gate is a blocking deployment-step job with a run record, so it is gated in every service that puts it in its deployment order; the alert is platform configuration read from the declaration, as JB8's is | **review only** |
| BR5 | Backups are encrypted, in a different failure domain (`region`, `account`, or both), and retained between a declared floor and ceiling with `drill.cadence ≤ floor` and `ceiling ≤ erasure_horizon`; deletion past the ceiling is the destination's lifecycle rule | encryption and failure domain are **schema-decided**; the two retention relations and the cadence relation are **arithmetic rules the runner checks**, each with its own rejection case; that the declared failure domain is the deployed one is BR3's review question again | **review only** |
| BR6 | Erasure survives a restore: an erasure ledger entry per `erasure-ledger.schema.json`, written in the erasure's transaction and copied through the outbox to the backup domain; after any restore every entry newer than `as_of` is replayed, reading the copy, before the service reports ready; audit events are redacted, never deleted | the entry is **schema-decided**, seven `ledger` cases. The replay is **decided by the `restore` scenario** and **both restore cases are verified detectors**: an implementation that reports ready before replaying fails exactly the at-readiness case; one that reads the ledger from the restored table fails both. That the table row shares the erasure's transaction is a call-graph fact (PC4) and stays a review question | **review only** |
| BR7 | A restore is a deployment: restore every primary store to one `as_of`, migrate forward, replay the ledger, rebuild derived stores, roll out with readiness gating traffic; `recovery.restore` is an operator-triggered single-flight idempotent job that emits an audit event; what is lost after `as_of` is stated and its reconciliation named in the runbook | the order is observable at the boundary — the restore case asserts the schema is at the release's version when replay runs and that erased rows are absent at readiness — and is the same `restore` scenario; the audit event is 080 AE5's enumeration; the reconciliation of post-`as_of` effects is a review question on the runbook | **review only** |
| BR8 | Recovery of an environment is a runbook in the repository's operations documentation at the path the declaration names, and the drill executes its commands | the path's presence is a file-exists check beside the schema (proposed, same job); that the runbook's steps and the drill's steps are the same steps resists a checker and is the review question stated in the rule | **review only** |

The corpus was run before landing: sixteen declaration cases (four of them
arithmetic rejections the schema cannot make), seven ledger cases and ten
drill cases reproduce their expected results against a reference
implementation. The two restore detectors were checked against deliberately
weakened implementations: one that flips readiness before replaying fails
exactly the at-readiness case and passes the other nine; one that reads the
erasure ledger from the restored table rather than from its copy in the
backup domain fails exactly the two detector cases and passes the other
eight. A third weakening, a freshness check that reads the newest run of any
outcome rather than the newest `succeeded` one, fails exactly the
failed-drills case, which is 057 JB8's success-not-attempts rule caught at
this standard's boundary.

Two rows above change as a result of this standard: SD9's deferral of backup
and restore to the roster now resolves to BR1 through BR7, and AE7's redaction
is re-applied after a restore by BR6's replay rather than assumed to survive
one.

## Secrets standard

Rules from [`032-secrets.md`](032-secrets.md) — how a secret reaches a
process, what is declared about it, where it may never be, how it is rotated,
and what a leak response is. The declaration is a schema; redaction and the
repository scan are decided by running an implementation against the corpus;
the leak response reuses the audit contract's schema, so an event that
violates AE2 or AE4 fails those rows too.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SE1 | A secret reaches a process as an environment variable or a file at a declared path, placed by the platform before start; application code never fetches one through a vendor SDK; a declared secret absent at start blocks serving (SC3) or exits `78` (WK4) | the absent-at-start half is SC3's lifecycle corpus case and WK4's `one_shot` case (`missing variable exits 78`); the no-fetch half **resists a checker honestly** — a call-graph fact PC4 keeps a gate away from. Review question: *what process talks to the secret store, and is it the application?* | **review only** |
| SE2 | Every secret a service's processes read is declared per `secret-declaration.schema.json`, with id, kind, delivery, purpose, backing service, owner, issuer, age, rotation and images; an undeclared secret in the environment is a finding | **schema-decided** — thirteen `declarations` corpus cases under `job-contract-conformance`; the environment-vs-declaration diff is a live check in `job-image-starts` (proposed `check-secret-declaration`) | **review only** |
| SE3 | The variable is `<SUBJECT>_<KIND>` with a closed kind set; an environment name is never the leading segment | **static and decidable** — the `secretName` pattern over every variable the declaration and `.env.example` list (fifteen `names` cases, one recorded as passing because the grammar cannot know a subject is vague); whether the subject names a real backing service is a review question | **review only** |
| SE4 | No secret value in the repository at any point in history; `.env` ignored, `.env.example` names and placeholders only; a scanner blocks every push; a value found in history is leaked, not deleted | the scanner is the gate (class of tool, run in CI and as push protection); `forbidden_locations` corpus cases for tracked paths and `.env.example` lines, **one a verified detector** — a low-entropy real value an entropy-only scanner passes | **review only** |
| SE5 | Never in an image, a log line, a URL or an error body; the emitter redacts by declared value first, by field name second, by shape only as a backstop | the Dockerfile half is **a grep with no false positives** (`ENV`/`ARG` naming a secret-grammar variable; proposed `check-image-secrets`); the log half is the `redaction` corpus against a running emitter under `job-contract-conformance`, **one case a verified detector** — a passphrase-shaped secret a shape-filtering redactor misses; the URL and error-body halves are HA3's problem+json validation plus review | **review only** |
| SE6 | One credential per backing service per service (the migration credential the designed exception); each image carries the least its jobs declare and the migrate image shares no secret; platform-issued before static | the migrate-alone rule is **schema-decided**; the one-credential count is a runner check over the declaration (corpus case); the image set against `images` is checkable once credentials are declared per image, which this declaration is — the row WK8 and SD13 were waiting on; platform-before-static is a review question on each `issued_by: static` | **review only** |
| SE7 | Every static secret has an owner and a `max_age_days` (default 90, ceiling 365); rotation is `restart` or `dual_window` with a procedure in the operations docs; a stale or never-rotated secret is a finding | the age and mode are schema-decided; the freshness comparison is four `rotation` corpus cases and, live, a check reading the platform store's rotation dates against the declaration (proposed `check-secret-freshness`); that the procedure is followed rather than worked around is review | **review only** |
| SE8 | A leak is rotated first, investigated second, audited as `secret.rotate`/`secret.revoke` with the secret as target by declaration id and no value in the event; history is never rewritten; handover rotates every secret the repository ever referenced | the event shape is **decided by `leak_response` corpus cases** against `contracts/audit/event.schema.json` plus the no-value scan; the order of operations and the handover rotation are review questions, stated as such | **review only** |
| SE9 | Development uses development backing services with credentials minted by the file that starts them; `.env.example` is the contract and matches the declaration; pipeline credentials are the CI store's, least-privilege, OIDC-federated where possible, never printed | the `.env.example`-matches-declaration diff is a static check beside SE2's; the compose admission is two `forbidden_locations` cases; that a development credential grants nothing outside the developer's machine is review | **review only** |
| SE10 | One secret store per platform (versioned values, an access log naming the principal, per-environment and per-service scoping); the store renders into the environment by the runtime's own mechanism class — an operator or driver syncing into an orchestrator's native secret object, native injection on managed container services, an agent rendering the unit's environment file or credential directory — on the platform's side of the variable; the repository ships a mapping of declared name to store path and never a value; encrypted secret files in the repository are not a store | the mapping's names against the declaration is the same gate as `.env.example`'s (SE2, SE9); a value in the mapping is SE4's scanner; that the mechanism is one from the table and that the application process holds no store credential are review questions (a call-graph and a platform fact, PC4). Which implementations meet the four properties is [`../solutions/032-secrets.md`](../solutions/032-secrets.md)'s and carries a date, not a gate | **review only** |

The corpus was run before landing: fifteen name cases, thirteen declaration
cases, nine redaction cases, fourteen forbidden-location cases, four rotation
cases and four leak-response cases all reproduce their expected results
against a reference redactor, scanner and freshness check. Both detectors were
checked against deliberately weakened implementations: a redactor that filters
declared values through a shape test before honouring them passes eight of the
nine redaction cases and fails exactly the passphrase; a scanner that knows
the placeholder grammar but decides "real value" by entropy passes thirteen of
the fourteen forbidden-location cases and fails exactly `SMTP_PASSWORD=hunter2`.

Three rows above change as a result of this standard: SC3's row gains the
secret half of its declared-variables check; WK8's and SD13's credential facts
become checkable against `images` and `backing_service` in the declaration;
SC2's row can name the redaction corpus for its no-secret half.

## Feature flags standard

Rules from [`038-feature-flags.md`](038-feature-flags.md) — the evaluation
API, the declaration and its lifetime, the default, the boundary with
authorization, the context, and the sweep. The evaluation API is an
OpenFeature profile, so FF1 binds to a specification rather than an
invention; the declaration, the context and the browser's evaluated set are
schemas; the default rule and the authorization boundary are decided by
running an evaluation boundary against the corpus.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| FF1 | Application code evaluates through the OpenFeature evaluation API; the provider is set from configuration at start; a vendor SDK is only ever a provider; an evaluation never throws; a provider down is `degraded`, never `503` | **resists a checker at its own level** — whether domain code imports a provider is a fact about source, and a gate reading source for it is the PC4 violation. The observable halves are live: the startup line names the provider (`job-image-starts`, proposed), and `/readyz` stays `200` with the provider unreachable (SC6's gate) | **review only** |
| FF2 | Every flag is declared in the repository against `flag-declaration.schema.json`; the declaration is built into the image; an evaluation of an undeclared flag is a finding and never reaches the provider; flag names and permission strings are disjoint sets | **schema-decided** for the file: fifteen `declarations` cases. **One `evaluation` case is a verified detector** — a provider holding a flag no declaration names, which an implementation that asks the provider first answers from the provider and passes every other case. Disjointness is an intersection of two committed sets (proposed `check-flag-names`) | **review only** |
| FF3 | Four kinds: `release` and `experiment` carry `expires` and `removal`, `operational` and `entitlement` carry `review_by`; `expires` is at most 180 days after `created`; the day after either date the flag is a finding | the kind-conditional fields are **schema-decided**; the 180-day horizon and the date comparison are decided by the `expiry` corpus part, seven cases (proposed `check-flag-declarations`, static over one committed file). That a kind was chosen honestly is a review question | **review only** |
| FF4 | Every boolean flag defaults to `false` and is named for what `true` turns on; the call site's default is the declared default; every failure returns the declared default with `reason: ERROR` and the specification's code, logged once per flag per process | the boolean default is **schema-decided**. **One `evaluation` case is a verified detector**: the provider unavailable, which a fail-open implementation answers `true` and passes every case in which the provider is up. A call-site default disagreeing with the declaration is an `evaluation` finding case. Whether a non-boolean default is the shipped variant is a review question | **review only** |
| FF5 | A flag decides whether a capability is shown or wired and never whether a subject is allowed; an `entitlement` flag is evaluated beside a permission, never instead; a flag appears in no grant, role, `/me` permission list or `check` argument; flag on and permission denied is `403`; flag off is `404` | **decided by the `gating` corpus** — four cases. **One is a verified detector**: entitlement on and permission denied, which an implementation treating the flag as authorization serves and passes the other three. `check-flag-names` (FF2's) catches a flag name in the permission set | **review only** |
| FF6 | The evaluation context is `targeting_key`, `tenant_id`, `user_id`, `environment`, `release_version`, `service` and a flat `attributes` map; never an email, a name, an address, an IP, a birth date or free text; ids are public ids | **schema-decided** by `evaluation-context.schema.json` at the platform hook: ten `contexts` cases, including the key denylist, the `@`-in-value rule and a nested object. The denylist catches spellings and not the property, so *would this attribute identify a person* stays the review question on every new attribute | **review only** |
| FF7 | Flags are evaluated by the server; the browser receives an evaluated set per `evaluated-set.schema.json` in the application configuration; the anonymous bootstrap carries only global flags; no provider credential in the bundle; a change takes effect on the next load or a documented refresh | the served document is **schema-decided** (four `evaluated_sets` cases) under `job-image-starts`; the no-credential half is WC2's proposed `check-bundle-config` grep for a provider hostname or SDK key in the build output. That the client renders from the set rather than evaluating rules is a review question | **review only** |
| FF8 | Every evaluation is a `feature_flag.evaluation` event on the request's span with the OpenTelemetry attributes; never a log line per evaluation; the provider at start, the first error per flag per process, and a pushed change are logged with the flag's name in a field | the attribute names are checkable against the semantic conventions where the propagation corpus runs live (040's `job-contract-conformance`); the no-line-per-evaluation rule is a review question on every diff that logs | **review only** |
| FF9 | Values live in the provider, existence in the declaration; the provider is attached by configuration, one of three admitted shapes stated in Conventions; the file provider's overrides are SC3 variables named `FLAG_<AREA>_<FLAG>`; no process holds another service's provider credential | the Conventions declaration is a grep; the variable naming is `check-service-contract`'s (SC3, proposed); the credential half is the per-image credential fact WK8's row waits on | **review only** |
| FF10 | Assignment is a pure function of flag name and targeting key; exposure is recorded once per subject per experiment as an `experiment.exposed` event through the outbox; an experiment expires with a decision in `removal` | the `experiments` corpus part decides determinism and once-per-subject recording against a repository's assigner; that the event goes through the outbox is AM4's row; the decision is a review question at expiry | **review only** |
| FF11 | Removal is one change: declaration, call sites and dead path together; `flags.sweep` is a periodic job under 057 with `stale_after`, reporting each overdue flag by name, owner and removal condition; the same comparison runs as a CI check on the declaration file | the CI half is `check-flag-declarations` (FF3's, proposed); the job's declaration is JB3's schema and its staleness is JB8's alert. A declaration with no call site resists a checker honestly — a grep for the name finds the common case and misses a generated accessor — and stays a review question | **review only** |

The corpus was run before landing: fifteen declaration cases, ten context
cases, four evaluated-set cases, ten evaluation cases, four gating cases,
two experiment cases and seven expiry cases all reproduce their expected
results against a reference evaluation boundary, and the three detectors
were checked against deliberately weakened boundaries. The fail-open
boundary — `true` on provider error — fails exactly the provider-unavailable
case; the provider-first boundary — asking the provider before the
declaration — fails exactly the undeclared-flag case; the
flag-as-authorization handler fails exactly the entitled-and-denied case;
each passes everything else.

## Notifications standard

Rules from [`058-notifications.md`](058-notifications.md) — the notification
record, the decide-send-status pipeline over 055 and 057, consent and the
floor, suppression, templates, render-time authorization, the provider
adapter, and the in-app channel. The record, the preference and the category
declaration are schemas; the decide, unsubscribe and render rules are decided
by running an implementation against the corpus.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| NF1 | A notification is a message to a person with an identity record, through one of five channels, about a 055 event; operator alerts and audiences without an identity record are not notifications | — resists honestly: whether a message is to a person or to a rota is judgment. Review question: *who is the recipient's identity record, and which event caused this* | **review only** |
| NF2 | The pipeline is `notify.decide` (per-event, idempotent on the event's `(source, id)`), `notify.send.<channel>` (idempotent or `at_most_once` per JB2, never `at_least_once` for transactional), and the provider's status webhooks re-enveloped under AM8; `notification.release` and `notification.purge` are periodic; all run in the pool with the provider credential in no server image | the job declarations are JB3's schema and WK2's image set; `status-events.json` fixes the event types and transitions; that decide writes rows and messages in one transaction is AM4's call-graph question | **review only** |
| NF3 | One record per recipient per channel per event in the service's database, closed shape, no address and no body; a suppressed row names its reason; retention declared per category; the notification id in every log line and never the body; a transactional failure is an alert | **schema-decided** — `notification.schema.json` under `job-contract-conformance`: sixteen `records` cases including the address, body, missing-provider, missing-reason and security-by-preference rejections. Log fields are checkable against the OC4 block; the alert is platform configuration | **review only** |
| NF4 | The recipient is a user public id; the address is resolved at send time from the identity record, referenced by `address_id` where a specific one is meant; optional notifications go only to a verified address, transactional may reach an unverified one | the no-address half is schema-decided (closed property set); `channelAddress` shape is schema-decided; the verified rule is decided by three `decide` cases. That the send job resolves rather than caches the address is a review question | **review only** |
| NF5 | Two classes; declared categories with `security` required and `marketing` opt-in; consent per category per channel; a transactional preference switches channel only while one remains; RFC 8058 one-click on every optional email, `Auto-Submitted` on every notification email, neither unsubscribe header on transactional; `GET` changes nothing | **decided by three corpus parts**: `category-declaration.schema.json` and `preference.schema.json` for the declarations, eight `decide` cases for consent and the switch, nine `unsubscribe` header cases and four endpoint cases. **One endpoint case is a verified detector**: an implementation that withdraws consent on `GET` fails `a-get-on-the-unsubscribe-link-changes-nothing` and passes everything else. Whether a category's class was chosen honestly is a review question | **review only** |
| NF6 | The floor: new-device sign-in, credential or second-factor change, contact change (to old and new), privileged role granted, export and deletion requests notify on every declared channel with no preference, quiet hours or rate limit consulted | **decided by the `decide` corpus, and its case is the verified detector**: `a-preference-cannot-suppress-the-security-floor` fails an implementation that treats `security` as one more transactional category and channel-switches it, which passes every other case. The schema refuses a `security` row suppressed by preference and a `security` preference row. That the product's list of privileged roles is complete is a review question | **review only** |
| NF7 | A hard bounce suppresses the address for every class, a complaint suppresses optional, a soft bounce suppresses nothing; suppression clears only on re-verification; an erased subject produces no row and no address is retained | five `decide` cases (bounce on the floor and on optional, complaint on each class, erased subject) and the `channelAddress` schema. That the status-event consumer sets suppression is a live test against the webhook endpoint (proposed) | **review only** |
| NF8 | Templates are files versioned with the code, rendered deterministically from id, version, locale, zone and payload; BCP 47 and IANA zone from the recipient; per-channel limits enforced at render; every template renders in every supported locale in CI | locale and zone formats are schema-decided (two `records` rejections); the render-in-CI rule is a test job a checker can see exists (proposed `check-templates`); purity of the render and the limits table are review questions | **review only** |
| NF9 | `check(recipient, permission, scope)` at send time against the subject, per template field; links to authenticated routes; single-use short-lived tokens with the unsubscribe token the stated exception | **decided by the `render_authorization` corpus**: four cases including the required-field refusal. Link targets and token lifetimes are a review question on every template | **review only** |
| NF10 | Collapse per key within the declared window; optional rate-limited per channel per day; quiet hours in the recipient's zone for optional only; `in_app` never deferred; transactional never deferred or limited; digests are periodic jobs | **decided by the `decide` corpus**: seven cases, including the Berlin/Los Angeles pair at one instant that fails an implementation evaluating quiet hours in UTC or the server's zone | **review only** |
| NF11 | One adapter interface per channel (`send`, `verify`); idempotency key is the notification id; adapter chosen by configuration; provider credential only in the pool and jobs images; provider webhooks verified inside the adapter per AM8; no vendor SDK in domain code | the credential placement is WK8's credential fact; the webhook handling is AM8's `signing` and `delivery` corpora; the no-SDK rule **must not** be gated — a checker reading imports is the PC4 violation — and is the review question | **review only** |
| NF12 | `in_app` records served by the service's API: cursor-paged list with `unread_count`, per-record read state, SSE stream as a hint with the list as the truth, rendered per request in the viewer's locale and zone, tenant-scoped | HA4's pagination and HA1/HA2's SSE rows cover the API shape; the `in_app` schema rules (no provider, `read_at`) are `records` cases; that the list is the truth and the stream a hint is a review question | **review only** |

The corpus was run before landing: twenty-seven record cases, twenty-four
decide cases, thirteen unsubscribe cases and four render cases all reproduce
their expected results against a reference implementation, and the two
detectors were checked against deliberately weakened implementations. A decide
that consults preferences before asking whether the category is the floor
passes twenty-three decide cases and fails exactly the one it exists to catch,
by channel-switching a new-device sign-in away from email; an unsubscribe
endpoint that withdraws consent on `GET` passes every other unsubscribe case
and fails exactly `a-get-on-the-unsubscribe-link-changes-nothing`. The quiet
hours cases were computed with the IANA database, not typed, so an
implementation proves its zone arithmetic against them.

## Data subject rights standard

Rules from [`082-data-subject-rights.md`](082-data-subject-rights.md) — the
inventory that says where personal data is, the request resources through
which a person asks for a copy or for removal, the package, the erasure job
and what survives it, and the hold. The inventory, the request and the
manifest are schemas; the erasure, export, hold and transition behaviours are
decided by running an implementation over one fixture.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| DR1 | Every store holding personal data is declared per `inventory.schema.json`, one entry per subject column, with a `none` entry for stores holding no personal data; a catalog table with no entry is a finding | **schema-decided** for the declaration (eight `inventory` cases) and **catalog-decided** for completeness: the `coverage` corpus part enumerates tables the way 025 SD6's gate does and names the undeclared table, the unknown column, the dangling `via`, the duplicate membership entry and the column with no tombstone (proposed `check-data-inventory`) | **review only** |
| DR2 | Both rights are request resources with one status machine, one problem-type set, one open request per subject per kind, `Idempotency-Key` on creation, and step-up verification within fifteen minutes for erasure; a request open past its 72-hour deadline is an alert | the resource is **schema-decided** (eight `requests` cases: each status requires and forbids its fields); the `transitions` part decides the step-up refusal, the open-request `200`, the cancellation rules and the download route under `job-contract-conformance` (proposed); that the deadline alert is wired is platform configuration read from the request table | **review only** |
| DR3 | The export is a zip of JSON Lines per exported entry plus a manifest and the subject's objects, built by a per-event job, bounded by tenant, free of internal keys, credentials and third-party columns, streamed through the download route as an attachment and deleted after seven days | the manifest is **schema-decided** (four `export` manifest cases); the package contents are decided by the `export` build cases — file list, counts, column sets — against a repository's builder (proposed, same job); whether an `export: false` has one of the three admitted reasons is a review question | **review only** |
| DR4 | Fourteen days of cancellable grace, a periodic dispatcher and a per-event erasure job, entries treated children before parents in keyset batches, scoped rows for the tenant and global rows when the last membership goes, `revokeAppAccess` and never identity deletion | the treatment order and the tenant-and-membership boundary are **decided by the `erasure` corpus** (`entries-are-treated-children-before-parents`, `erasure-is-bounded-by-tenant-…`); the grace mechanics by the `transitions` dispatch cases; that suppression runs first and revocation runs last is a sequence a boundary does not show, and stays a review question | **review only** |
| DR5 | Three treatments; anonymisation is an allowlist over structural columns with a fixed tombstone rule; `retain` needs a closed-set kind, a reference and an expiry, and is reduced at erasure time and purged at expiry; the audit store is anonymised with the AE7 stamp, never deleted | **decided by the `erasure` corpus, and two cases are verified detectors**: an implementation that scrubs identifying columns by name fails exactly `anonymise-is-an-allowlist-not-a-denylist`, and one that deletes every dependent row fails exactly `audit-rows-survive-redacted-by-subject`; the retain and purge cases cover the rest. Whether a treatment is the right one for its data and whether a basis is real are judgments | **review only** |
| DR6 | A legal hold suspends every deletion for its subject — erasure and retention purge — and never export or cancellation; placing and releasing are audited; the hold is visible on the request by id and instant; a hold past `review_at` is a finding | **decided by the `hold` corpus** (four lifecycle sequences) and the `held` conditionals of `request.schema.json`; that a hold is reviewed is a review question, stated as one | **review only** |
| DR7 | Every erasure ends by writing the `data_subject.erase` audit event, already conforming to AE7, and the 028 ledger entry, in the last batch's transaction; `completed` requires both ids in `result` | the `result` requirement is **schema-decided** (`a-completed-erasure-without-its-result-is-rejected`); that the two writes share the last batch's transaction is a call-graph fact PC4 keeps out of a gate, and is the review question on the job | **review only** |
| DR8 | A tenant leaving is `tenant.offboard`: reduce then drop under one-database-per-tenant, an enumerated erasure over every scoped table under row-level isolation; subjects with other memberships keep their rows there | the row-level half is the same enumeration SD6's gate performs and the same treatments the `erasure` corpus decides; the one-database half is an operator runbook, and that it exists is a review question | **review only** |

The corpus was run before landing. Eight inventory cases, six coverage cases,
eight request cases, seven erasure cases, seven export cases, four hold
sequences and twelve transition cases all reproduce their expected results
against a reference implementation, and the two DR5 detectors were checked
against deliberately weakened implementations: the one that scrubs columns by
name (email, name, phone, ip, user agent) passes every erasure case but the
allowlist case, where it leaves a free-text notes field carrying a phone
number; the one that deletes every dependent row and reduces only the
subject's own passes every erasure case but the audit case, where it removes
the trail 080 AE4 says outlives its subject. Each fails exactly the case it
exists to catch.

Three rows above change as a result of this standard: SD12's soft-deleted
personal data and AE7's redaction now have a document to point at instead of
the roster row, and 028's erasure ledger has the standard that writes it.

## Security baseline standard

Rules from [`085-security-baseline.md`](085-security-baseline.md) — what a
deployed service has before its domain is considered: what its image is built
from, what is scanned, which headers every response carries, where TLS and
rate limits apply, how input is bounded, how a finder reports, and what a
release says about its contents. Secrets are [`032-secrets.md`](032-secrets.md)'s
and register there. The header set is data, the pin grammar and the acceptance
entry are schemas, and the disclosure policy is a schema over the sections a
checker extracts from the markdown.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SB1 | Every `FROM` line names its image by digest with the version in-band as the tag or in a trailing comment; `scratch`, a declared stage and `--platform` are the only exemptions; a build-argument reference is refused; build stages included | **static and decidable with no false positives** — an extension of `check-ci-conformance` PIN reading every `FROM` in every Dockerfile against `base-image.schema.json`'s grammar (proposed `check-ci-conformance` FROM); thirteen `from-lines` corpus cases, one a verified detector for a checker that reads only the first `FROM` | **review only** |
| SB2 | Lockfile, reachability and image scans as shared jobs, each failing when it cannot run; new findings block from day one; an acceptance is an OSV id with a reason and an expiry, the window at most ninety days, an expired entry a finding | the entry shape is **schema-decided** by `acceptance.schema.json` read from each scanner's native file (proposed `check-scan-acceptances`); the calendar half is two `scan-acceptance` corpus cases; `job-osv-scan` and `job-go-govulncheck` exist, `job-image-scan` is proposed between `job-image-build` and `job-image-starts`. Whether a reason is true stays a review question | **review only** |
| SB3 | Three response classes — document, API, asset — each with a fixed header set per `response-headers.json`; strict nonce-plus-`'strict-dynamic'` CSP on documents, an inert CSP on API responses, HSTS with `includeSubDomains` everywhere, `no-store` on documents and authenticated API responses; `X-XSS-Protection` and `X-Powered-By` never sent, `Server` without a version, `X-Frame-Options` never a substitute for `frame-ancestors` | **live and cheap** — `job-image-starts` already requests `/readyz`; asserting the API-class set on that response and the document-class set on `/` is one more assertion in a job every repository calls (proposed). Twenty-one `headers` corpus cases, **two verified detectors**: `X-Frame-Options` without `frame-ancestors`, and HSTS without `includeSubDomains`. A header delegated to the edge is declared in Conventions and is a live check against the deployed environment, and whether it is actually set there is the review question | **review only** |
| SB4 | TLS on every hop that leaves a network the service owns, backing services included; TLS 1.2 floor, 1.3 preferred, Mozilla intermediate profile; certificates from the platform, never in the image, delivered as a secret file where the server terminates | the protocol floor and cipher profile are observable from outside with one handshake per listener (proposed live check); a private key in an image is a secret-scanning finding under the secrets standard; whether a hop declared private is private **resists a checker honestly** and stays the review question on the Conventions entry | **review only** |
| SB5 | Every unauthenticated route and every authentication route is rate limited, per address and per presented identifier, at stated floors; the refusal is 050 HA7's `429` with `Retry-After` and the RFC 9457 envelope | the refusal shape is 050 HA7's corpus case under a live harness; that a limit exists on an unauthenticated route is a live test that sends more than the floor (proposed); whether the floors were chosen rather than defaulted is a review question | **review only** |
| SB6 | Request bodies, query and path parameters are validated against the OpenAPI document before a handler runs and refused with the HA3 `errors` array; unknown request fields refused; `415` on an undeclared content type; 1 MiB JSON body, 32 levels, 8 KiB query string, refused with `413`/`414` before parsing | the size bounds and the unknown-field refusal are live behaviour cases (proposed, same harness as HA6/HA7); that the schemas the service enforces are the ones the document publishes is HA2's unfixable half and stays a review question | **review only** |
| SB7 | `SECURITY.md` at the root with Reporting, Response (numbers inside the three-day and fourteen-day ceilings), Scope, Safe harbour and Disclosure sections; `/.well-known/security.txt` per RFC 9116 on every served origin; the channel changed at handover | **schema-decided** by `security-md.schema.json` over the sections a checker extracts (proposed `check-security-md`); six corpus cases; `security.txt` presence and `Expires` within a year are a live request against the started image; that the channel is monitored is a review question | **review only** |
| SB8 | A CycloneDX 1.6 JSON SBOM per image, generated from the built image in the build run, attached to the release under `<image>.cdx.json` and pushed as an OCI referrer where supported | presence is a release fact: `job-version-release` can assert one asset per image the run built (proposed); that it was generated from the image rather than the source is a provenance fact the job itself controls once it generates it | **review only** |
| SB9 | Least privilege is stated by 000 Terms, 032, 035 WK8, 025 SD3/SD9/SD13 and 080 AE6; this rule adds that the process in every runnable image runs as a non-root `USER` with a filesystem writable only where declared | `USER` is read from the same file SB1's checker reads, in the same pass (proposed, same extension); not yet in the corpus and this row says so; the writable-filesystem half is a runtime configuration fact | **review only** |
| SB10 | Security-relevant acts audit under 080 AE5 and notify under the notifications standard's floor; leak response is 032's; this rule adds nothing | — a pointer rule; enforced by the rows it points at | **review only** |

The corpus was run before landing. Twenty-one header cases, thirteen
`FROM`-line cases, ten acceptance cases and six disclosure-policy cases
reproduce their expected findings against a reference implementation driven
by `response-headers.json` and the three schemas, and the three detectors
were checked against deliberately weakened implementations: a header checker
that lets `X-Frame-Options` satisfy the framing requirement fails exactly the
one case it exists to catch and passes the other twenty; a header checker
that tests HSTS for presence and `max-age` alone fails exactly the
`includeSubDomains` case; a `FROM` checker that reads only the first `FROM`
fails exactly the multi-stage case whose runtime stage is the unpinned one.
