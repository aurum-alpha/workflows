# Workers: the shape, packaging, and deployment of what runs jobs

## Why this exists

Work that is not a request has to run somewhere, and the somewhere is a
packaging decision. Made by default, it produces a timer nobody knew was
there, or a credential in an image that had no business holding it. Or it
produces a queue that cannot scale without also scaling the server. This standard makes the
decision once. A worker takes one of two shapes, each its own deployable,
built with the service and versioned as the repository. What starts a
one-shot is a contract the platform states and off-the-shelf runners
satisfy, not a component the platform builds.

Nothing in the runner is invented. **OCI image and run semantics** give the
one-shot its whole interface: image, arguments, environment, exit code, and
`SIGTERM` then `SIGKILL` after a grace period. **POSIX
cron** gives the schedule its form, and the **Kubernetes `batch/v1`** Job
and CronJob supply the vocabulary of WK5's seven verbs.
**[Factor XII](https://12factor.net/admin-processes)** names the one-shot:
an admin process run as a one-off from the same release as the long-running
processes.

## The rules

### WK1. There are two worker models, and the trigger picks one

A worker takes one of two shapes:

1. **The pool**. A long-running process that consumes the service's queue and
   runs one per-event job per message, scaled by replicas against the backlog.
2. **The one-shot**. A short-running process that runs one job and exits with
   the outcome as its exit code. It starts on a tick, at a deployment step, or
   by an operator.

A stream of triggers, which is only ever a stream of messages, goes to the
pool. A single invocation, which is a tick, a deployment step, or an operator,
goes to a one-shot.

**The pool** connects to the service's transport (055 AM2) and dispatches
each message to the per-event job the message's `type` routes to. Replica
count scales it against the backlog. Its readiness is its connection to the
transport. Its shutdown is 030 SC4. The pool is 055 AM6's worker, named here
for what it runs.

**The outbox relay is a job the pool runs, never the server**. Under 055 AM4,
a producer writes its event to an outbox table inside the state change's
transaction. A relay publishes it to the transport afterwards. That relay is
a per-event job, `outbox.relay`, serial per key. It is idempotent because
AM3's inbox downstream absorbs a double publish.

It has the service's dependency closure, the service's credential, and the
service's configuration, so under WK2 it shares the service's pool image. The
outbox table is a second source the pool drains beside the transport's queue.
A service with an outbox needs no deployable it did not already have. A relay
built from another repository, including one reading the change stream, is
ruled out by WK2's one-repository rule.

When the transport is the queue table in the service's own database, the
outbox and the queue are the same row (055 AM4). There is nothing to
relay. A relay thread in the server is refused (055 AM6).

**The one-shot** starts and constructs the invocation for one job from its
arguments (WK4). It runs that job, writes the run record around it, maps the
outcome to an exit code, and exits. The runner (WK5) starts it on a tick, the
deployment starts it at a deployment step, or an operator starts it. The
migrate step of 025 SD3 is a one-shot.

**Three shapes are refused by name**. The timer loop is a scheduler fused
with a job. The worker inside the server is what 055 AM6 already refuses.
Work in the boot path runs once per replica rather than once, for the reason
025 SD3 refuses migrate-at-boot.

### WK2. A worker is packaged as the platform packages everything, and a job is not an image

A worker is a container image, built in the same build run as the service, at
the repository's version. It is built under [`010-ci.md`](010-ci.md)'s
Principles 7 and 15. That means built once per run, versioned as the
repository, and tested beside every other artifact of that run. The job it runs is code under 057's
contract, and is packaged only by being inside a worker.

**Which jobs share a worker image is decided by the three criteria of
[`010-ci.md`](010-ci.md) Principle 15**: the dependency closure, the
credential, and the configuration surface. Where all three are the same, jobs
share an image; where one differs, the image splits. Applied to workers:

- The **migrate image**, `<service>-migrate`, stands alone. It gets
  the migration credential and nothing else, per 025 SD3, and no other job
  is permitted to hold that credential.
- The **recovery image**, `<service>-recovery`, stands alone: it alone holds
  the restore credential ([`028-backup-and-recovery.md`](028-backup-and-recovery.md)
  BR3).
- A service's **ordinary one-shot jobs** run against the service's data with
  the service's runtime credential and the service's dependency closure. They
  share one one-shot image, `<service>-jobs`, and an argument selects the
  job. This is not the multi-entrypoint image this platform refuses. That
  image mixes a server, a consumer, and a migrator: three process shapes with
  three closures and three scaling profiles. A one-shot image has one shape,
  one closure, one credential, and no replica count.
- A one-shot job with a **dependency of its own** gets its own image, because
  its closure differs. Such a dependency is a rendering engine, a large
  model, or a driver the rest of the service does not carry.
- The **pool**, `<service>-pool`, is one image per queue, and WK3 says there is
  one queue by default.

A service lives in exactly one repository (025 SD13). Each service in a
shared repository therefore gets its own pool, jobs and migrate images, built
in the same run at the same version. No image gets a credential to another
service's state.

**Where a runtime cannot run a separate image**, the one-shot is a command in
the server image, run to completion by the runner. It has the same interface
and exit codes as any one-shot. It is never a request handler and never the
boot path. The repository records in its own decisions that it uses this
form. Migrations are excluded: the credential separation SD3 requires cannot
be had inside the server image. The alternative is a standard a legacy
runtime cannot adopt, which is a standard ignored there.

### WK3. One pool per service by default; partitioning is a measured optimisation

The dimension a pool scales on is the workload: messages arriving, time per
message, backlog depth. The answer to a backlog is replicas. A service
therefore has one pool image, draining its queue and, where the transport is
external, its outbox.

The exception is a service that has measured two workloads on that queue with
scaling properties that fight each other. That is a slow job starving a fast
one, or a burst of one type delaying every other. Then it partitions. It
moves the job to its own queue and its own pool by changing the job's
declaration, and records why in its own decisions.

### WK4. The one-shot's interface is one command, and it constructs the invocation

```
docker run --env-file <env> <service>-jobs:<version> <job.name> [--at <tick>] [--key <key>] [args...]
docker run --env-file <env> <service>-migrate:<version>
```

The one-shot reads the job's declaration (057 JB3) and refuses to run a job
that has none. It validates the arguments against the job's `args_schema`,
and builds the invocation (057 JB1). The invocation is a UUIDv7 `id`, the
service as `source`, the trigger kind, the `time`, a `traceparent`, and the
job key. The `traceparent` is one it starts or is handed in the environment.
The job key is derived by the trigger's rule.

For a tick the key is the job name and `--at`. The runner supplies `--at`
from the schedule, and it is what makes two firings of one tick one run. For
a deployment the key is the job name and the release version. For an operator
it is `--key` if given. Otherwise the one-shot mints and prints the key, so
the operator can rerun the same work or deliberately start new work.

It then opens the run record, runs the job, closes the record with the
outcome, and exits. The outcome maps to an exit code, fixed by
[`exit-codes.json`](../contracts/workers/exit-codes.json):

| Exit | Outcome or condition | Why this code |
|---|---|---|
| `0` | `succeeded`, `skipped` | The work is done or is being done by another run. A deployment waiting on a blocking job proceeds. |
| `1` | `failed` | The conventional general failure. A deployment stops. |
| `2` | `unknown` | Distinct from failure because the response is different: reconcile, do not rerun blindly. |
| `3` | `expired` | Distinct because the response is a decision about the work's meaning, not a retry. |
| `64` | bad arguments or unknown job | `EX_USAGE` from `sysexits.h`, which shells and runners already know. |
| `78` | missing or invalid configuration | `EX_CONFIG`, the same condition 030 SC3 makes a server refuse to serve on. |

It never daemonises and never sleeps for a next tick.

**Very long work has two admitted shapes, and the invoker decides**. When a
deployment must wait for the work, the job is a one-shot and blocks. An exit
code is the only outcome a pipeline can wait on. When the work is
operational and large, a backfill over a large table, it is written as a
self-continuing per-event job under 057 JB10. That job processes a batch,
checkpoints, produces the message for the next batch, and lets the pool carry
it. So a replica dying costs one batch rather than the run.

### WK5. The runner is the platform's, and it satisfies seven verbs

Something has to start a one-shot on a tick. This standard names no runner and
builds none: building one would be building a worse CronJob and owning it. It
states what the runner must do, in
[`runner-contract.json`](../contracts/workers/runner-contract.json). The
seven verbs:

1. **Run an image**, or a command in one, to completion with args and
   environment, and expose the exit code.
2. **Deliver `SIGTERM`** and wait the declared grace before `SIGKILL`.
3. **Enforce the declared deadline.**
4. **Fire a five-field cron schedule in UTC**, passing the tick as `--at`.
5. **Never start a second run of one schedule** while one is running.
6. **Never retry a failed run.** The next tick is the retry. A retry policy on
   top of a schedule produces two runs competing for one lock.
7. **Handle a missed tick by the declared policy**: run late within the
   window, or skip.

A runtime satisfies the contract or it does not, and a repository is
conformant on any that does. **Which components satisfy which verb, and by
which setting, is
[`solutions/035-workers.md`](../solutions/035-workers.md)**. A runtime
missing a verb is not a runner.

Two of those verbs duplicate guarantees the job already carries. The runner
forbids overlap, and 057 JB6 locks in the job. The runner does not retry, and
057 JB8 catches a job whose every tick fails. The runner's settings are
configuration anyone can change without reading a declaration; the job's
guarantees ship in tested code, and only those are counted.

### WK6. The declaration is rendered to the runner at deployment, and the rendered form is an artifact

The schedule, deadline, grace, and missed-tick policy live in the job's
declaration (057 JB3), in the repository, once. At deployment, a platform tool
renders every periodic job's declaration into the runner's native form for
the target runtime. That form is a CronJob manifest, a timer and service unit
pair, or a scheduler rule. The rendered form is an artifact of the release,
versioned with the image it starts, and never edited by hand. A change to a
schedule is a change to the declaration, reviewed as code, and the render
follows. That is 010-ci's Principle 1, one source of truth per pin.

The deployment pipeline and the operator are the other two triggers and need
no rendering. The pipeline runs the deployment-step jobs in declared order,
the migrate image first, blocking on each exit code. The operator runs WK4's
command.

### WK7. A worker exposes what scales it and what stops it

A pool exposes, in the 040 shape, the depth of its queue and the age of its
oldest unacknowledged message. Those two numbers are what a replica count is
tuned against and what an operator reads when a pool is behind. How a runtime
turns them into replicas is the runtime's, recorded in the repository's own
decisions. It exposes the 030 SC1 endpoints, with readiness meaning connected
to the transport and able to receive.

A one-shot exposes nothing beyond its logs, its run record, and its exit
code. It has no port, because it has no request to answer. Both carry
`job.name` and `job.run_id` in every log line and the run's trace attributes.
So a run is traceable from the worker's side and the job's side to the same
span.

### WK8. A worker's configuration and credential are the least its jobs need

Configuration is 030 SC3's. A worker's configuration surface is the union of
what its jobs declare they need, which is one of the three things WK2 splits
images on.

The pool and the ordinary one-shot image carry the service's runtime
credential. The migrate image carries the migration credentials and no
runtime credential. Those are the relational one and, where
[`027-json-document-storage.md`](027-json-document-storage.md) admits a JSON
document store, that store's declaration credential (027 DS7). The recovery
image carries the restore credential and the runtime credential for its run
record. No other image carries the restore credential
([`028-backup-and-recovery.md`](028-backup-and-recovery.md) BR3). No worker
image carries a credential for a database it does not own, because 057 JB9
gives a job no reason to have one.

## The artifacts

Per PC3, under [`contracts/workers/`](../contracts/workers/):

- **`runner-contract.json`**: WK5's seven verbs as data, with the settings
  that satisfy each verb in each runner.
- **`exit-codes.json`**: WK4's table.
- **`corpus.json`**: one-shot behaviour cases run against a repository's
  one-shot image.

## Decisions

- **A tick delivered as a message**. That would need the scheduler to produce
  into the service's transport, which 025 SD13 makes private. Invoking a
  one-shot needs only the image and the schedule. Where a tick's work is a
  fan-out, the job produces the messages through its own outbox.
