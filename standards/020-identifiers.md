# Identifiers and primitive representations

## Why this exists

Until a standard says what an identifier, an instant and a money value look
like, each product decides alone. Enumerable ids, timezone drift and
floating-point money follow. The other platform standards define schemas that
carry all three. This document answers once, so the others reference instead
of re-deciding.

These are wire rules, per PC1. They bind what crosses a boundary: a URL, a
payload, a log line, an event. What a language does in memory is its own
business until the value is serialized.

## The rules

### IP1. Internal keys never leave the service

A database's integer primary and foreign keys are an implementation detail
of storage. They do not appear in URLs, API payloads, events, logs, or
anything else that leaves the service.

A row that is addressable from outside the service carries a **separate,
opaque public identifier**. That identifier is generated at creation,
unique, immutable for the life of the row, and stored beside the internal
key. The internal key joins; the public id addresses.

The first rule: **never expose the sequence**. An enumerable id is a
resource-enumeration vulnerability and a business-metrics leak, such as
order volume readable from an invoice number. The second: **pick the public
format deliberately** (IP2). Exposing a UUID column that is also the primary
key fixes the first rule to the letter and loses the point. The public id
must be swappable without a schema migration rippling through every foreign
key.

**The public id is never the primary key and never the target of a foreign
key.** Joins use the internal key. A public id is also never a credential. It
names a row, and authorization decides whether the caller can touch that row.

**At every boundary, `id` is the public id.** A boundary is a
JSON or event member, a URL parameter or a log field. It is also an API type,
a domain type, or a parameter outside the storage layer. A name that crosses one is
either `id` (`ID` in Go, `$id` in PHP) or `<entity>_id`, a reference to
another entity. It holds a public id of IP2 part A. Where the field is
declared as one, it holds a display handle of IP2 part B. It never holds an
internal key.

Inside the database and the storage layer, the internal key keeps its
conventional name, `id`, and integer references are `<entity>_id`. The public
id column is `public_id`. The storage layer maps between the two. The integer
never surfaces under the name `id`. Column types are SD7 of
[`025-structured-data.md`](025-structured-data.md).

### IP2. The public id format table

What the id is for decides which format it takes, not what the first library
to hand generated. There are three cases. Part A is the id that addresses a
row. Part B is a display handle, a special case of public identifier that a
person is meant to read. Part C is an issued credential, which is not an
identifier at all.

#### Part A. Row public ids

A row public id addresses a row in a URL, a payload, an event or a grant scope.

| Format | Use when | Profile |
|---|---|---|
| **UUIDv7** | The default. Any row addressed from outside, and every table that grows at volume. | RFC 9562. Wire form: lowercase, canonical hyphenated, e.g. `01923e8a-7f4e-7cc3-9a2b-3f8d2c1b0a99`. A native `uuid` column. The application mints it until the pinned engine generates it natively. |
| **UUIDv4** | A row whose creation time or creation order is itself sensitive: an account, an invitation, a record whose rate of creation is private. | RFC 9562, random, lowercase canonical hyphenated. Postgres generates it with `gen_random_uuid()`. A native `uuid` column. |
| **nanoid** | Only an id a person types or reads aloud, where 36 characters is hostile. Never a high-volume table. | Alphabet `A-Za-z0-9_-` (the nanoid default), length ≥ 12, CSPRNG-generated, unique index plus insert-retry on collision. Stored under a binary collation. The generator also retries when its output has the shape of a display handle (`<prefix>_` then base62), so a row public id is never mistaken for one. |

Why UUIDv7 and not a random id by default: `public_id` is how every request
finds its row. It therefore carries a unique index that every insert writes to. A
random value lands on a random leaf of that index, which splits pages,
widens the index and keeps all of it hot. A UUIDv7 lands at the right edge, so
recent rows stay cached and the index stays compact. Both engines recommend an
ordered UUID for exactly this reason.

What a UUIDv7 costs is that its first 48 bits are its creation time, and
anyone holding the id can read them. For most rows that is nothing. Where the
creation instant or the creation rate is itself private, the row takes a
UUIDv4. The index cost then falls on a table that stays modest.

Why nanoid and not a truncated UUID: the use case is a short handle. A
truncated UUID is a nonstandard format wearing a standard's name, the worst
of both. At ≥ 12 characters over a 64-symbol alphabet (~71 bits) with a
unique index and insert-retry, collision is an engineering non-event. A nanoid is random
and wider than 16 bytes, so it is the slowest of the three to index. A UUID
with its hyphens removed fails the same way. It is neither a nanoid nor a UUID,
and it is not admitted.

Three formats are **not admitted**. ULID is a second answer to the question
UUIDv7 answers, per PC2: a spec with libraries, where UUIDv7 is an RFC with
native column types. Sequential integers as public ids are refused under
IP1. UUIDv1/v3/v5 are refused: MAC leakage, name-derivation, and no use case
here.

