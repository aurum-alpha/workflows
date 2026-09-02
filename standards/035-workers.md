# Workers: the shape, packaging, and deployment of what runs jobs

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/workers/`](../contracts/workers/). The words *service*, *server*,
*worker*, *process*, *job*, *run*, *trigger*, *release* and *deployment* are
used in the senses [`000-platform.md`](000-platform.md#terms) defines. What a
worker runs is a job, and jobs are [`057-jobs.md`](057-jobs.md)'s; the queue a
pool consumes is [`055-messaging.md`](055-messaging.md)'s; the server the
worker sits beside is [`030-service.md`](030-service.md)'s, and the worker
obeys that document's rules for logging, configuration, and shutdown in its own
terms.

This document governs **the worker**: the process that runs jobs. It defines
the two shapes a worker takes, how a worker is packaged and versioned, how the
platform's runner starts a worker on a tick, at a deployment step, or by an
operator's hand, how a job's declaration reaches that runner, and what a
worker exposes about itself. **What it does not define is the job**: its key,
its duplicate policy, its outcomes, its run record. A worker is the thing that
knows about triggers, images, exit codes, and schedulers, precisely so that a
job never has to.

## Why this exists

Work that is not a request has to run somewhere, and the somewhere is where
the cheapest answers do their damage. A timer inside the server runs once per
replica, dies with every deployment, and hides its schedule in code. A loop
that sleeps and wakes is a scheduler and a job fused into one binary, with the
scheduler part written badly. A migration in the boot path runs on every
replica of every rollout. A single binary that serves, consumes, and migrates
depending on a flag has the union of three dependency closures, three
configuration surfaces, three credentials, and three failure modes, and scales
all of them together because they are one image.

Each of those is a packaging decision made by default, and each has a cost
that arrives later: an outage traced to a timer nobody knew was there, a
credential found in an image that had no business holding it, a queue that
could not be scaled without also scaling the server. This standard makes the
packaging decision once. There are two shapes a worker takes. Each is its own
deployable, built with the service and versioned as the repository. The thing
that starts a one-shot is a contract the platform states and existing runners
satisfy, not a component the platform builds.

### The standards evaluated first, per PC2

Nothing in the runner is invented. **OCI image and run semantics** give the
one-shot its whole interface: an image, arguments, environment, an exit code,
and `SIGTERM` followed by `SIGKILL` after a grace period. **POSIX cron** gives
the schedule its form: five fields, read the same by every scheduler below.
**The Kubernetes `batch/v1` API**, Job and CronJob, is the most complete
written form of what a runner must do, and WK5's seven verbs are its
vocabulary; systemd timers with oneshot units, the container CLI driven by a
pipeline or an operator, and the managed schedulers of the major clouds satisfy
the same verbs. **[Factor XII](https://12factor.net/admin-processes)** names
the one-shot: an admin process run as a one-off from the same release, with
the same code, configuration, and dependencies as the long-running processes.

What the platform states is the contract those runners satisfy, so that a
repository is bound to the contract and not to a runner, and a runner can be
swapped by changing how a declaration is rendered rather than by changing a
job.

## The rules

### WK1. There are two worker models, and the trigger picks one

**The pool** is long-lived. It connects to the service's transport (055 AM2),
consumes the service's queue, dispatches each message to the per-event job the
message's `type` routes to, and is scaled by replica count against the
backlog. Its readiness is its connection to the transport; its shutdown is 030
SC4: on `SIGTERM` it stops taking messages, finishes what it holds within the
declared grace, and exits, and anything it held past that is redelivered. The
pool is 055 AM6's worker, named here for what it runs.

**The outbox relay is a job the pool runs, never the server.** 055 AM4 has a
producer write its event to an outbox table inside the state change's
transaction, and a relay publish it to the transport afterwards. That relay is
a per-event job, `outbox.relay`, serial per key, idempotent because AM3's inbox
downstream absorbs a double publish. It has the service's dependency closure,
the service's credential, and the service's configuration, so under WK2 it
shares the service's pool image: the outbox table is a second source the pool
drains beside the transport's queue, and a service with an outbox needs no
deployable it did not already have. When the transport is the queue table in
the service's own database, AM4 already notes the outbox and the queue are the
same row and there is nothing to relay. What no case admits is a relay thread
inside the server, for every reason AM6 gives against a timer there: it runs
per replica, it dies with every deployment, and the service contract's
lifecycle rules cannot see it.

**The one-shot** is short-lived. It starts, constructs the invocation for one
job from its arguments (WK4), runs that job, writes the run record around it,
maps the outcome to an exit code, and exits. It is started by the runner (WK5)
on a tick, by the deployment at a deployment step, or by an operator. The
migrate step of 025 SD3 is a one-shot, and was the first one written down.

**The trigger picks the model**, and nothing else does. A stream of triggers,
which is only ever a stream of messages, goes to the pool. A single invocation,
which is a tick, a deployment step, or an operator, goes to a one-shot. Three
shapes are refused by name: the timer loop, which is a scheduler fused with a
job; the worker inside the server, which 055 AM6 already refuses; and work in
the boot path, which runs once per replica rather than once, for the reason
025 SD3 refuses migrate-at-boot.

### WK2. A worker is packaged as the platform packages everything, and a job is not an image

A worker is a container image, built in the same build run as the service, at
the repository's version, under [`010-ci.md`](010-ci.md)'s Principles 7 and
15: built once per run, versioned as the repository, tested beside every other
artifact of that run. The job it runs is code under 057's contract, and is
packaged only by being inside a worker.

**Which jobs share a worker image is decided by three things, and by nothing
else**: the dependency closure, the credential, and the configuration surface.
Where all three are the same, jobs share an image. Where one differs, the
image splits. So:

- The **migrate image**, `<service>-migrate`, stands alone, always. 025 SD3
  gives it the migration credential and nothing else, and no other job may
  hold that credential.
- A service's **ordinary one-shot jobs**, which run against the service's data
  with the service's runtime credential and the service's dependency closure,
  share one one-shot image, `<service>-jobs`, and the job is selected by
  argument. This is not the multi-entrypoint image this platform refuses: that
  image mixed a server, a consumer, and a migrator, three process shapes with
  three closures and three scaling profiles. A one-shot image has one shape,
  one closure, one credential, and no replica count.
- A one-shot job with a **dependency of its own**, a rendering engine, a large
  model, a driver the rest of the service does not carry, gets its own image,
  because its closure differs.
- The **pool**, `<service>-pool`, is one image per queue, and WK3 says there is
  one queue by default.

**A repository is not a service, and images never cross the service line.** A
service is the set of processes that share one state under one credential and
one migration history, and a repository may hold several. Two services in one
repository have two credentials, so the credential criterion above gives each
its own pool image, its own jobs image, and its own migrate image, built in
the same run at the same version. The shared version is provenance: everything
in the run was tested together. It is not ownership. What makes a worker
*this* service's worker is that it holds this service's credential and is
migrated by this service's migrations, and a worker for the service next door
reaches this one through its interface or its messages, as 025 SD13 requires
of any other service.

**The converse holds too: a service lives in exactly one repository.** Every
process that holds a service's credential is built from the repository that
holds that service's migrations, in one run, at one version. The schema is
defined by the migrations and every query is coupled to it; a process built
elsewhere that reads the database gives one schema two release trains, and the
failure SD13 names for two services sharing a table becomes possible between
two halves of one service. Provenance binds only what was built together, so
one state means one repository. The credential is the checkable edge: a
database's credential appears in the deployables of one repository and no
other, which is what lets this rule be read from the build rather than from a
review. It also rules out a relay built elsewhere that reads the service's
tables through the change stream; the outbox relay is a job in the service's
pool, and nothing else.

**Where a runtime cannot run a separate image**, the one-shot is a command in
the service's server image, run to completion by the runner, with the same
interface and exit codes as any one-shot. It is never a request handler and
never the boot path, and the repository records in its own decisions that it
uses this form. Migrations are excluded from it: the credential separation SD3
requires cannot be had inside the server image.

### WK3. One pool per service by default; partitioning is a measured optimisation

The dimension a pool scales on is the workload: messages arriving, time per
message, backlog depth. The answer to a backlog is replicas. A service
therefore has one pool image, draining its queue and, where the transport is
external, its outbox, unless it has measured two workloads on that queue with
scaling properties that fight each other, a slow job starving a fast one, a
burst of one type delaying every other. Then it partitions, moves the job to
its own queue and its own pool by changing the job's declaration, and records
why in its own decisions. Partitioning is something a repository does with a
reason in hand, not a rule it follows in advance.

### WK4. The one-shot's interface is one command, and it constructs the invocation

```
docker run --env-file <env> <service>-jobs:<version> <job.name> [--at <tick>] [--key <key>] [args...]
docker run --env-file <env> <service>-migrate:<version>
```

The one-shot reads the job's declaration (057 JB3), refuses to run a job that
has none, validates the arguments against the job's `args_schema`, and builds
the invocation (057 JB1): a UUIDv7 `id`, the service as `source`, the trigger
kind, the `time`, a `traceparent` it starts or is handed in the environment,
and the job key derived by the trigger's rule. For a tick the key is the job
name and `--at`, which the runner supplies from the schedule and which is what
makes two firings of one tick one run; for a deployment it is the job name and
the release version; for an operator it is `--key` if given, else minted and
printed so the operator can rerun the same work or deliberately start new
work.

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

The one-shot logs to stdout in the 030 SC2 shape with `job.name` and
`job.run_id` in every line, never daemonises, and never sleeps for a next
tick. What the operator runs is what the runner runs and what the deployment
runs, which is 010-ci's Principle 2, a gate reproducible with one command,
applied to operations.

**Very long work has two admitted shapes, and the invoker decides.** When a
deployment must wait for the work, the job is a one-shot and blocks, because
an exit code is the only outcome a pipeline can wait on. When the work is
operational and large, a backfill over a large table, it is written as a
self-continuing per-event job under 057 JB10: process a batch, checkpoint,
produce the message for the next batch, and let the pool carry it, so a
replica dying costs one batch rather than the run.

### WK5. The runner is the platform's, and it satisfies seven verbs

Something has to start a one-shot on a tick. This standard names no runner and
builds none. It states what the runner must do, in
[`runner-contract.json`](../contracts/workers/runner-contract.json), and each
runtime the platform could sit on already has a component that does it:

| The runner must | Kubernetes Job / CronJob | systemd timer + oneshot | Container CLI, by a pipeline or an operator | Managed schedulers |
|---|---|---|---|---|
| Run an image, or a command in one, to completion with args and env, and expose the exit code | `Job`, `restartPolicy: Never` | `Type=oneshot`, `ExecStart=` | `docker run` | ECS RunTask, Cloud Run Jobs, Nomad `batch` |
| Deliver `SIGTERM` and wait the declared grace before `SIGKILL` | `terminationGracePeriodSeconds` | `TimeoutStopSec=` | `docker stop -t` | Task stop timeout |
| Enforce the declared deadline | `activeDeadlineSeconds` | `RuntimeMaxSec=` | `timeout` around the run | Task timeout |
| Fire a five-field cron schedule in UTC, passing the tick as `--at` | `schedule`, `timeZone: Etc/UTC` | `OnCalendar=`, translated from cron | Not a scheduler | EventBridge Scheduler, Cloud Scheduler, Nomad `periodic` |
| Never start a second run of one schedule while one is running | `concurrencyPolicy: Forbid` | A timer never starts an active unit | — | `prohibit_overlap` and equivalents |
| Never retry a failed run | `backoffLimit: 0` | No `Restart=` | — | Retry count zero |
| Handle a missed tick by the declared policy: run late within the window, or skip | `startingDeadlineSeconds` | `Persistent=` | — | Catch-up settings |

Two of those verbs duplicate guarantees the job already carries, and the
duplication is deliberate. The runner forbids overlap and 057 JB6 locks in the
job; the runner does not retry and 057 JB8 catches a job whose every tick
fails. The runner's settings are configuration that can be changed without
reading a declaration. The job's guarantees ship in tested code. The platform
counts only the second and configures the first so that the two never
disagree.

The runner's own record of runs, where it keeps one, is a convenience. 057
JB5's run record is the authority, so a runner that keeps nothing costs the
platform nothing.

### WK6. The declaration is rendered to the runner at deployment, and the rendered form is an artifact

The schedule, deadline, grace, and missed-tick policy live in the job's
declaration (057 JB3), in the repository, once. At deployment, a platform tool
renders every periodic job's declaration into the runner's native form for the
target runtime: a CronJob manifest, a timer and service unit pair, a scheduler
rule. The rendered form is an artifact of the release, versioned with the
image it starts, and never edited by hand; a change to a schedule is a change
to the declaration, reviewed as code, and the render follows. This is
010-ci's Principle 1, one source of truth per pin, applied to the one pin that
would otherwise live in a cluster.

The deployment pipeline and the operator are the other two triggers and need
no rendering: the pipeline runs the deployment-step jobs in declared order,
the migrate image first, blocking on each exit code; the operator runs WK4's
command.

### WK7. A worker exposes what scales it and what stops it

A pool exposes, in the 040 shape, the depth of its queue and the age of its
oldest unacknowledged message, because those two numbers are what a replica
count is tuned against and what an operator reads when a pool is behind. It
exposes the 030 SC1 endpoints, with readiness meaning connected to the
transport and able to receive. A one-shot exposes nothing beyond its logs, its
run record, and its exit code; it has no port, because it has no request to
answer. Both carry `job.name` and `job.run_id` in every log line and the run's
trace attributes, so a run is traceable from the worker's side and the job's
side to the same span.

### WK8. A worker's configuration and credential are the least its jobs need

Configuration comes from the environment, and absence blocks starting, as 030
SC3 requires of the server. A worker's configuration surface is the union of
what its jobs declare they need and nothing more, which is one of the three
things WK2 splits images on. The pool and the ordinary one-shot image carry
the service's runtime credential. The migrate image carries the migration
credential and no other. No worker image carries a credential for a database
it does not own, because 057 JB9 gives a job no reason to have one.

## The artifacts

Per PC3, under [`contracts/workers/`](../contracts/workers/):

- **`runner-contract.json`** — WK5's seven verbs as data: the requirement,
  the declaration fields it consumes, and the settings that satisfy it in each
  runner named above, so a renderer targets it and a checker reads it.
- **`exit-codes.json`** — WK4's table, consumed by the deployment step and by
  the corpus.
- **`corpus.json`** — one-shot behaviour cases run against a repository's
  one-shot image: an undeclared job exits `64`; a missing variable exits `78`;
  a held lock exits `0` with `skipped` in the run record; `SIGTERM` during a
  long job leaves a checkpoint and exits within grace; the same `--at` twice
  produces one run with an effect and one `skipped`; a failed blocking job
  exits `1`.

## Enforcement

Every WK rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. Mechanically
checkable, and first to move: that a repository's image set contains a migrate
image and a jobs image where it has one-shot jobs and a pool image where it
has per-event jobs (WK2, read from the CI catalog calls); that every periodic
declaration has a rendered counterpart in the deployment output and the two
agree (WK6); and the corpus against the one-shot image (WK4). Review
questions, said so in the ledger row: that no timer loop exists anywhere
(WK1), that images are split for the three reasons and no others (WK2), and
that a partition was measured before it was made (WK3).

## Decisions

- **Two worker models, not three** (2026-09-02). Every trigger is a stream or
  an invocation. The timer loop is the third shape everyone reaches for, and it
  is a scheduler and a job fused, with the scheduler half hidden in code.
- **The runner is adopted, not built** (2026-09-02). The seven verbs are
  Kubernetes `batch/v1`'s vocabulary, and every runtime the platform could
  plausibly sit on satisfies them. Building a runner would be building a worse
  CronJob and owning it.
- **The tick is an invocation, not a message** (2026-09-02). Delivering a tick
  as a message would need the scheduler to produce into the service's
  transport, which 025 SD13 makes private. Invoking a one-shot needs the image
  and the schedule. Where a tick's work is a fan-out, the job produces the
  messages through its own outbox and the messaging lane is entered by the
  service.
- **Ordinary one-shot jobs share one image** (2026-09-02). Images split on
  closure, credential, and configuration surface; jobs that share all three
  sharing an image is not the multi-entrypoint image the platform refuses,
  which mixed process shapes. The migrate image is the case where the
  credential differs, and it stands alone.
- **One pool per service by default** (2026-09-02). The scaling dimension is
  the workload and the lever is replicas. Partitioning is admitted as a
  measured optimisation and recorded where it is done.
- **The outbox relay rides in the pool** (2026-09-02). It is a per-event job
  with the service's closure and credential, so WK2 puts it in the service's
  pool image rather than in a deployable of its own or a thread in the server.
  The table transport removes it. A relay built from another repository,
  including one reading the change stream, is ruled out by the one-repository
  rule in WK2. The server never hosts it, for AM6's reasons.
- **A service lives in exactly one repository** (2026-09-02). Provenance binds
  only what was built together, and every process touching one schema must be
  bound to its migrations. The credential's presence in one repository's
  deployables is the checkable form.
- **The escape hatch for runtimes that cannot run a separate image**
  (2026-09-02). A command in the server image, run to completion, with
  migrations excluded. The alternative is a standard a legacy runtime cannot
  adopt, which is a standard ignored there.
- **Distinct exit codes for `unknown` and `expired`** (2026-09-02). Each calls
  for a different response than `failed`, and a pipeline or an operator reading
  the exit is the first place that response is chosen.
- **Numbered 035, beside the service contract** (2026-09-02). A worker is a
  process shape, the server's sibling, and its rules for logging,
  configuration, and shutdown are 030's in different terms. It references 055
  and 057 forward, which the document conventions allow.

## Out of scope, deliberately

- **The job itself.** Key, duplicate policy, outcomes, run record, lock,
  freshness: [`057-jobs.md`](057-jobs.md).
- **Autoscaling policy.** WK7 says what a pool exposes; how a runtime turns
  those numbers into replicas is the runtime's, and a repository's own decision
  to record.
- **Workflow engines.** A worker runs one job. A graph of jobs is a decision
  this platform has not taken, and 057 says how far messages carry sequencing
  without one.
