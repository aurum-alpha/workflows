# Async messaging: the envelope, delivery, and webhooks

## Why this exists

Every product eventually has work that does not belong inside a request. A
cleanup runs after the response has gone, and a call to an upstream system
must not hold a user waiting. A notification goes out, and a payment
provider sends a webhook when a charge settles. Another service needs to
know about an event. The need arrives one case at a time. Each case has a
cheapest possible answer, and that answer is wrong in a way that does not
show until later:

- **A timer inside the request-serving process** is the cheapest way to run
  something periodically. It is wrong for reasons that hold regardless of
  who writes it. It runs once per replica, so scaling out multiplies the
  work or races it. It dies with the process, so every deploy interrupts
  it. It retries nothing, records nothing, and is invisible to every rule
  the [service standard](030-service.md) states about a running process. A
  timer does not drain on `SIGTERM`, and a health check does not know it
  exists.
- **Doing a webhook's work inline before responding** is the cheapest way
  to handle one. It converts every slow write into a provider timeout, and
  every provider timeout into a redelivery of work already half done.
  Verifying the signature and remembering the provider's event id are the
  right first two decisions. The third, respond and *then* work, is the one
  that is not obvious until a redelivery has doubled a charge.
- **A synchronous call between services** is the cheapest integration, and
  it makes each product's availability the product of its dependencies'.
  An event the consumer picks up when it is ready is the shape that does
  not.

None of those is a failure of judgment. Each is what happens when the
questions have not been asked. What is a message, and what identifies it?
How many times can a consumer see it? What does a producer owe it before
the transaction commits? How is work outside a request meant to run at
all?

Without answers, each product takes the cheapest option and pays for it
separately and later. This document answers the questions once, from the
properties the answers must have. Then the cheapest option and the right
one are the same option.

### The standard evaluated first, per PC2

An envelope is a boundary format. PC2 says a boundary format is adopted
from an existing standard where one suffices and invented only where none
does. **CloudEvents 1.0 suffices as the envelope**, and this document
adopts it as a profile. Sufficiency means three specific properties. An
invented envelope would otherwise have to state and defend each of them on
its own:

- **Identity is defined, and it is the deduplication key.** The
  specification requires that `source + id` be unique for each distinct
  event. That is exactly the property a consumer needs to recognise a
  redelivery. It arrives as a normative rule of the standard rather than a
  convention this document would have to argue for.
- **Trace context is a defined extension.** The distributed-tracing
  extension carries `traceparent` and `tracestate` as attributes, defined
  against W3C Trace Context. That is precisely what
  [`040-observability.md`](040-observability.md) OC1 requires the envelope
  to carry, met by a standard rather than by a field this document names.
- **The shape leaves nothing this document needs unaddressed**. It has a
  type, a time, a subject, a schema reference for the payload, and a
  content type. It has an extension mechanism with a defined grammar. An
  HTTP binding exists with a structured mode and a registered media type,
  which is what a webhook needs.

What CloudEvents deliberately does not cover is **delivery**. How many
times does a message arrive, and what does a consumer do about it? What
does a producer do so that a message is never lost and never emitted
without the change it describes? That is where this document invents, and
it invents only there.

**Standard Webhooks** is adopted for signing at the edge. Its contract is
three headers, HMAC-SHA256 over the id, timestamp and body, a versioned
signature value, and a replay window on the timestamp. That is line for
line what this document would otherwise have had to specify. A steering
committee drawn from the platforms that send the most webhooks maintains
it. Inventing the same thing under a different header name would be a
second answer to a solved question.

Two candidates were considered and set aside. **AsyncAPI** describes
message APIs the way OpenAPI describes HTTP ones. It is a description
format for channels and is complementary to, not a substitute for, an
envelope. The **CloudEvents HTTP Webhook** specification adds an
abuse-protection handshake for receivers. It is admitted where a receiver
implements it and not required. Most receivers do not, and the signing
contract already gives what the handshake is for.

## The rules

### AM1. A message is a CloudEvent, under this profile

Every message is a **CloudEvents 1.0 event in JSON structured format**:
between services, from a service to itself, to or from a third party. The
choices the specification leaves open are pinned as follows:

