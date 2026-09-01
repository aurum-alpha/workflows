# The platform contract

One of the Aurum Alpha engineering standards — read
[`../STANDARDS.md`](../STANDARDS.md) for the charter this is written under,
and [`enforcement.md`](enforcement.md) for the tier each rule below actually
holds.

This document states the doctrine every application-layer standard is written
under: what form a fleet opinion about a platform capability is allowed to
take. The capabilities themselves — authentication, logging, jobs, audit, and
the rest — each get their own standard, tracked in this repository's issues
and indexed in the roster below. This document is the constitution those
standards are drafted against, the same way the charter is the constitution
for this one.

## Why this exists

Full-stack meta-frameworks have the right diagnosis. Authentication, RBAC,
background jobs, audit trails, observability, admin surfaces — every product
needs them, none of them differentiates a product, and an organisation that
re-derives them per product ships worse versions of all of them. A framework
answers each once and hands you the answer. That instinct — an opinion for
everything, decided once — is correct, and this standard exists to keep it.

What a framework gets wrong, for us, is the delivery vehicle. The answers
arrive as a CLI, a runtime library, and a deploy tool. Three consequences,
each fatal at fleet scale:

- **The library is a dependency the application can never leave.** Every
  generated app imports the framework's auth, jobs and observability at
  runtime; the framework's upgrade schedule becomes every product's upgrade
  schedule, and its abandonment becomes every product's problem.
- **One-shot generation locks in and drifts at the same time.** Scaffolded
  code is owned by the app and immediately starts diverging from the framework
  that emitted it, while still depending on its runtime — locked in *and*
  diverged, so upgrades become archaeology.
- **The framework's language decides the fleet's.** This fleet is Go,
  TypeScript, PHP and embedded C++. A library was never available as the
  fleet-wide answer to anything.

The charter already names the failure in the abstract: *a standard that only
works while a particular repository is reachable is not a standard, it is a
dependency.* A framework is that failure with a vendor attached. The remedy is
not fewer opinions — it is the same density of opinion, delivered in a form
that binds a Go service and a PHP service equally and keeps binding after
handover.

One more thing changed the economics. Frameworks cache opinions in generators
and libraries because boilerplate was expensive for people to write. Coding
agents write most of this organisation's code now, and for an agent the
scarce input is not scaffolding — it is a precise statement of what the output
must look like, and a gate that fails when it doesn't. A generator is a frozen
cache of an opinion. A specification with a conformance test *is* the opinion,
executable by any agent in any language, and it fails loudly when violated —
which is the charter's law, applied to the application layer.

## The rules

### PC1. An opinion is a contract, never a tool

A fleet answer to a platform capability is a **protocol** (behaviour stated at
a boundary: an endpoint, a message, a log line, an environment variable) or an
**interface specification** (a data model and operations with defined
semantics, implementable in any language). It is never a CLI an application's
lifecycle depends on, never a framework, never a shared runtime library an
application must import, never a deploy tool.

The corollary for what this repository may ship: **fleet tooling verifies, or
copies once.** A checker that fails a build, a conformance suite that runs a
corpus, a template that is copied at a repository's birth and never consulted
again — all allowed. A generator that stays attached to the application, a
tool that owns deploy, a runtime the fleet imports — not allowed, whoever
writes it. Building the framework in-house does not fix the framework problem;
it relocates it to a vendor we have to staff.

### PC2. Standard protocol first, profile second, internal contract last

Where an industry standard suffices — OIDC for identity, OTLP for telemetry,
W3C trace context for propagation, RFC 9457 for HTTP errors — the fleet
adopts it, as a **written profile**: the document pins the choices the
standard leaves open, because "we use OIDC" unpinned is four implementations
waiting to happen.

