# Aurum Alpha engineering standards

`aurum-alpha/workflows` is the definition of how this organisation builds
software: the standards themselves, and the shared CI infrastructure that
implements them — reusable workflows, composite actions, conformance checkers
and shared configuration. This page is the charter. It says what a standard is
here, what makes one binding, and indexes the rest. It states no engineering
rules itself — every rule belongs to a numbered document under `standards/`.

Not a convenience library of things several repos happened to need — the
answer, per language and per capability, that repos are standardized *onto*
rather than each arriving at independently.

That was already true of continuous integration, and the CI standard is the
worked example the rest of this follows: a document that states the rule and
the reasoning, a catalog that implements it once, and a checker that fails the
build when a repo drifts. The scope is now every layer of a product, not just
its pipeline.

**Two repos solving the same problem two ways is not diversity, it is the absence
of an opinion — and an organisation with no opinion re-litigates the same
decision every time someone starts a service.**

## What this is for

Every application faces two kinds of decision, and only one of them is its own.

Which pagination style, which error envelope, which identifier format, where
the session lives, what an audit row contains: real decisions, decided badly
more often than not, and **not decisions any particular product's problem has
an opinion about**. An invoicing system is not better or worse at invoicing for
having picked cursor pagination over offset. The choice still has to be made,
so each repository makes it alone, differently, and at the cost of an argument
that has already been had elsewhere.

The other kind is the domain: what an invoice *is* here, when it may be voided,
who is allowed to. That is the part a client is paying for and the only part
where a repository's own judgment is the right input.

So the purpose, in three steps:

1. **Remove the arbitrary decision from every repository, wherever the decision
   is not material to that application's purpose or domain.** Not to make the
   choices uniform for its own sake, but because a decision that could go
   either way should go one way once, here, with the reasoning written down.
2. **Which leaves each repository spending its judgment on business logic** —
   the domain, the workflow, the thing that is actually specific to it.
3. **Which is why this makes development faster, not slower.** A standards
   effort is assumed to be a tax. This one is the opposite: the decisions it
   removes were never free, they were being paid for repeatedly, in argument
   and in divergence, by people who had something better to think about.

That is also why the standards are written as contracts with conformance tests
rather than as advice. An arbitrary decision is only genuinely removed once
nobody has to remember it.

## Scope: internal and client work alike

These standards bind everything Aurum Alpha builds — the products we operate and
the systems we build for clients. A client engagement is not an exemption. It is
the case that matters most, because it is the code that leaves.

**A standard must survive handover.** A client repository follows these rules and
then, at handover, stops being able to reach this repository at all: no shared
job to call, no checker to run, no catalog to resolve. A standard that only works
while `aurum-alpha/workflows` is reachable is not a standard, it is a dependency.

Three consequences, and they constrain how every document here is written:

1. **State the rule, not just the mechanism.** A reader with no access to this
   repo must be able to read the rule, understand why it exists, and comply. The
   shared job is how *we* comply cheaply; it is never the only description of
   what compliance is.
2. **Every standard must be satisfiable without this repo.** Where a rule is
   normally met by calling a shared workflow, the document says what the
   workflow does in terms a person could reimplement.
3. **Handover is a copy, not a link.** A repository leaving the portfolio vendors the
   standards it was built to, so the rules travel with the code. What it loses is
   the updates, which is correct — it is no longer ours.

## The law

**A rule is not done when it is written. It is done when something fails if it
is broken.**

Every rule in the CI standard was written down first and violated afterwards, in
a repo whose CI was green the entire time, because writing a rule and enforcing
it are different acts and only the second one holds. A principle nobody can fail
is a preference.

That history also taught what *kind* of rule survives. Three rules failed the
same way in three disguises: one keyed on a file, one keyed on a filename, one
keyed on an outcome with no mechanism named. The common shape is that **a rule
naming anything other than the act itself stops applying the moment the act
moves.** Write rules against acts, then make something fail when the act is
wrong.

