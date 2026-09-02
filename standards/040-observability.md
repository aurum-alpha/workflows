# Observability transport and context propagation

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)). Read
[`999-enforcement.md`](999-enforcement.md) for the tier each rule holds. Artifacts:
[`contracts/observability/`](../contracts/observability/). Id and timestamp
formats referenced here are [`020-identifiers.md`](020-identifiers.md)'s.

## Why this exists

The [service baseline standard](030-service.md) gives
every service structured logging with a request id. This standard is what makes those ids mean something *across*
services: a request that crosses two services, or enters a job queue, must
not drop its identity at the boundary. Both halves are standard protocols —
W3C trace context for propagation, OTLP for telemetry transport — so per
PC2 this document is a profile that pins choices, not an invention. The one
internal piece is the id vocabulary: the named fields every log line and
audit event carries, the same in every language, because a correlation
field that is `traceId` in one service, `trace-id` in a second and absent
in a third is three grep patterns for one incident.

## The rules

### OC1. Context propagates as W3C trace context, across every boundary

Every HTTP call between services carries `traceparent`, and forwards
`tracestate` unmodified when one arrived. An inbound request with a valid
`traceparent` continues that trace; without one, the service starts a new
trace at its edge. No parallel correlation scheme is invented — a bespoke
correlation header beside `traceparent` is a second answer to a solved
question.

The async boundary is not an exception: the job envelope (the [messaging standard](055-messaging.md)) carries the same
`traceparent`/`tracestate` as envelope fields, and the worker that dequeues continues the trace that
enqueued. A background job with no trace identity is unattributable work —
the exact failure this rule exists to remove.

`tracestate` is forwarded, never parsed, never logged: it is other systems'
vendor baggage, and logging it leaks whatever they put there.

### OC2. One id vocabulary, the same named fields everywhere

Four ids exist. Each appears under exactly this snake_case name in every
log line and every audit event, in every language:

| Field | Format | Origin |
|---|---|---|
| `trace_id` | 32 lowercase hex (W3C) | from `traceparent`; minted by the first service in the chain |
| `span_id` | 16 lowercase hex (W3C) | the current span, where the service traces; omitted where it does not |
| `request_id` | UUIDv7 ([`020-identifiers.md`](020-identifiers.md) IP2) | minted by the receiving service at its edge, one per inbound request |
| `tenant_id` | a public id, per the identifiers standard | the authenticated tenant context, where one exists |

`trace_id` and `request_id` answer different questions and both exist on
purpose: the trace spans the chain and lives in the tracing backend; the
request id names one service's handling of one request, appears in that
service's logs, and is echoed to the caller in the `x-request-id` response
header — it is the value a person reads off an error page and pastes into
a support ticket, which a trace id sampled away cannot be.

These are **wire names, not code names**. The rule binds the bytes on an
emitted line, never the identifier in source: a Go struct writes
`TraceID string` with a `json:"trace_id"` tag — the field follows Go's own
initialisms rule, the tag follows this contract — and a TypeScript DTO maps
at the serialization boundary the same way. In-code style follows the
language authors' guides, per the [platform contract](000-platform.md).
snake_case is the wire choice because these fields flow into
underscore-native and case-insensitive systems: a Prometheus label admits
only `[a-zA-Z0-9_]`, an unquoted SQL identifier case-folds (`traceId` becomes
`traceid` silently), and a log grep matches raw bytes. camelCase degrades
at the first case-insensitive hop; snake_case round-trips the whole chain
unchanged.

`tenant_id` here is vocabulary, not authority: this standard says the
field's name, format and presence in telemetry. How tenant context is
*established* — from authenticated identity, never from a header an
external caller controls — belongs to the [authorization
standard](070-rbac.md). Between internal services it
travels with the request so telemetry
downstream stays attributable, and it is never read as an access-control
input from anything but the authorization layer's own establishment.

### OC3. Telemetry leaves the process as OTLP, to an endpoint from config