This holds for methodologies as much as wire protocols. **The
[twelve-factor app](https://12factor.net/) is the foundation under most of
this roster**, and a capability standard that restates a factor cites it and
pins what the factor leaves open, rather than re-deriving it in house style —
see the charter's *The foundation: twelve-factor* for the citation rule and
the one open tension.

An **internal contract** is invented only where no standard suffices, and the
capability's standard says why — naming the candidate that was evaluated and
the reason it fell short. An internal contract invented where a standard
existed is a second answer to a solved question, which is the failure this
whole repository exists to prevent.

### PC3. A contract is stated in artifacts, not prose alone

Each agreed capability contract carries, under `contracts/<capability>/` in
this repository:

- **The model** — schemas for its data shapes (JSON Schema for messages,
  events and log lines; OpenAPI fragments for endpoints).
- **The operations** — where the contract is interface-level, signatures with
  defined semantics, stated language-neutrally.
- **The conformance corpus** — test cases *as data*: given-this-then-that
  files any implementation in any language must pass.

The corpus is the piece that makes a polyglot standard enforceable from one
source. Prose drifts from N implementations silently; a corpus fails the one
that drifted, by name. A capability standard without its artifacts is agreed
in principle and unenforceable in fact — the ledger row says which state each
is in.

### PC4. Gates check the boundary, never the implementation

A conformance gate runs the corpus against the implementation, hits the
endpoint, validates the emitted line. It never checks which package is
imported, which framework handled the route, or what the source looks like.
The moment a gate tests an implementation choice, the choice has become a
dependency and PC1 is broken by the enforcement mechanism itself. Any
implementation that passes the corpus is conformant, including one written
from scratch in an afternoon — that escape hatch existing is the point.

### PC5. A package conforms to the spec, never the reverse

First-party convenience implementations of a contract — a Go module, a PHP
package, an npm package — are allowed, so each product does not hand-roll the
same envelope parser. They are allowed under a standing rule and three guard
rails, and the standing rule is the title of this section: the spec and its
corpus are normative, the package is downstream. A behaviour change lands in
the spec first, in its own change, and the package follows.

- **One package per capability contract.** No `aurum-common`. A grab-bag
  package is the framework re-forming by accretion.
- **No fleet package depends on another fleet package.** The moment they
  stack, importing one means importing the pile, and the pile is a framework.
- **Every package release passes the contract's own corpus** — the same gate
  a bespoke implementation faces, because per PC4 the gate cannot tell them
  apart, and per this rule it must not.

A repository may substitute its own implementation of any contract and stay
green. At handover, a client repository that uses a fleet package vendors it,
exactly as it vendors the standards documents — which these packages survive
because each is small, single-capability, and corpus-defined.

### PC6. Contracts evolve additively

Every versioned shape (envelopes, events, log lines) carries a schema-version
field. Changes are additive — new optional fields, never a removed or
repurposed one. A breaking change is a new version, and the contract states
its deprecation window: how long implementations must accept the old version
while emitting the new. A fleet of specifications without a change discipline
re-creates the drift problem one level up, with the added indignity that the
documents were supposed to be the fix.

## The capability roster

Every platform capability the fleet has an opinion on, or has decided to
have one. **A capability's absence from this table is a claim that the fleet
has considered it and declined** — so a reader can distinguish "not yet
written" (a row saying so) from "not considered" (a gap in this table, which
is a defect in this document). A row gains its link when the standard lands;
the ledger tracks what is enforced. Where a capability has no document yet,
the work is an issue in this repository.

