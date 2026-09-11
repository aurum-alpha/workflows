# Service interfaces: protocol selection and HTTP conventions

## Why this exists

Every product exposes an interface, and without a standard each decides
alone its protocol, its error shape, its pagination scheme and its
versioning habit. Whoever writes the second client pays: one error shape per
service, and a retry that is safe against one service and duplicates charges
against another. RFC 9457 is profiled for the error envelope and OpenAPI for
the description; this document pins the choices those standards leave open.

## The rules

### HA1. The protocol is chosen for the interaction, and HTTP is the default

**HTTP with JSON is the default, and every other choice needs a reason a
reviewer can hear**. Not because it is fastest; it is not. HTTP is the only
option every consumer, proxy, load balancer, debugger and support engineer
already understands. And the rest of the shared contracts are written
against it: the error envelope, the id vocabulary, trace propagation,
readiness, the audit trail. Leaving HTTP means leaving those and rebuilding
them.

| Interaction | Protocol | Why, and what it costs |
|---|---|---|
| Request/response: any public, partner or browser-facing surface | **HTTP/REST + JSON** | The default. Universally consumable, `curl`-debuggable, no codegen for the consumer, and every shared contract already applies. |
| Request/response between internal services, high volume or strongly typed | **gRPC** | Binary protobuf, generated clients, real streaming. **Requires HTTP/2 end to end.** Costs: not browser-native (needs a proxy and grpc-web), opaque on the wire to anyone debugging, and a schema pipeline to own. Admitted **service-to-service only**. |
| Server pushes to client, one direction | **SSE** | Plain HTTP: it inherits authentication, proxies, the error envelope, observability and automatic reconnection for free. **Requires HTTP/2 to survive contact with a real browser** (see below) **and OpenAPI 3.2 to be describable** (HA2). |
| Both ends push, low latency, genuinely conversational | **WebSocket** | Full duplex. Costs are large and listed below. |
| Fire-and-forget, durable, retried | **Not a synchronous protocol at all**: the [messaging standard](055-messaging.md)'s envelope. |

**HTTP/2 is a prerequisite for gRPC and SSE, not an interface**.

- **gRPC requires HTTP/2.** Not as an optimisation: its streaming modes and
  its status trailers have nowhere to live in HTTP/1.1's exchange model.
  Choosing gRPC is choosing HTTP/2 whether anyone writes that down.
- **SSE requires HTTP/2 to be usable at all in a browser**. Over HTTP/1.1
  each open event stream holds one of the browser's **six** connections
  *per domain, counted across every tab*. So a user with a few tabs open
  has starved the origin, and the next ordinary `fetch` blocks behind an
  event stream. Over HTTP/2 the streams multiplex and the negotiated
  ceiling defaults to **100**;
  [MDN documents both numbers](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events).
- **Full duplex over plain HTTP**, a client streaming a request body while
  reading the response body, is not expressible in HTTP/1.1 at all. An
  interaction that genuinely needs it needs HTTP/2 or a WebSocket, and that
  requirement belongs in the reason a repository writes down.

**HTTP/2 has to reach the service, not just the edge**. A load balancer that
terminates HTTP/2 and forwards HTTP/1.1 on the internal hop breaks gRPC
outright. It also silently reimposes the six-connection cap on SSE, while
every local test passes, because the developer's browser spoke to the
process directly. A repository serving gRPC or SSE states in its
**Conventions** where HTTP/2 is terminated. It also confirms the backend hop
carries it; inside a cluster the usual answer is h2c.

**SSE before WebSocket, unless the client genuinely needs to push**.

A WebSocket has no status codes, so the error envelope (HA3) does not apply
and each application invents its own. It cannot carry an `Authorization`
header from a browser. So authentication becomes a bespoke first-message
handshake or a token in a query string, which means in the URL and in the
access logs. It is stateful, so horizontal scaling needs sticky sessions or
a pub/sub backplane. It defeats ordinary HTTP caching and observability.
Reconnection, which SSE gives you in the browser for free, becomes yours to
write and yours to get wrong.

None of that means never. It means a WebSocket is justified by the client
needing to *send* at low latency: a collaborative editor, a terminal, a
live cursor. It is not justified by the server needing to send, which SSE
already does. A repository choosing one states the reason in its
**Conventions**.