Traces and metrics leave the application as **OTLP**. The endpoint and
protocol come from configuration — the OpenTelemetry standard's own
environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT` and family), per PC2:
the standard ships its own config contract, so inventing a house spelling
would be a second answer, and per [factor III](https://12factor.net/config)
that config belongs in the environment. The collector behind that endpoint
is an attached resource in the sense of
[factor IV](https://12factor.net/backing-services) — swappable per deploy,
named only by configuration. The default protocol is `http/protobuf`; gRPC
is admitted where the platform endpoint offers it.

What sits behind that endpoint — a collector, a vendor, a black hole in
dev — is the platform's problem, never the application's. **No
vendor-specific exporter or agent in application code**: the vendor lives
behind the collector.

Logs are not part of this rule, and stay where
[factor XI](https://12factor.net/logs) puts them: **structured lines to
stdout as an event stream, per the [service baseline
standard](030-service.md); OTLP is not required for
logs.** Factor XI is the justification, not a house preference — an
application that routes or stores its own logs has taken on the execution
environment's job, and these standards inherit it rather than restating
it. One answer per signal: stdout for logs, OTLP for the signals stdout
cannot carry.

An OpenTelemetry SDK is an implementation choice, not a shared dependency:
the contract is the wire protocol and the config variables, and an
implementation that emits conformant OTLP without the SDK is conformant
(PC4). The corollary per PC1: no shared wrapper library around the SDK.

### OC4. The context block is required, not decorative

Where a log line or audit event is emitted while request context exists,
the vocabulary fields carrying that context are present on it — `trace_id`
and `request_id` at minimum, `tenant_id` when tenant context is
established, `span_id` where the service traces. A service that logs
`payment failed` without them has logged that a payment failed for someone,
sometime, in some request — during the incident that is a fact, not a lead.
Lines emitted outside any request context (startup, shutdown, maintenance
jobs' own lifecycle) omit what does not exist and still name what does: a
maintenance job run carries the trace context its trigger carried, per OC1.

## The artifacts

Per PC3, under [`contracts/observability/`](../contracts/observability/):

- **`context.schema.json`** — `$defs` for `traceparent`, `traceId`,
  `spanId`, `requestId`, `tenantId`, and `contextFields` (the block OC4
  requires); log-line and audit-event schemas `$ref` these rather than
  restating.
- **`corpus.json`** — `validity` cases for the defs, and `propagation`
  cases: given a synthetic inbound `traceparent`, the fields an emitted
  log line must carry, with the continuation rules (same `trace_id`, new
  `request_id`, fresh trace when the inbound header is absent or invalid).

## Enforcement

Registered in [`999-enforcement.md`](999-enforcement.md) under "Observability
standard", every rule review-only today. OC1's and OC4's gate is the corpus
under `job-contract-conformance` — inject a `traceparent`, read the emitted
lines, black-box in any language. A live variant is available sooner:
`job-image-starts` already reads startup log lines and can assert the
vocabulary on them. OC2 is gated by the same corpus (field names and
formats are facts on emitted lines). OC3's config half is checkable (the
OTEL variables present, no vendor exporter config in app code is a review
question); its wire half is proven wherever the corpus runs against a live
process.

## Decisions

- **`request_id` is its own id, not the root span** (2026-08-31): traces
  are sampled, spans are tracing-backend citizens; the support-ticket
  value has to exist for every request and live in the service's own
  logs. UUIDv7 per the identifiers standard, echoed as `x-request-id`.
- **snake_case on the wire, language-native in code** (2026-08-31): the
  vocabulary's fields land in Prometheus labels, SQL columns and raw log
  greps, where camelCase either is illegal or silently case-folds;
  snake_case survives every hop. In-code names are out of this standard's
  scope entirely — Go writes `TraceID` per go.dev's CodeReviewComments and
  tags the JSON, which is the language authors' own answer to wire-vs-code.
- **`tracestate` forwarded, never logged** (2026-08-31): it is foreign
  vendors' baggage; logging it is logging unknown third-party data.
- **Logs stay stdout, not OTLP** (2026-08-31): [factor
  XI](https://12factor.net/logs) settled log transport long before we did,
  and the [service baseline
  standard](030-service.md) adopts it; a second pipeline
  for the same signal is the two-answers failure. OTLP is the answer for the
  signals stdout cannot carry, where twelve-factor is silent.
- **OTel's own env vars, no house spelling** (2026-08-31): the standard
  ships a config contract; adopting it whole is what PC2 means by
  profile.
