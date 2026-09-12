# The platform contract

## Why this exists

Every product needs authentication, authorization, background jobs, audit
trails, observability and admin surfaces, and none of them differentiates a
product. A full-stack meta-framework has the right diagnosis: answer each once
and hand every product the answer. Its vehicle is wrong for us, because a
runtime library, a CLI and a deploy tool bind one language and one vendor.

This standard keeps the density of opinion and fixes the form. A platform
capability is answered by a contract stated in artifacts and checked at the
boundary. That form binds a Go service and a PHP service equally, after
handover as before. A specification with a conformance test *is* the opinion.

## The rules

### PC1. An opinion is a contract, never a tool

The answer to a platform capability is a **protocol** or an **interface
specification**. A protocol is behaviour stated at a boundary: an endpoint, a
message, a log line, an environment variable. An interface specification is a
data model and operations with defined semantics, implementable in any
language, of which the authorization contract is the worked example. The
answer is never a CLI an application's lifecycle depends on, never a framework,
never a deploy tool. It is never a shared runtime library an application must
import.

A framework delivers its answers as a CLI, a runtime library and a deploy
tool, and each fails at this scale:

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

The [twelve-factor app](https://12factor.net/) is the foundation under most of
this roster. A rule restating a factor cites it and pins what the factor
leaves open.

An **internal contract** is invented only where no standard suffices, and the
capability's standard says why. It names the candidate that was evaluated and
the reason it fell short. An internal contract invented where a standard
existed is a second answer to a solved question.

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
hand-roll the same envelope parser. The spec and its corpus are normative and
the package is downstream. A behaviour change lands in the spec first, in its
own change, and the package follows. Three guard rails hold:

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
re-creates the drift problem one level up.

## Terms

The words the standards share, defined once. A standard uses these words in
these senses and defines only the words that are its own. Where a term's rules
live in a standard, the entry points there.

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
  the backing services they attach. It owns its state exclusively and lives in
  exactly one repository. Services integrate only through a server's interface
  or through messages, never through one another's state
  ([`025-structured-data.md`](025-structured-data.md) SD13).
- **Process.** An operating-system process, in exactly that sense: one running
  program with its own process id, address space, environment, standard
  streams, signals, and exit code. A container runs one process, of exactly
  one type, server or worker; several of one type are replicas
  ([`030-service.md`](030-service.md)).
- **Server.** A long-running process that handles network requests on demand,
  synchronously, and runs no jobs. A server is **stateless** when nothing it
  holds needs to survive its restart; every server we write is stateless. A
  server is **stateful** when it is itself where state lives. Every persistence
  engine is a stateful server, attached as a backing service rather than
  written.
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
  API. What a process has that is not a backing service is local and
  ephemeral: its image, its environment, its scratch disk.

### Delivery

- **Artifact.** Any output of a build run: an image, a browser bundle, a
  package, a rendered manifest. Every artifact carries the repository's
  version.
- **Image.** An OCI container image, the unit of packaging and deployment. An
  image does one thing: it is a server, or a worker, or the migrate step
  ([`010-ci.md`](010-ci.md), Principle 15).
- **Build run.** One execution of a repository's CI on one commit, producing
  every artifact the repository ships and testing them together. The artifacts
  of one run share a provenance and assert compatibility with one another by
  that fact ([`010-ci.md`](010-ci.md), Principle 7).
- **Version.** The repository's, in `.version`, SemVer, moved by a release pull
  request that touches nothing else ([`010-ci.md`](010-ci.md), Principle 15).
- **Release.** The published, versioned artifacts of one build run, tagged
  with the repository's version and suitable for deployment
  ([`010-ci.md`](010-ci.md)).
- **Deployment.** Taking a release's artifacts and running them in one
  environment, the migrate step first, then the servers and workers. Also the
  name of that trigger.
- **Environment.** A deployment target, such as development, staging or
  production, differing from every other only in configuration
  ([factor X](https://12factor.net/dev-prod-parity)).
- **Configuration.** The values a process reads from its environment at start
  ([factor III](https://12factor.net/config);
  [`030-service.md`](030-service.md) SC3). A process's configuration surface is
  the set it reads.
- **Credential.** A secret that grants a process access to a backing service
  ([`032-secrets.md`](032-secrets.md) SE6).
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
  the same transaction as the change that caused it
  ([`055-messaging.md`](055-messaging.md) AM4). **Inbox.** The table where a
  consumer records each `(source, id)` it has processed, in the same
  transaction as the effect (AM3).
- **Schedule.** A five-field cron expression in UTC, declared beside a job in
  the repository and rendered to the runner at deployment. **Tick.** One firing
  of a schedule at one scheduled instant, identified by the job's name and
  that instant. Two firings of one tick are therefore one piece of work.
- **Operator.** A person with the standing to run a job by hand, deploy a
  release, or intervene in a running system. The fourth trigger.
- **Migration.** One ordered `.sql` file that moves a database's schema forward
  and converges if run again. **The migrate step** is the deployment-triggered
  job that applies the pending ones
  ([`025-structured-data.md`](025-structured-data.md) SD2, SD3).
- **Backfill.** A job that populates data after an expand migration, never
  inside the migration.
- **Notification.** A message to a person with an identity record, through a
  channel, about an event ([`058-notifications.md`](058-notifications.md)). An
  alert to an operator is not one.
- **Flag.** A named, typed value a process asks for at a decision point. Its
  answer can differ by environment, tenant or user without a new release
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
  writes whole, under one id, carrying its own `schema_version`
  ([`027-json-document-storage.md`](027-json-document-storage.md)). Never a
  file, since a PDF or a spreadsheet is an object.
- **Backup.** A copy of a stateful server's state taken by the engine's own
  mechanism. It is kept in a different failure domain and proven restorable
  by a drill ([`028-backup-and-recovery.md`](028-backup-and-recovery.md)).
  Not a replica.
- **Erasure ledger.** The record, per erased subject per request, of what an
  erasure removed, transformed or redacted
  ([`028-backup-and-recovery.md`](028-backup-and-recovery.md) BR6).
- **Subject.** A person about whom a service holds data, identified inside the
  service by the application's own user public id
  ([`060-auth.md`](060-auth.md) AU3). What a service owes one is
  [`082-data-subject-rights.md`](082-data-subject-rights.md)'s.

### Governance

The charter ([`../README.md`](../README.md)) defines **standard**, **rule**,
**contract**, **corpus**, **gate**, and the enforcement **tiers**.
**Capability**, in this document's sense, is one of the concerns in the roster
below. It is something every product needs, nothing in any product's domain
has an opinion about, and the platform therefore decides once.

## The capability roster

Every platform capability these standards have an opinion on, or have decided
to have one. **A capability's absence from this table is a claim that we have
considered it and declined**. A row without a document is not yet written; a
capability missing from the table is a defect in this document.

| Capability | The standard takes the form of | Document |
|---|---|---|
| Authentication | OIDC profile | [`060-auth.md`](060-auth.md) |
| Authorization | Interface specification: model, operations, corpus | [`070-rbac.md`](070-rbac.md) |
| Identity provisioning | SCIM or admin API profile | [`060-auth.md`](060-auth.md) AU4 |
| Session lifecycle | Internal contract | [`060-auth.md`](060-auth.md) AU5, AU8 |
| Configuration | [Factor III](https://12factor.net/config) profile | [`030-service.md`](030-service.md) SC3 |
| Secrets | [Factor III](https://12factor.net/config) profile for delivery; internal contract for the declaration | [`032-secrets.md`](032-secrets.md) |
| Logging | [Factor XI](https://12factor.net/logs) profile | [`030-service.md`](030-service.md) SC2 |
| Health & readiness | Internal contract: two endpoints | [`030-service.md`](030-service.md) SC1 |
| Service lifecycle | [Factor IX](https://12factor.net/disposability) profile | [`030-service.md`](030-service.md) SC4 |
| Runtime provenance | Internal contract | [`030-service.md`](030-service.md) SC5 |
| Observability & context propagation | OTLP and W3C trace context profile | [`040-observability.md`](040-observability.md) |
| Service interfaces & HTTP APIs | HTTP, OpenAPI and RFC 9457 profile | [`050-http.md`](050-http.md) |
| Identifiers & primitives | RFC 9562, RFC 3339 and ISO 4217 profile | [`020-identifiers.md`](020-identifiers.md) |
| Structured data | SQL adopted whole; internal contract for migrations and isolation | [`025-structured-data.md`](025-structured-data.md) |
| JSON document storage | JSON Schema 2020-12 profile; internal contract for admission | [`027-json-document-storage.md`](027-json-document-storage.md) |
| Backup and recovery | Internal contract: a recovery declaration | [`028-backup-and-recovery.md`](028-backup-and-recovery.md) |
| Async messaging | CloudEvents 1.0 profile | [`055-messaging.md`](055-messaging.md) |
| Jobs | Interface specification | [`057-jobs.md`](057-jobs.md) |
| Workers | [Factor XII](https://12factor.net/admin-processes) profile | [`035-workers.md`](035-workers.md) |
| Audit events | Internal contract; OCSF at the export boundary | [`080-audit.md`](080-audit.md) |
| Security baseline | Internal contract | [`085-security-baseline.md`](085-security-baseline.md) |
| Feature flags | OpenFeature profile | [`038-feature-flags.md`](038-feature-flags.md) |
| Notifications | Internal contract | [`058-notifications.md`](058-notifications.md) |
| Blob storage | S3 API profile | [`026-blob-storage.md`](026-blob-storage.md) |
| Data subject rights | Internal contract | [`082-data-subject-rights.md`](082-data-subject-rights.md) |
| What a browser may hold | Internal contract | [`090-web-client.md`](090-web-client.md) WC1 |
| Client configuration | [Factor III](https://12factor.net/config) profile | [`090-web-client.md`](090-web-client.md) WC2 |
| API client contract | Internal contract | [`090-web-client.md`](090-web-client.md) WC3 |
| Presentation, formatting & i18n | `Intl` profile | [`090-web-client.md`](090-web-client.md) WC4 |
| Frontend observability | Internal contract | [`090-web-client.md`](090-web-client.md) WC5 |
| Web estate and the front door | Internal contract | [`091-web-estate.md`](091-web-estate.md) |
| Tenant hostnames | Internal contract | [`092-tenant-hostnames.md`](092-tenant-hostnames.md) |
| Billing | Internal contract | [`075-billing.md`](075-billing.md) |
