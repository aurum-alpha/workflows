# JSON document storage: the relational JSON column first, when a document database is admitted beside it, and which structured-data rules transfer

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/json-document-storage/`](../contracts/json-document-storage/). Nearly every
rule here is a rule of [`025-structured-data.md`](025-structured-data.md)
carried across or deliberately left behind; ids and timestamps are
[`020-identifiers.md`](020-identifiers.md)'s; the jobs that rebuild and
backfill a store are [`057-jobs.md`](057-jobs.md)'s; what is backed up is
[`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s; *service*,
*stateful server*, *backing service* and *credential* are used in the senses
[`000-platform.md`](000-platform.md#terms) defines.

**A document here is a JSON document** ([RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)):
a record whose shape is decided per document rather than per table — a form a
user designed, a payload a provider sent, a search-index entry, a read model
projected from many rows. It is **never a file a person would call a
document**: a PDF, a spreadsheet, a word-processor file, a scanned contract.
Those are bytes, and bytes are objects under
[`026-blob-storage.md`](026-blob-storage.md), whatever the product calls them.
Where this document and the industry say *document store* or *document
database*, read *JSON document store*.

This document governs **JSON documents and where they live**: the relational
engine's JSON column as the first answer, the hybrid model in which a
document database is attached beside the relational store when the column is
insufficient, which engine for which need, in which of two roles, what every
document carries, how a document's shape changes without a schema to migrate,
and how a store that is a copy is kept a faithful one. **What it does not
define is the relational store, blobs, or backup**: the first is
[`025-structured-data.md`](025-structured-data.md)'s, files and objects are
[`026-blob-storage.md`](026-blob-storage.md)'s, and
[`028-backup-and-recovery.md`](028-backup-and-recovery.md) says how a store
is backed up; this document only says which stores it may exclude.

## Why this exists

A JSON document store is the second persistence engine a product reaches
for, and it is reached for early, because its first week is easier than the relational
store's: no schema to write, no migration to run, a shape that is whatever the
code last serialised. Every advantage of that week is a decision deferred, and
the deferred decisions arrive together: what a document *is*, which fields
every one must carry, what happens to last year's documents when the shape
changes, whether a tenant's documents can be told from another's by more than
a field somebody remembered to filter on, and whether the store is the truth
or a copy of it.

The cheapest answers each fail as a general property. **Two systems of
record** — the invoice in a table and in a collection, each authoritative for
something — give two answers to one question the moment one write succeeds
and the other does not. **A document store as the only store** discards every
invariant the relational engine held for free — a foreign key, a uniqueness
constraint, a check on a money column, a transaction across two rows — and
each is re-implemented in code paths that multiply. **A schema that lives in
the code** means the store holds every shape the code has ever written, and a
reader that assumes the current one fails on the oldest document at the worst
moment. **A derived copy nobody rebuilds** drifts from its source one missed
event at a time, silently, because a stale search result is not an error
anything raises.

The relational engine's own JSON column already answers most of what a
document store is asked to do, with a standard query language, inside the
owning row's transaction, isolation predicate and backup. So this document
makes that column the default and the document database the exception that
states its reason — **the hybrid model**: rows and JSON columns in the
relational store for everything that can live there, and a document database
(a general-purpose document engine, a key-value document store, a search
engine) attached beside it for the data the column measurably cannot serve.
It splits the exception into two roles that differ in whether the data may be
lost, so the common case, a rebuildable projection, carries none of the
weight of a system of record. [The hybrid model](#the-hybrid-model-the-json-column-or-a-document-database)
below says which engine answers which need. What this removes from
every repository: whether a store is warranted, what a document must carry,
how its shape may change, and what a copy owes its source. What remains is
the shape of the documents, which is the domain's.

### The standards evaluated first, per PC2

**The document format is JSON** ([RFC 8259](https://www.rfc-editor.org/rfc/rfc8259))
**and the schema language for a document is JSON Schema, draft 2020-12** —
the language every contract here is written in. A collection's per-version
schema is a JSON Schema under a URI, and the reader validates against it.
Where an engine offers its own validator, usually a subset of an older draft,
the declaration may render into it as a backstop; the contract is the file in
the repository, which any language and any editor can open. An engine's
binary encoding is not the contract either.

**The query language of the relational engine's JSON column is standard**:
SQL/JSON path is part of ISO/IEC 9075 and every engine
[`025-structured-data.md`](025-structured-data.md) SD7 admits implements it —
a PC2 argument for making the column the first answer (DS1), since its query
is authored SQL under SD1. **No standard covers the document engines' query
languages**, and this document carries SD1's *reasoning* across instead: the
query is authored text in the engine's own language (DS3).

**Where an engine's wire protocol has several independent implementations**,
it is admitted as a profile of that protocol rather than as a vendor, and a
repository moves between implementations by configuration
([factor IV](https://12factor.net/backing-services)); the storage profile
(DS9) says which admitted engine has that property.

**For evolution, PC6 is the standard** — a schema-version field, additive
change, a new version for a breaking change with a window in which readers
accept the old one — applied by DS6 to a store where the schema has nowhere
else to live. **For freshness of a copy, 057 JB8 is the standard**: a derived
store whose rebuild has stopped is a periodic job's absence in another shape.

**What no standard covers** is what this document invents: the admission test
and its declaration (DS1), the two roles (DS2), the envelope (DS5), and the
version window a reader honours (DS6).

## The rules

### DS1. The relational store is the system of record, and a document store is admitted by declaration

**Every entity the product owns has its authoritative row in the relational
store. A document store is admitted only for data that is a document by
nature, only after the JSON column has been found insufficient, and never for
anything whose integrity a relational constraint governs.** A document store
holds no foreign key, no uniqueness that survives a race, no check on a money
field, and no transaction across an arbitrary set of documents; data that
needs any of those is rows under 025 SD10, whatever shape the code finds
convenient.

*A document by nature* means the unit is read and written whole, its shape is
decided per document rather than per collection — a form a user designed, a
payload a provider sent, a page a renderer assembled — and no other entity
holds a reference into its interior. That is the test SD10 already states for
the JSON column, so the column is the first answer: one row, one `jsonb`
value, queried with SQL/JSON path under SD1, inside the row's transaction and
isolation predicate, in the row's backup. A document database is admitted
only when the column fails one of three tests, and the admission
([`admission.schema.json`](../contracts/json-document-storage/admission.schema.json))
names which; [the hybrid model](#the-hybrid-model-the-json-column-or-a-document-database)
below says which engine each test usually leads to:

| Test | The column is insufficient when | Typical role |
|---|---|---|
| `query_shape` | The product filters, sorts, ranks or aggregates *inside* the documents in ways the relational engine's JSON indexing cannot serve: relevance, faceting, geospatial ranking over a user-authored shape. | derived (a search index) |
| `scale` | The collection's volume or write rate measurably degrades the transactional rows it sits beside, and the documents relate to nothing but their owner. The declaration states the number. | primary (an archive) |
| `derivedness` | The data is a projection of many rows into one read-optimised shape, rebuilt from them, read far more than written, and the projection's cost is what the column cannot amortise. | derived (a read model) |

The admission is a file in the repository beside the service, validated
against the schema, and the rest of this document binds to it: role, engine,
collections with their schemas and indexes, rebuild job, backup posture. **A
document store with no admission is not admitted**, in the sense 057 JB3
gives an undeclared job: a store nobody declared is a store nobody decided.

### DS2. A document store is derived or primary, and most are derived

**Every admitted store is declared in one of two roles, and the role decides
whether its loss is an incident or an inconvenience.**

| Role | What it is | May be lost | Backup | Rebuilt by |
|---|---|---|---|---|
| `derived` | A projection of the system of record: a search index, a read model, a denormalised view. Every document can be recomputed from rows that still exist. | Yes. Its recovery is its rebuild. | None, by declaration ([`028-backup-and-recovery.md`](028-backup-and-recovery.md) reads the field). | A job (DS8). |
| `primary` | The only copy of what it holds. Nothing in the product can recompute it. | No. It is a database in every sense of 025 and of 028. | Required, declared under 028. | Nothing; that is the definition. |

**A store is `primary` only when it holds data with no relational integrity to
lose (DS1) that cannot be reproduced**: a user-authored form definition, an
archive of provider payloads the provider will not resend. A search index, a
pre-joined read model, a materialised report: derived, however expensive the
rebuild, because the rows exist. **A store declared `derived` whose rebuild
cannot in fact reproduce it is a `primary` store that was misdeclared and is
not being backed up**, and that is the first thing a reviewer checks on an
admission, as 057 JB2 makes a misdeclared `idempotent` job the first check.

A derived store has exactly one writer, the projection job (DS8). A server
never writes a derived document directly, because a write that bypasses the
projection is one the rebuild will not reproduce, which makes the store
primary by accident.

### DS3. Which structured-data rules transfer, and which do not

[`025-structured-data.md`](025-structured-data.md) says its rules do not
transfer to a document store by analogy. This rule says which transfer, by
argument, and which are left behind because the property they protect does
not exist here:

| 025 rule | Here | Why |
|---|---|---|
| SD1, the query is authored text | **Transfers in its reasoning.** The query is written in the engine's own language — a query document, a search DSL body, a path expression — committed as text, bound to values through the driver, and read in review as it will run. No object-document mapper writes it at runtime; a thin mapper from document to language type is admitted, as SD1 admits a row mapper. | The review, debugging and profiling surface is the query; and operator injection through a document engine's query language is injection: a value never enters a query by string assembly, and an untrusted key never becomes an operator. |
| SD1, keyset paging | **Transfers verbatim.** Paging is `id > $cursor ORDER BY id LIMIT n` on the UUIDv7 id (DS4), never a skip count. | A skip is linear in what it skips and unstable under writes. |
| SD2, an ordered `.sql` file | **Does not transfer.** There is no DDL, so there is no ordered history of it; DS6 and DS7 do what a migration did. | The artifact SD2 binds does not exist. |
| SD3, the migrate image and the credential split | **Changes shape.** The collection and index declaration is applied by a deployment-step job before rollout, under a declaration credential the runtime never holds (DS7). | The property survives: schema change is a discrete step, never at boot, under a credential the server cannot use. |
| SD4, expand-only | **Transfers in its reasoning.** A field is added within a version; a version is bumped over three releases; a rewrite is a backfill (DS6, DS7). | Rollback is safe only when the previous release's reader accepts what the current one wrote. |
| SD5, declared isolation levels | **Transfers verbatim.** Every scoped document carries the field for every containing level (DS4). | The joinless predicate is the point, and a document store cannot join at all. |
| SD6, isolation proven by enumeration | **Transfers verbatim**, the enumeration walking the admission's collections instead of a catalog (DS4). | There is no catalog; the admission is the catalog. |
| SD7, per-engine storage profile | **Transfers in form** (DS9). | The wrong native type is how the identifiers rules fail silently, in any engine. |
| SD8, seeds and fixtures | **Transfers verbatim.** Reference documents are applied through the declaration step and converge; fixtures never reach a store holding real data. | The same failure: a demo tenant found in production. |
| SD9, an attached resource reached with the least it needs | **Transfers verbatim.** Connection from the environment; a runtime role that cannot create collections or indexes; TLS; a bounded pool surfaced in readiness; query parameters never in telemetry. | SD9 restates [factor IV](https://12factor.net/backing-services), and the factor does not know what engine it is talking to. |
| SD10, the schema carries its invariants | **Does not transfer, and its absence is DS1's test.** A document store enforces none of them. | Data that needs an invariant is relational; this is the line, not a gap. |
| SD11, one request, one transaction | **Does not transfer.** The document is the unit of atomicity; a change that must be atomic across a row and a document is written to the row, and the document follows through the outbox and the projection. An engine's multi-document transaction is not relied on. | A property of one engine is not a property this contract may bind. |
| SD12, a deleted row is gone | **Transfers verbatim**, and further: a derived document is deleted when its source row is, by the projection; a store is never the reason a hard delete becomes soft. | The compliance sentence is the same sentence. |
| SD13, private to its service; tested on the real engine | **Transfers verbatim.** One service, one store, one credential, every process holding it built from the one repository; tests run against the engine the product runs, never an in-memory stand-in. | A shared collection is a shared table with a different name; a query proven against a substitute is a different query proven. |

### DS4. A document is identified and scoped the way a row is

**The document's id is the public id of the entity it describes where it
describes one, and a UUIDv7 minted for it otherwise; it is stored in the
engine's id field and is never the engine's generated identifier.** A derived
document for an invoice carries the invoice's public id, so the projection is
an upsert by key and the rebuild converges; a primary document that is its
own entity is minted a UUIDv7 per [`020-identifiers.md`](020-identifiers.md)
IP2. An engine's generated identifier is a second format outside IP2's table,
usually carrying a timestamp and a machine id a consumer would parse against
IP3, and it leaves the service no more than an integer key does under IP1.

**Every scoped document carries, as top-level fields, the tenant public id
and the id of every containing isolation level** the product declares under
[`025-structured-data.md`](025-structured-data.md) SD5, in the names the rows
use: `tenant_id`, and `client_org_id` beneath it where that level exists.
Every query carries the predicate on those fields; a missing isolation
context denies, as SD6 requires; there is no bypass. **Every index on a
scoped collection leads with the outermost isolation field**, for SD10's
reason, and because on a partitioned store that keeps a tenant together.

**Isolation is proven by enumeration**, as SD6 proves it: the suite reads the
collections from the admission and, for each scoped one, asserts that every
document carries every containing field, that every index leads with the
outermost, and that a query issued in one context sees no document of
another. A collection added tomorrow is covered the day it lands; a
collection used but not declared is the finding.

### DS5. Every document carries the envelope

**Whatever else a document holds, it carries the five fields of
[`document-envelope.schema.json`](../contracts/json-document-storage/document-envelope.schema.json)
at its top level:**

| Field | Value | Why it is in every document |
|---|---|---|
| `id` | The DS4 identifier, in the engine's id field. | The key the projection upserts by and the cursor pages by. |
| `tenant_id` | The tenant public id where the collection is scoped, plus the field for each contained level. | DS4. Absent only on a collection the admission marks unscoped; the corpus asks the admission, not the document, for permission to omit it. |
| `schema_version` | A positive integer: the version of the collection's schema the document was written under. | DS6. The only place an existing document's schema can be recorded, because no DDL recorded it. |
| `created_at` | RFC 3339 UTC instant per IP4, stored per the engine's profile. | SD10's two timestamps, for SD10's reason. |
| `updated_at` | As above, maintained on every write. | The projection's freshness (DS8) is measured from it. |

The envelope schema is the one schema under `contracts/` that is **open**:
the body belongs to the collection's own versioned schema, and the envelope
only says what must be present around it. Every version of a collection's
schema keeps these five fields with these meanings, so a reader can read the
envelope of a document whose version it does not know and refuse it by name
(DS6). Nothing in the envelope is a soft-delete marker: SD12 transfers.

### DS6. The schema lives in the documents, and a reader honours a version window

**A document store has no schema to migrate, so the schema is versioned per
collection, every document says which version it is, and the discipline SD4
puts on DDL is put here on the reader and the writer.**

- **Within a version, change is additive.** A new *optional* field is added
  to the collection's schema without a version change, per PC6, and a reader
  ignores any field it does not know. A reader that refuses a document for
  carrying a field its schema does not list has made every additive change a
  breaking one; the corpus's detector case catches exactly that reader.
- **A version is minted for a change that is not additive**: a field becomes
  required, is removed, renamed, retyped, or changes meaning. The new version
  gets a new schema under a new URI.
- **A reader accepts the current version and the one before it, and refuses
  everything else by name.** A document above the window may carry a required
  field the reader cannot interpret; one below it is a document the backfill
  (DS7) should have rewritten. Either is refused with the version named, never
  read on a guess, because a document misread silently is corrupted on its
  next write. A document at the previous version is upgraded on read with the
  current version's defaults and is not rewritten by the reader: a read path
  that writes fails under a read-only credential.
- **A version bump is three releases, for SD4's reason.** Release one ships a
  reader that accepts `N` and `N+1` and a writer still writing `N`. Release
  two writes `N+1` and runs the backfill (DS7). Release three drops `N`, only
  after the backfill has reported nothing left. A release that first accepts
  `N+1` and first writes it at once fails during its own rollout, while
  replicas of the previous release still read; a release that drops `N`
  before the backfill completes refuses the documents it left behind. The
  corpus's `rollouts` part decides both.

Each version's schema is a JSON Schema in the repository, named in the
admission against its number, and the reader validates a document against it
before the body of any handler or job runs — 057 JB1's rule for a document.

### DS7. A rewrite is a backfill job, and the declaration is applied at deployment

**Existing documents are rewritten by a job under 057 JB10 — long,
single-flight, on demand, idempotent, rate-bounded, in keyset batches of the
id, run until it reports nothing left — and never by a script.** A version
bump's rewrite, a field's population, a re-projection after a bug: each is
that job, declared under JB3, leaving JB5's run record, resumable from JB7's
checkpoint. A store with no migration history has nothing else that could
say the rewrite happened.

**The collection and index declaration is the document store's migrate
step.** The admission names each collection, its current schema version, its
indexes and any reference documents; a deployment-triggered job —
`documents.declare`, `once_ever`, blocking, `single_flight`, idempotent —
applies it before rollout, in the same position as `schema.migrate`, and
converges: what exists is left alone, what is missing is created, and nothing
is dropped without the `-- expand-only-ok: <release>` reason SD4 requires of
a `DROP`, because an index the previous release's queries depend on is a
column that release reads. The job runs under a **declaration credential**
that can create collections and indexes and that the runtime credential lacks
(SD3's split, SD9's least privilege), and it ships in the migrate image,
which exists to hold what the server must never see. The declaration is a
desired state, not a sequence of steps, so it has no ordered file history;
the run record of `documents.declare` per release is the history.

### DS8. A derived store is rebuilt by a job, its freshness is watched, and it is not backed up

**A derived store is written by a projection and recreated by a rebuild, both
jobs, both declared in the admission by name.**

- **The projection** is a per-event job in the service's pool, consuming the
  service's own events through the outbox
  ([`055-messaging.md`](055-messaging.md) AM4): a row changes, the event is
  produced in that transaction, the projection upserts the document by its id
  (DS4), idempotent under JB2 because the upsert is keyed. The store lags the
  record by exactly the queue's lag, and a wrong document is a projection
  bug, never a lost write.
- **The rebuild** is `documents.rebuild` — `on_demand`, `single_flight`,
  `long`, `idempotent`, JB10's shape — which walks the system of record in
  keyset batches and re-projects every document, converging on what the
  projection would have produced. It is the store's recovery, exercised by
  [`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s drill as a
  rebuild into a scratch store and a comparison.
- **Freshness is a periodic job's success**, in JB8's pattern:
  `documents.reconcile` compares a sample of the record against the store on
  a schedule and succeeds when the store is within the declared lag; its
  `stale_after` is what alerts. A drifted store produces no error of its own,
  and JB8 exists for the failure that produces nothing.
- **It is excluded from backup by declaration.** The admission declares
  `backup: rebuild` and names the rebuild job, and that is what 028 reads to
  leave the store out. A derived store that is backed up has two recovery
  paths, and a restore of a stale copy over a live record is a corruption.

### DS9. An engine is admitted by a storage-profile entry

**No engine is mandated, and no engine is admitted until
[`storage-profiles.json`](../contracts/json-document-storage/storage-profiles.json)
carries its entry**, in the form [`025-structured-data.md`](025-structured-data.md)
SD7 established: for each primitive the native representation it lands in,
and why the obvious alternative is wrong. An entry fixes how the DS4
identifier is stored and which engine identifier is not used; how IP4
instants land, at what precision; that the isolation fields are top-level,
indexed and lead every index on a scoped collection; the form
`documents.declare` renders indexes into; what "authored text" is for the
engine's query language under DS3; the engine's own ceiling, so DS10's sits
under it; which roles the engine may take — a search engine is a projection
by construction and is `derived` only; and whether it is admitted as a
profile of a multi-implementation protocol or as a single implementation. The
file today carries a general-purpose document engine admitted as a
wire-protocol profile, a key-value document store, and two search engines,
each admitted as a single implementation; [the hybrid model](#the-hybrid-model-the-json-column-or-a-document-database)
says what each is for. An engine not in the file is admitted by adding its
entry, in its own change, with every field filled in — the door SD7 leaves
open.

### DS10. A document is not a blob, and a blob is not a document

**A document body larger than 256 KiB is a blob under
[`026-blob-storage.md`](026-blob-storage.md), and the document carries the
blob's reference rather than its content.** A document is read, indexed,
cached and replicated whole; past a few hundred kibibytes it is being used as
a file, and every read of its metadata pays for its content. The ceiling sits
well below any admitted engine's own limit because that limit is what the
engine survives, not what a design targets. The admission states each
collection's ceiling at or below 256 KiB, the writer enforces it, and a
document that would exceed it is refused rather than truncated. The rule
holds in the other direction: a document store never holds encoded file
content — a base64 image in a JSON field is a blob that escaped its standard
— and a blob store never holds a record queried by field.

## The hybrid model: the JSON column or a document database

The model has two halves and a default. **The relational store holds every
row and, in its JSON column, every JSON document that can live beside its
owner**: that is the default, and no declaration is needed for it. **A
document database is attached beside the relational store** — never instead
of it — for the collections the column cannot serve, and each such store is
one admission (DS1) naming the test the column failed. A product may run
several: a search engine for its index and a document engine for its archive,
each its own backing service under [`025-structured-data.md`](025-structured-data.md)
SD13. What a product never does is move its rows into a document database
because the documents are there.

### Stay on the JSON column when

- the document is read and written whole, beside the row that owns it, and
  the reads that reach inside it are by a handful of known paths a JSON index
  serves;
- the collection's size and write rate are a fraction of the table it sits
  in, and nobody has a number that says otherwise;
- the document must change in the same transaction as its owner, or its
  isolation must be the row's predicate and nothing looser;
- the product has one persistence engine today and this would be the second.
  The second engine is a second backup, a second credential split, a second
  profile, a second failure mode in every drill; it is bought with a stated
  reason, not with a preference.

### Move to a document database when the column fails a test, and choose by the test

| Engine class | Examples admitted in [`storage-profiles.json`](../contracts/json-document-storage/storage-profiles.json) | Answers | Role | What it gives up |
|---|---|---|---|---|
| **General-purpose document engine** | The engine behind the MongoDB wire protocol, admitted as a protocol profile because several servers implement it independently — a repository moves between them by connection string | `scale`: a large, write-heavy collection of self-contained documents that relates to nothing but its owner, queried by many interior fields with secondary indexes, whose volume is degrading the transactional tables beside it. `query_shape` where the shape is rich secondary indexing over per-document shapes rather than relevance. | `primary` or `derived` | Foreign keys, cross-document uniqueness, checks, a transaction with the owner row (DS3: SD10 and SD11 do not transfer). |
| **Key-value document store** | DynamoDB, admitted as a single implementation | `scale` at the far end: a collection accessed by known keys along access patterns designed up front — a per-tenant event log, a session-shaped record, a device's last-known state — at a write rate the relational engine will not sustain, with no ad-hoc query at all. | `primary` (its own copy) or `derived` (a keyed read model) | Every query the design did not anticipate; secondary indexes are declared and paid for; no interior query language. |
| **Search engine** | Elasticsearch and OpenSearch, each a single implementation — they share a lineage and have diverged | `query_shape`: relevance ranking, full-text analysis, faceting, aggregation and geospatial ranking over user-authored shapes, which the relational engine's JSON indexing cannot serve. | `derived` only, by construction | Durability as a system of record: an index is a projection, rebuilt from rows (DS8), and the profile admits no other role. |

Two of the three tests carry a number. `scale` is stated in the admission —
the collection's size and write rate, and what they did to the table beside
them — because "it will be big" is a forecast and not a test. `derivedness`
is stated as the read-to-write ratio and the cost of the join the projection
replaces. `query_shape` is stated as the query the column could not serve,
committed as the text DS3 requires, so a reviewer can try it against the
column and agree.

### The engine follows the data; examples

The admission test is easier to apply from examples than from its
definition. Read the data, and the store and the role follow.

| Data | Store | Role | Why |
|---|---|---|---|
| A user-authored form definition, rendered whole, beside its owner row | relational, JSON column | — | SD10's rule exactly: a document by nature, held inside the owner's transaction and isolation. |
| The same, in a product that searches inside thousands of definitions by field type and label | general-purpose document engine | `primary` | The column fails `query_shape` on secondary indexing over per-document shapes; the definitions are the only copy. |
| Full-text search over invoices, contacts and notes | search engine | `derived` | A search index is a projection; the rows exist. |
| A dashboard read model joining six tables, read a thousand times per write | general-purpose document engine, or a key-value store where the reads are by key alone | `derived` | `derivedness`: the projection is the cost the column cannot amortise. |
| A verbatim archive of every provider payload, kept for dispute | JSON column; a general-purpose document engine on stated `scale` | `primary` if moved | Relates to nothing but its owner and is never reproduced; the column first, the store when the number is stated. |
| A device's last-known state, one record per device, written every few seconds across a large estate | key-value document store on stated `scale` | `primary` | Known key, one access pattern, a write rate that is the test; nothing queries across devices except a job that walks keys. |
| An invoice with lines and totals | relational | — | Money, foreign keys, uniqueness: SD10's invariants, DS1's line. |
| Audit events | relational; a search index over them `derived` | — | [`080-audit.md`](080-audit.md) AE6's append-only grant is a role privilege the relational engine holds and a document store does not. |
| An uploaded PDF, a scanned contract, a spreadsheet, or a generated 3 MiB export | blob store under [`026-blob-storage.md`](026-blob-storage.md) | — | A file is not a document in this document's sense, whatever a person calls it; the row holds the reference. |

## The artifacts

Per PC3, under [`contracts/json-document-storage/`](../contracts/json-document-storage/):

- **`admission.schema.json`** — DS1's declaration: engine, role, the test the
  column failed, the collections with scoping, id source, schema versions by
  URI, indexes and ceiling, and the fields the role requires — a `derived`
  store names its system of record and its projection, rebuild and reconcile
  jobs and declares `backup: rebuild`; a `primary` store declares
  `backup: snapshot` and names no rebuild.
- **`document-envelope.schema.json`** — DS5's five fields, with `$ref`s into
  the identifiers and observability contracts, open to the collection's body.
- **`storage-profiles.json`** — DS9's table as data, in the form of 025's.
- **`corpus.json`** — four parts. `admissions`: declarations the schema
  accepts and rejects, plus four judgments the runner makes against the
  profile and across fields, each saying so. `envelopes`: documents the
  envelope accepts and rejects, plus two delegated to the admission — a scoped
  document without its tenant field, a document over its ceiling.
  `evolution`: what a reader accepts, upgrades or refuses and why; **one case
  is a detector** — a current-version document carrying a field the schema
  does not list, which a reader that closes its schema refuses while passing
  every other case. `rollouts`: release sequences judged safe or unsafe by
  whether any live reader meets a version it refuses.

## Enforcement

Every DS rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. Mechanically
checkable, and first to move to a gate: an admission present and valid for
every document store a service attaches (DS1, DS2), the envelope on every
sampled document (DS5), the reader's window and its tolerance of unknown
fields under the `evolution` corpus (DS6), the isolation enumeration over the
declared collections (DS4), and the admission's engine against the profile
file (DS9). Review questions, said so in the ledger row: whether a store
declared `derived` is genuinely rebuildable (DS2), whether a query was
authored as text or assembled by a mapper (DS3 — a gate reading the source
would be the PC4 violation), whether the projection is the only writer (DS8),
and whether a document over the ceiling was refused rather than truncated
(DS10).

## Decisions

- **The JSON column is the first answer and the store is the exception**
  (2026-09-02). Admitting a store wherever data is document-shaped leaves the
  transactional, isolation and backup guarantees of the row behind for data
  that could have kept them, and gives up the one standard query language. A
  store states which of three tests the column failed, so the decision is
  reviewable rather than a default.
- **The hybrid model names engine classes and their tests** (2026-09-03). A
  standard that admitted "a document store" without saying which kind left
  the choice between a search engine and a document engine to whoever built
  the feature, and the two answer different tests and take different roles.
  Naming the classes, with the admitted engines as examples and the test each
  answers, makes the column-versus-store decision and the which-store decision
  both reviewable. The examples are engines, not endorsements: an engine is
  admitted by its profile entry (DS9), and the class is what the standard
  binds to.
- **A document is a JSON document, and never a file** (2026-09-03). The word
  carries the opposite meaning to most readers, so the standard says which it
  means in its title and its first paragraph, and hands every file to 026.
- **Two roles, and the role decides backup** (2026-09-02). One concept would
  carry the weight of a system of record onto every search index, or the
  looseness of a cache onto the only copy of a user's work. Splitting on
  rebuildability makes the common case cheap and hands 028 one field to read.
- **Additive within a version, three releases for a bump, readers accept two
  versions** (2026-09-02). The alternative — bump on every change and accept
  any version the reader can parse — makes the number say nothing and leaves
  the reader guessing at a field it does not know. This is PC6 and SD4
  applied where the schema has nowhere else to live.
- **The declaration step is a deployment job in the migrate image**
  (2026-09-02). Indexes applied at boot are the replica race SD3 removed;
  from a script, a step with no run record; under the server's credential, a
  server that can create indexes, which SD9 forbids.
- **A derived store has no backup** (2026-09-02). Two recovery paths for one
  store means a restore can put a stale copy in front of a live record; the
  rebuild, exercised as a drill, is the only recovery whose result is the
  truth by construction.
- **256 KiB is the document ceiling** (2026-09-02). Large enough for any
  record a person reads or a form a person designs; small enough that a
  document is never a file; well under any admitted engine's limit, so that
  limit is never what stops a document growing.

## Out of scope, deliberately

- **The relational store.** [`025-structured-data.md`](025-structured-data.md),
  in full; this document borrows its rules by name and adds none to it.
- **Blobs, files and objects — including every file a person calls a
  document.** [`026-blob-storage.md`](026-blob-storage.md)'s; DS10 only draws
  the line and names the size.
- **Backup mechanism, objectives and the restore drill.**
  [`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s; this document
  hands it one declared field per store and the rebuild job for a derived one.
- **Caches and key-value stores.** A different kind of stateful server under
  [`000-platform.md`](000-platform.md#terms), with different loss semantics.
- **Erasure across a document store.** The [`082-data-subject-rights.md`](082-data-subject-rights.md)'s; SD12 transferring is what
  makes a document erasable.