| Capability | The fleet answer takes the form of | Standard |
|---|---|---|
| Authentication | OIDC profile — the provider authenticates, identity claims only | not yet written |
| Authorization | Application-owned RBAC as a full interface spec: model, operations, semantics, corpus — never derived from token claims | not yet written |
| Configuration | [Factor III](https://12factor.net/config) profile: variable naming, fail-loud on missing, no environment detection in code | [`service.md`](service.md) SC3 |
| Secrets | Delivery convention — how a secret reaches a process; never a vendor SDK in application code | not yet written |
| Logging | [Factor XI](https://12factor.net/logs) profile: structured log-line schema to stdout; transport is the platform's problem | [`service.md`](service.md) SC2 |
| Health & readiness | Two-endpoint contract, fixed paths and shapes | [`service.md`](service.md) SC1 |
| Service lifecycle | [Factor IX](https://12factor.net/disposability) profile: SIGTERM means drain — readiness flips, in-flight completes, stated timeout | [`service.md`](service.md) SC4 |
| Runtime provenance | The running service reports the commit and build it is | [`service.md`](service.md) SC5 |
| Observability & context propagation | OTLP profile; W3C trace context; one id vocabulary across logs, traces, events | [`observability.md`](observability.md) |
| Service interfaces & HTTP APIs | Protocol selection (HTTP default, gRPC internal-only, SSE before WebSocket); OpenAPI description; RFC 9457 errors; pagination, versioning, idempotency keys, retry semantics; snake_case wire naming | [`http.md`](http.md) |
| Identifiers & primitives | Internal keys never exposed; public-id format table; RFC 3339 UTC; integer minor-unit money | [`identifiers.md`](identifiers.md) |
| Data layer | Migrations-only schema change; seeding contract; tenancy isolation rules | not yet written |
| Async jobs & messaging | Internal envelope contract; at-least-once plus dedupe; signed webhooks | not yet written |
| Maintenance jobs | The Job interface contract: registration, single-flight, run observability — and where it lands against [factor XII](https://12factor.net/admin-processes) | not yet written |
| Audit events | Event schema contract with required context fields | not yet written |
| Security baseline | Response-header set, scanning, image pinning, secrets doctrine | not yet written |
| Feature flags | Evaluation contract; standard-first (OpenFeature is the candidate) | not yet written |
| Notifications | Message contract over the async envelope; provider at the boundary | not yet written |
| Blob storage | S3 API as the storage protocol; reference, tenancy and upload rules | not yet written |
| Data subject rights | Export and erasure as endpoint contracts | not yet written |
| What a browser may hold | Session cookie only: no token in JavaScript or web storage, no provider credential in the bundle, a `401` answered by navigating. The authentication architecture itself is the authentication row's | [`web-client.md`](web-client.md) WC1 |
| Client configuration | Fetched from the server at load, never compiled into the bundle — [factor III](https://12factor.net/config) honoured through the server's environment, and build-once preserved | [`web-client.md`](web-client.md) WC2 |
| API client contract | One generated client module owning problem+json parsing, idempotency keys, bounded retries and cursor paging at the boundary | [`web-client.md`](web-client.md) WC3 |
| Presentation, formatting & i18n | The other half of the base-representation rule: viewer's locale and zone, `Intl` formatting, currency exponents | [`web-client.md`](web-client.md) WC4 |
| Frontend observability | The browser does not originate the server's trace; correlation by request id; a closed error-report shape | [`web-client.md`](web-client.md) WC5 |

Two rows deserve a word on why they are the worked examples:

**Authorization** is the model interface-level contract. Its standard defines
the domain model (subject, role, permission, grant, scope) as schemas, the
operations (`check`, `grants-for`) as signatures with semantics — deny by
default, how tenancy scopes a grant — and a corpus of decision cases: given
these grants, this check returns deny. Three languages implement it; one
corpus judges all three. When someone asks what "an interface spec, not a
library" means, the answer is that standard.

**Async messaging** is the model internal contract: no wire standard covers
it fully (its standard evaluates CloudEvents before inventing), so the fleet
defines the envelope — and the discipline PC2 demands is visible right there:
the invention is scoped to the envelope, while the identity inside it stays
W3C trace context, per the propagation profile.

## Enforcement

Every rule here is review-only today, honestly, with the gates named per rule in
[`enforcement.md`](enforcement.md):

- **PC1 and PC2 resist a checker** and stay review questions: what
  constitutes "a tool the lifecycle depends on" or "a standard that
  suffices" is judgment. The review question is stated, which is the honest
  version of unenforced.
- **PC3 gets `check-contract-artifacts`**: an agreed capability's
  `contracts/<capability>/` tree exists, schemas parse, the corpus is
  non-empty. Cheap, no false positives, promotable early.
- **PC4 gets `job-contract-conformance`**: a shared job that runs a
  capability's corpus against a repository's implementation, adopted
  per-capability as corpora land. This is the gate that matters — the one
  that fails the implementation that drifted.
- **PC5 gates in the package repositories**: every release runs the corpus,
  and a manifest check asserts no fleet package depends on another.
- **PC6 gets `check-contract-evolution`**: a schema diff on every change to
  `contracts/` — removed or retyped fields fail; a version bump with a
  stated window passes.

What no checker will prove: that an opinion was delivered as a contract
rather than smuggled in as a dependency. That stays a review question on
every capability standard, and this document is what the reviewer points at.

## Open work

- Land the per-capability standards from the roster, each by the charter's
  own path: issue, document, ledger rows, artifacts.
- The first corpus run in anger. Authorization is the candidate, as the
  worked example above argues.
- The template repositories — the copy-once mechanism PC1 permits — are
  follow-on work once enough contracts exist for a template to have
  something to conform to.
