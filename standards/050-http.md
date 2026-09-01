# Service interfaces: protocol selection and HTTP conventions

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard from its
roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier each rule below
actually holds. Artifacts: [`contracts/http/`](../contracts/http/).

This document answers two questions in order: **which protocol** a given
interaction uses (HA1), and — for the default answer, HTTP — **what the
conventions are** (HA2 onward).

## Why this exists

Every product exposes an interface, and each one decided independently what
protocol to speak and then what its error shape, pagination scheme and
versioning habit would be. The cost is paid by whoever writes the second
client: a frontend that handles four error shapes, a retry that is safe
against one service and duplicates charges against another, a pagination
loop that silently skips rows when the collection changes underneath it —
and, before any of that, a WebSocket where a plain HTTP request would have
done, carrying its own auth scheme because it could not use the normal one.

Almost none of this needs inventing. RFC 9457 defines the error envelope,
OpenAPI describes the surface, and the HTTP specification already settled
retries and backpressure. Per PC2 this document is a **profile**: it pins
the choices those standards leave open, because "we use problem+json"
unpinned is four incompatible error shapes that all validate.

## The rules

### HA1. The protocol is chosen for the interaction, and HTTP is the default

**HTTP with JSON is the default, and every other choice needs a reason a
reviewer can hear.** Not because it is fastest — it is not — but because it
is the only option every consumer, proxy, load balancer, debugger and
support engineer already understands, and because the rest of the portfolio's
contracts are written against it: the error envelope, the id vocabulary,
trace propagation, readiness, the audit trail. Leaving HTTP means leaving
those and rebuilding them.