| Attribute | This profile pins |
|---|---|
| `specversion` | `1.0`. |
| `id` | A UUIDv7 per [`020-identifiers.md`](020-identifiers.md) IP2, minted by the producer. |
| `source` | A URI-reference naming the **producing service logically**, identical in every environment: `/invoicing`, never a hostname. Because `source + id` is the event's identity, a source that varies between staging and production would make one event two. |
| `type` | `<resource>.<event>`, lowercase `snake_case` segments, past tense: `invoice.voided`, `user.invited`. The producing service is not repeated in the type because `source` already names it. A type's meaning never changes; a different meaning is a different type (PC6). |
| `subject` | The public id of the entity the event is about, per IP1: `inv_9Kd2mQ…`, never an internal key. |
| `time` | When the occurrence happened, RFC 3339 UTC `Z` per IP4. Not when it was published. |
| `datacontenttype` | `application/json`. |
| `dataschema` | The URI of the JSON Schema `data` conforms to, carrying its version. This is how the payload evolves: additively under one URI, a breaking change under a new one, per PC6. |
| `traceparent`, `tracestate` | The distributed-tracing extension, carrying the trace of the request or job that produced the event, per OC1. `traceparent` is required. |
| `tenantid` | An extension attribute carrying the tenant public id where tenant context exists, per OC2. It is the same value that appears as `tenant_id` in the producer's log line. |
| `data` | The payload, `snake_case` keys per [`050-http.md`](050-http.md) HA8, primitives per the identifiers contract. |

On the naming of `tenantid`: CloudEvents' attribute grammar admits
lowercase letters and digits only, so the id vocabulary's `tenant_id`
cannot be an attribute name. Per PC2 the standard's own grammar is adopted
rather than fought, and the log-line field keeps its own name. It is the
same choice [`040-observability.md`](040-observability.md) OC3 makes for
OpenTelemetry's environment variables. The two names carry one value under
two spellings, and the profile says so rather than pretending otherwise.

**The relationship to audit events is deliberate and is not a duplicate**.
An audit event's `action` is the permission that authorized an act
([`080-audit.md`](080-audit.md) AE3, imperative: `invoice.void`). A
message's `type` is the occurrence that resulted (past: `invoice.voided`).
They answer different questions, *what was allowed* and *what happened*,
and one is a record kept while the other is a signal sent. A service can
emit both from one transaction, and that is often the right choice.

`data` carries what a consumer needs to act, and never a copy of the whole
aggregate. A consumer that needs more asks the producing service through
its interface. A payload that carries everything is a schema that changes
whenever anything does.

### AM2. The transport is not the contract

**This document pins the message and says nothing about what carries it**.
Each of these is an admitted transport, chosen per product for its actual
needs: a broker, a cloud queue, a stream, an HTTP `POST`. So is a table in
the producing service's own database, read with
`SELECT … FOR UPDATE SKIP LOCKED`. The contract is the envelope and the
semantics every rule below states. A gate that checked the broker would be
checking the implementation (PC4).