**Leaving HTTP never leaves the standards.** Whatever the protocol, the
shared contracts still bind. Trace context propagates
([`040-observability.md`](040-observability.md) OC1): in gRPC metadata, in
the WebSocket message envelope, in the SSE request that opened the stream.
Identifiers keep their formats ([`020-identifiers.md`](020-identifiers.md)).
Failures still state a reason rather than the fact of failure
([`030-service.md`](030-service.md) SC2). And a protocol without a native
error envelope defines one in its message schema rather than doing without.

### HA2. The API is described by a committed OpenAPI document

Every HTTP API carries an OpenAPI document, committed in the repository at a
stable path, describing every endpoint it serves. **3.1 is the floor, and a
service that serves SSE uses 3.2.**

3.1 rather than 3.0 for one concrete reason: 3.1's schema dialect *is*
JSON Schema 2020-12, the dialect every contract under
[`contracts/`](../contracts/) already speaks. That makes the shared
`$defs` (a timestamp, a public id, a money value) referenceable from
an API description instead of transcribed into it. A transcribed schema is
a copy that drifts.

**3.2 where there is a stream, for the same reason HA1 requires HTTP/2
there.** [OpenAPI 3.2](https://spec.openapis.org/oas/v3.2.0.html)
added sequential media types and `itemSchema`. That is
what lets a description say *what each event on a `text/event-stream`
looks like*. In 3.1 the best available description of an SSE endpoint is
that it returns a string. So the events, the actual payload, the part a
client must parse, go undescribed and ungenerated.

3.2 is not the blanket default because tooling has not uniformly caught up.
Generator support across the ecosystem is still maturing, and a
non-streaming API gains nothing from it that is worth that risk. Tying the
version to the capability that needs it keeps the conservative default
without leaving a hole. 3.1 is a floor, not a ceiling.

Whether the document is handwritten or generated from code is a per-stack
choice and belongs in a repository's **Conventions**. What is not a choice:
it exists, it is committed, and **it matches the running service**. A
description that has drifted from its implementation is worse than none,
because clients are generated from it.

### HA3. Errors are RFC 9457 problem+json, profiled

Every error response, every one, from every endpoint, is
`application/problem+json` per [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457),
in the shape
[`contracts/http/problem.schema.json`](../contracts/http/problem.schema.json)
defines. The profile:

| Member | Required | What this standard pins |
|---|---|---|
| `type` | yes | A **stable URI identifying the error class**, `https://errors.aurumalpha.dev/<service>/<slug>`. RFC 9457 does not require it to resolve, and this standard does not host it today; the form is pinned so it *can* become dereferenceable without changing any client. `about:blank` is admitted only where the status code alone is the whole story. |
| `title` | yes | Stable, human-readable, the same string for every instance of that `type`. It names the class, so it groups. |
| `status` | yes | The HTTP status code, repeated in the body so a logged or forwarded envelope stays complete. |
| `detail` | yes | **This instance's specific reason**, following the reason-giving rule of [`030-service.md`](030-service.md) SC2: which value, which rule, which limit. Never the bare class again, never a stack trace. |
| `instance` | where one exists | A URI for the specific occurrence: typically the request path. |
| `request_id` | yes | Extension member, the `request_id` from [`040-observability.md`](040-observability.md) OC2. It is what turns a screenshot of an error into a log query. |
| `errors` | for validation failures | Extension array, one entry per rejected field: `field`, `rule`, `message`. A client that must highlight three bad inputs cannot do it from prose. |

**`type` is a contract, `detail` is a courtesy.** Clients branch on `type`
and status; humans read `detail`. A service that changes `detail` wording
is free to. One that changes what `type` means has broken its clients, and
per PC6 that is a new `type`, not an edited one.

**A slug can be pinned by a standard** where clients of several products
branch on one class, so that each does not invent a spelling. The first is
`entitlement-required`, a `403` whose `errors` name the capability or metric
the tenant's plan lacks, under the [billing standard](075-billing.md) BL4.

SC2's redaction rule applies.

### HA4. Collections are paginated by opaque cursor

A collection endpoint returns `{ "data": [...], "next_cursor": string|null }`
and accepts `?limit=&cursor=`. The cursor is **opaque**: the server
generates it, the client echoes it, and nobody parses it, as an identifier
is opaque under [`020-identifiers.md`](020-identifiers.md) IP3. A client
that decodes a cursor has coupled itself to a query plan.

`next_cursor: null` means the end, unambiguously. An empty `data` array
with a non-null cursor is legal and does not mean the end. Filtering can
empty a page.

Every endpoint states its default and maximum `limit` in its OpenAPI
document, and clamps rather than erroring on an over-large one.

**Offset pagination is not admitted for collections that change**.
`?page=3` over a list that is being written to silently skips rows and
duplicates others as items shift between pages. The failure is invisible:
the client receives a well-formed page of wrong data. Where a collection is
genuinely static, an immutable export or a fixed report, a repository can
use offsets and says so in its **Conventions**.

### HA5. One major version in the path, and change is additive until it cannot be

The major version is a path prefix: `/v1/…`. It appears from the first
endpoint. Retrofitting a version onto an unversioned API means breaking
every client once to gain the ability to never break them again.

Change is **additive by default**, per PC6: new optional fields, new
endpoints, new enum members a client can ignore. None of those bump the
version. A removed field, a narrowed type, a changed meaning or a new
required request field is breaking. Breaking means `/v2/` alongside
`/v1/`, with the deprecation window stated in the API's documentation
before `/v1/` stops answering.

Minor and patch versions do not appear in the path. The build's version is
already reported by [`030-service.md`](030-service.md) SC5, which is where
"exactly which code answered me" belongs.

### HA6. Mutating endpoints accept an idempotency key

Every non-idempotent endpoint accepts an **`Idempotency-Key`** request
header: a `POST` that creates, anything that charges, sends, or dispatches.
The header's value is a client-generated identifier in an admitted format
([`020-identifiers.md`](020-identifiers.md) IP2). It is a header rather
than a body field: it is metadata about the request, and a header survives
a body the server never parses.

The server stores the key against the outcome for a **stated window**,
named in the endpoint's documentation. A repeat within that window
**returns the original response**, the same status and the same body,
without performing the work again. A repeat with the same key but a
*different* request body is a client defect and answers `422` with a `type`
naming the conflict. Silently serving the first response to a second,
different request is worse than refusing.

This exists so that HA7's retries are safe by contract rather than by luck.
A network timeout tells a client nothing about whether the work happened.
Without a key its only options are to risk a double charge or to abandon a
request that could well have succeeded.

### HA7. Backpressure is stated, and retries are bounded

A service under load answers **`429` with `Retry-After`**, always both. A
`429` without `Retry-After` tells a client to back off by an amount it must
guess, and every client guesses differently and wrongly. A service that is
temporarily unable answers `503`, with `Retry-After` where the duration is
knowable.

Clients retry **only** requests that are idempotent by method (`GET`,
`PUT`, `DELETE`) or carry an idempotency key (HA6). They retry with
**exponential backoff plus jitter**, a stated maximum attempt count, and an
overall deadline. Jitter is not decoration: without it a hundred clients
that failed together retry together, and the retry storm is the second
outage.

`Retry-After`, where present, wins over the client's own backoff
calculation. A server that says four seconds knows something the client's
exponent does not.

### HA8. Wire field names are snake_case, and the rule stops at the wire

Every field name in a JSON request or response body, and every query
parameter name, is `snake_case`. Headers keep HTTP's own convention
(`Idempotency-Key`, `Retry-After`), because the surrounding standard
governs a header rather than this one.

This is the house convention holding, not a new choice. The
[observability standard](040-observability.md) already fixes snake_case for
the context vocabulary. Log lines, audit events, job envelopes and SQL
identifiers are all snake_case already. One spelling therefore covers a
service's database, its log lines, its events and its API. Deviating on
this one surface is what would need the argument.

**The rule binds the bytes, never the identifier in source code**. A Go
server writes `CreatedAt string` with `json:"created_at"`: the field
follows
[go.dev's initialisms rule](https://go.dev/wiki/CodeReviewComments#initialisms),
and the tag follows this contract. A PHP or TypeScript server maps at its
serialization boundary the same way. A TypeScript client generates its types
from the OpenAPI document (HA2), so nobody hand-writes `created_at`. The
cost of the convention lands on the frontend, and generation removes it. A
repository wanting camelCase in its own code generates that mapping from the
same source rather than transcribing a parallel type by hand.

## The artifacts

Per PC3, under [`contracts/http/`](../contracts/http/):

- **`problem.schema.json`**: the profiled RFC 9457 envelope, `$ref`-ing the
  observability contract for `request_id`.
- **`pagination.schema.json`**: the collection envelope and cursor.
- **`corpus.json`**: validity cases for both, plus behavioural cases a live
  service must satisfy. The same idempotency key replays rather than
  repeats. A `429` carries `Retry-After`. An unknown route answers
  problem+json rather than a framework's HTML error page.
