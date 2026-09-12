# Aurum Alpha engineering standards

`aurum-alpha/workflows` defines how this organisation builds software. It
holds the standards and the shared CI infrastructure that implements them:
reusable workflows, composite actions, conformance checkers and shared
configuration. This page is the charter. It says what a standard is here, what
makes one binding, and indexes the rest. Every rule belongs to a numbered
document under `standards/`.

A document states the rule and the reasoning. A catalog implements it once. A
checker fails the build when a repository drifts. **Two repositories solving
the same problem two ways is not diversity. It is the absence of an opinion.**

## What this is for

Every application faces two kinds of decision, and only one of them is its own.

The first kind: which pagination style, which error envelope, which identifier
format, where the session lives, what an audit row contains. These are real
decisions, decided badly more often than not. **No particular product's problem
has an opinion about them.** Cursor pagination over offset makes an invoicing
system no better or worse at invoicing. The choice still has
to be made. So each repository makes it alone, differently, at the cost of an
argument that has already been had elsewhere.

The other kind is the domain: what an invoice *is* here, when it can be voided,
who is permitted to void it. That is the part a client pays for. It is the only
part where a repository's own judgment is the right input.

So the purpose, in three steps:

1. **Remove the arbitrary decision from every repository** wherever it is not
   material to that application's purpose or domain. The aim is not uniform
   choices for their own sake. A decision that could go either way goes one way
   once, here, with the reasoning written down.
2. **Each repository then spends its judgment on business logic**: the domain,
   the workflow, the thing that is specific to it.
3. **The standards make development faster, not slower.** The decisions they
   remove were never free. They were paid for repeatedly, in argument and in
   divergence.

The standards are written as contracts with conformance tests rather than as
advice. An arbitrary decision is only removed once nobody has to remember it.

## Scope: internal and client work alike

These standards bind everything Aurum Alpha builds: the products we operate and
the systems we build for clients. A client engagement is not an exemption. It is
the case that matters most, because it is the code that leaves.

**A standard must survive handover.** A client repository follows these rules.
At handover it stops being able to reach this repository at all: no shared job
to call, no checker to run, no catalog to resolve. A standard that only works
while `aurum-alpha/workflows` is reachable is not a standard. It is a
dependency.

Three consequences follow, and they constrain how every document here is
written:

1. **State the rule, not only the mechanism.** A reader outside this repo must
   be able to read the rule, see why it exists, and comply. The shared job is
   how *we* comply cheaply. It is never the only description of what compliance
   is.
2. **Every standard must be satisfiable without this repo.** A rule is often
   met by calling a shared workflow. In that case the document says what the
   workflow does, in terms a person could reimplement.
3. **Handover is a copy, not a link.** A repository leaving the portfolio
   vendors the standards it was built to. The rules then travel with the code.
   What it loses is the updates, which is correct: it is no longer ours.

## The law

**A rule is not done when it is written. It is done when something fails if it
is broken.**

Writing a rule and enforcing it are different acts, and only the second one
holds. A principle nobody can fail is a preference.

A rule that survives names the act itself. A rule keyed on a file, a filename
or an outcome with no mechanism named stops applying the moment the act moves.
Write rules against acts, then make something fail when the act is wrong.

### Three tiers, and the difference between them matters

- **gated**: a violation turns that repo's required check red. This is
  enforcement.
- **audit only**: a checker exists and reports, and nothing goes red. Every
  one of these is a candidate for the gate. A checker whose findings nothing
  acts on degrades to a checker that is itself wrong, silently.
- **review only**: nothing mechanical. Some rules resist automation honestly.
  Saying so is the point: an unenforced rule must be visibly unenforced, not
  quietly assumed. A rule that resists a checker gets the next best thing: a
  review question someone has to answer, not a line someone has to remember.

### A new standard's rules start review-only and name their gates

Landing a standard and landing its enforcement in one change is how standards
stall. So the sequence is fixed:

1. The standard lands with every rule registered in
   [`standards/999-enforcement.md`](standards/999-enforcement.md), at the tier
   that rule actually holds. For a new standard that is usually **review only**.
2. Each rule names, in that ledger, **the gate it is eventually getting**. Or it
   states plainly that it resists one and will stay review-only.
