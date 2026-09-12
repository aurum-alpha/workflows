# Backup and recovery: restore is exercised, objectives are declared, and erasure survives a restore

## Why this exists

Every service holds state in stateful servers it attaches, and every one of
those servers will at some point lose it. The causes are a disk, a region, an
operator's mistaken statement, and a leaked credential used to delete. The
cheapest answer is the hosting platform's checkbox, *automated backups: on*.
It is wrong as a general property, because a backup nobody has restored is a
hypothesis.

The second cheapest answer is replication, and it is not a backup: a replica
applies the `DROP` within seconds. Without a stated RPO every backup cadence
is acceptable, and without a stated RTO every restore procedure is fast
enough. Neither number is found to be wrong until a restore is under way. A
service that honours erasure still holds the erased rows in every backup
taken before the request. A restore from one of those undoes the erasure,
and nothing in the restore procedure knows it happened.

## The rules

### BR1. Every stateful backing service a service owns carries a recovery declaration

**A service declares four things for every stateful server it attaches. They
are how much of that store it is allowed to lose, and how long it is allowed
to be without it. They are how the copy is taken and kept, and how the copy
is proven restorable. The declaration is a file in the repository beside the
service, validated against
[`recovery-declaration.schema.json`](../contracts/backup-and-recovery/recovery-declaration.schema.json)**.
A store with no declaration is a store with no backup, and review treats it
as one. The question is not *is this backed up*, which a checkbox answers,
but *where is the declaration*, which an artifact does.

*Recovery point objective* is the longest span of committed state a service
is permitted to lose. *Recovery time objective* is the longest a service is
permitted to be without its state. Both are the terms of
[NIST SP 800-34](https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final) and
ISO 22301, in those senses.

| Field | Values | What it decides |
|---|---|---|
| `service` | the service's logical name | Which service owns every store below; one declaration per service ([`025-structured-data.md`](025-structured-data.md) SD13). |
| `erasure_horizon` | ISO 8601 duration | The longest an erased subject's data is allowed to persist in any copy. Bounds every retention ceiling (BR5); is the ledger's retention (BR6). `runbook` names BR8's path beside it. |
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

Three things read it. The platform reads it to configure the mechanism and
the retention lifecycle. The drill reads it to know what to restore and
assert. The deployment reads it to know whether the drill is fresh.

### BR2. The role decides whether there is a backup, and the engine's mechanism is the backup

**A store is `primary` when it is the only copy of what it holds, and
`derived` when a job can rebuild it from a primary**. A primary store is
backed up by its engine's mechanism. A derived store is not. It declares
`rebuild`, names the job or says that reads repopulate it, and its recovery
is running that rebuild against the restored primary. A backup of a derived
store is a second source of truth that can disagree with the first. So
declaring one is invalid, and so is declaring `rebuild` on a primary store.

| Kind | Mechanism for a primary store | Why not the alternative |
|---|---|---|
| `relational` | `pitr`: continuous archive of the write-ahead or binary log, restorable to any instant | A scheduled dump has an RPO of its cadence; PITR's is the archive lag, in seconds. |
| `object` | `versioning`, with replication to the failure domain; every overwrite and delete keeps the prior version | A scheduled bucket copy misses every object written and deleted between copies; versioning already is the point-in-time record. |
| `document` | `snapshot` or `pitr`, whichever the engine offers continuously | As relational. A primary JSON document store is a database in every sense used here. |
| `filesystem` | `snapshot` | A file-level copy of a live filesystem is consistent at no instant; a snapshot is. |
| `cache` | none; a cache is always `derived`, rebuilt `by: reads` | A cache that cannot be lost is a database with the wrong name, and is declared as one. |

**A queue is not a store this document backs up**. The durable record of a
message is the outbox row in the producing service's database
([`055-messaging.md`](055-messaging.md) AM4), backed up with it. Messages in
flight are redelivered or reproduced, and the inbox absorbs the repeat (AM3).

**The service never performs its own backup.** No job in its images dumps a
table, copies a bucket or exports a collection. Such a job holds the runtime
credential against every table and gives the store an RPO of its own
cadence. It puts the copy where that credential can reach it, which BR3
forbids. The service declares; the engine's mechanism copies; the service's
only executable part of backup is the drill.

### BR3. The backup credential is not the service's credential

**Three credentials touch a backup, and no process holds more than the one
its role needs.**

| Credential | Grants | Lives in | Never in |
|---|---|---|---|
| **Backup** | Read on the source; write on the destination. | The platform's backup mechanism for the engine. | Any image of the service: nothing the service runs can take a copy, so nothing it runs can take one to the wrong place. |
| **Restore** | Read on the destination; create and destroy a scratch stateful server; write to a target store during a restore. | The service's recovery image alone (BR4). | The server, the pool, the ordinary jobs image, the migrate image. |
| **Runtime** | What [`035-workers.md`](035-workers.md) WK8 gives the server, pool and jobs images. | Those images, and the recovery image for its run record (JB5). | The backup mechanism. |

