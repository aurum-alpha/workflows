# The platform contract

## Why this exists

Full-stack meta-frameworks have the right diagnosis. Authentication, RBAC,
background jobs, audit trails, observability, admin surfaces: every product
needs them, and none of them differentiates a product. An organisation that
re-derives them per product ships worse versions of all of them. A framework
answers each once and hands you the answer. That instinct, an opinion for
everything decided once, is correct, and this standard exists to keep it.

These capabilities are exactly the arbitrary decisions the charter's *What this
is for* describes. Every application must decide them, and no application's
domain has an opinion about how. This document says what form our answer to one
of them is allowed to take. **Each capability's own answer belongs to its
standard, in the roster below, never here.**

What a framework gets wrong, for us, is the delivery vehicle. The answers
arrive as a CLI, a runtime library, and a deploy tool. Three consequences
follow, each fatal at this scale:

- **The library is a dependency the application can never leave.** Every
  generated app imports the framework's auth, jobs and observability at
  runtime. The framework's upgrade schedule becomes every product's upgrade
  schedule, and its abandonment becomes every product's problem.
- **One-shot generation locks in and drifts at the same time.** Scaffolded
  code is owned by the app and starts diverging from the framework at once.
  It still depends on that framework's runtime. Locked in *and* diverged, so
  upgrades become archaeology.
- **The framework's language decides ours.** We build in Go, TypeScript, PHP
  and embedded C++. A library was never available as the single answer to
  anything.

The charter already names the failure in the abstract. *A standard that only
works while a particular repository is reachable is not a standard, it is a
dependency*. A framework is that failure with a vendor attached. The remedy is
not fewer opinions. It is the same density of opinion, delivered in a form
that binds a Go service and a PHP service equally. That form keeps binding
after handover.

One more thing changed the economics. Frameworks cache opinions in generators
and libraries because boilerplate was expensive for people to write. Coding
agents write most of this organisation's code now. For an agent the scarce
input is not scaffolding. It is a precise statement of what the output must
look like, and a gate that fails when it does not. A generator is a frozen
cache of an opinion.

A specification with a conformance test *is* the opinion. Any agent can
execute it in any language, and it fails loudly when violated. That is the
charter's law, applied to the application layer.

## The rules

### PC1. An opinion is a contract, never a tool

The answer to a platform capability is a **protocol** or an **interface
specification**. A protocol is behaviour stated at a boundary: an endpoint, a
message, a log line, an environment variable. An interface specification is a
data model and operations with defined semantics, implementable in any
language. The answer is never a CLI an application's lifecycle depends on,
never a framework, never a deploy tool. It is never a shared runtime library an
application must import.

The corollary for what this repository can ship: **shared tooling verifies, or
copies once**. Allowed: a checker that fails a build, a conformance suite that
runs a corpus. Also allowed: a template that is copied at a repository's birth
and never consulted again. Not allowed, whoever writes it: a generator that
stays attached to the application, a tool that owns deploy, a runtime every
application imports. Building the framework in-house does not fix the
framework problem. It relocates it to a vendor we have to staff.

### PC2. Standard protocol first, profile second, internal contract last

Where an industry standard suffices, the standard adopts it as a **written
profile**. Examples: OIDC for identity, OTLP for telemetry, W3C trace context
for propagation, RFC 9457 for HTTP errors, CloudEvents for messages. The
document pins the choices the standard leaves open, because "we use OIDC"
unpinned is four implementations waiting to happen.

