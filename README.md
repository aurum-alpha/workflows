# Aurum Alpha engineering standards

`aurum-alpha/workflows` defines how this organisation builds software. It
holds the standards themselves and the shared CI infrastructure that
implements them: reusable workflows, composite actions, conformance checkers
and shared configuration. This page is the charter. It says what a standard is
here, what makes one binding, and indexes the rest. It states no engineering
rules itself. Every rule belongs to a numbered document under `standards/`.

This repository is not a convenience library of things several repos happened
to need. It is the answer, per language and per capability, that repos are
standardized *onto*, so that each does not arrive at its own.

Continuous integration already worked this way, and the CI standard is the
worked example the rest follows. A document states the rule and the reasoning.
A catalog implements it once. A checker fails the build when a repo drifts.
The scope is now every layer of a product, not only its pipeline.

**Two repos solving the same problem two ways is not diversity. It is the
absence of an opinion.** An organisation with no opinion re-litigates the same
decision every time someone starts a service.

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
3. **This is why the standards make development faster, not slower.** A
   standards effort is assumed to be a tax. This one is the opposite. The
   decisions it removes were never free. They were paid for repeatedly, in
   argument and in divergence, by people who had something better to think
   about.

That is also why the standards are written as contracts with conformance tests
rather than as advice. An arbitrary decision is only removed once nobody has to
remember it.

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

Every rule in the CI standard was written down first and violated afterwards,
in a repo whose CI was green the entire time. Writing a rule and enforcing it
are different acts, and only the second one holds. A principle nobody can fail
is a preference.

That history also taught what *kind* of rule survives. Three rules failed the
same way in three disguises. One keyed on a file, one keyed on a filename, one
keyed on an outcome with no mechanism named. The common shape: **a rule naming
anything other than the act itself stops applying the moment the act moves**.
Write rules against acts, then make something fail when the act is wrong.

### Three tiers, and the difference between them matters

- **gated**: a violation turns that repo's required check red. This is
  enforcement.
- **audit only**: a checker exists but runs from a workstation when someone
  remembers. This is a habit, and habits are what drifted in the first place.
  Every one of these is a candidate for folding into the gate. A checker
  nothing runs does not degrade to weaker enforcement. It degrades to a checker
  that is itself wrong, silently.
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

