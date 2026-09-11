# Jobs: the unit of work, its key, and what it declares

## Why this exists

Every product accumulates work that is not a request. Send this, purge
that, poll the partner, recompute the totals, apply the schema change, fill
the new column. Each arrives with a cheapest answer, and the cheapest
answers share one omission.

The cheapest answers are a timer inside the server, a script on a host, and
a loop that runs "every night". Or a command someone runs when they
remember, or a handler bolted to a queue. None of them says what a unit of
that work *is*. So none of them can say what happens when it runs twice.
None can say how anyone would know it failed, or how anyone would know it
did not run at all.

The failures that follow are general properties, not accidents. A run is
repeated because a delivery was repeated, or a tick fired twice, or a
person pressed enter twice. It repeats its effect, and whether that is
harmless or a double payment depends on a decision nobody recorded.

A run that dies between doing the thing and writing it down leaves a state
nobody can name. A scheduled run that silently stops produces no error,
because absence is not an event. Two instances of the same run overlap
because the only thing preventing it was a scheduler setting somebody
changed. And when any of this is investigated, there is no record of runs
to investigate, only logs to grep.

This standard removes those decisions from every repository by making them
once. It answers what a job is, how it is keyed, and which of three
duplicate policies it declares. It answers what a job leaves behind and how
its absence is noticed. What remains for a repository is the body of the
job, which is the only part that is its domain.

### The standards evaluated first, per PC2

A job's boundary is its input and its outcome, and PC2 asks whether an
existing standard covers each before anything is invented.

**The input of a per-event job is a CloudEvent**. Under 055 the message a
consumer receives is already a CloudEvents 1.0 event under the platform
profile. Its identity is in `(source, id)`, its payload's schema in
`dataschema`, and its trace in `traceparent`. A job triggered by a message
takes that event as its input, unchanged. Nothing is invented for the
majority case.

**The input of an invoked job is not a CloudEvent**. A CloudEvent is a fact
about an entity: past tense, with a subject that is a public id. A tick, a
deployment step, and an operator's command are none of those things.
Forcing them into the envelope produces a type that is not past tense and a
subject that is not an id. That is the profile broken to look conformant.

So the invoked input is a platform schema,
[`invocation.schema.json`](../contracts/jobs/invocation.schema.json), shaped
as closely to the CloudEvents attribute set as honesty allows. It carries an
`id`, a `source`, a `time`, a `traceparent`, the job's name, the trigger
kind, and the arguments the job's own schema admits. A job sees one
interface either way (JB1).

