# Backup and recovery: restore is exercised, objectives are declared, and erasure survives a restore

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/backup-and-recovery/`](../contracts/backup-and-recovery/). The
words *service*, *stateful server*, *backing service*, *credential*,
*environment*, *release* and *deployment* are used in the senses
[`000-platform.md`](000-platform.md#terms) defines. The migrate step and the
one-database-per-service rule are [`025-structured-data.md`](025-structured-data.md)
SD3 and SD13's; the drill and the restore are jobs under
[`057-jobs.md`](057-jobs.md) run as one-shots under
[`035-workers.md`](035-workers.md); what erasure leaves of an audit event is
[`080-audit.md`](080-audit.md) AE7's; the erasure request is
[`082-data-subject-rights.md`](082-data-subject-rights.md)'s.

This document governs **the copy of a service's state that exists so the
state can be recovered**: which stores have one, what a service declares about
losing and regaining its state, who may take and who may restore the copy,
how a restore proceeds, how anyone knows the copy is restorable, and what
stops a restore from bringing back data a person asked to have erased. **What
it does not define is the store itself** — how structured, blob and document
data are written, isolated and deleted while the service runs, which are
[`025-structured-data.md`](025-structured-data.md)'s,
[`026-blob-storage.md`](026-blob-storage.md)'s and
[`027-document-storage.md`](027-document-storage.md)'s — nor the erasure
request that produces a ledger entry, which is the data subject rights
standard's.

## Why this exists

Every service holds state in stateful servers it attaches, and every one of
those servers will at some point lose it: a disk, a region, an operator's
mistaken statement, a migration that dropped what a marker said was safe, a
leaked credential used to delete rather than to read. The cheapest answer is
the hosting platform's checkbox — *automated backups: on* — and it is wrong as
a general property, because a backup nobody has restored is a hypothesis. A
backup mechanism fails silently in every way that matters: the snapshot runs
against a replica that stopped replicating, the archive fills a bucket whose
lifecycle rule deletes it, the restore needs a credential nobody kept, the
restored schema is three releases behind the image started against it.

The second cheapest answer is replication, and it is not a backup. A replica
applies every write, the `DELETE` and the `DROP` included, within seconds; it
protects against the loss of a machine and against nothing a person or a
program does. A snapshot in the same account under the same credential as the
source protects against hardware and not against the compromise of that
credential, which is the failure that deletes everything at once. Without a
stated RPO every backup cadence is acceptable, without a stated RTO every
restore procedure is fast enough, and neither number is found to be wrong
until a restore is under way.

A third failure belongs to organisations that honour erasure. A service that
deletes a person's rows on request, correctly and completely, still holds them
in every backup taken before the request. A restore from one of those brings
the rows back into a live system that has already told the person they are
gone: the erasure was performed and then silently undone, and nothing in the
restore procedure knows it happened.

This standard removes those decisions from every repository: which stores are
backed up and by what mechanism, what every service declares, whose credential
takes the copy and whose restores it, where the copy lives and for how long,
how a restore proceeds, how restorability is proven on a schedule, and how an
erasure outlives a restore. What remains for a repository is its numbers —
RPO, RTO, retention — and the verification query that says its data came back
whole, which are the only parts its domain has an opinion about.

### The standards evaluated first, per PC2

There is no wire protocol here; the boundary is a declaration a repository
writes and a procedure a job runs, and PC2's question is what existing
standard supplies each.

**The vocabulary is contingency-planning practice's.** *Recovery point
objective* — the longest span of committed state a service may lose, measured
backwards from the failure — and *recovery time objective* — the longest a
service may be without its state — are the terms of
[NIST SP 800-34](https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final) and ISO
22301, used in those senses. Neither gives a machine-readable artifact, so the
words are adopted and the declaration carrying them is invented (BR1).

**The mechanisms are the engines' own.** Point-in-time recovery from a
continuously shipped write-ahead log, object versioning with replication, the
snapshot facility of a document store or filesystem: each is a property of the
engine, offered by every managed instance and reproducible on a self-hosted
one. This standard names the class of mechanism per kind of store and no
product; a copy taken by a tool this platform would select — a dump job, a
backup agent — is refused (BR2) for the reason PC1 refuses a runtime library.

**The separate-failure-domain rule is the durable half of the 3-2-1 folk
rule** — the property, not the counting: at least one copy no failure of the
source, its account or its credential can reach (BR5). **The drill and the
restore are jobs under [`057-jobs.md`](057-jobs.md)** and one-shots under
[`035-workers.md`](035-workers.md), [factor XII](https://12factor.net/admin-processes)
applied to recovery; nothing about running them is invented.

**What no standard covers** is what this document invents: the recovery
declaration as a checkable artifact (BR1), the drill as a freshness signal
that gates deployment (BR4), and the one genuinely new mechanism, the erasure
ledger with its replay (BR6).

## The rules

### BR1. Every stateful backing service a service owns carries a recovery declaration

**A service declares, for every stateful server it attaches, how much of that
store it may lose, how long it may be without it, how the copy is taken and
kept, and how the copy is proven restorable — in a file in the repository
beside the service, validated against
[`recovery-declaration.schema.json`](../contracts/backup-and-recovery/recovery-declaration.schema.json).**
A store with no declaration is a store with no backup, and review treats it
as one: the question is not *is this backed up*, which a checkbox answers, but
*where is the declaration*, which an artifact does.

| Field | Values | What it decides |
|---|---|---|
| `service` | the service's logical name | Which service owns every store below; one declaration per service ([`025-structured-data.md`](025-structured-data.md) SD13). |
| `erasure_horizon` | ISO 8601 duration | The longest an erased subject's data may persist in any copy. Bounds every retention ceiling (BR5); is the ledger's retention (BR6). `runbook` names BR8's path beside it. |
| `stores[].kind` | `relational` · `object` · `document` · `filesystem` · `cache` | Which mechanisms are admitted (BR2). |
| `stores[].role` | `primary` · `derived` | Whether there is a backup at all (BR2). |
| `stores[].rpo`, `rto` | ISO 8601 durations | The objectives. `rpo` is forbidden on a derived store, which loses nothing that cannot be rebuilt; `rto` is required on both, because a rebuild takes time too. |
| `stores[].mechanism` | per the BR2 table | How the copy is taken. |
| `stores[].encrypted` | `true` | BR5, stated rather than assumed. |
| `stores[].failure_domain` | `region` · `account` · `region_and_account` | Where the copy lives relative to the source (BR5). |
| `stores[].retention` | `floor`, `ceiling` | How long a copy is kept (BR5). |
| `stores[].drill` | `cadence`, `stale_after` | How often restorability is proven, and when its absence alerts (BR4). |
| `stores[].verification` | a list of checks | What the drill asserts of the restored store (BR4). |
| `stores[].rebuild` | `by: job` with the job's name, or `by: reads` | Derived stores only: how the store is regained without a backup. |

Three things read it: the platform, to configure the mechanism and the
retention lifecycle; the drill, to know what to restore and assert; the
deployment, to know whether the drill is fresh. A repository holding several
services holds one declaration per service, because each service's stores sit
behind a different credential and are restored on a different day.

### BR2. The role decides whether there is a backup, and the engine's mechanism is the backup

**A store is `primary` when it is the only copy of what it holds, and
`derived` when a job can rebuild it from a primary.** A primary store is
backed up by its engine's mechanism. A derived store is not: it declares
`rebuild`, names the job or says that reads repopulate it, and its recovery is
running that rebuild against the restored primary. A backup of a derived store
is a second source of truth that can disagree with the first, so declaring one
is invalid, and so is declaring `rebuild` on a primary store.

| Kind | Mechanism for a primary store | Why not the alternative |
|---|---|---|
| `relational` | `pitr` — continuous archive of the write-ahead or binary log, restorable to any instant | A scheduled dump has an RPO of its cadence; PITR's is the archive lag, in seconds. |
| `object` | `versioning`, with replication to the failure domain — every overwrite and delete keeps the prior version | A scheduled bucket copy misses every object written and deleted between copies; versioning already is the point-in-time record. |
| `document` | `snapshot` or `pitr`, whichever the engine offers continuously | As relational. A primary document store is a database in every sense used here. |
| `filesystem` | `snapshot` | A file-level copy of a live filesystem is consistent at no instant; a snapshot is. |
| `cache` | none — a cache is always `derived`, rebuilt `by: reads` | A cache that cannot be lost is a database with the wrong name, and is declared as one. |

**A queue is not a store this document backs up.** The durable record of a
message is the outbox row in the producing service's database
([`055-messaging.md`](055-messaging.md) AM4), backed up with it; messages in
flight are redelivered or reproduced, and the inbox absorbs the repeat (AM3).

**The service never performs its own backup.** No job in its images dumps a
table, copies a bucket or exports a collection: such a job holds the runtime
credential against every table, gives the store an RPO of its own cadence,
and puts the copy where that credential can reach it, which BR3 forbids. The
service declares; the engine's mechanism copies; the service's only
executable part of backup is the drill.

### BR3. The backup credential is not the service's credential

**Three credentials touch a backup, and no process holds more than the one
its role needs.**

| Credential | Grants | Lives in | Never in |
|---|---|---|---|
| **Backup** | Read on the source; write on the destination. | The platform's backup mechanism for the engine. | Any image of the service: nothing the service runs can take a copy, so nothing it runs can take one to the wrong place. |
| **Restore** | Read on the destination; create and destroy a scratch stateful server; write to a target store during a restore. | The service's recovery image alone (BR4). | The server, the pool, the ordinary jobs image, the migrate image. |
| **Runtime** | What [`035-workers.md`](035-workers.md) WK8 gives the server, pool and jobs images. | Those images, and the recovery image for its run record (JB5). | The backup mechanism. |

The property this buys: **a compromise of the runtime credential cannot
destroy the backups**, because that credential can neither write to the
destination nor delete a version there. The destination refuses deletion under
any credential the service's deployables hold — an object lock, a retention
rule the service's principals cannot change — so the copy survives the event it
exists for. The restore credential is why the recovery image stands alone
under WK2's credential criterion: the one deployable that may read a copy.

### BR4. Restore is exercised, and a stale drill blocks a deployment

**A backup not restored recently is assumed unrestorable.** Every primary
store's declaration names a drill cadence, and `recovery.drill` is a periodic
job under [`057-jobs.md`](057-jobs.md) — `periodic`, `single_flight`, `long`,
`idempotent` on its tick — run as a one-shot from the recovery image on the
platform's runner ([`035-workers.md`](035-workers.md) WK5). One run, in
order:

1. **Restores** the newest copy of every primary store into a scratch
   environment — one in [factor X](https://12factor.net/dev-prod-parity)'s
   sense, differing from production only in configuration — and records the
   copy's `as_of`, the latest committed instant it contains.
2. **Migrates** the restored relational store forward with the release's
   migrate image ([`025-structured-data.md`](025-structured-data.md) SD3): the
   from-previous-release run against a real prior state, and the proof of
   SD2's convergence against a copy taken between apply and record.
3. **Replays the erasure ledger** (BR6) for every entry newer than `as_of`.
4. **Rebuilds** every derived store by its declared job, and times it.
5. **Verifies** with every check in the store's `verification` list: a SQL
   query the repository authored ([`025-structured-data.md`](025-structured-data.md)
   SD1) with a minimum row count; a sample of object references whose stored
   checksums must match the objects; and the service's own server image
   started against the scratch and answering `/readyz` with `200`
   ([`030-service.md`](030-service.md) SC1). Readiness is required in every
   primary store's list: a store the service cannot serve from is not
   recovered.
6. **Measures** the objectives: drill start minus `as_of` is the achieved
   RPO, restore start to readiness the achieved RTO, and either over its
   declared value ends the drill `failed`. The declaration was a promise, and
   the drill is where it is tested rather than the incident.
7. **Records** the run in `job_runs` ([`057-jobs.md`](057-jobs.md) JB5) with
   the achieved values, and **destroys** the scratch, so a restored copy of
   production data exists for minutes and under one credential.

**Absence is the failure**, per JB8: `stale_after` is declared beside
`cadence`, and the platform alerts when the newest `succeeded` `recovery.drill`
row is older than it. The signal is success; a drill that runs weekly and
fails weekly is stale. **The same query gates deployment**:
`recovery.assert_drilled` is a blocking deployment-step job, once per release,
that reads the newest `succeeded` drill row and exits `failed` when it is older
than `stale_after`. The clock starts at the first copy: a store whose oldest
copy is younger than the cadence has nothing to drill yet and is not stale.

### BR5. Backups are encrypted, out of the source's failure domain, and retained between a floor and a ceiling

**Encrypted**, at rest and in transit, under a key the runtime credential
cannot use; the declaration says `encrypted: true` so the property is
reviewable rather than inherited from a default someone can change.

**In a different failure domain than the source.** For production the copy is
in a different region, a different account, or both, and the declaration says
which. A different region survives the loss of the region; a different account
survives the compromise or deletion of the source account, which is what a
leaked credential produces. Neither alone is the other, so the declaration
admits `region`, `account` and `region_and_account` and nothing weaker; a
snapshot beside its source is availability.

**Retained between a declared floor and ceiling.** The floor is bounded below
by the drill cadence (`drill.cadence ≤ retention.floor`): were drills rarer
than the floor, a mechanism that broke could leave no restorable copy within
retention by the time a drill noticed. Thirty days is the recommended floor,
because a corruption found by a monthly reconciliation — the shortest business
cycle that reads everything — must still have a copy from before it. The
ceiling is bounded above by the service's `erasure_horizon`
(`retention.ceiling ≤ erasure_horizon`): a copy older than the horizon is
erased data still held, and the horizon is what the service tells its data
subjects, under the data subject rights standard, about how long a copy may
outlive their request. Ninety days is the recommended horizon; longer needs a
reason the repository records. Deletion past the ceiling is the destination's
lifecycle rule and never a job of the service (BR3).

### BR6. Erasure survives a restore

**An erasure the service performed is performed again after any restore,
before the service is readmitted to traffic, so no restore resurrects erased
data.** The mechanism is the erasure ledger.

The ledger records every erasure the service has carried out: one entry per
erased subject per request, shaped by
[`erasure-ledger.schema.json`](../contracts/backup-and-recovery/erasure-ledger.schema.json)
— the subject's public id and type ([`020-identifiers.md`](020-identifiers.md)
IP1), the tenant, the erasure request's public id, the instant, and the
entities touched with the treatment each received: `delete` for rows removed,
`anonymise` for rows kept with the subject's fields transformed, `redact` for
audit events kept with their identification removed
([`080-audit.md`](080-audit.md) AE7). It carries identifiers and never
personal data, because it outlives the erasure by the whole retention window.

**The ledger is kept twice, and the second copy is the one that matters.** It
is a table in the service's database, written in the erasure job's own
transaction so the erasure and its entry cannot separate (the reasoning of
[`080-audit.md`](080-audit.md) AE8 and [`055-messaging.md`](055-messaging.md)
AM4), and an append-only copy in the backup failure domain, delivered through
the outbox by a per-event job so the copy is as reliable as the erasure. The
table is the query surface; **the copy is what replay reads**, because the
table is exactly what a restore rolls back: a database restored to `as_of` has
no entry for any erasure after `as_of`, which are precisely the ones that must
be replayed. An implementation reading the restored table replays nothing
that matters and passes every test that does not restore.

**Replay re-runs the erasure.** For every entry with `erased_at` later than
`as_of`, the restore runs the service's erasure job for that subject again —
the same job the data subject rights standard defines, with the same declared
treatments — and writes the entry back into the restored table. Irreversible
destruction is idempotent ([`057-jobs.md`](057-jobs.md) JB2), so an entry
replayed against a copy that never held the subject is a no-op, and replaying
every entry is admitted where it is simpler than selecting the newer ones.
Replay redacts audit events and never deletes them: AE7 holds after a restore
as before it. **Replay completes before readiness.** The restored service
answers `/readyz` `503` until the replay's run record is `succeeded`; a server
that serves between restore and replay serves erased data, for however short
a window. Entries are retained for the `erasure_horizon` and no longer: past
it no copy holds the subject, and the entry is itself a record that a person
existed.

### BR7. A restore is a deployment

**A restore is not an operation on a database; it is a deployment of a
release whose first step replaces the state.** It names a release and an
environment, and its steps run in this order, each blocking on the last:

| Step | What runs | Credential | Why here |
|---|---|---|---|
| 1 | Every primary store restored to one `as_of` — the relational store's instant is the anchor, and the object store is restored to its versions as of the same instant | restore | One instant across stores, or a row references an object version that does not exist yet. The row is the source of truth per [`026-blob-storage.md`](026-blob-storage.md): after a restore an object without a row is an orphan the purge job removes, and a row without an object is a verification finding. |
| 2 | The release's migrate image, forward from the copy's schema version | migration | SD3's from-previous-release run in earnest; SD2's convergence is what makes a copy taken mid-migration safe. |
| 3 | Erasure ledger replay (BR6) | runtime | Before anything can read. |
| 4 | Derived stores rebuilt by their declared jobs | runtime | They depend on the primaries being final. |
| 5 | Servers and workers roll out; readiness admits traffic | runtime | `/readyz` is `503` until steps 2 to 4 have `succeeded` run records. |

`recovery.restore` is an `on_demand`, `single_flight`, `long`, `idempotent`
job, operator-triggered and keyed on the operator's supplied key so a retried
restore continues rather than restarts (WK4). It emits an audit event under
[`080-audit.md`](080-audit.md) with the operator as actor and the store as
target: a restore is the most consequential write a service receives, and
AE5's fourth item covers it.

**What a restore loses is everything after `as_of`, said here rather than
discovered.** Restored outbox rows are relayed again and absorbed downstream by
AM3's inboxes. Messages published after `as_of` describe changes the restored
state no longer holds, and consumers that acted on them hold effects whose
cause is gone; reconciling those is the domain's, and the runbook names who
does it. A restore over a live store is the one place an RPO is paid rather
than declared.

### BR8. The runbook is in the repository, and the drill runs it

**Recovery of a whole environment is a documented procedure in the
repository's operations documentation, at the path the declaration names, and
the drill executes that procedure's commands.** This is AGENTS.md rule 3
applied to the procedure most likely to be run under pressure by someone who
did not write it. The runbook states, per store and in order: the command
that restores it (WK4's form), the credential the operator needs and where it
is issued, how `as_of` is chosen, what passing verification looks like, what
is lost after `as_of` and who reconciles it, and who is told. A runbook step
the drill does not execute is a step nobody has tested.

## Classifying a store

| Store | Kind · role | Mechanism | Drill verifies | Why |
|---|---|---|---|---|
| The service's relational database | `relational` · `primary` | `pitr` | A query over the table the product cannot operate without, plus readiness | The system of record; its `as_of` anchors every other store. |
| The bucket holding user uploads | `object` · `primary` | `versioning` | A sample of references whose checksums match the objects, plus readiness | The rows reference the objects; the objects have no other copy. |
| A search index or materialised read model | `document` · `derived` | `rebuild` by its projection job | The rebuild completes within `rto` | Every document is a projection of rows a primary holds. |
| A cache | `cache` · `derived` | `rebuild` by `reads` | Nothing; a cold cache is a slow minute | A cache that must be restored is a database. |
| A read replica | not in the declaration | — | — | It applies every delete within seconds; availability, not recovery. |
| A snapshot in the source account under the source credential | not a backup | — | — | It survives a disk and not a leaked credential; no admitted failure domain is that weak. |
| The queue | not in the declaration | — | — | The outbox row is the durable record; the transport redelivers. |

## The artifacts

Per PC3, under [`contracts/backup-and-recovery/`](../contracts/backup-and-recovery/):

- **`recovery-declaration.schema.json`** — BR1's declaration, with the
  conditional rules that make it more than a field list: a primary store
  carries objectives, a mechanism admitted for its kind, encryption, a
  failure domain, retention, a drill and a verification list including
  readiness; a derived store carries `rebuild` and none of those; a cache is
  derived; a relational store's mechanism is `pitr`. Four arithmetic
  relations the schema cannot express are checked by the runner:
  `floor ≤ ceiling`, `ceiling ≤ erasure_horizon`, `cadence ≤ floor`,
  `cadence ≤ stale_after`.
- **`erasure-ledger.schema.json`** — BR6's entry, with `$ref`s into the
  identifiers and observability contracts for ids, instants and the tenant, a
  closed treatment set, and a closed property set so no personal field can be
  added to a record kept for the whole retention window.
- **`corpus.json`** — three parts. `declarations`: declarations the schema
  and the arithmetic rules accept and reject, each rejection naming its rule.
  `ledger`: entries accepted and rejected. `drills`: freshness, objectives,
  and a restore followed by replay whose expected state is stated both at
  readiness and after — the case separating an implementation that replays
  before readmitting from one that readmits first, and the case separating
  one reading the ledger's copy from one reading the restored table.

## Enforcement

Every BR rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. Mechanically
checkable, and first to move: the validity of a declaration for every store a
service's configuration names (BR1, BR2, BR5 — the schema plus the four
arithmetic rules); the freshness query BR4 already runs as a deployment step,
a gate the moment `recovery.assert_drilled` is in a service's deployment
order; and the `drills` corpus against a repository's recovery image, which
decides BR6's ordering at the boundary — `/readyz` is observed and erased rows
are queried for. Review questions, said so in the ledger row: whether a store
the configuration attaches is missing from the declaration (BR1), whether a
store declared `derived` is genuinely rebuildable (BR2), where a credential
actually lives (BR3 is a fact about the platform's configuration, not the
repository), and whether the runbook's steps and the drill's steps are the
same steps (BR8).

## Decisions

- **A store with no declaration is a store with no backup** (2026-09-02). A
  platform default that backs up everything it can see makes the question
  unanswerable from the repository and makes every store look covered.
- **Derived stores are rebuilt, never backed up** (2026-09-02). A backup of a
  projection is a second source of truth that can disagree with the first;
  declaring the rebuild job costs one field.
- **The engine's mechanism, never a job of the service** (2026-09-02). A dump
  job gives an RPO of its cadence, holds the runtime credential against every
  table, and puts the copy where that credential can reach it.
- **Three credentials, and the recovery image stands alone** (2026-09-02).
  A leaked runtime credential cannot destroy the backups only if nothing the
  service runs can write to the destination.
- **The drill measures the objectives rather than reading them**
  (2026-09-02). A declared RTO nobody has timed is a wish; a slow restore is a
  failed drill, so the declaration is tested on the drill's schedule.
- **A stale drill blocks deployment, as a job** (2026-09-02). An alert is read
  by whoever is on call; a blocked deployment by whoever is shipping. A
  deployment-step job under 057 has a run record and the same command by
  hand; a pipeline condition has neither.
- **The cadence is bounded by the floor and the ceiling by the horizon**
  (2026-09-02). Both are inequalities rather than numbers: a drill rarer than
  the floor can find a broken mechanism after the last good copy aged out,
  and a copy older than the horizon is erased data still held. Thirty and
  ninety days are defaults a repository may move with a reason.
- **The ledger is kept in the database and copied out, and replay reads the
  copy** (2026-09-02). Written in the erasure's transaction so the two cannot
  separate; copied out because the table is exactly what a restore rolls
  back. A ledger only outside loses the tie; one only inside is useless.
- **Replay precedes readiness** (2026-09-02). A window in which a restored
  service serves erased rows is an erasure undone for whoever asked in it,
  and the window's length is no defence. Readiness is the existing gate on
  traffic, so the rule costs no new mechanism.
- **A restore is a deployment** (2026-09-02). It names a release and an
  environment, and every step after the first — migrate, replay, rebuild,
  roll out — is one a deployment already has. Calling it a database
  operation hides the migrate step, the one most often forgotten.

## Out of scope, deliberately

- **The erasure request, the data inventory and the treatments.**
  [`082-data-subject-rights.md`](082-data-subject-rights.md)'s. This document
  consumes the entry that standard's erasure job writes.
- **The object reference and the orphan purge, and when a document store is
  admitted and in which role.** [`026-blob-storage.md`](026-blob-storage.md)'s
  and [`027-document-storage.md`](027-document-storage.md)'s; BR7 relies on
  the row being the source of truth, and BR2 takes the role 027 declares.
- **High availability.** Replicas, failover and multi-zone placement keep a
  service serving through the loss of a machine; they replicate every mistake
  and are not recovery.
- **Recovery of the platform itself.** The runner, the backup mechanism and
  the registry are backing services in [factor IV](https://12factor.net/backing-services)'s
  sense; their recovery is the platform's operations documentation's.
