# Observability transport and context propagation

## Why this exists

The [service baseline standard](030-service.md) gives every service
structured logging with a request id. This standard is what makes those ids
mean something *across* services. A request that crosses two services, or
enters a job queue, must not drop its identity at the boundary. Both halves
are standard protocols: W3C trace context for propagation, OTLP for telemetry
transport. So per PC2 this document is a profile that pins choices, not an
invention.

The one internal piece is the id vocabulary: the named fields every log line
and audit event carries, the same in every language. Without it, a
correlation field is `traceId` in one service, `trace-id` in a second and
absent in a third. That is three grep patterns for one incident.

## The rules

### OC1. Context propagates as W3C trace context, across every boundary

Every HTTP call between services carries `traceparent`, and forwards
`tracestate` unmodified when one arrived. An inbound request with a valid
`traceparent` continues that trace; without one, the service starts a new
trace at its edge. No parallel correlation scheme is invented. A bespoke
correlation header beside `traceparent` is a second answer to a solved
question.

The async boundary is not an exception. The job envelope (the [messaging
standard](055-messaging.md)) carries the same `traceparent`/`tracestate` as
envelope fields. The worker that dequeues continues the trace that enqueued.
A background job with no trace identity is unattributable work. That is the
exact failure this rule exists to remove.

The service forwards `tracestate`, never parses it and never logs it. It is
other systems' vendor baggage, and logging it leaks whatever they put there.

### OC2. One id vocabulary, the same named fields everywhere

Four ids exist. Each appears under exactly this snake_case name in every
log line and every audit event, in every language:

| Field | Format | Origin |
|---|---|---|
| `trace_id` | 32 lowercase hex (W3C) | from `traceparent`; minted by the first service in the chain |
| `span_id` | 16 lowercase hex (W3C) | the current span, where the service traces; omitted where it does not |
| `request_id` | UUIDv7 ([`020-identifiers.md`](020-identifiers.md) IP2) | minted by the receiving service at its edge, one per inbound request |
| `tenant_id` | a public id, per the identifiers standard | the authenticated tenant context, where one exists |

`trace_id` and `request_id` answer different questions, and both exist on
purpose. The trace spans the chain and lives in the tracing backend. The
request id names one service's handling of one request and appears in that
service's logs. The service echoes it to the caller in the `x-request-id`
response header. It is the value a person reads off an error page and pastes
into a support ticket. A trace id that sampling dropped cannot be that value.

These are **wire names, not code names**. The rule binds the bytes on an
emitted line, never the identifier in source. A Go struct writes
`TraceID string` with a `json:"trace_id"` tag. The field follows Go's own
initialisms rule, and the tag follows this contract. A TypeScript DTO maps
at the serialization boundary the same way. In-code style follows the
language authors' guides, per the [platform contract](000-platform.md).

The wire choice is snake_case because these fields flow into
underscore-native and case-insensitive systems. A Prometheus label admits
only `[a-zA-Z0-9_]`. An unquoted SQL identifier case-folds (`traceId` becomes
`traceid` silently). A log grep matches raw bytes. At the first
case-insensitive hop, camelCase degrades. Across the whole chain, snake_case
round-trips unchanged.

`tenant_id` here is vocabulary, not authority. This standard says the
field's name, format and presence in telemetry. How tenant context is
*established* belongs to the [authorization standard](070-rbac.md): from
authenticated identity, never from a header an external caller controls.
Between internal services it travels with the request, so telemetry
downstream stays attributable. It is never read as an access-control input
from anything but the authorization layer's own establishment.

### OC3. Telemetry leaves the process as OTLP, to an endpoint from config

Traces and metrics leave the application as **OTLP**. The endpoint and
protocol come from configuration, in the OpenTelemetry standard's own
environment variables (`OTEL_EXPORTER_OTLP_ENDPOINT` and family), per PC2.
The standard ships its own config contract, so a house spelling would be a
second answer. Per [factor III](https://12factor.net/config), that config
belongs in the environment. The collector behind that endpoint is an
attached resource in the sense of
[factor IV](https://12factor.net/backing-services): swappable per deploy,
named only by configuration. The default protocol is `http/protobuf`; gRPC
is admitted where the platform endpoint offers it.

What sits behind that endpoint is the platform's problem, never the
application's: a collector, a vendor, a black hole in dev. **No
vendor-specific exporter or agent in application code**: the vendor lives
behind the collector.

Logs are not part of this rule. They stay where
[factor XI](https://12factor.net/logs) puts them: **structured lines to
stdout as an event stream, per the [service baseline
standard](030-service.md)**. **OTLP is not required for logs**.

Factor XI is the justification, not a house preference. An application that routes or
stores its own logs has taken on the execution environment's job. These
standards inherit that rule rather than restating it. One answer per signal:
stdout for logs, OTLP for the signals stdout cannot carry.

An OpenTelemetry SDK is an implementation choice, not a shared dependency.
The contract is the wire protocol and the config variables. An
implementation that emits conformant OTLP without the SDK is conformant
(PC4). The corollary per PC1: no shared wrapper library around the SDK.

### OC4. The context block is required, not decorative

Where a service emits a log line or audit event while request context
exists, the vocabulary fields for that context are present on it. That means
`trace_id` and `request_id` at minimum, `tenant_id` when tenant context is
established, and `span_id` where the service traces. A service that logs
`payment failed` without them has logged that a payment failed for someone,
sometime, in some request. During the incident that is a fact, not a lead.
Lines emitted outside any request context (startup, shutdown, maintenance
jobs' own lifecycle) omit what does not exist and still name what does. A
maintenance job run carries the trace context its trigger carried, per OC1.

## The artifacts

Per PC3, under [`contracts/observability/`](../contracts/observability/):

- **`context.schema.json`**: `$defs` for `traceparent`, `traceId`,
  `spanId`, `requestId`, `tenantId`, and `contextFields` (the block OC4
  requires). Log-line and audit-event schemas `$ref` these rather than
  restating them.
- **`corpus.json`**: `validity` cases for the defs, and `propagation`
  cases. A propagation case gives a synthetic inbound `traceparent` and the
  fields an emitted log line must carry. It carries the continuation rules:
  same `trace_id`, new `request_id`, and a fresh trace when the inbound
  header is absent or invalid.

## Decisions

- **`request_id` is its own id, not the root span** (2026-08-31): traces
  are sampled, and spans are tracing-backend citizens. The support-ticket
  value has to exist for every request and live in the service's own
  logs. UUIDv7 per the identifiers standard, echoed as `x-request-id`.
- **snake_case on the wire, language-native in code** (2026-08-31): the
  vocabulary's fields land in Prometheus labels, SQL columns and raw log
  greps. There camelCase either is illegal or silently case-folds;
  snake_case survives every hop. In-code names are out of this standard's
  scope entirely. Go writes `TraceID` per go.dev's CodeReviewComments and
  tags the JSON, which is the language authors' own answer to wire-vs-code.
- **`tracestate` forwarded, never logged** (2026-08-31): it is foreign
  vendors' baggage; logging it is logging unknown third-party data.
- **Logs stay stdout, not OTLP** (2026-08-31): [factor
  XI](https://12factor.net/logs) settled log transport long before we did,
  and the [service baseline standard](030-service.md) adopts it. A second
  pipeline for the same signal is the two-answers failure. OTLP is the
  answer for the signals stdout cannot carry, where twelve-factor is silent.
- **OTel's own env vars, no house spelling** (2026-08-31): the standard
  ships a config contract; adopting it whole is what PC2 means by
  profile.