**Known departures: none today.** One tension that was open is now settled. It
is settled the way [factor XII](https://12factor.net/admin-processes) states
it: admin and management tasks run as one-off processes. The jobs and workers
capabilities on the platform roster take exactly that shape. Each is a one-shot
worker built from the same release as the servers, not an interface registered
inside a server. Their standards state that against factor XII rather than
around it.

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
its reason. The reason is a property of the rule: what it prevents, what it
costs, why the alternative fails. It is stated so that a reader with no
knowledge of this organisation's history could check it. *Another repository
already does this* is not a reason. It is a report that a decision was once
made, and it says nothing about whether the decision was right.

A rule resting on precedent inherits every mistake of the place it was copied
from. It cannot be examined without going there. Where an existing
implementation has a good argument, the document makes the argument and drops
the attribution. The argument stands on its own or it does not stand.

**A standard names no repository, ever.** Not as justification, not as
motivation, not as colour, not as an example, not as an incident report. It
does not count repositories. It does not describe any repository's current
state, past state, or distance from the rule.

A standard is a specification. It stands on principle. Which repositories
comply, and how far each one is from compliance, is not the standard's
concern. That is tracked where the code is, and nowhere in this repository's
documents.

The reason is durability. A rule that binds every repository, current and
future, cannot depend on what one repository does today. A document that
surveys the estate has made its argument contingent on a survey that is stale
the day it merges. A document that names the repository an incident came from
has made a reader go there to check the argument.

Where an incident taught the author a rule, the document states the failure
mode as the general property it is. *A timer in the request process runs once
per replica* is that form. A reader cannot tell from the text which
repository, if any, taught it, and does not need to. The Decisions log at the
foot of every standard is where this bites hardest. Each entry is the reason a
choice went one way. An entry that reads *as done in …* or *because N products
do …* is a decision nobody made.

`tools/check-doc-style` holds the countable half: a repository name or an
inventory phrase in a standard is a finding. The one name a document is
permitted to carry is `aurum-alpha/workflows`, because it is this repository's
own address. The one citation of the past that is permitted is the CI
standard's decisions log, which cites the change that settled each row. It
cites a change in this repository's own history, never a repository.

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

A document written before this convention converges on it. Any passage that
changes meets it. `tools/check-doc-style` measures the distance: sentence
length, paragraph length, the banned words, and dashes in prose. It reports
in this repository's CI and does not gate until the documents are under the
threshold. The judgement half of the convention, one idea per sentence and
one meaning per word, stays a review question.

## Non-compliance is tracked where the code is

This repository holds the standard. **It does not hold the list of who is
failing it.** Gaps in the standards or the catalog are issues *here*. A
repository that does not yet meet a standard has work in *its own* tracker.

A repo that does not yet comply has work to do in its own issue tracker,
against its own code, prioritized against its own roadmap. Recording that here
turns the standard into a scoreboard. It gives every standards change a second
diff to maintain. It puts a client repository's shortcomings in a repository it
will never own.

The rule, therefore: **no document under `standards/` names a repository at
all**, whether to describe its state or to justify a rule by it. Two things are
deliberately not covered by that:

- **The CI standard's decisions log**, which cites the change that settled
  each row. That is a record of this repository's own history, not a
  description of another repository's state. It is the one place a citation of
  the past is admitted. It does not extend to a standard's rules or its
  reasoning, which name no repository at all. See D4.
- **Checker allow-lists,** and only where the entry names a *waived rule*.
  `tools/` carries per-repo entries because a gate has to know what it is
  currently letting through. Each entry states the gap it represents: a debt
  with a name, not a permission. The target state for every list is empty.

**A checker never holds a list of who is subject to it.** That is the carve-out
above read backwards, and it is not admitted. The gates run inside each
repository's own CI, so calling a gate is what subjects a repository to it. A
name list gating who gets judged can only be redundant with that call, or
disagree with it. Where a repository has standing debt it declares the window
itself, through a job input in its own `ci.yml`. That is the same rule as the
paragraphs above: the state lives with the code. A checker that decides what to
report from a repository's *name* has made this repository the scoreboard by
another route.

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
| `010` | 1–18 | [`010-ci.md`](standards/010-ci.md) | Pipeline doctrine, the shared job catalog, build/release/publish | largely gated |
| `015` | DC | [`015-commands.md`](standards/015-commands.md) | Developer commands: the commands a person types, one name per capability meaning the same thing in every repository, each script's body equal to the invocation its gate runs and derived from the catalog rather than copied, the repository's shape deciding which commands exist, no second name and no package manager between a script and a local binary | gated |
| `020` | IP | [`020-identifiers.md`](standards/020-identifiers.md) | Identifiers and primitive representations: public vs internal ids, the format table, timestamps, money | review, corpus written |
| `025` | SD | [`025-structured-data.md`](standards/025-structured-data.md) | Structured data: SQL as the query language, migrations as ordered `.sql` files shipped in the image, expand-only, declared isolation levels proven by enumeration, per-engine storage profile, schema invariants, transactions, hard delete by default, one database per service | review, corpus written |
| `026` | BS | [`026-blob-storage.md`](standards/026-blob-storage.md) | Blob storage: the S3 API as the storage protocol behind a boundary module, one private bucket per service per environment, the key grammar, the object reference as the source of truth, every read and write served through the service by object id after the RBAC check and never a URL to the store, uploads the server streams and verifies, scan before serve, hard delete through the outbox and a purge job | review, corpus written |
| `027` | DS | [`027-json-document-storage.md`](standards/027-json-document-storage.md) | JSON document storage (never files — those are 026's): the relational store is the system of record and its JSON column is the first answer; a document database is admitted beside it, the hybrid model, by declaration naming the test the column failed, with the engine class chosen by the test, in one of two roles, derived or primary; the envelope every document carries; additive change within a schema version and a three-release bump; the declaration step and the backfill as jobs; a derived store rebuilt, watched, and excluded from backup | review, corpus written |
| `028` | BR | [`028-backup-and-recovery.md`](standards/028-backup-and-recovery.md) | Backup and recovery: a recovery declaration per stateful store (RPO, RTO, mechanism, retention, drill), derived stores rebuilt rather than backed up, three credentials with the backup's outside the service, restore exercised by a periodic drill that measures the objectives and gates deployment, and an erasure ledger replayed before readiness so a restore never resurrects erased data | review, corpus written |
| `030` | SC | [`030-service.md`](standards/030-service.md) | The service contract: health and readiness, structured logging, configuration, graceful shutdown, runtime provenance | review, live gate available |
| `032` | SE | [`032-secrets.md`](standards/032-secrets.md) | Secrets: delivered as environment variables or declared files, never fetched through a vendor SDK; one store per platform rendered into the environment by the runtime's own mechanism (operator or CSI driver, native injection, systemd credentials), the repository shipping only the mapping; every secret declared with an owner, an age and its images; `<SUBJECT>_<KIND>` names; nothing in the repository, the image, a log line, a URL or an error body; redaction by declared value; rotation by restart or dual window; a leak is rotated first and audited | review, corpus written |
| `035` | WK | [`035-workers.md`](standards/035-workers.md) | Workers: the pool and the one-shot, images cut on closure, credential and configuration, one repository per service, the one-shot's command and exit codes, the seven-verb runner contract, declarations rendered at deployment | review, corpus written |
| `038` | FF | [`038-feature-flags.md`](standards/038-feature-flags.md) | Feature flags: OpenFeature as the evaluation API with the provider as configuration, a declared flag with a kind and a lifetime, `false` as every boolean's default, a flag never standing in for a permission, a closed evaluation context, server-side evaluation with an evaluated set for the browser, a sweep that finds overdue flags | review, corpus written |
| `040` | OC | [`040-observability.md`](standards/040-observability.md) | Observability transport and context propagation: W3C trace context, the id vocabulary, OTLP | review, corpus written |
| `050` | HA | [`050-http.md`](standards/050-http.md) | Service interfaces: protocol selection (HTTP, gRPC, SSE, WebSocket), OpenAPI, RFC 9457 errors, cursor pagination, versioning, idempotency, backpressure, snake_case wire naming | review, corpus written |
| `055` | AM | [`055-messaging.md`](standards/055-messaging.md) | Async messaging: CloudEvents 1.0 as the envelope, at-least-once with inbox and outbox, workers not timers, Standard Webhooks signing in and out | review, corpus written |
| `057` | JB | [`057-jobs.md`](standards/057-jobs.md) | Jobs: the unit of work as an interface, the key as distinct from the delivery, three duplicate policies, the declaration, five outcomes, the run record, single-flight in the job, absence as the failure of a periodic job, backfills | review, corpus written |
| `058` | NF | [`058-notifications.md`](standards/058-notifications.md) | Notifications: the record as the source of truth, a three-job pipeline over the async envelope, two classes with consent per category per channel, the security floor, RFC 8058 unsubscribe, suppression on the address, templates as versioned files, authorization at render time, the provider behind one adapter, the in-app channel as an API | review, corpus written |
| `060` | AU | [`060-auth.md`](standards/060-auth.md) | Authentication: the identity tier, the proxy-minted identity token, identity linkage, provisioning, sessions, deployment topologies | review, corpus written |
| `070` | RB | [`070-rbac.md`](standards/070-rbac.md) | Authorization: the permission and role model, scope containment, the check operation, and the decision corpus | review, corpus written |
| `075` | BL | [`075-billing.md`](standards/075-billing.md) | Billing: the catalog as a file that provisions the provider, the subscription as a projection of an append-only ledger, four kinds of entitlement and nothing per user, the check as a pure function run after the permission and before the domain operation with its own `403` problem type, one provider adapter off the request path, webhooks in and reconciliation by a job, plan-change and trial policy, money events audited and exportable | review, corpus written |
| `080` | AE | [`080-audit.md`](standards/080-audit.md) | Audit events: the record of consequential acts — actor separate from target, the action string is the permission string, the floor of what must emit, retention and erasure | review, corpus written |
| `082` | DR | [`082-data-subject-rights.md`](standards/082-data-subject-rights.md) | Data subject rights: the personal-data inventory as a declaration, export and erasure as request resources with one status machine, the package format, three treatments with allowlist anonymisation, grace and dispatch, the legal hold, and the audit-plus-ledger proof | review, corpus written |
| `085` | SB | [`085-security-baseline.md`](standards/085-security-baseline.md) | Security baseline: base images pinned by digest with the version in-band, three scans with expiring acceptances, the response header set per response class asserted by the start check, TLS on every non-private hop, rate limits on open and authentication routes, schema-validated and size-bounded input, `SECURITY.md` and `security.txt`, a CycloneDX SBOM per image per release, non-root images | review, corpus written |
| `090` | WC | [`090-web-client.md`](standards/090-web-client.md) | The web client: what a browser may hold as a credential, runtime configuration, the API client module, presentation and i18n, frontend error reporting | review, corpus written |
| `091` | WE | [`091-web-estate.md`](standards/091-web-estate.md) | The web estate: three surface classes with fixed identity postures, the host convention as the class boundary, the front door as a built directory with environments serving the bootstrap document, content as data in the repository, every surface maintainable from its repository alone, the four seams as existing contracts, automated actors as workload identities, campaign pages in the front door's zone | review, gates named |
| `092` | TH | [`092-tenant-hostnames.md`](standards/092-tenant-hostnames.md) | Tenant hostnames: a tenant as an authentication boundary, what the hostname decides before login and only agrees after, the four invalid host-and-identity cases, host-only session cookies, one callback host per topology, a pre-issued wildcard and a custom-domain state machine with the tenant table as the certificate allowlist, tenant hosts `noindex` | review, gates named |
| `999` | — | [`999-enforcement.md`](standards/999-enforcement.md) | The ledger: every rule, its gate, its tier | — it is the register |
| — | A | [`AGENTS.md`](AGENTS.md) | How coding agents work in an Aurum Alpha repository: one guidance source, the work queue, the approval gate | rules 1-5 gated, rest review |

Standards still to be written are tracked as issues in this repository. The
platform contract's capability roster names which capability is waiting on
one. Each issue carries the reasoning it was raised with, so the document can
be written from the argument rather than from memory. Each lands with the next
free number and its own prefix.

## Acceptable solutions: the register of what satisfies a standard

A standard states a rule and the reasoning behind it, and both are meant to
outlive the tools that satisfy them. **The tools do not cooperate.** A provider
is acquired and renamed. A package stops being maintained. A vendor's language
coverage changes in a minor release. A protocol everyone implements arrives and
makes the adapter question moot. A document that named those tools is then
wrong in the way this repository exists to prevent: quietly, because prose
does not fail.

**A standard that lists what to buy has put its most perishable sentence inside
its most durable document.**

Removing the sentence is not the answer either. Someone starting a capability
has to pick something. A standard that pins a specification and names nothing
that implements it has handed back the arbitrary decision this repository
exists to take away.

So the perishable half lives in a second class of document, under `solutions/`:
**the acceptable solutions register**. There is one per standard that needs
one, sharing that standard's number. So
[`solutions/038-feature-flags.md`](solutions/038-feature-flags.md) answers
[`standards/038-feature-flags.md`](standards/038-feature-flags.md), and the
number is still the address.

The pattern is borrowed from performance-based building codes. Those state
what a wall has to achieve and, in separate documents, name constructions
deemed to satisfy it. Building the named construction settles compliance with
no argument. Building something else is permitted and carries the burden of
demonstrating compliance another way. The requirement outlives the products,
the products are revised without reopening the requirement, and nobody
confuses the two. Those are exactly the three properties wanted here.

A register does one job. For one standard, it names the routes known to
satisfy its rules and says **which rule ids** each route satisfies. It says
which rules the route leaves for the repository to build anyway, and carries
the date each claim was last checked.

Five rules, because each is a way this class fails quietly:

1. **A register never states a rule.** Every requirement lives in the standard;
   the register only claims that something meets one. The test is destructive
   and worth applying to any sentence in doubt. **Delete the whole register,
   and every rule must still stand, with every repository still able to
   comply**. Compliance is then slower, with each repository arguing its own
   choice. A register sentence that fails that test is a rule in the wrong
   document. No ledger row covers it there, and no reader looking for rules
   will find it.
2. **Absence is not refusal.** An option the register does not name is not
   forbidden; it is unexamined. A repository is permitted to take it by
   demonstrating compliance against the standard's rules. It is then entered
   here, so the next repository does not repeat the demonstration. What *is*
   refused is refused by a rule in the standard, and the register cites that
   rule.
3. **A listing is a technical claim on a date, never an endorsement or a
   purchase.** No prices, no contract terms, no vendor ranking. No comparison
   table that reads as a bake-off. Commercial terms perish faster than anything
   technical. A register carrying them becomes a procurement document that
   nobody updates and everyone quotes. The question a register answers is *does
   this route comply*, not *what to buy*.
4. **Every entry carries the date it was last checked, and a stale entry reads
   as stale.** The horizon is **180 days**. An entry not re-checked within it
   is a finding, the same way an overdue flag is. A register is permitted to
   lower the horizon and is not permitted to raise it. This is the whole
   mechanism of the class. An entry that rots silently is worse than no entry,
   because it carries this repository's authority while being wrong.
5. **A register is permitted to name one default route**, argued, for a
   repository with no reason to choose otherwise. That is not a ranking of
   vendors. It is the charter's own purpose, an arbitrary decision made once,
   applied to the one place a standard deliberately leaves open. The default is
   a technical argument a reader can disagree with, and the register says what
   would change it.

**A tool the standard dictates is part of the rule and stays in the standard.**
The register carries a choice the standard leaves open. It never carries a
choice the standard has already closed. A document pins a component in two
cases. Either a rule is stated in that component's vocabulary, or an
enumeration in `contracts/` decides what is admitted. In the second case a
checker holds a repository to it. In both the component is a rule, and moving it to a register
would turn an enforced decision into a dated survey.

The two are told apart by one question: **would naming something else here be
a violation, or a choice?** A violation means it stays.

Registers in existence today: `032`, `035`, `038`, `060`, `075`, `091`. A
standard with no register is one of two things, and the difference matters.
Either its implementations have not been surveyed yet, which is a gap, tracked
as an issue like any other. Or it closes the choice itself, as the JSON
document storage standard's engine roster does in `contracts/`. Neither is a
statement that the standard admits nothing.

**A register is vendored at handover like a standard**, and the freeze bites
harder here. A client repository keeps a document whose claims stop being
re-checked on the day it leaves. Rule 4 is what protects that reader. The
dates travel with the entries, and a reader can see for themselves how old the
survey is.

Adding one follows the standards path, shortened. Open an issue with the
argument. Write `solutions/<number>-<slug>.md` against the rule ids it claims
to satisfy. Register the class's checkable claims in the ledger, and add the
number to the list above.

## What is here

- `standards/`: the numbered documents above.
- `solutions/`: the acceptable solutions registers. Per standard, what is
  known to satisfy its rules, and when that was last checked.
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

Changing an existing rule follows the same path. A rule that has been violated
in production gets its incident written into the document beside it. That
evidence is the reason these documents get followed. It is also the reason the
next person does not re-litigate a decision already paid for once.
