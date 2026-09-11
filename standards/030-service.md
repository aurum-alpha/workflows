# The service contract

## Why this exists

These standards cover how a service is built, tested, packaged and shipped.
They said nothing about what the running thing must **expose**. So every
product answered the same operational questions independently, and several
answered them by not answering. Across the six TypeScript SaaS products at
the time this was written: no health endpoint anywhere, three different
logging answers, and rate limiting in two. The logging answers were a library
in two, a hand-rolled logger in three, nothing in one.

The health endpoint is the one that pays immediately. `job-image-starts`
exists to prove a built image actually runs. With no endpoint to hit, the
strongest claim it can make is that the process did not exit within the
timeout. **A service that starts, fails to reach its database, and sits
there answering nothing passes that check today**. Giving every service a
readiness endpoint turns a shared job already in the catalog from a liveness
guess into a real gate. No new job, no new infrastructure.

Most of what follows is [twelve-factor](https://12factor.net/) applied to
these applications, and each rule cites the factor it rests on. What this
document adds is the part twelve-factor deliberately leaves open: the actual
paths, field names and response shapes. Without them, six conformant
services are still six different services to operate.

## The rules

### SC1. Two endpoints, fixed paths, fixed shapes

Every service exposes both, and they answer different questions:

| Path | Question | Checks dependencies | Failure means |
|---|---|---|---|
| `/healthz` | Is this process alive? | **No** | Restart me |
| `/readyz` | Can this process serve traffic? | **Yes** | Stop routing to me |

Conflating them is the classic operational error. A readiness check wired to
the restart probe turns one slow database into an infinite restart loop of
otherwise healthy processes. A liveness check that talks to a database
reports the database's health as the process's.

Both are **unauthenticated, never cached** (`Cache-Control: no-store`), and
respond `application/json` in the shape
[`contracts/service/health.schema.json`](../contracts/service/health.schema.json)
defines. `/healthz` returns `200` whenever the process is alive.

**Every readiness check declares whether the service can serve without it**.
That declaration is what makes `/readyz` answer its own question instead of
an easier one:

| Body `status` | Code | Means |
|---|---|---|
| `ok` | `200` | every check passes |
| `degraded` | `200` | a check the service can serve without is failing. **Route to me anyway**. |
| `fail` | `503` | a check the service cannot serve without is failing. Stop routing to me. |

**The status code is the routing contract and stays binary**, because a load
balancer has exactly two behaviours. `degraded` is the body telling a human
and a dashboard that something is wrong while the correct answer is still
"send me traffic". A service that returns `503` because its optional cache
is cold has removed itself from rotation over a condition it was built to
tolerate. That is a self-inflicted outage.

Each readiness check names the dependency it probed, whether it is required,
its own outcome, and how long it took. A readiness endpoint that returns
`{"status":"ok"}` while checking nothing is worse than no endpoint, because
it converts an unknown into a wrong answer.

### SC2. One structured log line, to stdout

Logs go to stdout as an event stream, per
[factor XI](https://12factor.net/logs). The application never routes,
rotates, or stores its own logs, because that is the execution
environment's job. This rule is inherited, not invented.

What this standard pins is the line itself: **one JSON object per line**.
It carries `ts` (an instant per [`020-identifiers.md`](020-identifiers.md)
IP4), `level`, `msg` and `service`. Whenever request context exists, it also
carries the context block from [`040-observability.md`](040-observability.md)
OC2 and OC4. Schema:
[`contracts/service/logline.schema.json`](../contracts/service/logline.schema.json).

Levels are the five of `debug`, `info`, `warn`, `error`, `fatal`. The
threshold comes from configuration (SC3), never from code that detects its
environment. Multi-line output (a stack trace, a pretty-printed object) is a
field within the one JSON object, never a second line. A log pipeline splits
on newlines, so a stack trace printed raw becomes forty unattributed lines
that no query will ever join back together.

A human-readable renderer for local development is fine, and is a rendering
of the same records, chosen by configuration.

**A failure line states the reason, never the fact of failure**. Every
`error` and `fatal` line answers three questions. A line that answers fewer
is not a log entry; it is a notification that logging happened:

- **What operation** was attempted, specifically. Not "request failed" but
  the operation the code was performing.
- **On what**, identified. Name the connection string's host and port, the
  configuration key, the record's public id, the endpoint called, the file
  path, or the queue name. Whatever a person needs to go and look at the
  thing.
- **Why it failed**: the underlying cause, as received. That is the errno,
  the upstream status code and body, or the constraint violated. Or it is
  the validation rule that rejected, or the timeout that elapsed and its
  limit. Where the
  failure wraps another failure, preserve the chain rather than replace it.

`error occurred`, `operation failed`, `invalid input`, `something went
wrong`, `internal error`, `unexpected error`: these are **failure
classes, and a class is not a diagnosis**. They are good as the opening of
a message and useless as the whole of one. So the rule is not that the
words are forbidden but that they must be followed through:

| Not this, alone | This |
|---|---|
| `invalid input` | `invalid input: expiry_date must be RFC 3339 full-date, got "31/08/2026"` |
| `operation failed` | `charge authorisation failed: acquirer returned 402 insufficient_funds` |
| `internal error` | `internal error: template render panicked on nil customer address` |
| `something went wrong` | `webhook delivery failed after 5 attempts: connect refused to hooks.example.com:443` |

The test is a question, not a word list: **what kind of error, on which
operation, with which input, and what exactly went wrong**? A message that
leaves any of those unanswered when the code was holding the answer is the
defect. Every failure has a specific cause at the moment it is logged.
Discarding it there is choosing to make the next incident harder in
exchange for nothing. An error line that cannot be acted on without
attaching a debugger is a defect in the line, not a fact about the
failure.

The specifics live in **fields**, so they can be queried. `msg` names the
failure mode precisely enough to be useful on its own while staying stable
enough to group. That is `mysql connect timeout`, not `db error` and not
`mysql connect timeout after 5000ms to db-primary:3306`. The one exception
is a terminal `fatal` that precedes an exit (SC6). Nothing downstream will
ever query it, and a human is reading raw stdout, so `msg` carries the whole
diagnosis in plain words.

**Specific is not the same as verbose, and it is never an excuse to leak**.
Name the configuration key, never its value. Reference a record by its
public id (`020-identifiers.md` IP1), never by dumping its contents. Name the
field that failed validation, not the personal data that failed it.

A secret, a token, a credential, or a full connection string with its
password in a log line is a defect of its own. So is protected personal
data in a log line.
The redaction rules belong to [`032-secrets.md`](032-secrets.md). *What*
failed and *why* is almost never the sensitive part; the payload is.

### SC3. Configuration comes from the environment, and absence blocks serving

Config lives in environment variables, per
[factor III](https://12factor.net/config). This standard's additions:

- **Names are `SCREAMING_SNAKE_CASE`**, and describe the thing rather than
  its consumer: `DATABASE_URL`, `OTEL_EXPORTER_OTLP_ENDPOINT`.
- **A required variable has no default**. A service missing one, or holding
  an invalid one, **does not serve traffic**. Per SC6 it still starts its
  endpoints and says so rather than dying. Its message names **every**
  missing or invalid variable at once, not the first one. Discovering a
  broken configuration one restart at a time is how a ten-minute deploy
  becomes an hour.
- **An optional variable's default is the safe value**. The service logs
  the value at startup, so the running configuration is knowable from the
  logs.
- **No environment detection in code**. Nothing branches on `NODE_ENV`,
  a hostname, the presence of a Docker socket, or whether a path exists.
  Differences between deploys are *values*, not code paths. That is what
  makes [factor X](https://12factor.net/dev-prod-parity) parity real. The
  code that ran in staging is byte-identical to the code in production, and
  only its inputs differed. A service that behaves differently because it
  guessed where it was running has an untestable branch in it.

Secrets arrive the same way, and [`032-secrets.md`](032-secrets.md) governs
them; nothing here permits logging one.

### SC4. SIGTERM means drain

On `SIGTERM`, in order: **flip readiness to failing**, stop accepting new
work, let in-flight work finish, close pools and connections, exit `0`.
Per [factor IX](https://12factor.net/disposability), a process that dies
badly is a process that cannot be deployed safely.

The order is the rule. Flipping readiness *first* is what makes a rolling
deploy non-lossy. The load balancer stops sending new requests while the
process is still able to finish the ones it has. Exiting immediately on
`SIGTERM`, the default in most runtimes, drops every in-flight request,
and does so silently. That is why this is stated rather than assumed.

The drain deadline is configuration with a stated default, and it is shorter
than the orchestrator's kill timeout. A service that has not finished
draining by its deadline exits anyway and **logs what it abandoned**: work
lost quietly is work nobody reconciles.

### SC5. The running service says which build it is

CI Principle 13 already requires the commit and build timestamp baked into
every artifact. Nothing required the running service to *tell* you which
one it is. So during an incident the question "is the fix actually
deployed?" was answered by inference.

Every service, at startup, emits **one log line carrying its service name,
version, commit SHA and build timestamp**. It reports the same values in
the `/healthz` body. Two places on purpose. The log line is unconditional
and is what CI reads, so the assertion does not depend on how a repository
exposes an endpoint. The endpoint is what a human hits at three in the
morning.

Exposing a commit SHA on an unauthenticated endpoint is a deliberate, small
disclosure. It tells an unauthenticated reader exactly which published
vulnerabilities to try. It is accepted here because incident response needs
it more than an attacker does. The alternative, provenance only in logs,
puts it behind exactly the access an incident responder might be waiting
on. Where a repository's threat model disagrees,
[`085-security-baseline.md`](085-security-baseline.md) governs endpoint
exposure, and the startup log line still satisfies this rule.

### SC6. Start fast, degrade rather than block, and never crashloop

**The listener and both endpoints come up as early as the process can bring
them up**. Everything else happens after, and concurrently: connection
pools, cache warming, dependency probes, first token fetches. A service
that spends thirty seconds proving its world is intact before it answers
`/healthz` is a service nobody can diagnose for thirty seconds.

**A dependency is not a startup gate**. The test is simple: *if this
dependency vanished an hour after startup, would the service have to cope*?
It would. Dependencies fail at runtime, and code that handles that already
exists or must exist. A dependency the service must handle gracefully at
3pm is not a dependency worth dying over at boot.

So the service **assumes its dependencies are up**, starts, and reports
their real state on `/readyz`. It handles failures at request time through
the same paths it uses in steady state. Probing at startup only to refuse
to start reimplements the runtime error path badly. It does so in a place
with no request to fail and nobody to tell.

Two consequences worth stating, because both get built wrong by default:

- A missing **optional** dependency means the service starts `degraded`
  and serves. That is the mode existing gracefully-degrading code was
  written for; refusing to start instead throws it away.
- A missing **required** dependency means the service starts, reports
  `fail` on `/readyz`, and takes no traffic. That is the same outcome as
  refusing to start, except it is observable, curl-able, and does not
  restart in a loop.

**The one exception is a startup migration**. Some services migrate the
schema at boot and cannot serve correctly against the old schema. Such a
service is permitted to block on the database for that migration, and its
**Conventions** section says so. That is a real dependency on a real
operation, not a reflexive check.

**Misconfiguration is the one thing that blocks serving** (SC3), and it
still does not stop the endpoints. A misconfigured service binds its port
and serves `/healthz` and `/readyz`. It reports `fail` with a check named
for the configuration and a detail naming every broken variable. It logs
the same at `fatal`, and **stays up in that state**. It never serves
application traffic.

Readiness that never passes is how an orchestrator fails a rollout and
rolls back. It is strictly more debuggable than the alternative.

**Exiting is for one situation: the process cannot serve its own health
endpoints**. It could not bind its port, or the runtime itself is failing.
Everything else is a state to *report*, at length, on an endpoint that
answers. That includes bad config, an unreachable database, an expired
credential, and a missing optional service.

**A failure to bind exits immediately and non-zero, and that is correct
even though it crashloops**. The two crashloops are not the same failure
wearing one name. The difference is what makes one acceptable:

- **Deterministic and immediate**. A port that is taken is taken on every
  restart, at the same instant, with the same message. Restarting hides
  nothing and races nobody; the loop is just the same true statement
  repeated. This is fail-early, fail-often working as intended, and it is
  the *only* honest option. A process that cannot bind cannot report
  anything on an endpoint, because there is no endpoint.
- **Conditional and slow**. A process that exits because a database was
  unreachable restarts into a world that might have changed. It flaps, and
  produces a scrolling restart counter racing whoever is trying to read
  the logs. It converts a five-second diagnosis into archaeology, and
  everything above bans it.

A bind failure is the one case where nothing else will ever be readable, so
**the message carries the whole diagnosis**. That is a `fatal` line per
SC2 naming the address and port it tried, the underlying cause, and the
service. It says so plainly, in the `msg` field itself, not in a generic
"startup failed" with the useful part buried in a nested object. It is the
last thing the process writes, and it is on stdout. There every restart
puts another identical copy in front of whoever finally looks.

The word doing the work in the rule above is *cannot*. Exiting because a
dependency is down is not inability, it is a service declining to hold a
state it was built to hold.

## Decisions

- **`degraded` exists, and routing stays binary** (2026-08-31): this
  document first had a binary `ok`/`fail`. The argument was that a third
  value needs a third routing behaviour. It does not. The *status code*
  carries routing (200 or 503) and the *body* carries the truth. So a
  service tolerating a failed optional dependency reports `degraded` and
  keeps taking traffic. Without the distinction, "graceful degradation"
  has nowhere to be expressed and every failed dependency becomes an
  outage.
- **A dependency is never a startup gate** (2026-08-31): the service must
  survive losing a dependency at 3pm. Refusing to boot on it at 3am is
  therefore a second, worse implementation of the same error path. That
  one has no request to fail and nobody to tell. The exception is a
  startup migration, because that is a real operation against a real
  dependency rather than a reflexive check.
- **Misconfiguration blocks serving, never observability** (2026-08-31):
  an earlier draft had it exit before binding a port. That optimises for
  the wrong reader. A process that stays up reporting `fail` with the
  broken variables named can be curled, and its logs stay put. One that
  exits leaves a restart counter and a scrollback race.
- **Crashlooping is a defect, except when it is the only honest answer**
  (2026-08-31): a process that cannot bind has no endpoint to report on.
  So it exits non-zero and loops: deterministically, immediately, with an
  identical message every time, which hides nothing and races nobody. A
  process that exits because a dependency was down loops conditionally and
  slowly, flapping against whoever is reading the logs. The first is
  fail-early working; the second is the banned one. What separates them is
  whether restarting could produce a different answer.

## Out of scope, deliberately

**The error envelope is not here**. It belongs to the [service interfaces
standard](050-http.md) with the rest of the request/response contract
(RFC 9457, pagination, idempotency). An error shape is an API concern
rather than a service-lifecycle one. Splitting it across two documents is
how two answers to one question get born. The proposal that raised this
standard listed it; this is the scope decision, stated rather than silently
dropped.

Rate limiting and response headers belong to the [`085-security-baseline.md`](085-security-baseline.md) for the same reason.

## The artifacts

Per PC3, under [`contracts/service/`](../contracts/service/):

- **`health.schema.json`**: the `/healthz` and `/readyz` response shapes,
  including the check record and the provenance block.
- **`logline.schema.json`**: the one log line, `$ref`-ing the identifiers
  contract for its timestamp and the observability contract for its context
  block. Three contracts compose here rather than restating each other,
  which is the whole point of PC3's artifacts.
- **`corpus.json`**: validity cases for both schemas, plus lifecycle cases
  a live implementation must satisfy. Readiness `503`s when a dependency
  fails; startup fails naming every missing variable; `SIGTERM` flips
  readiness before draining.
