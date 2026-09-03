# Data subject rights: export and erasure as endpoint contracts, and the inventory that makes them answerable

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/data-subject-rights/`](../contracts/data-subject-rights/). It
leans on [`050-http.md`](050-http.md) for the request resources,
[`057-jobs.md`](057-jobs.md) and [`035-workers.md`](035-workers.md) for the
work, [`025-structured-data.md`](025-structured-data.md),
[`026-blob-storage.md`](026-blob-storage.md) and
[`027-json-document-storage.md`](027-json-document-storage.md) for the stores,
[`080-audit.md`](080-audit.md) for the record, [`060-auth.md`](060-auth.md)
for the identity, [`070-rbac.md`](070-rbac.md) for who may act for whom, and
[`020-identifiers.md`](020-identifiers.md) for ids and instants.

This document governs **what a service owes a person about whom it holds
data**: the inventory that says where that data is, the request through which
the person, or a tenant administrator acting for them, asks for a copy or for
removal, the package the copy takes, the job that removes it and what
survives, and the hold that suspends removal. **What it does not define is
the storage the data sits in, the audit record, the identity, or the
notification** — 025's, 026's, 027's, 080's, 060's and
[`058-notifications.md`](058-notifications.md)'s.

## Why this exists

Every service that holds data about people will be asked two questions by
one of them: *give me everything you hold about me*, and *remove it*. The
regimes that grant those rights differ in deadline and vocabulary and agree on
the two acts, and no product's domain has an opinion about how the request is
received, how its progress is reported, what shape the copy takes, or what
"removed" means at the row — decisions the charter says are made once, here.

Left to each repository, the cheapest answers arrive first, and each fails as
a general property. **A script written when the request comes** exports what
its author remembers of the schema and deletes what its author knew about; the
table added last quarter is in neither. **A delete with the foreign keys left
to cascade** removes what the keys reach — the invoices a tax authority
requires kept, the audit trail 080 AE4 says outlives its subject — and leaves
what they do not: the object in the bucket, the document in the index, the
provider's copy, the row in yesterday's backup. **A `deleted_at` column called
erasure** holds the data after its owner asked otherwise (025 SD12). **A
database dump filtered by user id** hands the person internal keys, a
password hash, and every other person who shares a row with them.

The four share one omission: none can say *where the personal data is*. Both
questions are functions of that one input — the stores that hold data about a
person, the column that ties each row to them, and what happens to the row
when they leave — and without it every answer is a guess that ages with the
schema. With it, export and erasure are mechanical: a job walking a
declaration in dependency order. The declaration is the hard part, and this
standard makes it a schema, so a store holding personal data with no entry
fails a check instead of surfacing in a complaint. Everything else — routes,
statuses, errors, verification, package, treatments, grace, deadlines, holds,
proof — is decided here; the inventory's contents remain the repository's
domain judgment, made once, reviewed as a diff.

### The standards evaluated first, per PC2

The rights are defined by law and not by a technical standard: the regimes
state outcomes and deadlines, never formats or endpoints. PC2's evaluation is
therefore of the pieces a technical answer is assembled from.

**050's HTTP conventions cover the boundary and are adopted whole**: the
request is a resource with a status, errors are RFC 9457 problem+json (HA3),
creation accepts an `Idempotency-Key` (HA6), the wire is snake_case (HA8).
**057 and 035 cover the work**: an export is a per-event job started by the
request's outbox message, an erasure a per-event job dispatched when its grace
ends, retention a periodic job. **ZIP and JSON Lines are adopted for the
package**: a container every operating system opens, and a row format a job
streams in keyset batches (057 JB7) — which is what "structured, commonly used
and machine-readable" means in practice. **060 AU4's `revokeAppAccess`** ends
the subject's access to the identity tier.

**The Data Transfer Project** was evaluated for the package and not adopted:
it moves data between providers through vertical-specific models, and the
recipient here is the person, whose data has the shape of the service's own
inventory. **The W3C Data Privacy Vocabulary** describes processing activities
rather than tables and is not the inventory's form; its legal-basis concepts
are borrowed for the `legal_basis.kind` values so a retention declaration maps
onto a record of processing without translation. **What no standard covers,
and this document invents**: the inventory and its coverage check (DR1), the
request's status machine (DR2), grace and dispatch (DR4), the treatment
vocabulary and allowlist anonymisation (DR5), the hold (DR6), the proof pair
(DR7).

## The rules

### DR1. The data inventory is the precondition, and it is a declaration

**Every store that holds data about a person is declared, in the repository
beside the schema, against
[`inventory.schema.json`](../contracts/data-subject-rights/inventory.schema.json).**
One inventory per service, because 025 SD13 gives each service its own stores
and none can declare another's. An entry names the store and its kind
(`relational`, `document`, `blob`, `external`), the column that ties a row to
the subject, the entry through which that column resolves where the subject is
reached indirectly (`via`), whether the store is tenant-scoped, its treatment
on erasure (DR5), and whether it is in the export (DR3).

**One entry per subject column, not per table.** A row that names two people
— a message with a sender and a recipient, an audit event with an actor and a
target — is two entries with two treatments, because erasure targets a subject
and a subject may appear in either position. An implementation that reasons
per row gets exactly one of the two right: the failure 080 AE7's redaction
corpus already detects, arriving here for every table.

**A store with no personal data is declared too**, with `treatment: none` and
a reason. The inventory is complete when every table in the engine's catalog
has an entry, and the coverage check enumerates the catalog to prove it — 025
SD6's pattern, for the same reason: a list of tables to check rots the day
someone adds a table, and an enumeration cannot, so absence from the inventory
is the finding rather than a table quietly assumed clean. The check also
refuses an inventory it cannot execute: a retained or excluded
column the table lacks, a `via` naming no entry, two membership entries (DR4),
and a `NOT NULL` non-text column that is neither structural nor retained, for
which reduction has no value to write — fixed by an expand migration (025
SD4) or by retaining the column, never by the job improvising a sentinel.

### DR2. Both rights are request resources under one status machine

Both rights are exercised by creating a request resource, shaped by
[`request.schema.json`](../contracts/data-subject-rights/request.schema.json),
and reading it until it is terminal. The routes, under 050 HA5's prefix:

| Route | Who | Authorized by |
|---|---|---|
| `POST /v1/me/data-exports` · `GET …/{id}` · `GET …/{id}/download` | the subject | identity: the actor is the target |
| `POST /v1/me/erasures` · `GET …/{id}` · `POST …/{id}/cancel` | the subject | identity, plus step-up |
| `POST /v1/tenants/{tenant_id}/subjects/{subject_id}/data-exports` | a tenant administrator | `data_subject.export` in the tenant's scope (070 RB5) |
| `POST /v1/tenants/{tenant_id}/subjects/{subject_id}/erasures` | a tenant administrator | `data_subject.erase` in the tenant's scope, plus step-up |
| `POST /v1/tenants/{tenant_id}/subjects/{subject_id}/legal-holds` · `POST …/{id}/release` | a tenant administrator | `legal_hold.place` · `legal_hold.release` |

The four permissions are declared per 070 RB1 so the administrator's form has
a check and the audit event an action (080 AE3). The self-service form is
authorized by identity and audits under the same action string, so one query
finds every export of one person's data whoever asked (080 AE5's sixth floor).

**Statuses** are one vocabulary for both kinds: `pending`, `running`,
`completed`, `failed`, and per kind `expired` (an export whose package window
closed), `cancelled` and `held` (an erasure). The schema binds which fields
each status requires — a completed export its package, a completed erasure
its result (DR7), a held erasure its hold (DR6), a failed request its problem
type and detail — so **a request cannot claim completion without the thing
completion produced.** Errors are 050 HA3 problem types, stable per class:
`step-up-required` (403), `erasure-not-cancellable` (409), `export-not-ready`
(409), `export-expired` (410), `hold-exists` (409).

**One open request per subject per kind.** A second creation while one is
open returns the open resource with `200` rather than a new one with `201`;
creation honours `Idempotency-Key` per 050 HA6; the job is `idempotent` on the
request id per 057 JB2. A retried click, a retried request and a redelivered
message produce one export and one erasure.

**Verification is a contract.** An erasure is created or cancelled only when
the requester's `auth_time` (060 AU2) is within fifteen minutes; otherwise the
answer is `403 step-up-required`, and the client re-authenticates rather than
retrying. Fifteen minutes completes the flow and leaves an unattended session
unable to destroy an account. An export needs the session alone: it reveals
to the subject what they may already read. The instant checked is recorded as
`verified_at`, so the verification is a fact on the resource and not a memory
of the handler; the administrator's form is verified the same way.

**Deadlines are a floor the service meets, and lateness is an alert.** Every
request carries `deadline_at`: 72 hours after creation for an export, 72 hours
after the grace period for an erasure. The strictest common regime allows a
month; 72 hours is an engineering floor, because once the inventory exists the
work is a job over a declaration and only a backlog makes it slow. A request
open past its deadline is an alert computed from the request table the way
057 JB8 computes staleness.

### DR3. The export: a job-built package, tenant-bounded, delivered as a blob

**Creating an export request writes the request row and one
`data_export.requested` message to the outbox in one transaction** (055 AM4),
and the pool runs `export.build`: per-event, serial per request, `long`,
`idempotent` — never "process pending exports nightly", which 057 refuses.

**The package is a zip containing `manifest.json`, one `rows/<entry>.jsonl`
file per exported entry — suffixed `.<subject_column>` where a store carries
two entries — and one `blobs/<entry>/<object public id>` file per object the
subject's rows own.** Each `.jsonl` line is one row as JSON: snake_case keys
(050 HA8), primitives in 020's wire forms, every exported column except the
internal key (020 IP1, excluded without being named) and the entry's
`export_excludes`. An exported entry with no rows for this subject still
yields an empty file, so a recipient can tell *nothing held* from *not
exported*. The manifest,
[`manifest.schema.json`](../contracts/data-subject-rights/manifest.schema.json),
lists every file with its SHA-256 and names the request, subject, tenant, the
release that built it and the digest of the inventory it was built from: the
package is a function of the inventory, and that is the join a reviewer uses.

**`export: false` needs one of three reasons**: the rows are credential
material (a session, whose id is a credential under 090 WC1), a derived
projection of entries already exported (a search index under 027), or a
provider's copy of what the service already exports. `export_excludes` names
the columns withheld from an exported entry: a credential hash, or the columns
describing another person in a shared row. **The package never carries a
credential, a secret, an internal key, or another person's data.**

**Tenancy bounds the package**: scoped entries contribute the request's
tenant's rows and global entries the subject's, so a person in two tenants
receives two packages from two requests — 025 SD6's isolation applied to the
one read that crosses every table. **Delivery is through the service, and
never a URL — on the resource or anywhere else.** The job writes the package
to the service's own bucket under 026 as an object the request row owns;
`GET …/{id}/download` checks the requester and streams the object per
[`026-blob-storage.md`](026-blob-storage.md) BS5 with
`Content-Disposition: attachment`, answering `200`. The package is available
for seven days from completion, after which the route answers `410
export-expired`, the request reads `expired`, and the retention job deletes
the object: a concentrated copy of personal data is held no longer than the
person needs to collect it.

### DR4. Erasure is a grace period, then a job that walks the inventory in order

**Creating an erasure request starts a grace period, fourteen days by
default, during which nothing moves and the subject may cancel.** The subject
is told at creation and at cancellation through 058's security floor, so a
request made from a borrowed session is seen by its owner while it can still
be withdrawn. A product shortens the grace in its **Conventions** with a
reason, and never lengthens it past the point where grace plus the 72-hour
floor exceeds the shortest statutory deadline it is under; fourteen days is
the longest default that leaves room for a failed run and a retry under a
one-month regime. Once grace has ended the request is no longer cancellable
(`409 erasure-not-cancellable`): the data is moving in batches, and a
cancellation now would leave a state nobody declared.

**Dispatch is a periodic job and the erasure is a per-event job**, split the
way 057's `digest.schedule` and `digest.send` are: `erasure.dispatch` runs
hourly, single-flight, selects requests whose grace has ended and that carry
no hold (DR6), moves each to `running`, and writes one `erasure.due` message
per request to the outbox; `subject.erase` runs per event, serial per subject,
`long`, `idempotent`, and does the work.

**The job walks the inventory children before parents.** Entries carrying
`via` are treated before the entry they name, so a foreign key never dangles
mid-run and a crash between batches leaves a state a rerun continues from.
Within an entry the work is keyset batches, one transaction each, checkpoint
after every batch (057 JB7, JB10), applying the declared treatment (DR5) to
the tenant's rows for a scoped entry and all rows for a global one. Blobs go
through 026's mechanism as their owning rows go, documents through 027's, an
`external` entry through the provider's interface, a failure there failing
the run. Notification suppression under 058 happens first.

**Global rows go when the last membership goes.** The inventory marks one
entry as the subject's tenant memberships. A scoped erasure treats the
tenant's rows, then checks whether a membership remains in any other tenant;
if none does, the global entries — the person row, the identity link — are
treated and 060 AU4's `revokeAppAccess` is called. A product with no
membership entry treats global rows on every erasure. The application never
disables the identity itself (AU4); it revokes its own access and records it.
**The order is fixed and the corpus checks it**: suppression, scoped entries
children-first, the membership test, global entries children-first,
`revokeAppAccess`, the two records of DR7, `completed`.

### DR5. Three treatments, and anonymisation is an allowlist

An entry declares what happens to the subject's rows, and there are three
answers, because there are three things a row can be after its subject leaves:
gone, kept without the person, or kept with the person under an obligation.

| Treatment | The rows | The declaration carries |
|---|---|---|
| `delete` | Removed. The default, per 025 SD12. | Nothing further. |
| `anonymise` | Reduced to their structural columns plus `retained_columns`; every other value tombstoned. The row remains for the rows that reference it and identifies nobody once every entry is treated. | `retained_columns`, an allowlist, declared even when empty. Optionally a `stamp`. |
| `retain` | Reduced the same way, keeping the subject linkage, and deleted by the retention job when the basis expires. | `retained_columns`, and `legal_basis`: a `kind` from a closed set, a `reference` naming the obligation, `retain_for`, and the column it counts `from`. |

**Structural columns survive every reduction**: the internal key, the public
id, the isolation columns (025 SD5), `created_at` and `updated_at`, the
entry's subject column, and the stamp columns. **Everything else is tombstoned
unless the allowlist names it** — `NULL` where nullable, the literal
`[erased]` where `NOT NULL` text. An allowlist and never a denylist, because a
list of columns to scrub is complete only until the next migration, and
because the column that leaks is the free-text one: a notes field carrying a
phone number is personal data whatever its name says. The corpus's first
detector is exactly that field.

**What `anonymise` leaves is 080 AE7's shape, generalised.** The subject's
public id remains on the rows that referenced it and resolves to a shell row
that identifies nobody, as an audit event keeps `actor.id` and loses
`display`. The residue is anonymous on one condition — every entry naming the
subject has been treated — which is why DR1's coverage check exists: one
undeclared table re-identifies the whole graph. The audit store is declared
`anonymise` with the AE7 stamp (`erased_at`, `erased_subjects`) and **never
`delete`**; the corpus's second detector is an implementation that removes
the trail 080 AE4 says outlives its subject.

**`retain` is the only treatment that keeps personal data against the
subject's request, and it is admitted only with the obligation named and an
expiry declared.** The `kind` is closed — `legal_obligation`, `legal_claims`,
`contract` — so a declaration cannot invent a basis; the `reference` names the
statute, clause or claim. A retained row is reduced at erasure time, not at
expiry: the invoice keeps its amount, currency, issue date and tax id for
seven years and loses the billing email now. On expiry `retention.purge` —
057's own periodic example — deletes it. A basis without `retain_for` is
refused by the schema, for 080 AE7's reason against a missing ceiling. In
every treatment the job reads the declaration and applies the tombstone rule;
a product wanting a richer transformation — a generalised postcode, a bucketed
age — declares the derived column as retained and populates it in ordinary
code, so the job stays a function of the declaration and is never ad hoc.

### DR6. A legal hold suspends deletion, is audited, and is visible

**A hold is a row naming a subject, placed and released by an administrator
holding `legal_hold.place` and `legal_hold.release`, and both acts are
audited** under those action strings (080 AE3). While a hold stands, no
deletion for that subject runs: the dispatcher moves an erasure whose grace
ends to `held`, and `retention.purge` skips the subject's expired rows. A hold
suspends neither export — it preserves evidence, not the person's right to
see it — nor cancellation, which remains the subject's while nothing has run.
**Release resumes; it does not complete.** A released request returns to
`pending` and the next dispatch runs it, with no new request or verification.

**The hold is visible on the request** as `hold.id` and `hold.placed_at`; the
administrator's reason is not, because it may name a dispute the subject is a
party to. A hold carries a `review_at`, and a hold past review is a finding in
057 JB8's shape: a hold nobody reviews is retention forever under a better
name. The hold table is itself an inventory entry, `retain` under
`legal_claims`.

### DR7. Every erasure leaves two records: the audit event and the ledger entry

An erasure that cannot be proved ran is a promise. The job therefore ends by
writing two records in the same transaction as its last batch, and a request
is `completed` only when both exist. **The audit event** (080), action
`data_subject.erase`, actor the requester, target the subject, is written
*after* the subject's identification is gone, so it carries the subject's
public id and no display, with `erased_at` and `erased_subjects` naming the
subject from the moment it is written: the event that proves the erasure is
the first event that conforms to it. **The erasure ledger entry** (028)
carries the subject's public id, the tenant, the request id, the entries
treated and the instant; it is what a restore replays before a service is
readmitted to traffic, so a backup taken before the erasure cannot resurrect
what it removed, and its retention is 028's to state. The ledger's treatment
vocabulary is 028's: `delete`, `anonymise`, and `redact` for an append-only
store carrying AE7's stamp, which is what this standard's `anonymise` means
on the audit store; a `retain` entry writes nothing to the ledger, because
nothing was done to the row. The longest any copy of an erased subject's data
persists is the service's `erasure_horizon` (028 BR5), and that is the number
stated to subjects. The request's `result`
carries both ids, the counts, and whether identity access was revoked, so the
resource answers *what happened* without a log query.

### DR8. A tenant leaving takes its subjects' data with it

A tenant offboarding is an erasure over every row the tenant owns, run as an
operator-triggered job, `tenant.offboard`: on-demand, single-flight, `long`,
`idempotent`. Its shape depends on 025 SD6's isolation mechanism, stated so
the mechanism is chosen with this cost known. Under **one database per
tenant** it is a reduction followed by a drop: the retain and anonymise
treatments run so that only rows with a legal basis remain, the database is
held read-only under the retention credential until `retention.purge` reports
nothing left, and the drop is the final operator step; the bucket follows
026's deletion rules the same way. Under **row-level isolation** it is an
erasure over every scoped table, enumerated from the catalog as SD6's gate
enumerates them, children before parents. In both, subjects who belong to
other tenants keep their rows there, global rows go only when DR4's
membership test says so, and the tenant's *subjects'* data is treated by the
same declaration as any single erasure.

## Classifying a store

Examples beat definitions here; every row below is a corpus fixture entry.

| Store | Entry | Why |
|---|---|---|
| the person row | `anonymise`, `retained_columns: []`, global, `export_excludes: [password_hash]` | Becomes the shell every other row may still reference; the hash is a credential and leaves with nothing. |
| tenant memberships | `delete`, `membership: true` | The row that says the subject belongs; its absence everywhere is what lets global rows go. |
| invoices | `retain` under `legal_obligation`, seven years from `issued_at`, keeping amount, currency, issue date and tax id | The obligation names the columns; the billing email is not among them and goes now. |
| audit events | two `anonymise` entries, by actor and by target, AE7 stamp, third-party columns excluded from export | The trail survives; the identification of whichever side the subject was on does not. |
| messages | two `anonymise` entries, by sender and by recipient, keeping body and time | The other party still holds the message (025 SD12); the subject's identity behind it is gone. |
| notification provider | `external`, `delete`, `export: false` | A copy the service placed there, removed through the provider's interface. |

## The artifacts

Per PC3, under
[`contracts/data-subject-rights/`](../contracts/data-subject-rights/):

- **`inventory.schema.json`** — DR1's declaration and DR5's treatment
  vocabulary as conditional rules: a retained entry carries its basis and its
  allowlist, an anonymised entry its allowlist, a deleted entry neither, a
  blob entry its owning row, an entry declared free of personal data its
  reason alone.
- **`request.schema.json`** — DR2's resource and its status machine: which
  fields each kind and each status requires and forbids.
- **`manifest.schema.json`** — DR3's manifest: provenance, the row format,
  every file with its digest.
- **`corpus.json`** — seven parts over one fixture: `inventory` and
  `requests`, schema-decided; `coverage`, a catalog against the inventory
  with the expected findings; `erasure`, an implementation run over the
  fixture, compared on the rows that remain and the treatment order, with two
  detectors; `export`, manifests validated and the built file list, counts and
  column sets compared; `hold`, the lifecycle with a hold placed and released;
  `transitions`, state and action mapped to status or problem type.

## Enforcement

Every DR rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. Mechanically
checkable, and first to move: the inventory's schema validity and its coverage
against the engine's catalog (DR1 — the generative check, and the one worth
the most, because it fails when a table is added without a declaration); the
request and manifest shapes (DR2, DR3); and the erasure, export, hold and
transition parts under `job-contract-conformance`. What stays a review
question, said so in the ledger row: whether a treatment fits its data and a
legal basis is real (DR5), whether `export: false` has one of the three
reasons (DR3), whether suppression, revocation and the two records happen in
the order stated (DR4, DR7), and whether a hold is reviewed (DR6).

## Decisions

- **The inventory is a schema, with one entry per subject column**
  (2026-09-02). A register in prose cannot be executed or checked against a
  catalog, so it is stale by the next migration; a declaration is the input
  to both jobs and fails a check when a table it does not name appears.
  Per-table entries cannot express a row naming two people, and the audit
  corpus's position-versus-subject detector showed that failure first.
- **Anonymisation is an allowlist, and the audit store is anonymised rather
  than deleted** (2026-09-02). A denylist of identifying columns is complete
  only until the next column, and the column that leaks is the free-text one
  nobody classified; the intuitive erasure — delete everything with the id on
  it — removes the one record that proves the erasure happened. The cost is
  that an empty list must be written down, which is a decision made visible.
- **`retain` needs a closed-set kind, a reference and an expiry**
  (2026-09-02). A checker cannot require what it cannot recognise, and keeping
  identified data forever is a decision made on purpose or not at all (AE7).
- **Fourteen days of grace with a security notification, 72 hours to
  complete, dispatch periodic and erasure per-event** (2026-09-02). Immediate
  erasure was rejected because a request from a borrowed session is
  irreversible and its owner learns of it afterwards; the legal maximum as the
  deadline was rejected because it would license a queue a month deep; one
  periodic job erasing every due request in one run was rejected as the shape
  057 refuses, since splitting them makes one subject's failure one subject's
  retry.
- **Step-up for erasure, session for export; a hold suspends deletion only**
  (2026-09-02). An export discloses only what the subject may already read,
  and a hold exists to preserve evidence rather than to withdraw that right;
  deletion is the one act a hijacked session must not complete, and 060 AU2
  carries `auth_time` for exactly this.
- **The application revokes access and never deletes the identity**
  (2026-09-02). 060 AU4 gives one account to many applications and forbids
  any one of them to disable it; what the identity tier does when no
  application holds a grant is that tier's rule to state.

## Out of scope, deliberately

- **The stores, the audit record's shape, the ledger's replay, the
  notification's content.** 025, 026 and 027 build the stores; 080 AE7 defines
  the tombstone pair; 028 owns the ledger and its replay; 058 the message.
- **Consent, purposes and the lawful basis for processing in the first
  place.** A record of processing says why data is held; this standard
  governs what happens when the subject asks about it or asks it to stop.
- **A tenant's export of its own business records.** The product's domain;
  DR8 binds only the subjects' side.