A row public id carries no type. A prefix such as `lic_` on a location's
address tells every caller what the id points at. It also invites any service
that parses it to dispatch on the prefix (IP3). The type belongs in the route
and in a field. An id is never derived from other data, such as an identity
provider's subject. A derived id is as guessable as its source.

The nanoid alphabet contains `_`, so a display handle is also a valid nanoid
by shape, and a schema cannot tell the two apart. The rule is therefore kept
at three points: the generator, the `CHECK` on a nanoid `public_id` column
(SD7), and review.

#### Part B. Display handles

A display handle is a special case of public identifier. It is a value
shown to a person on purpose, for support, integration or connectivity. Nobody
then reads a nanoid or a UUID out of a URL. Examples are the account id
on a settings page and an integration's connection id. The id of an API key
is another, as distinct from its secret (part C). The prefix tells the reader
what kind of thing the value names.

| Format | Profile |
|---|---|
| **Display handle** | `<prefix>_<body>`: prefix lowercase `[a-z][a-z0-9]{0,7}`, one underscore, body from the **base62 alphabet only** (`A-Za-z0-9`, no `_` or `-`), length ≥ 12, CSPRNG-generated. The first underscore therefore always delimits the prefix. One stable prefix per concept, recorded in the owning service's docs. |

A display handle is **an attribute of the row, beside its row public id**. It
has its own column, such as `accounts.account_ref`. The column is unique,
indexed and immutable, and the handle is minted at creation. It is never the
primary key, the row public id, or the target of a foreign key. It is never a
URL path segment, a grant scope, an audit `target.id`, an event `subject` or a
log field.

A person quotes the handle. A support or integration surface can resolve a row
by it, and nothing else addresses a row by it. Quoting one proves nothing about
the caller, so a surface that resolves by handle authenticates the caller
another way.

#### Part C. Issued credentials

A credential a product issues to a caller, such as an API key, is neither a row
public id nor a display handle. It is secret, and how it is stored, shown and
revoked is not an identifier question. This standard covers only the
identifier side.

A credential can carry an issuer prefix, so a person or a secret scanner can
tell which system it came from. The prefix is a label, and no service branches
on it. A credential is never a row's public id and never a primary or foreign
key. It never appears in a URL path, a grant scope or an audit `target.id`.

### IP3. Ids are opaque

No consumer parses meaning out of an identifier. The timestamp inside a
UUIDv7 is an index-locality property, not an API, and nothing reads it
back. The prefix on a display handle is for the person reading a screen. A
service that switches behaviour on it has turned an id into a type field, and
type belongs in a field. The one act permitted on a foreign id is equality
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

A clock produces every timestamp; nobody writes one by hand.

**The server speaks base representations, and presentation is the UI's
job**. Formatting an instant into a viewer's time zone, or a money value into
`€1.999,00`, happens in the presentation layer against the canonical forms
here. That half of the rule is [`090-web-client.md`](090-web-client.md) WC4's.
A server that emits pre-localised values has baked one viewer's locale into
every consumer and turned every other consumer's rendering into a parsing
job.

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

Sub-minor-unit precision (per-unit prices, FX rates) belongs to the standard
of the capability that needs it; this rule forbids floats and implied
currencies, not precision.

### IP6. A duration is an ISO 8601 duration

A span of time on the wire is an **ISO 8601 duration string**:
`PnYnMnWnDTnHnMnS`. For example, `P1D` is a day and `PT4H` is four hours.
This covers every API field, event field, declaration and stored value that
holds a span: a deadline, a grace period, an SLA, a retention window.

It is not a bare number of seconds or milliseconds with the unit in the
field name. That is IP4's Unix-integer problem again. The unit lives outside the
value, and the first consumer that reads it wrongly is off by a factor of a
thousand. The exception is a **measurement**, such as a latency the
server observed. A `duration_ms` count is a sample, not a setting, and a
number is its honest type.

The direction is IP4's:

1. **Accept liberally.** An API accepts any valid ISO 8601 duration,
   including weeks and a fraction on the lowest-order component.
2. **Emit canonically.** Zero components are dropped, and a duration of
   nothing is `PT0S`. A server never folds one unit into another on the
   way out: `PT36H` stays `PT36H`.

**Years and months are calendar units, not fixed lengths.** A month is 28
to 31 days, and a year 365 or 366. They convert to each other, because a
year is always twelve months, but never to days. A product that needs a
fixed span refuses a calendar unit by name in its validation error.

How a person sees and enters a duration is the presentation layer's job,
in [`090-web-client.md`](090-web-client.md) WC4.

## The artifacts

Per PC3, the contract lives under
[`contracts/identifiers/`](../contracts/identifiers/):

- **`primitives.schema.json`**: JSON Schema (2020-12) `$defs` for
  `uuidv7`, `uuidv4`, `nanoid`, `prefixedHandle`, `publicId` (the row union),
  `timestamp`, `timestampInput`, `date`, `duration`, `money`, `currency`.
  `prefixedHandle` is the display handle of part B.

  Every other contract's
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