### Three tiers, and the difference between them matters

- **gated** — a violation turns that repo's required check red. This is
  enforcement.
- **audit only** — a checker exists but runs from a workstation when someone
  remembers. This is a habit, and habits are what drifted in the first place.
  Every one of these is a candidate for folding into the gate. A checker nothing
  runs does not degrade to weaker enforcement — it degrades to a checker that is
  itself wrong, silently.
- **review only** — nothing mechanical. Some rules resist automation honestly.
  Saying so is the point: an unenforced rule should be visibly unenforced, not
  quietly assumed. A rule that resists a checker gets the next best thing — a
  review question someone has to answer, not a line someone has to remember.

### A new standard's rules start review-only and name their gates

Landing a standard and landing its enforcement in one change is how standards
stall. So the sequence is fixed:

1. The standard lands with every rule registered in
   [`standards/999-enforcement.md`](standards/999-enforcement.md), at the tier that
   rule actually holds — for a new standard, usually **review only**.
2. Each rule names, in that ledger, **the gate it is eventually getting** — or
   states plainly that it resists one and will stay review-only.
3. Promoting a rule to gated is its own change, and the ledger row moves with it.

A rule that lands review-only with no proposed gate and no admission that it
cannot have one is not finished. That is exactly the failure the law above
describes, arriving one document earlier.

**The tier describes the rule's enforcement, never the document's standing.** A
merged document is binding — see the writing conventions below.

## The foundation: twelve-factor