**The trace attributes of a run are OpenTelemetry's.** The
[FaaS semantic conventions](https://opentelemetry.io/docs/specs/semconv/faas/faas-spans/)
already name what a run needs. `faas.trigger` takes the values `pubsub`,
`timer` and `other` for the message, tick, and deployment-or-operator
triggers. `faas.invocation_id` is the run id, and `faas.cron` and
`faas.time` describe a timer trigger. The
[messaging conventions](https://opentelemetry.io/docs/specs/semconv/messaging/messaging-spans/)
name the span in which a per-event job processes its message. The attribute
names are adopted rather than reinvented. So a trace of a run reads the
same as a trace of a function invocation anywhere else.

**A schedule is a POSIX cron expression.** Five fields, in UTC. Every
scheduler a worker could run under accepts it, and it is the one form an
operator reads without a manual.

**What no standard covers** is the part this document invents. That is the
job key as distinct from the delivery id, and the duplicate policy and its
claim mechanism. It is also the run record, and the rule that a periodic
job's absence is its failure. Those are JB2, JB4, JB5 and JB8.

## The rules

### JB1. A job is a function from an input to an outcome

A job is named, and its name is a stable identifier in the form
`resource.verb`, imperative: `invoice.send`, `retention.purge`,
`schema.migrate`, `ledger.reconcile`. The name is distinct from the event
type that can trigger it: `invoice.issued` is a fact, `invoice.send` is the
work it causes.

The interface, stated language-neutrally:

```
run(input, ctx) -> outcome

input   an Event (055 AM1) for a per-event job, or an Invocation
        (contracts/jobs/invocation.schema.json) for a tick, deployment,
        or operator trigger. Either carries: key, trigger, time,
        traceparent, and the payload or arguments validated against the
        job's declared schema.

ctx     run_id (UUIDv7), the checkpoint store, the run record writer,
        and the deadline as an instant. Nothing else.

outcome one of: succeeded | failed | skipped | unknown | expired (JB4)
```

A job **ends**. It has no loop, no sleep waiting for its next turn, and no
knowledge of what started it. The same job body runs unchanged when a pool
dispatches to it for a message, and when a one-shot runs it for a tick. It
also runs unchanged when an engineer runs it from a laptop against a
development database. JB3's declaration is what lets a worker construct the
input for any trigger. A job that can tell the difference has read
something it is not permitted to read.

The job's payload or arguments are validated against a JSON Schema the job
names, before the body runs. For a per-event job that is the event's
`dataschema`; for an invoked job it is the `args_schema` in its declaration.
A job never parses its own input by hand.

### JB2. Every job has a key and a declared duplicate policy, and no run repeats an effect silently

**The key names the work, not the delivery.** For a per-event job the key is
the event's `(source, id)`. For a periodic job it is the job name and the
scheduled tick. So two firings of one tick share a key and a late firing
does not. For a deployment job it is the job name and the release version.
For an operator-triggered job it is the job name and an id the operator
supplies or the worker mints, and the operator is told which. The inbox row
of 055 AM3 deduplicates a *delivery*, and the job key deduplicates the
*work*; the two coincide only for the per-event case.

**A second run of the same key happens.** 055 delivers at least once. A
scheduler can fire a tick twice. A person can run a command twice. A worker
can die after the effect and before the record. The duplicate policy is
what the job promises when it does. There are exactly three, because there
are exactly three places an effect can live relative to the transaction
that records it.

| Policy | A second run of the same key | Mechanism | Which triggers can run it |
|---|---|---|---|
| `idempotent` | Has no effect and reports the first run's outcome. | The key is checked and written in the same transaction as the effect. For an effect across a boundary, the far side deduplicates: an idempotency key it honours, a natural key we choose, or an operation idempotent by nature. | Any. |
| `at_most_once` | Has no effect. If the first run crashed between acting and recording, reports `unknown` and hands off to reconciliation. | Claim first: write intent under the key and commit; act; record completion. A duplicate meets the claim and stops. The window between act and record cannot be closed, so it is made visible. | Any, a message included: the redelivery meets the claim. |
| `at_least_once` | Can repeat the effect. Declared acceptable because a lost effect costs more than a repeated one. | Act, then record. No claim. The declaration is the consent. | Any, because the declaration says duplicates are fine. |

**`idempotent` is the default and the majority**. It is always achievable
when the effect is in the service's own database, because the key and the
effect commit together. It is achievable across a boundary exactly when the
far side offers something to deduplicate on. Where it offers nothing and
the effect is not idempotent by nature, exactly-once is impossible, and the
job declares which failure it prefers.

`at_most_once` loses an effect on a crash and says so; `at_least_once`
repeats one and has said in advance that this is fine. A job whose
declaration says `idempotent` while its effect crosses a boundary with no
dedup handle is misdeclared. That is the first thing a reviewer checks.

**A key can carry a validity window**. Some work is idempotent by key and
still wrong by meaning when repeated late: an order at a price, a bid, an
offer that expires. The declaration states `valid_for`, and a run whose key
is older than that ends `expired`, neither deduplicated nor repeated.

Two apparent exceptions that are not. Irreversible destruction, such as
wipe, delete, or revoke, is idempotent because the second run is a no-op.
Randomness is idempotent once the first run stores its result under the
key. And one caution: a provider's idempotency key usually has a time
limit. So the run record, not the provider, is what stops a job calling
again after it has succeeded.

### JB3. Every job declares its class beside its code

A job carries a declaration, validated against
[`declaration.schema.json`](../contracts/jobs/declaration.schema.json), in
the repository next to the job. The worker reads it to construct the input
and enforce the class. It is rendered at deployment into whatever runs
one-shots (035 WK6), and read by the alerting. **A job with no declaration
does not run**: the worker refuses to load it, which is the mechanical half
of this rule.

| Field | Values | What it decides |
|---|---|---|
| `name` | `resource.verb` | Identity, the lock name, the run record's `job_name`. |
| `recurrence` | `once_ever` · `per_event` · `periodic` · `on_demand` | The trigger. `per_event` is the only value that means a stream and therefore a pool; the other three are invocations and therefore one-shots. |
| `concurrency` | `single_flight` · `serial_per_key` · `parallel` | Whether the job takes the JB6 lock, and how a pool can spread the work. |
| `duration` | `short` · `long` | Short means inside the transport's redelivery window; long means the job checkpoints and resumes (JB7). |
| `blocking` | `true` · `false` | Whether the invoker waits for the outcome. Only a deployment does, and it forces a one-shot. |
| `duplicate_policy` | `idempotent` · `at_most_once` · `at_least_once` | JB2. Required. A missing value is a missing declaration. |
| `input` | `{ "event": <dataschema URI> }` or `{ "args_schema": <URI> }` | What the body receives, validated before it runs. |
| `valid_for` | ISO 8601 duration, optional | The key's validity window; past it a run ends `expired`. |
| `deadline` | ISO 8601 duration | The longest a run can take before the worker is killed (JB7). |
| `grace` | ISO 8601 duration | Time between `SIGTERM` and `SIGKILL`, in which a long job checkpoints. |
| `schedule` | `cron` (five fields, UTC) · `missed`: `run_late` or `skip` · `window` | Periodic jobs only. Rendered to the runner; never read by the job. |
| `stale_after` | ISO 8601 duration, periodic only, default twice the cadence | JB8. Lives beside `schedule` so neither changes without the other in view. |
| `reconcile` | the job or role that resolves `unknown`, `at_most_once` only | JB4. An `at_most_once` job with nobody named to resolve its unknowns is misdeclared. |

The declaration is the whole of what a repository decides about a job's
operation. Everything else follows from it mechanically. The decisions that
are not the domain's are made by filling in a form whose every field has a
defined consequence.

### JB4. A run ends in one of five outcomes, and each has an owner

| Outcome | Meaning | Who acts |
|---|---|---|
| `succeeded` | The effect is done and recorded. | Nobody. |
| `failed` | The body raised or returned failure before the effect was recorded. Under `idempotent` and `at_most_once`, no effect happened or the claim stands; under `at_least_once`, an effect might have happened. | A per-event job is redelivered under 055 AM5. A periodic job waits for its next tick. A deployment job blocks the deployment. An operator's job is rerun by the operator. |
| `skipped` | A single-flight job found its lock held by a live run, or an idempotent job found its key already done. | Nobody, for the skip itself. A held lock means a run outlasting its cadence, and that overrun is what alerts. |
| `unknown` | An `at_most_once` job holds a claim with no completion, and the run that made the claim is gone. The effect might or might not have happened. | The reconciliation job or role named in the declaration's `reconcile` field. `unknown` is never left to age out. |
| `expired` | The key was older than `valid_for` when the run started. | Whoever owns the meaning of the work decides whether to issue a fresh key. The platform never re-issues one. |

`skipped` exits a one-shot with success. It is not a failure of this run
that another run is doing the work. The failure, if there is one, is the
overrun, and JB8 catches it.

### JB5. Every run leaves a record, and the record is the authority

One row per run, in the service's own database (025 SD13), written by the
worker around the body. The worker opens it when the run starts and closes
it with the outcome. The shape is fixed by
[`run-record.json`](../contracts/jobs/run-record.json), a storage profile
in the manner of 025's:

```
job_runs
  run_id        uuidv7      primary key
  job_name      text        the declaration's name
  job_key       text        JB2's key; unique with job_name for
                            idempotent and at_most_once jobs
  trigger       text        message | tick | deployment | operator
  worker        text        pool | one_shot
  started_at    instant     025 storage profile: millisecond, UTC
  finished_at   instant     null while running
  outcome       text        JB4, null while running
  claimed_at    instant     at_most_once only: the claim, JB2
  touched       integer     rows, messages, items: the job's own count
  checkpoint    json        long jobs: where to resume, JB7
  trace_id      text        040 OC1, the run's trace
```

The row is the mechanism for three other rules, not a report beside them.
JB2's claim is the row with `claimed_at` set and `finished_at` null. JB6's
lock is taken against it. JB8's freshness check is a query over it.
Whatever runs the worker can keep its own history of runs, and that history
is a convenience.

Every log line a run writes carries `job.name` and `job.run_id` in the 040
OC4 context block. The run's span carries the OpenTelemetry attributes
named above. So a run is a query, a log filter, and a trace, and all three
agree.

### JB6. Single-flight is enforced by the job, whatever runs it

A job declared `single_flight` takes an advisory lock named for the job in
the service's database before doing anything else. It releases the lock
when the run ends. Held means the run ends `skipped`. A job declared
`serial_per_key` does the same with the key's partition, typically the
tenant or the aggregate, folded into the lock name.

The runner can forbid overlapping runs and a queue can be given one
consumer. Both are configuration that someone who has not read the
declaration can change. The lock ships in the code that was tested, and it
is the only guarantee this standard counts. Under 025 SD11 the migrate step
already requires exactly this; JB6 is that rule for every job that needs
it.

### JB7. Every job has a deadline, honours cancellation, and a long job resumes

A run past its declared `deadline` is killed by whatever runs it, and the
job is written on the assumption that this will happen. On `SIGTERM`,
delivered by the worker within `grace`, a `short` job either finishes or
abandons. If it abandons, its policy decides what a rerun means.

A `long` job writes a checkpoint at least once per unit of work, and on
cancellation writes its last one and exits within `grace`. A rerun of the
same key reads the checkpoint and continues rather than starting over or
refusing. This is 030 SC4 applied to a process that was going to exit
anyway. It is what makes a long job safe to deploy over.

The unit of work for a long job over a table is a keyset batch on the
UUIDv7 key (025 SD1). Each batch is one transaction, with a checkpoint
after it. A long job that holds one transaction for its whole run has
declared itself `long` and behaved as `short`. It will be the thing that
holds the lock the next migration is waiting on.

### JB8. For a periodic job, absence is the failure

A per-event job that stops being run shows a growing queue. A periodic job
that stops being run shows nothing at all: no error, no log line, no failed
run. A run that never started produced none of those. So a periodic job
declares `stale_after` beside its schedule, and the platform alerts when
the newest `succeeded` row for that job is older than it. The default is
twice the cadence; a weekly job might want less, and a job that runs every
minute might want more. The two numbers are read together because they are
written together.

The signal is *success*, not attempts. A job that runs every night and
fails every night is stale under this rule.

### JB9. A job produces through the outbox and reads only its own service's database

Anything a job needs another service to know becomes a message under 055
AM4, written to the outbox in the same transaction as the effect. So a
job's fan-out is exactly as reliable as its work. Anything another service
owns is reached through that service's interface or its messages, never its
state (025 SD13). A job that reconciles two services is two jobs and a
queue.

### JB10. A backfill is a long, single-flight, on-demand, idempotent job, and never a migration

A schema change that needs existing rows populated ships as an expand
migration (025 SD4) followed by a backfill job. The migration never carries
the population itself: a migration runs inside the deployment window and a
backfill runs for as long as the data needs. The backfill has JB7's
properties and one more, a rate bound so the service keeps serving while it
runs. It is run again until it reports nothing left, and each run
converges.

Where a backfill is too large for one process to be trusted with, it is
written as a self-continuing per-event job. That job processes a batch,
checkpoints, produces the message for the next batch, and lets the pool
carry it. The choice between the two shapes is 035 WK4's.

## Classifying a job

The declaration is easier to fill in from examples than from definitions,
so the standard carries them. Read the class, and the trigger, the worker,
and the failure semantics follow.

| Job | Class | Duplicate policy | Trigger → worker | Why |
|---|---|---|---|---|
| `invoice.send`, via a provider with an idempotency key | `per_event` · `parallel` · `short` | `idempotent` | message → pool | The provider dedupes on the job key. |
| `invoice.send`, via plain SMTP | `per_event` · `parallel` · `short` | `at_most_once` | message → pool | Same job, different far side. Claim first; a crash between send and record is `unknown` and a person decides. |
| `schema.migrate` | `once_ever` · `single_flight` · `short` · blocking | `idempotent` | deployment → one-shot | Converges by SD2. SD3 owns the specifics. |
| `retention.purge` | `periodic` · `single_flight` · `long` | `idempotent` | tick → one-shot | Deleting what is gone is a no-op. Keyset batches, checkpoint per batch. |
| `digest.schedule`, then `digest.send` | `periodic` · `single_flight` · `short`, then `per_event` · `parallel` · `short` | `idempotent`, then per the sender | tick → one-shot, then message → pool | The tick's job only writes one message per tenant to the outbox, keyed on job and tick. Fan-out through the queue makes one tenant's failure one tenant's retry. |
| `partner.poll` | `periodic` · `single_flight` · `short` | `idempotent` | tick → one-shot | Reading is idempotent; findings become messages keyed on the partner's ids. Time turns into events here. |
| `card.charge` | `per_event` · `serial_per_key` · `short` | `idempotent` | message → pool | The job key is the provider's idempotency key; serial per customer so two charges cannot race. |
| `payments.submit_file`, a rail with no idempotency key | `periodic` · `single_flight` · `short` | `at_most_once` | tick → one-shot | Claim first. `unknown` is resolved by a reconciliation job against the rail's acknowledgement. |
| `device.dispense` | `per_event` · `serial_per_key` · `short` | `at_most_once` | message → pool | A second command is a second dose. The command carries the job key; a device that tracks command ids becomes the dedup handle and moves this row to `idempotent`. |
| `order.place` | `per_event` · `serial_per_key` · `short` · `valid_for` | `at_most_once` | message → pool | Idempotent by key would still be wrong by meaning a minute later; a late retry ends `expired`. |
| `reminder.push` | `per_event` · `parallel` · `short` | `at_least_once` | message → pool | A second nudge costs less than a missed one, and the declaration says so. |
| `column.backfill` | `on_demand` · `single_flight` · `long` | `idempotent` | deployment or operator → one-shot | Each batch converges; the checkpoint makes a rerun resume. Never inside the migration. |
| `outbox.relay` | `per_event` · `serial_per_key` · `short` | `idempotent` | message → pool | The committed row is the event; publishing twice is absorbed downstream by AM3's inbox. |
| `deadletter.replay` | `on_demand` · `single_flight` · `short` | `idempotent` | operator → one-shot | Re-produces messages under their original ids, so a second replay is absorbed by the consumers' inboxes. |
| `cache.warm` | once per deployment · `single_flight` · `short` | `at_least_once` | deployment → one-shot | "On server start" is the deployment in disguise; work in the server's boot path runs once per replica, not once. |
| "process pending exports nightly" | refused | — | — | A per-event job wearing a periodic trigger. The request is a message and the exporter is a pool. |

## The artifacts

Per PC3, under [`contracts/jobs/`](../contracts/jobs/):

- **`declaration.schema.json`**: JB3's declaration, including the
  conditional requirements. A periodic job has a schedule and a staleness
  threshold. An `at_most_once` job names its reconciler. A per-event job's
  input is an event and any other job's is an args schema. Only a
  `once_ever` or `on_demand` job can block.
- **`invocation.schema.json`**: JB1's invoked input, with `$ref`s into the
  identifiers and observability contracts for `id`, `time` and
  `traceparent`. It also carries the trigger-specific field each trigger
  kind must carry.
- **`run-record.json`**: JB5's table shape per engine, in the form of 025's
  storage profiles, with the outcome enumeration and the uniqueness rule
  for the key.
- **`corpus.json`**: three parts. `declarations`: declarations the schema
  must accept and reject, each rejection naming the rule. `keys`: for each
  trigger kind, the input and the key JB2 derives from it. `policies`: run
  sequences with crash points, and the effects and outcomes each duplicate
  policy must produce. They include the case that separates a claim-first
  implementation from an act-first one by crashing between the two. They
  include the case that separates a validity-window implementation from a
  dedup-only one by arriving late.

## Decisions

- **Invocations are not CloudEvents** (2026-09-02). A CloudEvent is a
  past-tense fact about an entity with a public id; a tick, a deployment
  step, and a command are none of those. The invocation schema borrows the
  attribute names and stops there, so the per-event majority pays nothing
  and the minority is not misdescribed.
- **Idempotency is a dimension with three values, not a requirement**
  (2026-09-02). An effect inside the service's database can always be made
  idempotent. An effect across a boundary can be made idempotent only when
  the far side offers a dedup handle. Where it does not, exactly-once is
  impossible and the job declares which failure it prefers. The earlier
  position, that every job must be idempotent, assumed a queue behind every
  trigger. It was wrong for physical actuation, plain SMTP, rails with no
  idempotency key, single-use resources, and any legacy interface that
  mints its own ids.
- **The job key is distinct from the delivery id** (2026-09-02). The inbox
  row of 055 AM3 names a delivery and coincides with the work only for
  per-event jobs. A tick, a deployment, and an operator have no delivery,
  and a key derived from them is what lets a duplicate firing produce one
  effect.
- **The lock is in the job, not the runner** (2026-09-02). Every runner can
  forbid overlap and every queue can be given one consumer, and both are
  configuration. The guarantee this standard counts is the one that ships
  in the tested code.
- **A held lock is `skipped` and exits zero** (2026-09-02). The
  alternative, a non-zero exit, makes every long night read as a failure.
  The fault is the overrun, and JB8 alerts on the overrun.
- **The run record lives in the service's database** (2026-09-02). Logs
  answer "what happened". They do not answer "when did this last succeed"
  without a query engine over the logs, which JB8 would need on a schedule.
  The table is the mechanism for the claim, the lock, and the freshness
  rule, not a report beside them.
- **The runner never retries; the next tick is the retry** (2026-09-02). A
  retry policy on top of a schedule produces two runs competing for one
  lock, and JB8 already catches the case where every tick fails.
- **Staleness is declared per job with a default of twice the cadence**
  (2026-09-02). A fixed multiple is wrong at both ends of the cadence
  range, and putting the number beside the schedule is what keeps the two
  honest.

## Out of scope, deliberately

- **Packaging, deployment, and invocation.**
  [`035-workers.md`](035-workers.md), in full. This document is written so
  that a job can be moved between worker models without reading it.
- **Orchestration of many jobs.** A job is one step. A graph of steps with
  dependencies is a workflow, and a workflow engine is a decision this
  platform has not taken. A job that needs another job to have finished
  produces a message and lets the next job consume it. That is the only
  orchestration this standard admits.
- **Notifications to people.** The
  [`058-notifications.md`](058-notifications.md)'s, riding 055's envelope;
  a job that sends one produces the message and stops.