| Interaction | Protocol | Why, and what it costs |
|---|---|---|
| Request/response — any public, partner or browser-facing surface | **HTTP/REST + JSON** | The default. Universally consumable, `curl`-debuggable, no codegen for the consumer, and every portfolio contract already applies. |
| Request/response between internal services, high volume or strongly typed | **gRPC** | Binary protobuf, generated clients, real streaming. **Requires HTTP/2 end to end.** Costs: not browser-native (needs a proxy and grpc-web), opaque on the wire to anyone debugging, and a schema pipeline to own. Admitted **service-to-service only**. |
| Server pushes to client, one direction | **SSE** | Plain HTTP: it inherits authentication, proxies, the error envelope, observability and automatic reconnection for free. **Requires HTTP/2 to survive contact with a real browser** (see below) **and OpenAPI 3.2 to be describable** (HA2). |
| Both ends push, low latency, genuinely conversational | **WebSocket** | Full duplex. Costs are large and listed below. |
| Fire-and-forget, durable, retried | **Not a synchronous protocol at all** — the [async messaging standard](000-platform.md#the-capability-roster)'s envelope. |

**HTTP/2 is not on that list because it is not an interface — but it is a
prerequisite for two things on it, and that is the part to get right.** You
do not design "an HTTP/2 API" the way you design a REST or a gRPC one: REST
over HTTP/2 is the same REST, and enabling the version changes no
application code. So one common move stays wrong — adopting gRPC "since we
are on HTTP/2 anyway" is a non-sequitur, because the transport does not
argue for the interface.

What that framing gets wrong, if left there, is that **the table above is
not all available over HTTP/1.1.** An HTTP/1.1 connection carries one
request and then one response; there is no working multiplexing (pipelining
is disabled everywhere it was implemented) and no full duplex. HTTP/2 adds
concurrent streams over one connection, server-initiated streams, and
bidirectional flow — capabilities, not tuning. Concretely:

- **gRPC requires HTTP/2.** Not as an optimisation: its streaming modes and
  its status trailers have nowhere to live in HTTP/1.1's exchange model.
  Choosing gRPC is choosing HTTP/2 whether anyone writes that down.
- **SSE requires HTTP/2 to be usable at all in a browser**, and this is the
  fact that makes the recommendation below practical rather than nostalgic.
  Over HTTP/1.1 each open event stream holds one of the browser's **six**
  connections *per domain, counted across every tab* — so a user with a few
  tabs open has starved the origin and the next ordinary `fetch` blocks
  behind an event stream. Over HTTP/2 the streams multiplex and the
  negotiated ceiling defaults to **100**;
  [MDN documents both numbers](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events).
  An SSE surface on HTTP/1.1 passes every local test and fails as soon as
  someone opens tabs.
- **Full duplex over plain HTTP** — a client streaming a request body while
  reading the response body — is not expressible in HTTP/1.1 at all. An
  interaction that genuinely needs it needs HTTP/2 or a WebSocket, and that
  requirement belongs in the reason a repository writes down.

The operational half of this is what actually bites: **HTTP/2 has to reach
the service, not just the edge.** A load balancer that terminates HTTP/2 and
forwards HTTP/1.1 on the internal hop breaks gRPC outright and silently
reimposes the six-connection cap on SSE — while every local test passes,
because the developer's browser spoke to the process directly. A repository
serving gRPC or SSE states in its **Conventions** where HTTP/2 is terminated
and confirms the backend hop carries it; inside a cluster the usual answer
is h2c.

HTTP/3 changes the transport again — QUIC, and no TCP head-of-line blocking
under a multiplexed connection — with the same HTTP semantics above it. It
is an edge capability to enable where the edge supports it, and unlike
HTTP/2 it is not a prerequisite for anything in the table.

**SSE before WebSocket, unless the client genuinely needs to push.** This is
the choice most often made wrongly, and in one direction: a WebSocket opened
for a live feed that only ever flows server-to-client. What that discards is
not small. A WebSocket has no status codes, so the error envelope (HA3) does
not apply and each application invents its own. It cannot carry an
`Authorization` header from a browser, so authentication becomes a
bespoke first-message handshake or a token in a query string — in the URL,
in the access logs. It is stateful, so horizontal scaling needs sticky
sessions or a pub/sub backplane. It defeats ordinary HTTP caching and
observability. Reconnection, which SSE gives you in the browser for free,
becomes yours to write and yours to get wrong.

None of that means never. It means a WebSocket is justified by the client
needing to *send* at low latency — a collaborative editor, a terminal, a
live cursor — and not by the server needing to send, which SSE already does.
A repository choosing one states the reason in its **Conventions**.

**Leaving HTTP never leaves the standards.** Whatever the protocol, the
portfolio's contracts still bind: trace context propagates
([`040-observability.md`](040-observability.md) OC1) — in gRPC metadata, in the
WebSocket message envelope, in the SSE request that opened the stream;
identifiers keep their formats ([`020-identifiers.md`](020-identifiers.md));
failures still state a reason rather than the fact of failure
([`030-service.md`](030-service.md) SC2); and a protocol without a native error
envelope defines one in its message schema rather than doing without.

### HA2. The API is described by a committed OpenAPI document

Every HTTP API carries an OpenAPI document, committed in the repository at a
stable path, describing every endpoint it serves. **3.1 is the floor, and a
service that serves SSE uses 3.2.**

3.1 rather than 3.0 for one concrete reason: 3.1's schema dialect *is*
JSON Schema 2020-12, the dialect every contract under
[`contracts/`](../contracts/) already speaks. That makes the portfolio's shared
`$defs` — a timestamp, a public id, a money value — referenceable from an
API description instead of transcribed into it, and a transcribed schema is
a copy that drifts.

**3.2 where there is a stream, for the same reason HA1 requires HTTP/2
there.** [OpenAPI 3.2](https://spec.openapis.org/oas/v3.2.0.html) (September
2025) added sequential media types and `itemSchema`, which is what lets a
description say *what each event on a `text/event-stream` looks like*. In
3.1 the best available description of an SSE endpoint is that it returns a
string, so the events — the actual payload, the part a client must parse —
go undescribed and ungenerated. A standard that recommends SSE in HA1 and
then pins the one version that cannot describe it would be recommending an
undocumented surface.

3.2 is not the blanket default because tooling has not uniformly caught up:
generator support across the ecosystem is still maturing, and a
non-streaming API gains nothing from it that is worth that risk. Tying the
version to the capability that needs it keeps the conservative default
without leaving a hole. A repository already on 3.2 everywhere is
conformant and need not justify it; 3.1 is a floor, not a ceiling.

Whether the document is handwritten or generated from code is a per-stack
choice and belongs in a repository's **Conventions**. What is not a choice:
it exists, it is committed, and **it matches the running service**. A
description that has drifted from its implementation is worse than none,
because clients are generated from it.

### HA3. Errors are RFC 9457 problem+json, profiled

Every error response — every one, from every endpoint — is
`application/problem+json` per [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457),
in the shape
[`contracts/http/problem.schema.json`](../contracts/http/problem.schema.json)
defines. The profile:

| Member | Required | What this standard pins |
|---|---|---|
| `type` | yes | A **stable URI identifying the error class**, `https://errors.aurumalpha.dev/<service>/<slug>`. RFC 9457 does not require it to resolve, and this standard does not host it today; the form is pinned so it *can* become dereferenceable without changing any client. `about:blank` is admitted only where the status code alone is the whole story. |
| `title` | yes | Stable, human-readable, the same string for every instance of that `type` — it names the class, so it groups. |
| `status` | yes | The HTTP status code, repeated in the body so a logged or forwarded envelope stays complete. |
| `detail` | yes | **This instance's specific reason**, following the reason-giving rule of [`030-service.md`](030-service.md) SC2: which value, which rule, which limit. Never the bare class again, never a stack trace. |
| `instance` | where one exists | A URI for the specific occurrence — typically the request path. |
| `request_id` | yes | Extension member, the `request_id` from [`040-observability.md`](040-observability.md) OC2. It is what turns a screenshot of an error into a log query. |
| `errors` | for validation failures | Extension array, one entry per rejected field: `field`, `rule`, `message`. A client that must highlight three bad inputs cannot do it from prose. |

**`type` is a contract, `detail` is a courtesy.** Clients branch on `type`
and status; humans read `detail`. A service that changes `detail` wording is
free to; one that changes what `type` means has broken its clients, and per
PC6 that is a new `type`, not an edited one.

The same redaction rule as SC2 applies with more force, because this
envelope crosses the trust boundary: never a secret, never a credential,
never a record's contents, never an internal hostname, path or stack. **What
failed and why is almost never the sensitive part.**

### HA4. Collections are paginated by opaque cursor

A collection endpoint returns `{ "data": [...], "next_cursor": string|null }`
and accepts `?limit=&cursor=`. The cursor is **opaque** — it is generated by
the server, echoed by the client, and never parsed by anyone, exactly as an
identifier is opaque under [`020-identifiers.md`](020-identifiers.md) IP3. A client
that decodes a cursor has coupled itself to a query plan.

`next_cursor: null` means the end, unambiguously. An empty `data` array with
a non-null cursor is legal and does not mean the end — filtering can empty a
page.

Every endpoint states its default and maximum `limit` in its OpenAPI
document, and clamps rather than erroring on an over-large one.

**Offset pagination is not admitted for collections that change.** `?page=3`
over a list that is being written to silently skips rows and duplicates
others as items shift between pages, and the failure is invisible: the
client receives a well-formed page of wrong data. Where a collection is
genuinely static — an immutable export, a fixed report — a repository may
use offsets and says so in its **Conventions**.

### HA5. One major version in the path, and change is additive until it cannot be

The major version is a path prefix: `/v1/…`. It appears from the first
endpoint, because retrofitting a version onto an unversioned API means
breaking every client once to gain the ability to never break them again.

Change is **additive by default**, per PC6: new optional fields, new
endpoints, new enum members a client can ignore. None of those bump the
version. A removed field, a narrowed type, a changed meaning or a new
required request field is breaking, and breaking means `/v2/` alongside
`/v1/` — with the deprecation window stated in the API's documentation
before `/v1/` stops answering.

Minor and patch versions do not appear in the path. The build's version is
already reported by [`030-service.md`](030-service.md) SC5, which is where "exactly
which code answered me" belongs.

### HA6. Mutating endpoints accept an idempotency key

Every non-idempotent endpoint — `POST` that creates, anything that charges,
sends, or dispatches — accepts an **`Idempotency-Key`** request header whose
value is a client-generated identifier in an admitted format
([`020-identifiers.md`](020-identifiers.md) IP2).

The server stores the key against the outcome for a **stated window**, named
in the endpoint's documentation. A repeat within that window **returns the
original response** — the same status, the same body — without performing
the work again. A repeat with the same key but a *different* request body is
a client defect and answers `422` with a `type` naming the conflict, because
silently serving the first response to a second, different request is worse
than refusing.

This exists so that HA7's retries are safe by contract rather than by luck.
A network timeout tells a client nothing about whether the work happened;
without a key its only options are to risk a double charge or to abandon a
request that may well have succeeded.

### HA7. Backpressure is stated, and retries are bounded

A service under load answers **`429` with `Retry-After`**, always both: a
`429` without `Retry-After` tells a client to back off by an amount it must
guess, and every client guesses differently and wrongly. A service that is
temporarily unable answers `503`, with `Retry-After` where the duration is
knowable.

Clients retry **only** requests that are idempotent by method (`GET`,
`PUT`, `DELETE`) or carry an idempotency key (HA6), with **exponential
backoff plus jitter**, a stated maximum attempt count, and an overall
deadline. Jitter is not decoration: without it a hundred clients that failed
together retry together, and the retry storm is the second outage.

`Retry-After`, where present, wins over the client's own backoff
calculation. A server that says four seconds knows something the client's
exponent does not.

### HA8. Wire field names are snake_case, and the rule stops at the wire

Every field name in a JSON request or response body, and every query
parameter name, is `snake_case`. Headers keep HTTP's own convention
(`Idempotency-Key`, `Retry-After`), because a header is governed by the
surrounding standard rather than by this one.

This is the house convention holding, not a new choice: the
[observability standard](040-observability.md) already fixes snake_case for the
context vocabulary, and log lines, audit events, job envelopes and SQL
identifiers are all snake_case already. One spelling therefore covers a
service's database, its log lines, its events and its API, and it is
deviating on this one surface that would need the argument.

**The rule binds the bytes, never the identifier in source code.** This is
the half that gets misread, so it is stated rather than implied, and it
generalises the wire-names-not-code-names paragraph the observability
standard already applies to telemetry fields:

- **A Go server writes `CreatedAt string` with `json:"created_at"`**, and
  `UserID` with `json:"user_id"` — the field follows
  [go.dev's initialisms rule](https://go.dev/wiki/CodeReviewComments#initialisms),
  the tag follows this contract. Renaming a Go field to `created_at` to
  match the wire is the wrong fix and produces un-idiomatic Go for no gain.
  Note that the tag is mandatory either way: Go marshals `CreatedAt` as
  `"CreatedAt"` untagged, so `json:"created_at"` and `json:"createdAt"`
  are identical work, and snake_case additionally makes a service's API
  agree with its own columns.
- **A PHP or TypeScript server maps at its serialization boundary** — a
  DTO, a resource class, a serializer — for the same reason and with the
  same freedom in its own code.
- **A TypeScript client generates its types from the OpenAPI document**
  (HA2), so nobody hand-writes `created_at` anywhere. A repository that
  wants camelCase in its own code generates that mapping from the same
  source, in one place, rather than transcribing a parallel type by hand.
  A hand-maintained interface mirroring the API is the drift HA2 exists to
  prevent, and it is not made acceptable by casing.

In-code naming is out of scope for this standard entirely, and follows the
language authors' own guides per the [platform contract](000-platform.md). A
repository does not record a **Conventions** entry to use idiomatic naming
in its own source; that is the default everywhere.

## The artifacts

Per PC3, under [`contracts/http/`](../contracts/http/):

- **`problem.schema.json`** — the profiled RFC 9457 envelope, `$ref`-ing the
  observability contract for `request_id`.
- **`pagination.schema.json`** — the collection envelope and cursor.
- **`corpus.json`** — validity cases for both, plus behavioural cases a live
  service must satisfy: the same idempotency key replays rather than
  repeats, a `429` carries `Retry-After`, an unknown route answers
  problem+json rather than a framework's HTML error page.

## Enforcement

Registered in [`999-enforcement.md`](999-enforcement.md) under "HTTP API standard",
every rule review-only today. The mechanisms, in the order they become
cheap:

- **The OpenAPI document exists and lints** — a static check, the cheapest
  in this standard.
- **The error envelope is real** — `job-image-starts` already talks to a
  running service, so requesting a route that cannot exist and asserting
  problem+json against the schema is one more poll. That single case catches
  the most common failure in the portfolio today: a framework's default HTML
  error page escaping to clients from the one path nobody wrote a handler
  for.
- **Idempotency and backpressure** need a live harness driving two requests
  and reading headers — the same `job-contract-conformance` the other
  capability standards wait on.

What no checker will prove: that the OpenAPI document still describes the
service. That is why HA2 states it as a rule with a reason rather than
implying the gate covers it — the honest gate is a repository's own
contract tests, and the review question is whether they exist.

## Decisions

- **snake_case in request and response bodies** (2026-08-31): this is the
  house convention holding, not a fresh choice. Log lines, audit events,
  job envelopes and the id vocabulary are already snake_case, and SQL
  identifiers case-fold toward it, so one spelling covers the database, the
  log line, the event and the API — and deviating on this one surface is
  what would need the justification.

  The cost lands on the frontend, not the backends, which is the opposite
  of how it first reads. Go marshals `CreatedAt` as `"CreatedAt"` unless it
  is tagged, so `json:"created_at"` and `json:"createdAt"` are the same
  work — the tag is mandatory either way — while snake_case additionally
  makes a service's two boundaries agree with each other, since its columns
  are already snake_case. camelCase would introduce a database-to-API
  mismatch that does not currently exist.

  What the frontend pays is smaller than it looks, because HA2 requires a
  committed OpenAPI document: a TypeScript client **generates** its types
  rather than hand-writing them, so nobody types `created_at`, and a
  repository wanting camelCase in its own code generates that mapping from
  the same source. In-code naming is untouched either way, per the platform
  contract.
- **OpenAPI 3.1 as the floor, 3.2 where there is a stream** (2026-08-31):
  3.1's dialect is JSON Schema 2020-12, so the existing `$defs` under `contracts/` are
  referenceable rather than transcribed. The first draft stopped there and
  pinned 3.1 outright, which was already eleven months stale — 3.2 shipped
  in September 2025 — and, worse, incoherent: HA1 recommends SSE and 3.1
  cannot describe an event stream's payload. Tying the version to the
  capability rather than raising the floor for everyone keeps the
  conservative default while closing that hole, and it is the same shape as
  HA1's HTTP/2 requirement. **OpenAPI 4.0 is not a reason to wait**: the
  Moonwalk group has no release date and is spending 2026 on LLM clients.
- **Cursor, not offset** (2026-08-31): offset pagination over a changing
  collection returns well-formed wrong answers, which is the worst failure
  mode available — no error, no signal, missing rows.
- **`Idempotency-Key` as a header, not a body field** (2026-08-31): it is
  metadata about the request rather than part of it, and a header survives
  a body the server chooses not to parse.
- **HTTP/2 is stated as a requirement, not left to the edge** (2026-08-31):
  the first draft of HA1 called HTTP/2 purely a transport detail that
  decides nothing. That is half right and the wrong half to lead with. It
  does not decide the interface, but it is a hard prerequisite for gRPC and
  the difference between SSE working and SSE exhausting a browser's
  six-connection budget — so the rule names which interactions require it,
  and requires the backend hop to carry it rather than assuming the edge is
  the whole story.
