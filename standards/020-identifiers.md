# Identifiers and primitive representations

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)). It is a per-capability
standard from that contract's roster. Read
[`999-enforcement.md`](999-enforcement.md) for the tier each rule below
actually holds. Artifacts:
[`contracts/identifiers/`](../contracts/identifiers/).

## Why this exists

Nothing in the portfolio says what an identifier is. Internal integer primary
keys leak into URLs and payloads, or do not, per product, and public id
formats are whatever the first migration picked. The oldest cross-service
bugs there are, enumerable ids, timezone drift and floating-point money, are
each one missing page of doctrine. The other platform standards define
schemas: log lines, audit events, job envelopes, the RBAC model. Each of
those has to say what a timestamp, an id, and a money value look like. This
document answers once, so the others reference instead of re-deciding.

These are wire rules, per PC1. They bind what crosses a boundary: a URL, a
payload, a log line, an event. What a language does in memory is its own
business until the value is serialized.

One rule spans all of them: **the server speaks base representations, and
presentation is the UI's job, never the server's**. Localisation and i18n
happen in the presentation layer, against the canonical forms below. That
means formatting an instant into a viewer's time zone, a money value into
`€1.999,00`, or a date into the reader's convention. A server that emits
pre-localised values has baked one viewer's locale into every consumer. It
has turned every other consumer's correct rendering into a parsing job.

## The rules

### IP1. Internal keys never leave the service

A database's integer primary and foreign keys are an implementation detail
of storage. They do not appear in URLs, API payloads, events, logs, or
anything else that leaves the service.

A row that is addressable from outside the service carries a **separate,
opaque public identifier**. That identifier is generated at creation,
unique, immutable for the life of the row, and stored beside the internal
key. The internal key joins; the public id addresses.

These are two rules that usually get conflated, so they are stated apart.
The first: **never expose the sequence**. An enumerable id is a
resource-enumeration vulnerability and a business-metrics leak, such as
order volume readable from an invoice number. The second: **pick the public
format deliberately** (IP2). Exposing a UUID column that is also the primary
key fixes the first rule to the letter and loses the point. The public id
must be swappable without a schema migration rippling through every foreign
key.

### IP2. The public id format table

What the id is for decides which format a public id takes, not what the
first library to hand generated. The admitted formats:

| Format | Use when | Profile |
|---|---|---|
| **UUIDv7** | The default for machine-scale entities: rows created at volume, referenced across services, stored in indexed columns. | RFC 9562. Wire form: lowercase, canonical hyphenated, e.g. `01923e8a-7f4e-7cc3-9a2b-3f8d2c1b0a99`. |
| **nanoid** | User-facing handles: ids a person sees, types, or shares in a URL, where 36 characters is hostile. | Alphabet `A-Za-z0-9_-` (the nanoid default), length ≥ 12, CSPRNG-generated, unique index plus insert-retry on collision. |
| **Prefixed handle** | A nanoid that benefits from being self-describing in logs and support tickets, e.g. `cus_V1StGXR8Z5jd`. | `<prefix>_<body>`: prefix lowercase `[a-z][a-z0-9]{0,7}`, one underscore, body from the **base62 alphabet only** (`A-Za-z0-9`, no `_` or `-`), length ≥ 12. The first underscore therefore always delimits the prefix. One stable prefix per entity type, recorded in the owning service's docs. |

Why UUIDv7 and not UUIDv4: a v4 in an indexed column is random-insert index
fragmentation bought for no benefit. The v7 timestamp prefix gives insert
locality while staying a standard UUID to every driver and column type.
**UUIDv4 is admitted only where an external system requires it or the value
is never indexed**. A v4 in an indexed column needs a written defence in
the owning repository.

Why nanoid and not a truncated UUID: the use case is a short handle. A
truncated UUID is a nonstandard format wearing a standard's name, the worst
of both. At ≥ 12 characters over a 64-symbol alphabet (~71 bits) with a
unique index and insert-retry, collision is an engineering non-event.

Three formats are **not admitted**. ULID is a second answer to the question
UUIDv7 answers, per PC2. Sequential integers as public ids are refused under
IP1. UUIDv1/v3/v5 are refused: MAC leakage, name-derivation, and no use case
here.

### IP3. Ids are opaque

No consumer parses meaning out of an identifier. The timestamp inside a
UUIDv7 is an index-locality property, not an API, and nothing reads it
back. The prefix on a prefixed handle is for humans in logs. A service that
switches behaviour on it has turned an id into a type field, and type
belongs in a field. The one act permitted on a foreign id is equality
comparison, byte for byte. That is also why wire forms are pinned to one
case: a consumer that case-folds ids has invented a second equality.

### IP4. Timestamps are RFC 3339 UTC, and a date is not a timestamp

The rule is three stages, and the direction matters:

1. **Accept liberally.** An API accepts any valid RFC 3339 instant as
   input, offset forms included. A caller in Sydney sends `+11:00` and is
   not wrong to.
2. **Normalise before persistence.** The server converts to UTC at the
   edge, truncating below the repository's pinned precision. What is
   stored is always the normalised instant. Nothing downstream of the
   edge ever sees an offset form.