3. Promoting a rule to gated is its own change, and the ledger row moves with it.

A rule that lands review-only with no proposed gate and no admission that it
cannot have one is not finished. That is exactly the failure the law above
describes, arriving one document earlier.

**The tier describes the rule's enforcement, never the document's standing.** A
merged document is binding. See the writing conventions below.

## The foundation: twelve-factor

**[The Twelve-Factor App](https://12factor.net/) is the ground these standards
are built on**, not a reference we consulted. The factors cover config in the
environment, logs as event streams, strict build/release/run separation, and
disposable processes that shut down gracefully. Most of what the CI standard
and the platform contract say about a service's behaviour is twelve-factor,
applied here with the open choices pinned.

Two consequences for how these documents are written:

- **Where a rule restates a factor, the document cites the factor as its
  justification.** "Logs go to stdout because we said so" is a preference.
  "Logs go to stdout per [factor XI](https://12factor.net/logs), because the
  application must not concern itself with routing or storage" is an argument.
  A reader can check it against a source older and more tested than we are.
  Claiming a well-known idea as a house invention also costs credibility with
  exactly the engineers we want reading these documents.
- **Where a rule departs from a factor, the document says so, in the rule,
  with the reason**. A silent departure is worse than a stated one. The next
  reader assumes we did not know.

A standard here adds the part twelve-factor deliberately leaves open. That is
the *specific* names, formats and endpoints that let four languages
interoperate. Factor III says config lives in the environment. It does not say
what the variables are called. That pinning is ours, and it is the only part
that is.

**Known departures: none.** Admin and management tasks run as one-off
processes per [factor XII](https://12factor.net/admin-processes). The jobs and
workers standards take that shape. A one-shot worker is built from the same
release as the servers, never registered as an interface inside a server.

## How these documents are written

Each convention below stops a failure that is quiet.

**A merged document is binding, and says nothing about its own status.** No
document carries a `Status: proposed` or `Status: agreed` header. Review
happens in the pull request. Merging it is the approval. A status line on a
merged document is either wrong or noise. Wrong, because it still says
"proposed"; noise, because it says "agreed", which every merged document is.
What varies per rule is how it is *enforced*, and that lives in one place: the
ledger.

**A document references other documents, never a tracker.** It uses relative
markdown links between `.md` files, always. A reader can click such a reference
and open it, rather than hunt for a name. An issue or pull request number in
doctrine is a citation to something a reader outside this repository cannot
open. It says nothing once merged, and it ages into a dead reference: a
document citing its own paperwork.

Where a rule depends on a standard **not yet written**, the reference still
has to be a working link. So it points at the row that tracks it:
`[the secrets standard](standards/000-platform.md#the-capability-roster)`.
That link resolves today and lands the reader on a row that says "not yet
written". It becomes a direct link to the document when one lands. A bare name
is not a reference, a link to a missing file is a 404, and this form is
neither. Pending work is still tracked as issues here; the documents just do
not cite them.

**A rule is argued from principle, never from precedent.** Every rule carries
its reason: what it prevents, what it costs, why the alternative fails. A
reader with no knowledge of this organisation's history can check it.
*Another repository already does this* is a report that a decision was once
made, not a reason. Where an implementation has a good argument, the document
makes the argument and drops the attribution.

**A standard names no repository, ever.** Not as justification, motivation,
colour, example or incident report. It does not count repositories. It does
not describe any repository's state or distance from the rule. Which
repositories comply is tracked where the code is, never in a standard.

A rule that binds every repository, current and future, cannot depend on what
one repository does today. Where an incident taught the author a rule, the
document states the failure mode as the general property it is. *A timer in
the request process runs once per replica* is that form.
`tools/check-doc-style` holds the countable half. The one name a document
carries is `aurum-alpha/workflows`, its own address.

**A document states the rule and the reason, never the history of the
decision**. It does not say what the text said before, when a sentence
changed, or which incident taught it. The pull request holds that. Where an
alternative was considered and not taken, the document says so and why, under
Decisions. A Decisions entry that restates the rule is not a decision; a
Decisions entry that narrates the drafting is history. `tools/check-doc-style`
flags the phrases history arrives in.

**A document has no preamble.** It opens with what it governs and its rules.
It cites another document only where a rule leans on it for justification or
defers a part to it. A list of related standards, a prose table of contents,
and a pointer to the ledger are not content.

**A document is written in Simplified Technical English.** The writing rules
of [ASD-STE100](https://www.asd-ste100.org/) are the standard for every
document in this repository. They were made for maintenance manuals, where a
sentence that is misread costs an aircraft. A rule that is misread here costs
a product the same way, one release later. The readers include engineers
whose first language is not English, and agents that turn a sentence into
code. Both read a short sentence correctly. Neither reads a long one the same
way twice.

The rules we hold to, stated in our words:

- **A sentence gives one idea.** A descriptive sentence has at most 25 words.
  An instruction has at most 20.
- **A paragraph has one topic and at most six sentences.** The first
  sentence states the topic.
- **The voice is active and the tense is present.** The actor is named: *the
  job writes the row*, not *the row is written*.
- **A rule is an instruction.** *Put the catalog in the repository.* *Do not
  set `Domain=`.* A requirement uses *must*. A permission uses *can* or *is
  permitted*. The banned words do not appear; `tools/check-doc-style --help`
  lists them.
- **A word has one meaning.** A technical name such as *tenant*, *webhook*
  or *cursor* is used as its standard names it. It is not varied for style.
  A noun cluster has at most three words.
- **A full stop joins two ideas.** A dash does not. A sentence that needs a
  dash to hold together is two sentences.
- **A table, a list, a code block or a diagram carries what it carries
  best.** Prose is not used where a table is clearer.

`tools/check-doc-style` measures the mechanical half in this repository's
CI: sentence length, paragraph length, the banned words, and dashes in prose.
The judgement half, one idea per sentence and one meaning per word, stays a
review question.

## Non-compliance is tracked where the code is

This repository holds the standard. **It does not hold the list of who is
failing it.** Gaps in the standards or the catalog are issues here. A
repository that does not yet comply has work in its own tracker, against its
own code. Recording it here turns the standard into a scoreboard and puts a
client repository's shortcomings in a repository it will never own.

One place names a repository: **a checker allow-list, where the entry names a
waived rule.** A gate has to know what it is letting through. Each entry
states the gap it represents, and the target state for every list is empty.

**A checker never holds a list of who is subject to it**. The gates run inside
each repository's own CI, so calling a gate is what subjects a repository to
it. Where a repository has standing debt it declares the window itself,
through a job input in its own `ci.yml`.

## The standards

Every standard here is binding. Consult the relevant one before any change it
governs, in any repository. The **Enforcement** column says how much of it is
held mechanically today; the ledger says which rule is which.

**Each document has a number, and the number is its address.** It is stable for
the document's life, never reused and never reassigned. An address that moves
is worse than none, because every citation that used it now points somewhere
else silently. Numbers are spaced by ten so a document can be inserted where
the reading order wants it. Otherwise a new standard takes the next free slot.
`000` is where to start. `999` is the ledger, last because it indexes
everything above it.

`AGENTS.md` carries no number. Cursor, Claude Code and `check-agent-docs` all
address it by name at the repository root, which is an address already.

**Every rule has a short id**, and the **Prefix** column is the map. The CI
standard's principles are bare numbers, and each other standard carries a
mnemonic prefix. The id names a section in the standard's own document, which
holds the rule and its reasoning. It also names a row in the ledger, which
holds the mechanism that enforces it and the tier it actually holds. Document
number plus rule id is a full citation. `060 AU5` names one rule in one
document, and still will after ten more standards land.

| # | Prefix | Document | Covers | Enforcement |
|---|---|---|---|---|
| `000` | PC | [`000-platform.md`](standards/000-platform.md) | The platform contract: application-layer opinions as protocols and interface specs, never tools | review, gates named |
| `010` | 1–21 | [`010-ci.md`](standards/010-ci.md) | Pipeline doctrine, the shared job catalog, build/release/publish | largely gated |
| `015` | DC | [`015-commands.md`](standards/015-commands.md) | Developer commands: one name per capability, each script's body the invocation its gate runs | gated |
| `016` | LD | [`016-local-development.md`](standards/016-local-development.md) | Local development: the listen port from the environment, host bindings in one aligned block, the development image | review only |
| `020` | IP | [`020-identifiers.md`](standards/020-identifiers.md) | Identifiers and primitive representations: public vs internal ids, the format table, timestamps, money | review, corpus written |
| `025` | SD | [`025-structured-data.md`](standards/025-structured-data.md) | Structured data: SQL, migrations as ordered `.sql` files, isolation by enumeration, one database per service | review, corpus written |
| `026` | BS | [`026-blob-storage.md`](standards/026-blob-storage.md) | Blob storage: the S3 API behind a boundary module, the object reference as truth, reads served by the service | review, corpus written |
| `027` | DS | [`027-json-document-storage.md`](standards/027-json-document-storage.md) | JSON document storage: the relational JSON column first, a document database by declaration, the envelope | review, corpus written |
| `028` | BR | [`028-backup-and-recovery.md`](standards/028-backup-and-recovery.md) | Backup and recovery: a recovery declaration per store, three credentials, the drill, the erasure ledger | review, corpus written |
| `030` | SC | [`030-service.md`](standards/030-service.md) | The service contract: health and readiness, structured logging, configuration, graceful shutdown, runtime provenance | review, live gate available |
| `032` | SE | [`032-secrets.md`](standards/032-secrets.md) | Secrets: delivered by the platform as environment or files, declared with an owner and an age, never in the repository | review, corpus written |
| `035` | WK | [`035-workers.md`](standards/035-workers.md) | Workers: the pool and the one-shot, images cut on closure, the seven-verb runner contract | review, corpus written |
| `038` | FF | [`038-feature-flags.md`](standards/038-feature-flags.md) | Feature flags: OpenFeature, a declared flag with a kind and a lifetime, never an authorization input | review, corpus written |
| `040` | OC | [`040-observability.md`](standards/040-observability.md) | Observability transport and context propagation: W3C trace context, the id vocabulary, OTLP | review, corpus written |
| `050` | HA | [`050-http.md`](standards/050-http.md) | Service interfaces: protocol selection (HTTP, gRPC, SSE, WebSocket), OpenAPI, RFC 9457 errors, cursor pagination, versioning, idempotency, backpressure, snake_case wire naming | review, corpus written |
| `055` | AM | [`055-messaging.md`](standards/055-messaging.md) | Async messaging: CloudEvents 1.0 as the envelope, at-least-once with inbox and outbox, workers not timers, Standard Webhooks signing in and out | review, corpus written |
| `057` | JB | [`057-jobs.md`](standards/057-jobs.md) | Jobs: the unit of work, its key, three duplicate policies, the declaration, the run record | review, corpus written |
| `058` | NF | [`058-notifications.md`](standards/058-notifications.md) | Notifications: the record as truth, a three-job pipeline, consent per category per channel, the security floor | review, corpus written |
| `060` | AU | [`060-auth.md`](standards/060-auth.md) | Authentication: the identity tier, the proxy-minted identity token, identity linkage, provisioning, sessions, deployment topologies | review, corpus written |
| `070` | RB | [`070-rbac.md`](standards/070-rbac.md) | Authorization: the permission and role model, scope containment, the check operation, and the decision corpus | review, corpus written |
| `075` | BL | [`075-billing.md`](standards/075-billing.md) | Billing: the catalog as a file, the subscription as a ledger projection, four kinds of entitlement, the check | review, corpus written |
| `080` | AE | [`080-audit.md`](standards/080-audit.md) | Audit events: the record of consequential acts — actor separate from target, the action string is the permission string, the floor of what must emit, retention and erasure | review, corpus written |
| `082` | DR | [`082-data-subject-rights.md`](standards/082-data-subject-rights.md) | Data subject rights: the personal-data inventory, export and erasure as requests, three treatments, the legal hold | review, corpus written |
| `085` | SB | [`085-security-baseline.md`](standards/085-security-baseline.md) | Security baseline: digest-pinned images, three scans, response headers, TLS, rate limits, input bounds, SBOM | review, corpus written |
| `090` | WC | [`090-web-client.md`](standards/090-web-client.md) | The web client: what a browser may hold as a credential, runtime configuration, the API client module, presentation and i18n, frontend error reporting | review, corpus written |
| `091` | WE | [`091-web-estate.md`](standards/091-web-estate.md) | The web estate: three surface classes, the host convention, the front door as a built directory, the four seams | review, gates named |
| `092` | TH | [`092-tenant-hostnames.md`](standards/092-tenant-hostnames.md) | Tenant hostnames: a tenant as an authentication boundary, host-only cookies, the custom-domain state machine | review, gates named |
| `999` | — | [`999-enforcement.md`](standards/999-enforcement.md) | The ledger: every rule, its gate, its tier | — it is the register |
| — | A | [`AGENTS.md`](AGENTS.md) | How coding agents work in an Aurum Alpha repository: one guidance source, the work queue, the approval gate | rules 1-5 gated, rest review |

Standards still to be written are tracked as issues in this repository. The
platform contract's capability roster names which capability is waiting on
one. Each issue carries the reasoning it was raised with, so the document can
be written from the argument rather than from memory. Each lands with the next
free number and its own prefix.

## Acceptable solutions: the register of what satisfies a standard

A standard outlives the tools that satisfy it. Providers are renamed,
packages stop being maintained, a protocol arrives and makes an adapter moot.
**A standard that lists what to buy has put its most perishable sentence
inside its most durable document**. Yet someone starting a capability has to
pick something, and a standard that names nothing has handed back the
arbitrary decision.

So the perishable half lives under `solutions/`: **the acceptable solutions
register**, one per standard that needs one, sharing that standard's number.
[`solutions/038-feature-flags.md`](solutions/038-feature-flags.md) answers
[`standards/038-feature-flags.md`](standards/038-feature-flags.md). The
pattern is the building code's: the code states what a wall achieves, and a
separate document names constructions deemed to satisfy it.

A register names the routes known to satisfy one standard's rules and says
which rule ids each route satisfies. It says which rules the route leaves for
the repository to build anyway. Four rules:

1. **A register never states a rule.** Delete the whole register, and every
   rule must still stand, with every repository still able to comply.
2. **Absence is not refusal.** An option the register does not name is
   unexamined. A repository can take it by demonstrating compliance against
   the standard's rules, and is then entered here. What is refused is refused
   by a rule in the standard, and the register cites that rule.
3. **A listing is a technical claim on a date, never an endorsement or a
   purchase.** No prices, no contract terms, no vendor ranking. Commercial
   terms perish faster than anything technical.
4. **A register can name one default route**, argued, for a repository with
   no reason to choose otherwise, and says what would change it.

**A tool the standard dictates is part of the rule and stays in the
standard**. A document pins a component where a rule is stated in that
component's vocabulary, or where an enumeration in `contracts/` decides what
is admitted. The test: **would naming something else be a violation, or a
choice?** A violation stays in the standard.

Registers in existence today: `032`, `035`, `038`, `060`, `075`, `091`. A
standard with no register has not been surveyed yet, or closes the choice
itself in `contracts/`. A register is vendored at handover like a standard.

Adding one follows the standards path, shortened. Open an issue with the
argument. Write `solutions/<number>-<slug>.md` against the rule ids it claims
to satisfy. Add the number to the list above.

## What is here

- `standards/`: the numbered documents above.
- `solutions/`: the acceptable solutions registers. Per standard, what is
  known to satisfy its rules.
- `contracts/`: the artifacts behind the application-layer standards. JSON
  Schemas and conformance corpora, one directory per capability.
- `.github/workflows/job-*.yml`: the shared job catalog. One reusable workflow
  per capability, consumed by every repository that has that capability.
- `tools/check-*`: the conformance checkers. Each runs both inside a
  repository's own CI and as a portfolio-wide sweep, from one source.
- `config/`, `setup/`: shared configuration and composite actions.
- `dependency-versions.json`: the package versions every adopting repository
  is held to. It names the package manager, the dev/build toolchain, and the
  handful of runtime packages that have converged. It names versions, never
  repositories.

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

Changing an existing rule follows the same path. The document states the new
rule and its reason. Where the old rule was an alternative worth recording, it
goes under Decisions with why it lost. The pull request holds the rest.