Two limits follow from standards already in force. **A table used as a
queue belongs to exactly one service**. A service can queue work for
itself in its own database, and two services never share one.
[`025-structured-data.md`](025-structured-data.md) SD13 says a database is
private to its service, and a shared queue table is a shared table with a
different name. Between services, the transport is a broker or an HTTP
push. And **the transport is an attached resource** in the sense of
[factor IV](https://12factor.net/backing-services): named by
configuration, swappable per deploy, and never assumed to be in-process.

### AM3. Delivery is at-least-once, and the consumer is idempotent

**Every transport admitted here delivers a message at least once, and no
transport delivers it exactly once end to end**. A consumer that crashes
after acting and before acknowledging sees the message again. A broker
that loses an acknowledgement redelivers. A relay that retries after a
timeout publishes twice. Exactly-once is not a property a transport can
offer across the process boundary. A design that assumes it has a bug that
appears only under load.

So **the consumer is idempotent, and the standard says how**:

- **The deduplication key is `(source, id)`**, the identity CloudEvents
  already guarantees unique. A consumer records the keys it has processed
  and treats a repeat as already done.
- **The record is written in the same transaction as the effect**. The
  consumer's inbox, the table of processed keys, commits with the change
  the message caused, or neither commits. A key recorded before the effect
  is a message lost on the next crash. An effect committed before the key
  is a message applied twice on the next redelivery. This is
  [`025-structured-data.md`](025-structured-data.md) SD11's one-transaction
  rule with the message as the request.
- **The inbox is retained at least as long as the transport can
  redeliver**, and the retention is stated. A key forgotten before the
  last possible redelivery is a duplicate waiting to happen.
- **Where the effect can be made idempotent by construction, it is**.
  Examples: an upsert keyed on the subject, a state transition guarded by
  the current state, a balance computed rather than incremented. Each is
  safe to apply twice without an inbox at all, and the inbox becomes the
  backstop rather than the mechanism.

**The inbox deduplicates the delivery; the job's duplicate policy governs
the effect.** [`057-jobs.md`](057-jobs.md) JB2 gives every job one of three
policies. For an `idempotent` job the inbox row and the effect commit
together, and the rules above are the whole story.

An `at_most_once` job has an effect across a boundary with no dedup
handle. Examples: a plain SMTP send, a device command, a payment rail
without an idempotency key. For that job the consumer claims the key before acting
and records after, so a redelivery meets the claim. A crash between the
two is reported as `unknown` rather than repeated. For an `at_least_once`
job the declaration itself is the consent to a repeat. A message can
therefore trigger a job of any policy, but it is not permitted to trigger
a job that has not declared one.

**Ordering is not guaranteed, and a consumer does not depend on it.** Two
messages about different subjects arrive in any order. Two about the same
subject arrive in order only where the transport promises it for that key.
A consumer written to tolerate reordering keeps working when a transport
is swapped for one that does not promise. Tolerating reordering means a
version on the subject, or a check against current state. Where order genuinely matters, the producer
says so in the payload, with a sequence number or the prior state, rather
than on the wire.

### AM4. A message is produced in the transaction that caused it

**A producer never publishes a message its state change did not commit,
and never commits a state change whose message was not captured**. Both
failures are ordinary. Publish, then fail to commit, and a consumer acts
on something that never happened. Commit, then fail to publish, and the
change is invisible to everything downstream. No ordering of the two
operations avoids both, because they are two systems and either can fail
after the other succeeds.

**The outbox is how this is met**. The producer writes the event, as the
AM1 envelope, to an outbox table in its own database inside the same
transaction as the state change. That is
[`025-structured-data.md`](025-structured-data.md) SD11 again: one
transaction. A relay reads the outbox and publishes to the transport,
marking each row published. The relay is a per-event job, `outbox.relay`,
run by the service's pool worker ([`035-workers.md`](035-workers.md) WK1)
and never by the server.

The relay is itself a consumer of the outbox under AM3. That is why it can
publish a row twice, and why AM3's deduplication is what makes that
harmless. This is the same reasoning [`080-audit.md`](080-audit.md) AE8
applies to the audit row. The inference *no message, therefore no change*
is only sound if the two cannot separate.

A transport that supports a transactional publish from the same database,
a queue table in the service's own database, satisfies this directly. The
outbox and the queue are the same row. Every other transport needs the
relay.

### AM5. Failure is bounded and visible

A message a consumer cannot process is not retried forever, is not dropped
silently, and does not stop the messages behind it.

- **Retries are bounded, with exponential backoff and jitter.** The
  attempt count and the schedule are configuration, stated per consumer. A
  transient failure (a dependency down, a lock timeout) is retried. A
  permanent one (a payload that fails its schema, a subject that does not
  exist) is not. The handler distinguishes the two in what it returns.
- **After the last attempt the message is dead-lettered**, with the
  envelope intact, the attempt count, and the last error. A dead letter is
  a fact for a person to look at; a message discarded after N failures is
  a fact nobody will.
- **Dead letters are replayable.** Replay is an operator-triggered job
  (`deadletter.replay`, [`057-jobs.md`](057-jobs.md)) that redelivers the
  same envelope, id and all. AM3 makes that safe, which is the second
  reason AM3 keys on the envelope's identity rather than on a delivery
  attempt's.
- **A poison message never blocks the queue**. A consumer that stops on
  the first message it cannot process has converted one bad payload into
  an outage for every message behind it. The bad one is dead-lettered and
  the next is taken.
- **Every failure is logged with the context block** of
  [`040-observability.md`](040-observability.md) OC4: the trace the
  envelope carried, continued, plus the event `id` and `type`. So a dead
  letter can be traced back to the request that produced it.

### AM6. Work outside a request is a consumer, in a worker

**A message triggers background work, and a consumer running in a worker
process performs it.** A timer inside the HTTP process does not. A timer
in the request-serving process runs once per replica, so three replicas do
the work three times or race to. It dies with the process on every deploy.
It has no retry, no dead letter, no deduplication, no record that it ran.
And the service standard's lifecycle rules cannot see it: `SIGTERM` drains
requests and not timers, readiness reports on the listener and not the
loop.

**The worker is its own image**, built in the same build run as the server
and carrying the same version. It links the consumer and not the listener,
so the server *cannot* consume and the worker *cannot* listen. That makes
the timer ban above structural rather than remembered.

The worker has its own dependency closure, its own configuration surface,
its own scaling and its own deployment. A worker and a server differ in
every one of those. An image that is both has a dependency closure, a
configuration surface and a failure mode that are the union of the two. An
image does one thing; two things are two images. The two worker models,
the pool and the one-shot, and how their images are cut, are
[`035-workers.md`](035-workers.md)'s. The consumer here is the pool.

Two things bind the worker to the service, and they are different things:
**provenance** and **ownership**.

**Provenance** is the build run. [`010-ci.md`](010-ci.md) versions the
repository rather than the artifact, so every image one build run produces
was compiled once. BUILD ONCE means the build job is the only compiler in
the run, and the image build never recompiles. Every such image is built
every time whether or not its files changed, and tested against the others
in that run. It asserts compatibility with them by construction. A worker
at one version consuming rows a server at another version migrated is not
a state a deployment can produce.

**Ownership** is the credential. A worker that holds this service's
database credential and is migrated by this service's migrations is this
service's worker, whatever else the repository holds. A worker with its
own state is another service, with its own credential and its own images,
whether or not it shares the repository. Its data is
[`025-structured-data.md`](025-structured-data.md) SD13's, and the
messages between the two services are the only thing they share.

Workers obey [`030-service.md`](030-service.md) SC4 in their own terms. On
`SIGTERM` a worker stops taking messages, finishes what it holds within
the stated timeout, and exits. Any message it held past that is
redelivered, which is what at-least-once buys.

Work that runs *on a schedule* rather than *on a message* is a job under
[`057-jobs.md`](057-jobs.md). That includes the nightly report, the
retention sweep, and the backfill
[`025-structured-data.md`](025-structured-data.md) SD4 sends here. The
platform's runner invokes it as a one-shot worker on a tick
([`035-workers.md`](035-workers.md) WK5); the tick is an invocation, not a
message. Where that job's work is a fan-out, it produces messages through
the outbox and the pool consumes them under this rule. The documents meet
at the message: 057 says what the work is, 035 says what runs it, this one
says how the message travels.

### AM7. A webhook leaving is a signed CloudEvent

A message delivered to a third party is **the AM1 envelope, in structured
mode over HTTP `POST` with `Content-Type: application/cloudevents+json`,
signed per Standard Webhooks**:

| Header | Value |
|---|---|
| `webhook-id` | The event's `id`. One identity for the message and the delivery, so the receiver's deduplication key is the same key AM3 uses. |
| `webhook-timestamp` | Unix seconds at the time of *this delivery attempt*. Not the event's `time`, which does not change across retries. |
| `webhook-signature` | `v1,<base64>`: HMAC-SHA256 with the endpoint's secret over `webhook-id + "." + webhook-timestamp + "." + body`, the body being the exact bytes sent. |

- **One secret per endpoint**, `whsec_`-prefixed base64, delivered to the
  receiver out of band. It is rotated by sending two signatures
  (space-separated in the header, per the specification) through an
  overlap window. So a rotation is never a moment of unverifiable
  deliveries.
- **Delivery is retried per AM5**, with the specification's response
  semantics. `2xx` is success. `410 Gone` disables the endpoint. `429`,
  `502` and `504` throttle. Anything else is a failure to retry. The
  schedule spans days, not minutes, because the receiver's outage is not
  the sender's to decide the length of.
- **The receiver is told how to verify**, in the product's documentation.
  That means the three headers, the signed string, and the tolerance to
  apply to the timestamp (five minutes is the profile's). It also means
  verifying over the raw body before parsing it. A parsed-and-re-serialised
  body is a different byte sequence and a different signature.

Signing binds the delivery to the sender and the timestamp binds it to a
window. Together they mean a captured delivery cannot be replayed later
and a forged one cannot be constructed without the secret. What signing
does not do is encrypt, so a webhook body carries what the receiver needs
and not a byte more.

### AM8. A webhook arriving is verified, recorded, and then processed

A message from a third party enters through an endpoint that does exactly
four things, in this order:

1. **Verifies the signature over the raw request body**, with the
   provider's scheme and the endpoint's secret. It rejects with `400` on
   failure or on a timestamp outside tolerance. Parsing comes after
   verifying, never before, for the byte-identity reason above.
2. **Re-envelopes the payload as an AM1 event**, with `source` naming the
   provider (`/stripe`) and `id` set to *the provider's event id*. So
   `(source, id)` is the deduplication key without any provider-specific
   logic, and a redelivered provider event is a repeat under AM3 like any
   other.
3. **Records it durably**, to the inbox or to the service's own queue
   table, in one transaction.
4. **Responds `2xx`.** Then, and only then, the work happens, as a
   consumer under AM3 through AM6.

The order is the rule. A handler that does the work before responding
turns the provider's timeout into a redelivery of work already half done.
A handler that responds before recording turns a crash into a lost event.
A handler that parses before verifying has trusted a body it has not yet
authenticated. The provider's redelivery, the crash and the forged request
are all ordinary, and this order survives all three.

## The artifacts

Per PC3, under [`contracts/messaging/`](../contracts/messaging/):

- **`envelope.schema.json`**: the AM1 profile as JSON Schema 2020-12 over
  the CloudEvents JSON format. It carries the required attributes with
  this profile's constraints, the two extension attributes, and `data` as
  an object. Ids, timestamps and trace fields are `$ref`s into the
  identifiers and observability contracts, never restated.
- **`corpus.json`**: three parts.
  - `validity`: envelopes that must be accepted or rejected, with the
    reason.
  - `delivery`: sequences of deliveries to a consumer, with the number of
    effects an idempotent consumer must produce. The sequences are the
    same `(source, id)` twice, two ids with one source, one id under two
    sources, and a replay from the dead letter.
  - `signing`: given a secret, an id, a timestamp and a body, the exact
    `webhook-signature` value. It also gives a tampered body, a wrong
    secret and a stale timestamp that must each be rejected. The values
    are computed, so an implementation in any language proves its HMAC
    against them.

## Decisions

- **CloudEvents is the envelope** (2026-09-02). It defines an event's
  identity as `source + id` and requires it unique, and it carries trace
  context as a defined extension. It binds to HTTP in a structured mode
  with a registered media type. Those are the three properties an envelope
  must have. A standard with a defined grammar meets them, rather than a
  shape this document would defend alone. Delivery semantics are invented
  because no wire standard states them, and the invention stops there.
- **`(source, id)` is the deduplication key** (2026-09-02). It is the
  identity the specification already guarantees unique, so adopting it
  costs nothing and inventing another would give one message two
  identities.
- **`tenantid`, not `tenant_id`, at the envelope** (2026-09-02). The
  extension-attribute grammar forbids the underscore. The standard's
  grammar is adopted whole, as OpenTelemetry's environment variables were,
  and the two spellings of one value are stated rather than hidden.
- **`type` is past tense and `source` is logical** (2026-09-02). A message
  reports an occurrence, so its type says what happened. The audit action
  says what was allowed and stays imperative, and the two are different
  questions. `source` is a logical name because it is half of the event's
  identity, and an identity must not change between environments.
- **Standard Webhooks for signing** (2026-09-02). The proposal was to
  invent HMAC over body plus timestamp with a replay window, which is that
  specification's contract to the letter. Adopting it means a receiver
  with an existing verifier verifies without reading our documentation.
- **At-least-once stated, exactly-once refused** (2026-09-02). No
  transport offers exactly-once across the process boundary. A document
  that implied one would license consumers that fail under exactly the
  conditions a queue exists to survive.
- **Outbox and inbox, both, in the service's own transaction** (2026-09-02).
  It is the only construction in which neither a lost message nor a
  duplicated effect is possible without a distributed transaction, which
  nothing here offers. The relay is a consumer like any other, which is
  why the two patterns are one rule seen from both ends.
- **Timers in the HTTP process are refused, and the worker is its own image**
  (2026-09-02). A timer multiplies by the replica count, dies with every
  deploy, and is invisible to every lifecycle rule in force. The worker is
  a separate image because an image does one thing. Its dependencies, its
  configuration surface, its scaling and its failure mode are its own. And
  compatibility with the service comes from the shared version and build
  run, not from sharing bytes.