3. **Emit canonically.** Anything the service produces (responses, logs,
   events) is **RFC 3339, UTC, `Z` suffix, at the repository's one pinned
   fractional precision**: `2026-08-31T14:07:02.417Z`. Not a Unix integer,
   which is unreadable in logs and ambiguous in unit. Not an offset form:
   `+02:00` makes equal instants unequal strings, and string inequality is
   how deduplication breaks.

Precision is **three digits by default, and a one-way ratchet**. A
repository with a real need for finer timekeeping pins six or nine digits
instead, and says so in its own **Conventions** section. It applies that
precision to everything it emits: never fewer than three, never mixed
widths. One fixed width per emitter is what keeps string equality and
instant equality the same test.

A clock produces every timestamp; nobody writes one by hand. Local time
exists only in the presentation layer, per the base-representation rule
above.

A **calendar date** (a birthdate, a due date, a holiday) is not an instant
and does not get a time or a zone glued on. It is RFC 3339 `full-date`:
`2026-08-31`. A birthdate stored as midnight-UTC is off by one for half
the planet, permanently.

Storage profile: MySQL columns are `DATETIME(3)` holding UTC, or
`DATETIME(6)` where the repository pins six digits. They are never
`TIMESTAMP`, whose 2038 ceiling and session-zone conversion are both traps.
Calendar dates use `DATE`. Other engines state their profile in the
[structured-data standard](025-structured-data.md) as they are admitted.

### IP5. Money is integer minor units plus an explicit currency

A monetary amount on the wire is two fields that travel together: an
**integer count of minor units** and an **ISO 4217 uppercase currency
code**. For example, `{"amount": 1999, "currency": "USD"}` is $19.99.
`{"amount": 1999, "currency": "JPY"}` is ¥1999, because the minor-unit
exponent is the currency's, not a universal 2. ISO 4217 says JPY has zero
decimals. IEEE 754 floats are not admitted for money in any wire shape:
`0.1 + 0.2` is the whole argument. An amount without a currency is not an
amount, and a currency assumed from context is a defect waiting for the
first non-USD tenant.

Sub-minor-unit precision (per-unit prices, FX rates, fractional cents) is
out of scope here. It belongs to the standard of the capability that needs
it. What this rule forbids is floats and implied currencies, not precision.

## The artifacts

Per PC3, the contract lives under
[`contracts/identifiers/`](../contracts/identifiers/):

- **`primitives.schema.json`**: JSON Schema (2020-12) `$defs` for
  `uuidv7`, `nanoid`, `prefixedHandle`, `publicId` (the union), `timestamp`,
  `timestampInput`, `date`, `money`, `currency`. Every other contract's
  schema references these by `$ref` rather than restating a pattern: one
  source of truth per primitive, mechanically. The two timestamp defs carry
  IP4's direction. Request-side schemas reference `timestampInput` (any
  valid RFC 3339). Everything stored or emitted references `timestamp`
  (canonical `Z`). A response schema referencing `timestampInput` has the
  rule backwards.
- **`corpus.json`**: the conformance corpus as data, in two parts.
  `validity`: values that must be accepted or rejected against a named
  `$def`. `canonical`: parse-then-emit cases, where an implementation reads
  `input` and must emit exactly `emit`. An implementation in any language
  passes the whole file or names the case it fails.

## Enforcement

Registered in [`999-enforcement.md`](999-enforcement.md) under "Identifiers
standard". Honestly: everything lands review-only, and the gates it is
getting are the platform contract's own mechanisms.
`check-contract-artifacts` proves the tree above stays present and parsing.
`job-contract-conformance` runs `corpus.json` against an implementation
once that shared job exists.

IP1 is the one rule with a capability-specific gate to name. That gate is a
schema-level check that externally addressable tables carry a public id
column in an admitted format. It is buildable once the
[structured-data standard](025-structured-data.md) gives a checker a schema
to read. Until then IP1 is the review question on every API-shaped diff:
*does anything in this payload count rows?*

## Decisions

- **UUIDv7 over ULID** (2026-08-31). Identical property (time-ordered,
  128-bit), but UUIDv7 is an RFC with native column types and driver
  support everywhere the portfolio runs. ULID is a spec with libraries. PC2
  picks the standard.
- **`Z`, never `+00:00`; pinned fractional precision, default three,
  never fewer** (2026-08-31). One canonical string per instant within an
  emitter, so string equality and instant equality agree. Dedupe keys and
  log grep both depend on it. Finer timekeeping is a per-repository
  extension (six or nine digits, stated in its Conventions), never a
  reduction and never a mix.
- **Prefixed-handle body is base62, not full nanoid alphabet**
  (2026-08-31). Keeping `_` out of the body makes the first underscore an
  unambiguous prefix delimiter, without a parsing rule anyone can get
  wrong.
- **`DATETIME(3)` over `TIMESTAMP` in MySQL** (2026-08-31). `TIMESTAMP`
  ends in 2038 and silently converts through the session time zone. Both
  are the class of bug this standard exists to remove.
