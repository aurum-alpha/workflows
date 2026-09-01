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
| — | Standard pnpm version | `check-dependency-versions` | gated¹ |
| — | Shared lint config unedited (`.oxlintrc.json`) | `check-eslint-config` | gated¹ |
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
| IP1 | Internal integer keys never leave the service; addressable rows carry a separate opaque public id | schema-level column check, buildable once the [data-layer standard](000-platform.md#the-capability-roster) defines a readable schema; until then the stated review question | **review only** |
| IP2 | Public ids use an admitted format from the table (UUIDv7, nanoid profile, prefixed handle); UUIDv4-in-an-index needs a written defence | `job-contract-conformance` running `contracts/identifiers/corpus.json` (proposed) | **review only** |
| IP3 | Ids are opaque — equality only, no parsing meaning out of them | — resists honestly; review question on consumers | **review only** |
| IP4 | Instants are RFC 3339 UTC `Z` at one pinned fractional precision (default three digits, extendable to six or nine, never fewer); calendar dates are `full-date`; MySQL profile `DATETIME(3)` | corpus validity + canonical cases (proposed, same job) | **review only** |
| IP5 | Money is integer minor units + ISO 4217 code, together; floats never | corpus validity cases (proposed, same job) | **review only** |

IP2, IP4 and IP5 are exactly what a corpus can hold: their gate is the
platform contract's own `job-contract-conformance`, and the corpus already
exists, so promoting them is building the job, not writing the cases. IP1's
mechanical gate is named but waits on the [data-layer
standard](000-platform.md#the-capability-roster). IP3 resists a checker — what a
consumer does with an id after receiving it is not a fact on disk — and the
document states the review question instead.

## Observability standard

Rules from [`040-observability.md`](040-observability.md) —
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
| AE4 | An event is self-contained, immutable and outlives its subject: display denormalized at write time, append-only, no cascade from the target's deletion, values not references, never a credential | the shape half is schema-decided. That the store is genuinely append-only and uncascaded is a schema fact once the [data-layer standard](000-platform.md#the-capability-roster) gives a checker a schema to read; that no credential reaches `changes` is SC2's judgment again | **review only** |
| AE5 | The floor of what must emit: authentication and session lifecycle, authorization changes, identity lifecycle, destructive writes, security-posture configuration, bulk personal-data export — and reads otherwise **not** audited | **the generative gate, and the one worth the most here** — enumerate the routes guarded by a destructive permission, exercise each, assert an event carrying that permission as its action. Fourteen `floor` cases in the corpus describe the acts; two of them are negative | **review only** |
| AE6 | Append-only discipline is required — `INSERT` and `SELECT`, retention deletion under a separate credential. Hash chaining is **not** required; tamper-evidence needs an anchor outside the writer's reach | the grant is a schema fact, readable once the data-layer standard lands. That the request path holds no update is a review question | **review only** |
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