**[The Twelve-Factor App](https://12factor.net/) is the ground these standards
are built on**, not a reference we consulted. Config in the environment, logs
as event streams, strict build/release/run separation, disposable processes
that shut down gracefully — most of what the CI standard and the platform
contract say about how a service behaves is twelve-factor, applied here
with the open choices pinned.

Two consequences for how these documents are written:

- **Where a rule restates a factor, the document cites the factor as its
  justification.** "Logs go to stdout because we said so" is a preference;
  "logs go to stdout per [factor XI](https://12factor.net/logs), because the
  application must not concern itself with routing or storage" is an argument
  a reader can check against a source older and more tested than we are.
  Claiming a well-known idea as a house invention also costs credibility with
  exactly the engineers we want reading these documents.
- **Where a rule departs from a factor, the document says so, in the rule,
  with the reason.** A silent departure is worse than a stated one: the next
  reader assumes we did not know.

What a standard here adds on top of a factor is the part twelve-factor
deliberately leaves open — the *specific* names, formats and endpoints that
let four languages interoperate. Factor III says config lives in the
environment; it does not say what the variables are called. That pinning is
ours, and it is the only part that is.

**Known departures: none today.** One tension that was open is settled the
way [factor XII](https://12factor.net/admin-processes) states it: admin and
management tasks run as one-off processes, and the jobs and workers
capabilities on the platform roster take exactly that shape, a one-shot worker
built from the same release as the servers, rather than an interface
registered inside a server. Their standards state that against factor XII
rather than around it.

## How these documents are written

Three conventions, because all three failures are quiet ones.

**A merged document is binding, and says nothing about its own status.** No
document carries a `Status: proposed` or `Status: agreed` header. Review happens
in the pull request; merging it is the approval. A status line on a merged
document is either wrong (it still says "proposed") or noise (it says "agreed",
which every merged document is). What varies per rule is how it is *enforced*,
and that lives in one place: the ledger.

**A document references other documents, never a tracker.** Relative markdown
links between `.md` files, always — a reference a reader can click and open,
not a name they have to go hunting for. An issue or pull request number in
doctrine is a citation to something a reader outside this repository cannot
open, that says nothing once merged, and that ages into a dead reference — a
document citing its own paperwork.

Where a rule depends on a standard **not yet written**, the reference still
has to be a working link, so it points at the row that tracks it:
`[the secrets standard](standards/000-platform.md#the-capability-roster)`.
That link resolves today, lands the reader on a row that says "not yet
written", and becomes a direct link to the document when one lands. A bare
name is not a reference and a link to a file that does not exist is a 404;
this is the form that is neither. Pending work is still tracked as issues
here; the documents just do not cite them.

**A rule is argued from principle, never from precedent.** Every rule carries
its reason, and the reason is a property of the rule — what it prevents, what
it costs, why the alternative fails — stated so that a reader with no knowledge
of this organisation's history could check it. *Another repository already does
this* is not a reason. It is a report that a decision was once made, and it
says nothing about whether the decision was right; a rule resting on it
inherits every mistake of the place it was copied from and cannot be examined
without going there. Where an existing implementation has a good argument, the
document makes the argument and drops the attribution. The argument stands on
its own or it does not stand.

**A standard is not an inventory of what exists.** It names no repository,
counts no repositories, and describes no repository's current state — not as
justification, not as motivation, not as colour. What a repository does today
is irrelevant to a rule that binds every repository, current and future, and a
document that opens by surveying the estate has made its argument contingent
on a survey that is stale the day it merges. Where an incident taught the
author a rule, the document states the failure mode as the general property it
is — *a timer in the request process runs once per replica* — so that a reader
cannot tell from the text which repository, if any, taught it. The Decisions
log at the foot of every standard is where this bites hardest: each entry is
the reason a choice went one way, and an entry that reads *as done in …* or
*because N products do …* is a decision nobody made.

## Non-compliance is tracked where the code is

This repository holds the standard. **It does not hold the list of who is
failing it.** Gaps in the standards or the catalog are issues *here*; a
repository that does not yet meet a standard has work in *its own* tracker.

A repo that does not yet comply has work to do in its own issue tracker,
against its own code, prioritized against its own roadmap. Recording that here
turns the standard into a scoreboard, gives every standards change a second
diff to maintain, and puts a client repository's shortcomings in a repository it
will never own.

The rule, therefore: **no document under `standards/` names a repository at
all**, whether to describe its state or to justify a rule by it. Two things are
deliberately not covered by that:

- **The CI standard's decisions log**, which cites the change that settled
  each row. That is a record of this repository's own history, not a
  description of another repository's state, and it is the one place a
  citation of the past is admitted. It does not extend to a standard's rules or
  its reasoning, which name no repository at all — see D4.
- **Checker allow-lists.** `tools/` carries per-repo entries because a gate has
  to know what it is currently letting through. Each entry states the gap it
  represents — a debt with a name, not a permission — and the target state for
  every list is empty.

## The standards

Every standard here is binding. Consult the relevant one before any change it
governs, in any repository. The **Enforcement** column says how much of it is
held mechanically today; the ledger says which rule is which.

**Each document has a number, and the number is its address.** It is stable for
the life of the document, never reused and never reassigned — an address that
moves is worse than none, because every citation that used it now points
somewhere else silently. Numbers are spaced by ten so a document can be
inserted where the reading order wants it; otherwise a new standard takes the
next free slot. `000` is where to start. `999` is the ledger, last because it
indexes everything above it. `AGENTS.md` carries no number because Cursor,
Claude Code and `check-agent-docs` all address it by name at the repository
root, which is an address already.

**Every rule has a short id**, and the **Prefix** column is the map: the CI
standard's principles are bare numbers, and each other standard carries a
mnemonic prefix. The id names a section in the standard's own document (the
rule and its reasoning) and a row in the ledger (the mechanism that enforces it
and the tier it actually holds). Document number plus rule id is a full
citation: `060 AU5` names one rule in one document and still will after ten
more standards land.

| # | Prefix | Document | Covers | Enforcement |
|---|---|---|---|---|
| `000` | PC | [`000-platform.md`](standards/000-platform.md) | The platform contract: application-layer opinions as protocols and interface specs, never tools | review, gates named |
| `010` | 1–18 | [`010-ci.md`](standards/010-ci.md) | Pipeline doctrine, the shared job catalog, build/release/publish | largely gated |
| `020` | IP | [`020-identifiers.md`](standards/020-identifiers.md) | Identifiers and primitive representations: public vs internal ids, the format table, timestamps, money | review, corpus written |
| `025` | SD | [`025-structured-data.md`](standards/025-structured-data.md) | Structured data: SQL as the query language, migrations as ordered `.sql` files shipped in the image, expand-only, declared isolation levels proven by enumeration, per-engine storage profile, schema invariants, transactions, hard delete by default, one database per service | review, corpus written |
| `026` | BS | [`026-blob-storage.md`](standards/026-blob-storage.md) | Blob storage: the S3 API as the storage protocol behind a boundary module, one private bucket per service per environment, the key grammar, the object reference as the source of truth, every read and write served through the service by object id after the RBAC check and never a URL to the store, uploads the server streams and verifies, scan before serve, hard delete through the outbox and a purge job | review, corpus written |
| `027` | DS | [`027-document-storage.md`](standards/027-document-storage.md) | Document storage: the relational store is the system of record and the JSON column is the first answer; a document store is admitted by declaration in one of two roles, derived or primary; the envelope every document carries; additive change within a schema version and a three-release bump; the declaration step and the backfill as jobs; a derived store rebuilt, watched, and excluded from backup | review, corpus written |
| `028` | BR | [`028-backup-and-recovery.md`](standards/028-backup-and-recovery.md) | Backup and recovery: a recovery declaration per stateful store (RPO, RTO, mechanism, retention, drill), derived stores rebuilt rather than backed up, three credentials with the backup's outside the service, restore exercised by a periodic drill that measures the objectives and gates deployment, and an erasure ledger replayed before readiness so a restore never resurrects erased data | review, corpus written |
| `030` | SC | [`030-service.md`](standards/030-service.md) | The service contract: health and readiness, structured logging, configuration, graceful shutdown, runtime provenance | review, live gate available |
| `032` | SE | [`032-secrets.md`](standards/032-secrets.md) | Secrets: delivered as environment variables or declared files, never fetched through a vendor SDK; every secret declared with an owner, an age and its images; `<SUBJECT>_<KIND>` names; nothing in the repository, the image, a log line, a URL or an error body; redaction by declared value; rotation by restart or dual window; a leak is rotated first and audited | review, corpus written |
| `035` | WK | [`035-workers.md`](standards/035-workers.md) | Workers: the pool and the one-shot, images cut on closure, credential and configuration, one repository per service, the one-shot's command and exit codes, the seven-verb runner contract, declarations rendered at deployment | review, corpus written |
| `038` | FF | [`038-feature-flags.md`](standards/038-feature-flags.md) | Feature flags: OpenFeature as the evaluation API with the provider as configuration, a declared flag with a kind and a lifetime, `false` as every boolean's default, a flag never standing in for a permission, a closed evaluation context, server-side evaluation with an evaluated set for the browser, a sweep that finds overdue flags | review, corpus written |
| `040` | OC | [`040-observability.md`](standards/040-observability.md) | Observability transport and context propagation: W3C trace context, the id vocabulary, OTLP | review, corpus written |
| `050` | HA | [`050-http.md`](standards/050-http.md) | Service interfaces: protocol selection (HTTP, gRPC, SSE, WebSocket), OpenAPI, RFC 9457 errors, cursor pagination, versioning, idempotency, backpressure, snake_case wire naming | review, corpus written |
| `055` | AM | [`055-messaging.md`](standards/055-messaging.md) | Async messaging: CloudEvents 1.0 as the envelope, at-least-once with inbox and outbox, workers not timers, Standard Webhooks signing in and out | review, corpus written |
| `057` | JB | [`057-jobs.md`](standards/057-jobs.md) | Jobs: the unit of work as an interface, the key as distinct from the delivery, three duplicate policies, the declaration, five outcomes, the run record, single-flight in the job, absence as the failure of a periodic job, backfills | review, corpus written |
| `058` | NF | [`058-notifications.md`](standards/058-notifications.md) | Notifications: the record as the source of truth, a three-job pipeline over the async envelope, two classes with consent per category per channel, the security floor, RFC 8058 unsubscribe, suppression on the address, templates as versioned files, authorization at render time, the provider behind one adapter, the in-app channel as an API | review, corpus written |
| `060` | AU | [`060-auth.md`](standards/060-auth.md) | Authentication: the identity tier, the proxy-minted identity token, identity linkage, provisioning, sessions, deployment topologies | review, corpus written |
| `070` | RB | [`070-rbac.md`](standards/070-rbac.md) | Authorization: the permission and role model, scope containment, the check operation, and the decision corpus | review, corpus written |
| `080` | AE | [`080-audit.md`](standards/080-audit.md) | Audit events: the record of consequential acts — actor separate from target, the action string is the permission string, the floor of what must emit, retention and erasure | review, corpus written |
| `082` | DR | [`082-data-subject-rights.md`](standards/082-data-subject-rights.md) | Data subject rights: the personal-data inventory as a declaration, export and erasure as request resources with one status machine, the package format, three treatments with allowlist anonymisation, grace and dispatch, the legal hold, and the audit-plus-ledger proof | review, corpus written |
| `085` | SB | [`085-security-baseline.md`](standards/085-security-baseline.md) | Security baseline: base images pinned by digest with the version in-band, three scans with expiring acceptances, the response header set per response class asserted by the start check, TLS on every non-private hop, rate limits on open and authentication routes, schema-validated and size-bounded input, `SECURITY.md` and `security.txt`, a CycloneDX SBOM per image per release, non-root images | review, corpus written |
| `090` | WC | [`090-web-client.md`](standards/090-web-client.md) | The web client: what a browser may hold as a credential, runtime configuration, the API client module, presentation and i18n, frontend error reporting | review, corpus written |
| `999` | — | [`999-enforcement.md`](standards/999-enforcement.md) | The ledger: every rule, its gate, its tier | — it is the register |
| — | A | [`AGENTS.md`](AGENTS.md) | How coding agents work in an Aurum Alpha repository: one guidance source, the work queue, the approval gate | rules 1-5 gated, rest review |

Standards still to be written are tracked as issues in this repository, and the
platform contract's capability roster names which capability is waiting on one.
Each issue carries the reasoning it was raised with, so the document can be
written from the argument rather than from memory. Each lands with the next
free number and its own prefix.

## What is here

- `standards/` — the numbered documents above.
- `contracts/` — the artifacts behind the application-layer standards: JSON
  Schemas and conformance corpora, one directory per capability.
- `.github/workflows/job-*.yml` — the shared job catalog. One reusable workflow
  per capability, consumed by every repository that has that capability.
- `tools/check-*` — the conformance checkers. Each runs both inside a
  repository's own CI and as a portfolio-wide sweep, from one source.
- `config/`, `setup/` — shared configuration and composite actions.
- `dependency-versions.json` — the package versions every adopting repository
  is held to: the package manager, the dev/build toolchain, and the handful of
  runtime packages that have converged. It names versions, never repositories.

## Adding or changing a standard

1. **Open an issue first**, stating the rule and the reasoning. A standard
   arriving as a finished document with no argument attached is a preference
   with formatting.
2. **Write the document under `standards/`**, at the next free number. State
   the rule, the reasoning, and what compliance looks like to a reader outside
   this repo.
3. **Register every rule in the ledger**, at the tier it actually holds today
   and with the gate it is getting.
4. **Add the row to the index above.**

Changing an existing rule follows the same path. A rule that has been violated
in production gets its incident written into the document beside it — that
evidence is the reason these documents get followed, and the reason the next
person does not re-litigate a decision already paid for once.
