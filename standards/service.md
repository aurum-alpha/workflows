# The service contract

One of the Aurum Alpha engineering standards, written under the platform
contract ([`platform.md`](platform.md)) — a per-capability standard from its
roster. Read [`enforcement.md`](enforcement.md) for the tier each rule below
actually holds. Artifacts: [`contracts/service/`](../contracts/service/).

## Why this exists

The fleet standardizes how a service is built, tested, packaged and shipped.
It said nothing about what the running thing must **expose**, so every
product answered the same operational questions independently, and several
answered them by not answering. Across the six TypeScript SaaS products at
the time this was written: no health endpoint anywhere, three different
logging answers (a library in two, a hand-rolled logger in three, nothing in
one), and rate limiting in two.

The health endpoint is the one that pays immediately. `job-image-starts`
exists to prove a built image actually runs, and with no endpoint to hit,
the strongest claim it can make is that the process did not exit within the
timeout. **A service that starts, fails to reach its database, and sits
there answering nothing passes that check today.** Giving every service a
readiness endpoint turns a shared job the fleet already runs from a liveness
guess into a real gate — no new job, no new infrastructure.

Most of what follows is [twelve-factor](https://12factor.net/) applied to
this fleet, and each rule cites the factor it rests on. What this document
adds is the part twelve-factor deliberately leaves open: the actual paths,
field names and response shapes, without which six conformant services are
still six different services to operate.

## The rules

### SC1. Two endpoints, fixed paths, fixed shapes

Every service exposes both, and they answer different questions:

| Path | Question | Checks dependencies | Failure means |
|---|---|---|---|
| `/healthz` | Is this process alive? | **No** | Restart me |
| `/readyz` | Can this process serve traffic? | **Yes** | Stop routing to me |

Conflating them is the classic operational error: a readiness check wired to
the restart probe turns one slow database into an infinite restart loop of
otherwise healthy processes, and a liveness check that talks to a database
reports the database's health as the process's.

Both are **unauthenticated, never cached** (`Cache-Control: no-store`), and
respond `application/json` in the shape
[`contracts/service/health.schema.json`](../contracts/service/health.schema.json)
defines. `/healthz` returns `200` whenever the process is alive. `/readyz`
returns `200` when every dependency check passes and **`503` when any
fails** — the status code is the contract, because that is what a load
balancer reads; the body explains, and is what a human reads.

Each readiness check names the dependency it probed, its own outcome, and
how long it took. A readiness endpoint that returns `{"status":"ok"}` while
checking nothing is worse than no endpoint, because it converts an unknown
into a wrong answer.

### SC2. One structured log line, to stdout

Logs go to stdout as an event stream, per
[factor XI](https://12factor.net/logs): the application never routes,
rotates, or stores its own logs, because that is the execution
environment's job. This rule is inherited, not invented.

What the fleet pins is the line itself: **one JSON object per line**,
carrying `ts` (an instant per [`identifiers.md`](identifiers.md) IP4),
`level`, `msg`, `service`, and — whenever request context exists — the
context block from [`observability.md`](observability.md) OC2 and OC4.
Schema:
[`contracts/service/logline.schema.json`](../contracts/service/logline.schema.json).

Levels are the five of `debug`, `info`, `warn`, `error`, `fatal`, and the
threshold comes from configuration (SC3), never from code that detects its
environment. Multi-line output — a stack trace, a pretty-printed object —
is a field within the one JSON object, never a second line: a log pipeline
splits on newlines, so a stack trace printed raw becomes forty unattributed
lines that no query will ever join back together.

A human-readable renderer for local development is fine, and is a rendering
of the same records, chosen by configuration.

### SC3. Configuration comes from the environment, and absence is fatal

Config lives in environment variables, per
[factor III](https://12factor.net/config). The fleet's additions:

- **Names are `SCREAMING_SNAKE_CASE`**, and describe the thing rather than
  its consumer: `DATABASE_URL`, `OTEL_EXPORTER_OTLP_ENDPOINT`.
- **A required variable has no default.** A service missing one **fails at
  startup**, before binding a port, and its message names **every** missing
  variable at once — not the first one, because discovering a missing
  configuration one restart at a time is how a ten-minute deploy becomes an
  hour.
- **An optional variable's default is the safe value**, and the value is
  logged at startup so the running configuration is knowable from the logs.
- **No environment detection in code.** Nothing branches on `NODE_ENV`,
  a hostname, the presence of a Docker socket, or whether a path exists.
  Differences between deploys are *values*, not code paths, which is what
  makes [factor X](https://12factor.net/dev-prod-parity) parity real: the
  code that ran in staging is byte-identical to the code in production, and
  only its inputs differed. A service that behaves differently because it
  guessed where it was running has an untestable branch in it.

Secrets arrive the same way and are governed by the [secrets
standard](platform.md#the-capability-roster); nothing here permits logging
one.

### SC4. SIGTERM means drain

On `SIGTERM`, in order: **flip readiness to failing**, stop accepting new
work, let in-flight work finish, close pools and connections, exit `0`.
Per [factor IX](https://12factor.net/disposability), a process that dies
badly is a process that cannot be deployed safely.

The order is the rule. Flipping readiness *first* is what makes a rolling
deploy non-lossy: the load balancer stops sending new requests while the
process is still able to finish the ones it has. Exiting immediately on
`SIGTERM` — the default in most runtimes — drops every in-flight request,
and does so silently, which is why this is stated rather than assumed.

The drain deadline is configuration with a stated default, and it is shorter
than the orchestrator's kill timeout. A service that has not finished
draining by its deadline exits anyway and **logs what it abandoned**: work
lost quietly is work nobody reconciles.

### SC5. The running service says which build it is

CI Principle 13 already requires the commit and build timestamp baked into
every artifact. Nothing required the running service to *tell* you which
one it is, so during an incident the question "is the fix actually
deployed?" was answered by inference.

Every service, at startup, emits **one log line carrying its service name,
version, commit SHA and build timestamp**, and reports the same values in
the `/healthz` body. Two places on purpose: the log line is unconditional
and is what CI reads, so the assertion does not depend on how a repository
chooses to expose an endpoint; the endpoint is what a human hits at three
in the morning.

Exposing a commit SHA on an unauthenticated endpoint is a deliberate, small
disclosure: it tells an unauthenticated reader exactly which published
vulnerabilities to try. It is accepted here because incident response needs
it more than an attacker does, and because the alternative — provenance
only in logs — puts it behind exactly the access an incident responder may
be waiting on. Where a repository's threat model disagrees, the [security
baseline standard](platform.md#the-capability-roster) governs endpoint
exposure, and the startup log line still satisfies this rule.

## Out of scope, deliberately

**The error envelope is not here.** It belongs to the [HTTP API
standard](platform.md#the-capability-roster) with the rest of the
request/response contract (RFC 9457, pagination, idempotency), because an
error shape is an API concern rather than a service-lifecycle one, and
splitting it across two documents is how two answers to one question get
born. The proposal that raised this standard listed it; this is the
scope decision, stated rather than silently dropped.

Rate limiting and response headers belong to the [security baseline
standard](platform.md#the-capability-roster) for the same reason.

## The artifacts

Per PC3, under [`contracts/service/`](../contracts/service/):

- **`health.schema.json`** — the `/healthz` and `/readyz` response shapes,
  including the check record and the provenance block.
- **`logline.schema.json`** — the one log line, `$ref`-ing the identifiers
  contract for its timestamp and the observability contract for its context
  block. Three contracts compose here rather than restating each other,
  which is the whole point of PC3's artifacts.
- **`corpus.json`** — validity cases for both schemas, plus lifecycle cases
  a live implementation must satisfy: readiness `503`s when a dependency
  fails, startup fails naming every missing variable, `SIGTERM` flips
  readiness before draining.

## Enforcement

Registered in [`enforcement.md`](enforcement.md) under "Service standard",
every rule review-only today. The split that matters, and the reason this
standard is the strongest promotion candidate in the ledger:

- **Static** — a proposed `check-service-contract` asserts the endpoints are
  registered and required variables are declared. Cheap, runs beside the
  existing checkers, catches the common regression of someone deleting a
  route.
- **Live** — `job-image-starts` **already accepts an `http` probe** and
  already reads startup output. Pointing it at `/readyz`, asserting the
  response validates against the schema, and asserting the provenance line
  appears is an extension of a job every repository already calls, gated
  per-repository as each adopts the endpoint. No flag day.

That live check is the one that matters, because it exercises the running
artifact rather than the source that claims to produce it — and it upgrades
the fleet's existing "the process did not exit" claim into "the service came
up, reached its dependencies, and said what it was."