The property this buys: **a compromise of the runtime credential cannot
destroy the backups**. That credential can neither write to the destination
nor delete a version there. The destination refuses deletion under any
credential the service's deployables hold, through an object lock or a
retention rule the service's principals cannot change. So the copy survives
the event it exists for. The restore credential is why the recovery image
stands alone under WK2's credential criterion: the one deployable that is
permitted to read a copy.

### BR4. Restore is exercised, and a stale drill blocks a deployment

**A backup not restored recently is assumed unrestorable.** Every primary
store's declaration names a drill cadence. `recovery.drill` is a periodic
job under [`057-jobs.md`](057-jobs.md): `periodic`, `single_flight`, `long`,
`idempotent` on its tick. It runs as a one-shot from the recovery image on
the platform's runner ([`035-workers.md`](035-workers.md) WK5). One run, in
order:

1. **Restores** the newest copy of every primary store into a scratch
   environment, and records the copy's `as_of`, the latest committed instant
   it contains. The scratch environment is one in
   [factor X](https://12factor.net/dev-prod-parity)'s sense, differing from
   production only in configuration.
2. **Migrates** the restored relational store forward with the release's
   migrate image ([`025-structured-data.md`](025-structured-data.md) SD3).
   That is the from-previous-release run against a real prior state, and the
   proof of SD2's convergence against a copy taken between apply and record.
3. **Replays the erasure ledger** (BR6) for every entry newer than `as_of`.
4. **Rebuilds** every derived store by its declared job, and times it.
5. **Verifies** with every check in the store's `verification` list. One
   check is a SQL query the repository authored
   ([`025-structured-data.md`](025-structured-data.md) SD1) with a minimum
   row count. Another is a sample of object references whose stored
   checksums must match the objects. Another is the service's own server
   image started against the scratch and answering `/readyz` with `200`
   ([`030-service.md`](030-service.md) SC1). Readiness is required in every
   primary store's list: a store the service cannot serve from is not
   recovered.
6. **Measures** the objectives. Drill start minus `as_of` is the achieved
   RPO, restore start to readiness the achieved RTO. Either over its declared
   value ends the drill `failed`. The declaration was a promise, and the
   drill is where it is tested rather than the incident.
7. **Records** the run in `job_runs` ([`057-jobs.md`](057-jobs.md) JB5) with
   the achieved values, and **destroys** the scratch. So a restored copy of
   production data exists for minutes and under one credential.

**Absence is the failure**, per JB8: `stale_after` is declared beside
`cadence`, and the platform alerts when the newest `succeeded` `recovery.drill`
row is older than it. The signal is success; a drill that runs weekly and
fails weekly is stale. **The same query gates deployment**:
`recovery.assert_drilled` is a blocking deployment-step job, once per
release. It reads the newest `succeeded` drill row and exits `failed` when it
is older than `stale_after`. The clock starts at the first copy. A store
whose oldest copy is younger than the cadence has nothing to drill yet and is
not stale.

### BR5. Backups are encrypted, out of the source's failure domain, and retained between a floor and a ceiling

**Encrypted**, at rest and in transit, under a key the runtime credential
cannot use. The declaration says `encrypted: true`, so the property is
reviewable rather than inherited from a default someone can change.

**In a different failure domain than the source**. For production the copy
is in a different region, a different account, or both, and the declaration
says which. A different region survives the loss of the region. A different
account survives the compromise or deletion of the source account, which is
what a leaked credential produces. Neither alone is the other. So the
declaration admits `region`, `account` and `region_and_account` and nothing
weaker; a snapshot beside its source is availability.

**Retained between a declared floor and ceiling.** The floor is bounded below
by the drill cadence (`drill.cadence ≤ retention.floor`). Were drills rarer
than the floor, a mechanism that broke could leave no restorable copy within
retention by the time a drill noticed. Thirty days is the recommended floor.
A corruption found by a monthly reconciliation, the shortest business cycle
that reads everything, must still have a copy from before it. The ceiling is
bounded above by the service's `erasure_horizon`
(`retention.ceiling ≤ erasure_horizon`).

A copy older than the horizon is erased data still held. The horizon is what
the service tells its data subjects about how long a copy can outlive their
request. It tells them under the data subject rights standard. Ninety days
is the recommended horizon; longer needs a reason the repository records.
Deletion past the ceiling is the destination's lifecycle rule and never a
job of the service (BR3).

### BR6. Erasure survives a restore

**An erasure the service performed is performed again after any restore,
before the service is readmitted to traffic, so no restore resurrects erased
data**. The mechanism is the erasure ledger.

The ledger records every erasure the service has carried out: one entry per
erased subject per request, shaped by
[`erasure-ledger.schema.json`](../contracts/backup-and-recovery/erasure-ledger.schema.json).
An entry holds the subject's public id and type
([`020-identifiers.md`](020-identifiers.md) IP1), the tenant, the erasure
request's public id, and the instant. It holds the entities touched with the
treatment each received. The treatments are `delete` for rows removed, and
`anonymise` for rows kept with the subject's fields transformed. The third is
`redact`, for audit events kept with their identification removed
([`080-audit.md`](080-audit.md) AE7). It carries identifiers and never
personal data, because it outlives the erasure by the whole retention window.

**The ledger is kept twice, and the second copy is the one that matters**. It
is a table in the service's database, written in the erasure job's own
transaction, so the erasure and its entry cannot separate. That is the
reasoning of [`080-audit.md`](080-audit.md) AE8 and
[`055-messaging.md`](055-messaging.md) AM4. It is also an append-only copy in
the backup failure domain. The copy is delivered through the outbox by a
per-event job, so it is as reliable as the erasure.

The table is the query surface; **the copy is what replay reads**, because
the table is exactly what a restore rolls back. A database restored to
`as_of` has no entry for any erasure after `as_of`, which are precisely the
ones that must be replayed. An implementation reading the restored table
replays nothing that matters and passes every test that does not restore.

**Replay re-runs the erasure.** For every entry with `erased_at` later than
`as_of`, the restore runs the service's erasure job for that subject again.
That job is the same job the data subject rights standard defines, with the
same declared treatments. The restore writes the entry back into the
restored table. Irreversible destruction is idempotent
([`057-jobs.md`](057-jobs.md) JB2).

So an entry replayed against a copy that never held the subject is a no-op.
Replaying every entry is admitted where it is simpler than selecting the
newer ones. Replay redacts audit events and never deletes them: AE7 holds
after a restore as before it.

**Replay completes before readiness.** The restored service answers `/readyz`
`503` until the replay's run record is `succeeded`. A server that serves
between restore and replay serves erased data, for however short a window.
Entries are retained for the `erasure_horizon` and no longer. Past it no
copy holds the subject, and the entry is itself a record that a person
existed.

### BR7. A restore is a deployment

**A restore is not an operation on a database; it is a deployment of a
release whose first step replaces the state**. It names a release and an
environment, and its steps run in this order, each blocking on the last:

| Step | What runs | Credential | Why here |
|---|---|---|---|
| 1 | Every primary store restored to one `as_of`. The relational store's instant is the anchor, and the object store is restored to its versions as of the same instant | restore | One instant across stores, or a row references an object version that does not exist yet. The row is the source of truth per [`026-blob-storage.md`](026-blob-storage.md): after a restore an object without a row is an orphan the purge job removes, and a row without an object is a verification finding. |
| 2 | The release's migrate image, forward from the copy's schema version | migration | SD3's from-previous-release run in earnest; SD2's convergence is what makes a copy taken mid-migration safe. |
| 3 | Erasure ledger replay (BR6) | runtime | Before anything can read. |
| 4 | Derived stores rebuilt by their declared jobs | runtime | They depend on the primaries being final. |
| 5 | Servers and workers roll out; readiness admits traffic | runtime | `/readyz` is `503` until steps 2 to 4 have `succeeded` run records. |

`recovery.restore` is an `on_demand`, `single_flight`, `long`, `idempotent`
job, operator-triggered and keyed on the operator's supplied key so a retried
restore continues rather than restarts (WK4). It emits an audit event under
[`080-audit.md`](080-audit.md) with the operator as actor and the store as
target. A restore is the most consequential write a service receives, and
AE5's fourth item covers it.

**What a restore loses is everything after `as_of`, said here rather than
discovered**. Restored outbox rows are relayed again and absorbed downstream
by AM3's inboxes. Messages published after `as_of` describe changes the
restored state no longer holds. Consumers that acted on them hold effects
whose cause is gone. Reconciling those is the domain's, and the runbook names
who does it. A restore over a live store is the one place an RPO is paid
rather than declared.

Recovery of the platform itself, the runner, the backup mechanism and the
registry, is the platform's operations documentation's.

### BR8. The runbook is in the repository, and the drill runs it

**Recovery of a whole environment is a documented procedure in the
repository's operations documentation, at the path the declaration names.
The drill executes that procedure's commands**. This is AGENTS.md rule 3
applied to the procedure most likely to be run under pressure by someone who
did not write it.

The runbook states, per store and in order, the command that restores it
(WK4's form). It states the credential the operator needs and where it is
issued. It states how `as_of` is chosen, what passing verification looks
like, what is lost after `as_of` and who reconciles it, and who is told. A
runbook step the drill does not execute is a step nobody has tested.

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

- **`recovery-declaration.schema.json`** is BR1's declaration with its
  conditional rules per role and kind, plus the four arithmetic relations the
  runner checks: `floor ≤ ceiling`, `ceiling ≤ erasure_horizon`,
  `cadence ≤ floor`, `cadence ≤ stale_after`.
- **`erasure-ledger.schema.json`** is BR6's entry, with a closed treatment set
  and a closed property set.
- **`corpus.json`** has three parts: `declarations`, `ledger` and `drills`.