This holds for methodologies as much as wire protocols. **The
[twelve-factor app](https://12factor.net/) is the foundation under most of
this roster**. A capability standard that restates a factor cites it and pins
what the factor leaves open. It does not re-derive the factor in house style.
See the charter's *The foundation: twelve-factor* for the citation rule and
the one open tension.

An **internal contract** is invented only where no standard suffices, and the
capability's standard says why. It names the candidate that was evaluated and
the reason it fell short. An internal contract invented where a standard
existed is a second answer to a solved question. That is the failure this
whole repository exists to prevent.

### PC3. A contract is stated in artifacts, not prose alone

Each agreed capability contract carries, under `contracts/<capability>/` in
this repository:

- **The model**: schemas for its data shapes (JSON Schema for messages,
  events and log lines; OpenAPI fragments for endpoints).
- **The operations**: where the contract is interface-level, signatures with
  defined semantics, stated language-neutrally.
- **The conformance corpus**: test cases *as data*. Given-this-then-that
  files any implementation in any language must pass.

The corpus is the piece that makes a polyglot standard enforceable from one
source. Prose drifts from N implementations silently; a corpus fails the one
that drifted, by name. A capability standard without its artifacts is agreed
in principle and unenforceable in fact. The ledger row says which state each
is in.

### PC4. Gates check the boundary, never the implementation

A conformance gate runs the corpus against the implementation, hits the
endpoint, validates the emitted line. It never checks which package is
imported, which framework handled the route, or what the source looks like.
The moment a gate tests an implementation choice, the choice has become a
dependency. PC1 is then broken by the enforcement mechanism itself. Any
implementation that passes the corpus is conformant, including one written
from scratch in an afternoon. That escape hatch existing is the point.

### PC5. A package conforms to the spec, never the reverse

First-party convenience implementations of a contract are allowed: a Go
module, a PHP package, an npm package. They exist so each product does not
hand-roll the same envelope parser. They are allowed under a standing rule and
three guard rails. The standing rule is the title of this section: the spec
and its corpus are normative, the package is downstream. A behaviour change
lands in the spec first, in its own change, and the package follows.

- **One package per capability contract.** No `aurum-common`. A grab-bag
  package is the framework re-forming by accretion.
- **No shared package depends on another shared package.** The moment they
  stack, importing one means importing the pile, and the pile is a framework.
- **Every package release passes the contract's own corpus.** That is the
  same gate a bespoke implementation faces. Per PC4 the gate cannot tell them
  apart, and per this rule it must not.

A repository is permitted to substitute its own implementation of any contract
and stay green. At handover, a client repository that uses a shared package
vendors it, exactly as it vendors the standards documents. These packages
survive that because each is small, single-capability, and corpus-defined.

### PC6. Contracts evolve additively

Every versioned shape (envelopes, events, log lines) carries a schema-version
field. Changes are additive: new optional fields, never a removed or
repurposed one. A breaking change is a new version. The contract states its
deprecation window: how long implementations must accept the old version
while emitting the new. A body of specifications without a change discipline
re-creates the drift problem one level up. The added indignity is that the
documents were supposed to be the fix.

## Terms

The words the standards share, defined once. A standard uses these words in
these senses and defines only the words that are its own. Where a term's rules
live in a standard, the entry points there. Where that standard is not yet
written, it points at the roster row.

### Structure

- **Platform.** The body of standards, contracts and shared workflows in this
  repository, together with the tools that enforce them. Not a runtime and not
  a library (PC1).
- **Portfolio.** The set of repositories the platform's standards apply to,
  present and future. A standard is written for the portfolio and never for any
  member of it (the charter's D4).
- **Repository.** The unit of versioning and of building. One repository has
  one version, and one build run produces every artifact it ships at that
  version ([`010-ci.md`](010-ci.md), Principles 7 and 15). A repository can
  hold one service or many.
- **Service.** A collection, never a process. It is the servers and workers
  that together supply one capability under one name and one ownership, plus
  the backing services they attach. A service has one or more processes. It
  can have no server, when it is workers only, or no worker. Where a service
  holds state, that state lives in a stateful server it attaches. The service
  owns that state exclusively: the schema, the bucket, the volume, the topic,
  and the credential to it.

  Every process that holds that credential belongs to the service
  ([`025-structured-data.md`](025-structured-data.md) SD13 states this for
  structured data). A service lives in exactly one repository. The reason:
  every process that touches one schema must be built beside that schema's
  migrations, in one run, at one version. A repository can hold several
  services. Services integrate only through a server's interface or through
  messages, never through one another's state.
- **Process.** An operating-system process, in exactly that sense: one running
  program with its own process id, address space, environment, standard
  streams, signals, and exit code. Nothing more abstract is meant anywhere in
  these standards. A container runs one process. It starts, becomes ready,
  receives `SIGTERM`, and exits, and [`030-service.md`](030-service.md)'s
  rules bind it. A process is of exactly one type, server or worker, never
  both. Several processes of one type are replicas.
- **Server.** A long-running process that handles network requests on demand,
  synchronously, and runs no jobs. A server is **stateless** when nothing it
  holds needs to survive its restart, because its state lives in a stateful
  server it attaches. Every server the portfolio writes is stateless. A server
  is **stateful** when it maintains state across restarts and is itself where
  that state lives. Every persistence engine is a stateful server, and they
  differ only in the shape of what they persist.

  The shapes: structured data in a relational database, documents in a
  document store, keys and values in a cache, objects in an object store.
  Also files on a network filesystem, blocks on a block-storage target,
  messages in a broker. None stands above the others. Each is a stateful
  server the portfolio attaches as a backing service rather than writes. The
  rules that bind what is inside it are the data standards', not the service
  contract's.
- **Worker.** A process, long-running or short-running, that executes jobs
  outside any request, in response to a trigger. The long-running form, the
  **pool**, consumes a queue and is scaled by replicas against its backlog. The
  short-running form, the **one-shot**, runs one job and exits with the outcome
  as its exit code. Workers are [`035-workers.md`](035-workers.md)'s.
- **Client.** Anything that initiates a request to a server. Examples: a
  browser running the web client ([`090-web-client.md`](090-web-client.md)),
  another service's process, a command-line tool, a third party. A client
  carries an identity ([`060-auth.md`](060-auth.md)) and is authorized
  ([`070-rbac.md`](070-rbac.md)). It never holds a credential to any
  service's state.
- **Backing service.** A service a process consumes over the network, attached
  by configuration and never by code ([`030-service.md`](030-service.md) SC3;
  [factor IV](https://12factor.net/backing-services)). Ours or a vendor's: one
  stateful server or a cluster of them, a broker, a mail relay, a third-party
  API. There is no third kind of thing a process reaches over the network. It
  is a server, or a service made of servers, which is why the word is service
  and not resource. What a process has that is not a backing service is local
  and ephemeral: its image, its environment, its scratch disk.

### Delivery

- **Artifact.** Any output of a build run: an image, a browser bundle, a
  package, a rendered manifest. Every artifact carries the repository's
  version.
- **Image.** An OCI container image, the unit of packaging and deployment. An
  image does one thing: it is a server, or a worker, or the migrate step, and
  never more than one of those. Images are cut on dependency closure,
  credential and configuration surface ([`010-ci.md`](010-ci.md), Principle
  15).
- **Build run.** One execution of a repository's CI on one commit, producing
  every artifact the repository ships and testing them together. The artifacts
  of one run share a provenance and assert compatibility with one another by
  that fact ([`010-ci.md`](010-ci.md), Principle 7).
- **Version.** The repository's, in `.version`, SemVer, moved by a release pull
  request that touches nothing else. Never an artifact's
  ([`010-ci.md`](010-ci.md), Principle 15).
- **Release.** The officially published, versioned artifacts of one build
  run, suitable for operational deployment. That is the images, bundles and
  rendered manifests, tagged with the repository's version. A release is made
  by the release pull request and publishes what main has already gated. It
  runs nothing anywhere ([`010-ci.md`](010-ci.md)).
- **Deployment.** Taking a release's artifacts and running them in one
  environment. The deployment-triggered jobs run as steps in declared order
  with the migrate step first, then the servers and workers roll out. A
  deployment names a release and an environment. Also the name of that
  trigger.
- **Environment.** A deployment target, such as development, staging or
  production, differing from every other only in configuration
  ([factor X](https://12factor.net/dev-prod-parity)).
- **Configuration.** The values a process reads from its environment at start
  ([factor III](https://12factor.net/config);
  [`030-service.md`](030-service.md) SC3). A process's configuration surface is
  the set it reads.
- **Credential.** A secret that grants a process access to a backing service.
  One credential per backing service per service; the migration credential
  separate from the runtime credential. A database's credential is present in
  the deployables of one repository and no other, which is the checkable edge
  of a service.
- **Runner.** The platform component that starts a one-shot worker on a tick,
  at a deployment step, or by an operator's hand. The platform states what a
  runner must do and builds none; every runtime it could sit on supplies one.
- **Secret.** A configuration value whose disclosure grants access or lets
  someone forge something a service trusts. Examples: a credential, a signing
  or encryption key, a webhook secret. Every credential is a secret; not every
  secret is a credential. Delivered, declared, named, redacted and rotated per
  [`032-secrets.md`](032-secrets.md).
- **Finding.** What a checker or a scan reports when a rule is broken at a
  boundary it can see. It is a named slug, attributable to a rule, that a gate
  turns red on and an audit prints. An acceptance
  ([`085-security-baseline.md`](085-security-baseline.md) SB2) is a finding a
  repository has recorded a dated reason to tolerate.

### Work

- **Job.** The definition of a bounded task: named, with an input, a key, a
  declared class, and an outcome. A job is never a process; it is packaged only
  by being inside a worker. Jobs are [`057-jobs.md`](057-jobs.md)'s.
- **Run.** One execution of a job by a worker, with a run id, a trigger, a key,
  and an outcome. A record of all four lands in the service's database.
- **Trigger.** What causes a run. There are four: a **message** arriving, a
  **tick** of a schedule, a **deployment** step, and an **operator**. A stream of
  triggers, which is only ever messages, goes to a pool; a single invocation
  goes to a one-shot.
- **Event.** An occurrence a service reports as a fact: past tense, about one
  entity. **Message.** An event in its envelope, on a transport, with an
  identity: a CloudEvent under the profile of
  [`055-messaging.md`](055-messaging.md) AM1. The two words name the fact and
  its carriage; 055 says "message" wherever the envelope is meant.
- **Transport.** The mechanism that carries messages: a broker, a cloud queue,
  a stream, a table in the service's own database, an HTTP push. The transport
  is not the contract ([`055-messaging.md`](055-messaging.md) AM2).
- **Queue.** The buffer, on a transport, from which a pool consumes, delivering
  each message at least once. A queue belongs to one service.
- **Outbox.** The table in a service's database where a message is written in
  the same transaction as the change that caused it. A relay job publishes it
  from there ([`055-messaging.md`](055-messaging.md) AM4). **Inbox.** The
  table where a consumer records each `(source, id)` it has processed, in the
  same transaction as the effect ([`055-messaging.md`](055-messaging.md) AM3).
- **Schedule.** A five-field cron expression in UTC, declared beside a job in
  the repository and rendered to the runner at deployment. **Tick.** One firing
  of a schedule at one scheduled instant, identified by the job's name and
  that instant. Two firings of one tick are therefore one piece of work.
- **Operator.** A person with the standing to run a job by hand, deploy a
  release, or intervene in a running system. The fourth trigger.
- **Migration.** One ordered `.sql` file that moves a database's schema forward
  and converges if run again. **The migrate step** is the deployment-triggered
  job that applies the pending ones. A one-shot worker runs it in its own image
  with its own credential ([`025-structured-data.md`](025-structured-data.md)
  SD2, SD3).
- **Backfill.** A job that populates data after an expand migration: long,
  single-flight, resumable, rate-bounded, and never inside the migration.
- **Notification.** A message to a person with an identity record, through a
  channel, about an event. It is recorded per recipient per channel in the
  sending service's database ([`058-notifications.md`](058-notifications.md)).
  An alert to an operator is not one.
- **Flag.** A named, typed value a process asks for at a decision point. Its
  answer can differ by environment, tenant or user without a new release. It
  is declared in the repository, evaluated through the OpenFeature API, and
  never an authorization input
  ([`038-feature-flags.md`](038-feature-flags.md)).

### Data

- **System of record.** The store whose rows are the authority for an entity:
  the relational store ([`027-json-document-storage.md`](027-json-document-storage.md)
  DS1). Every other store holding a copy of that entity is *derived* from it
  and rebuildable by a job. A store that is not rebuildable is *primary* and
  is a database in every sense.
- **Object.** Bytes under a key in an object store, owned by exactly one row
  of one service's database, which holds its reference. The store is a
  stateful server attached as a backing service
  ([`026-blob-storage.md`](026-blob-storage.md)).
- **Document.** A JSON document: a record a JSON document store reads and
  writes whole, under one id. It carries its own `schema_version` because no
  schema outside it records its shape
  ([`027-json-document-storage.md`](027-json-document-storage.md)). Never a
  file, since a PDF or a spreadsheet is an object. Never a row's substitute
  where a relational constraint governs the data.
- **Backup.** A copy of a stateful server's state taken by the engine's own
  mechanism under a credential no process of the service holds. It is kept in
  a different failure domain, and proven restorable by a drill
  ([`028-backup-and-recovery.md`](028-backup-and-recovery.md)). Not a replica,
  which applies every mistake within seconds.
- **Erasure ledger.** The record, per erased subject per request, of what an
  erasure removed, transformed or redacted. It is kept in the service's
  database and copied to the backup domain. It is replayed after any restore
  before the service is readmitted to traffic
  ([`028-backup-and-recovery.md`](028-backup-and-recovery.md) BR6).
- **Subject.** A person about whom a service holds data, identified inside the
  service by the application's own user public id
  ([`060-auth.md`](060-auth.md) AU3). What a service owes one is
  [`082-data-subject-rights.md`](082-data-subject-rights.md)'s.

### Governance

The charter ([`../README.md`](../README.md)) defines the words about the
documents themselves: **standard**, **rule**, **contract**, **corpus**,
**gate**, and the enforcement **tiers**. They are not restated here.
**Capability**, in this document's sense, is one of the concerns in the roster
below. It is something every product needs, nothing in any product's domain
has an opinion about, and the platform therefore decides once.

## The capability roster

Every platform capability these standards have an opinion on, or has decided to
have one. **A capability's absence from this table is a claim that we have
considered it and declined**. A reader can then distinguish "not yet written"
from "not considered". The first is a row saying so. The second is a gap in
this table, which is a defect in this document.

A row gains its link when the standard lands; the ledger tracks what is
enforced. Where a capability has no document yet, the work is an issue in this
repository.

| Capability | The standard takes the form of | Document |
|---|---|---|
| Authentication | OIDC profile: a proxy is the relying party, one signed identity token crosses to the backend, the application is never in the authentication chain | [`060-auth.md`](060-auth.md) |
| Authorization | Application-owned RBAC as a full interface spec: model, operations, semantics, corpus — never derived from token claims | [`070-rbac.md`](070-rbac.md) |
| Identity provisioning | The application originates the user and creates the identity; four operations over SCIM or an admin API | [`060-auth.md`](060-auth.md) AU4 |
| Session lifecycle | Idle and absolute limits, invisible refresh, back-channel logout with a short-token backstop; a session bound to exactly one tenant at login, a tenant being an authentication boundary and a role an authorization boundary inside it | [`060-auth.md`](060-auth.md) AU5, AU8 |
| Configuration | [Factor III](https://12factor.net/config) profile: variable naming, fail-loud on missing, no environment detection in code | [`030-service.md`](030-service.md) SC3 |
| Secrets | [Factor III](https://12factor.net/config) profile for delivery: an environment variable, or a file at a declared path, placed by the platform before the process starts; never a vendor SDK in application code; one secret store per platform, rendered into the environment by the runtime's own mechanism, the repository shipping a name-to-store-path mapping and never a value. A per-service declaration of every secret (owner, kind, images, age, rotation mode) that the redactor, the image set and the freshness check read; `<SUBJECT>_<KIND>` naming; a secret is recognised by declaration, never by shape; rotate first, then investigate, then audit | [`032-secrets.md`](032-secrets.md) |
| Logging | [Factor XI](https://12factor.net/logs) profile: structured log-line schema to stdout; transport is the platform's problem | [`030-service.md`](030-service.md) SC2 |
| Health & readiness | Two-endpoint contract, fixed paths and shapes | [`030-service.md`](030-service.md) SC1 |
| Service lifecycle | [Factor IX](https://12factor.net/disposability) profile: SIGTERM means drain — readiness flips, in-flight completes, stated timeout | [`030-service.md`](030-service.md) SC4 |
| Runtime provenance | The running service reports the commit and build it is | [`030-service.md`](030-service.md) SC5 |
| Observability & context propagation | OTLP profile; W3C trace context; one id vocabulary across logs, traces, events | [`040-observability.md`](040-observability.md) |
| Service interfaces & HTTP APIs | Protocol selection (HTTP default, gRPC internal-only, SSE before WebSocket); OpenAPI description; RFC 9457 errors; pagination, versioning, idempotency keys, retry semantics; snake_case wire naming | [`050-http.md`](050-http.md) |
| Identifiers & primitives | Internal keys never exposed; public-id format table; RFC 3339 UTC; integer minor-unit money | [`020-identifiers.md`](020-identifiers.md) |
| Structured data | SQL as the query language with no runtime generation; migrations as ordered `.sql` files shipped in the image and run as a step before rollout; expand-only; declared isolation levels that are the RBAC scope types, proven by enumeration; per-engine storage profile | [`025-structured-data.md`](025-structured-data.md) |
| JSON document storage | The relational store is the system of record and its JSON column is the first answer; a document database — a document engine, a key-value document store, a search engine — is admitted beside it, the hybrid model, by a declaration naming which of three tests the column failed and in one of two roles — derived (rebuilt by a job, not backed up) or primary (a database in every sense); the structured-data rules for tenancy, identity, hard delete, privacy and authored queries transfer, migrations become a version window and a backfill, and the schema lives in the documents | [`027-json-document-storage.md`](027-json-document-storage.md) |
| Backup and recovery | A recovery declaration per stateful store — RPO, RTO, the engine's mechanism, retention between a floor and a ceiling bounded by the erasure horizon, a drill cadence; derived stores declared `rebuild` and not backed up; restore exercised as a periodic job that measures the objectives and blocks a deployment when stale; an erasure ledger copied to the backup domain and replayed before readiness | [`028-backup-and-recovery.md`](028-backup-and-recovery.md) |
| Async messaging | CloudEvents 1.0 profile as the envelope; at-least-once with `(source, id)` deduplication through inbox and outbox; workers, never timers; Standard Webhooks signing at the edge | [`055-messaging.md`](055-messaging.md) |
| Jobs | The job as an interface: a named, bounded task with an input, a key, a declared class and an outcome; three duplicate policies; a run record; single-flight in the job; absence as the failure of a periodic job | [`057-jobs.md`](057-jobs.md) |
| Workers | Two worker models, the pool and the one-shot, packaged per service and started by a runner the platform specifies and does not build — [factor XII](https://12factor.net/admin-processes) made specific | [`035-workers.md`](035-workers.md) |
| Audit events | Internal event contract: application data and not a log line; actor separate from target; the action string is the permission string; a stated floor of what must emit; OCSF at the export boundary rather than as the record | [`080-audit.md`](080-audit.md) |
| Security baseline | Base images pinned by digest as actions are; lockfile, reachability and image scans with acceptances that expire; a fixed response header set per response class (document, API, asset), asserted by the start check; TLS floor and rate-limit floor; `SECURITY.md` plus RFC 9116 `security.txt`; CycloneDX SBOM per image; secrets doctrine is the secrets row's | [`085-security-baseline.md`](085-security-baseline.md) |
| Feature flags | OpenFeature profile as the evaluation API, the provider as configuration; a flag declared in the repository with one of four kinds and a date after which it is a finding; every boolean defaults to `false`; a flag gates and never authorizes; the evaluation context is the id vocabulary and carries nothing personal; the browser receives an evaluated set | [`038-feature-flags.md`](038-feature-flags.md) |
| Notifications | The record in the service's database as the truth for *did we tell them*; a pipeline of three 057 jobs and two 055 messages; two classes with consent per declared category per channel and a security floor no preference mutes; RFC 8058 one-click unsubscribe; provider behind one adapter, swapped by configuration | [`058-notifications.md`](058-notifications.md) |
| Blob storage | S3 API profile as the storage protocol; one private bucket per service per environment; an object reference in the owning row and never a URL of any kind; every read and write passes through the service by object id after the authorization check, the store reachable from the service alone; uploads the server streams to the store and verifies against the bytes; scan before serve by declared audience; hard delete through the outbox and a periodic purge | [`026-blob-storage.md`](026-blob-storage.md) |
| Data subject rights | Export and erasure as request resources over 050's conventions, worked by 057 jobs from a declared personal-data inventory; three treatments (`delete`, `anonymise` as an allowlist, `retain` under a named basis with an expiry); a legal hold; every erasure proved by an audit event and a ledger entry | [`082-data-subject-rights.md`](082-data-subject-rights.md) |
| What a browser may hold | Session cookie only: no token in JavaScript or web storage, no provider credential in the bundle, a `401` answered by navigating. The authentication architecture itself is the authentication row's | [`090-web-client.md`](090-web-client.md) WC1 |
| Client configuration | Fetched at load from `/config.json`, never compiled into the bundle — [factor III](https://12factor.net/config) honoured through the serving origin's environment, and build-once preserved; one document shape for every estate surface, naming its class and environment | [`090-web-client.md`](090-web-client.md) WC2 |
| API client contract | One generated client module owning problem+json parsing, idempotency keys, bounded retries and cursor paging at the boundary | [`090-web-client.md`](090-web-client.md) WC3 |
| Presentation, formatting & i18n | The other half of the base-representation rule: viewer's locale and zone, `Intl` formatting, currency exponents | [`090-web-client.md`](090-web-client.md) WC4 |
| Frontend observability | The browser does not originate the server's trace; correlation by request id; a closed error-report shape | [`090-web-client.md`](090-web-client.md) WC5 |
| Web estate and the front door | Three surface classes — front door, product, internal — each with a fixed identity posture and decidable from the host name; the front door as a built directory with environments, no session or credential, its origin rendering the web client's bootstrap document; content as data in the repository with a CMS only as a declared source; every surface maintainable from its repository alone; four seams that are existing contracts; automated actors as workload identities | [`091-web-estate.md`](091-web-estate.md) |
| Tenant hostnames | The hostname chooses a tenant's entry before login and is only checked for agreement after; `404` at the edge for a host that names no tenant; host-only session cookies with `Domain=` never set; one callback host per topology; a pre-issued wildcard for subdomains and a `pending → verified → active` state machine for custom domains with the tenant table as the certificate allowlist; tenant hosts `noindex` | [`092-tenant-hostnames.md`](092-tenant-hostnames.md) |
| Billing | The catalog as a versioned file in the repository from which the provider is provisioned; the subscription as a projection of an append-only ledger with recorded and effective times and one pending change; four entitlement kinds — capability, quota, allowance, setting — never per user; a pure derivation with a decision corpus, run after the permission and before the domain operation, refused as `403 entitlement-required`; one provider adapter off the request path; webhooks in under AM8 and reconciliation as a periodic job that raises a finding | [`075-billing.md`](075-billing.md) |

Two rows deserve a word on why they are the worked examples:

**Authorization** is the model interface-level contract. Its standard defines
the domain model (subject, role, permission, grant, scope) as schemas. It
defines the operations (`check`, `grants-for`) as signatures with semantics:
deny by default, how tenancy scopes a grant. It carries a corpus of decision
cases: given these grants, this check returns deny. Three languages implement
it; one corpus judges all three. When someone asks what "an interface spec,
not a library" means, the answer is that standard.

**Async messaging** is the model of PC2 working as intended, and it did not
go the way this paragraph first predicted. Its standard was expected to
evaluate CloudEvents and then invent an envelope. The evaluation found that
CloudEvents suffices. So the envelope is a profile, and the invention is
confined to what no wire standard covers. That is delivery: at-least-once, the
inbox and the outbox, the worker. The discipline PC2 demands is visible in
what did *not* get invented.

## Open work

- Land the per-capability standards from the roster, each by the charter's
  own path: issue, document, ledger rows, artifacts.
- The first corpus run in anger. Authorization is the candidate, as the
  worked example above argues.
- The template repositories, the copy-once mechanism PC1 permits, are
  follow-on work. They wait until enough contracts exist for a template to
  have something to conform to.
