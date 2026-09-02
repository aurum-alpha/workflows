# Blob storage: the S3 profile, what a stored object is, and how it is referenced

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/blob-storage/`](../contracts/blob-storage/). *Service*, *server*,
*worker*, *job*, *backing service*, *credential* and *environment* are used in
the senses [`000-platform.md`](000-platform.md#terms) defines. Ids and
timestamps are [`020-identifiers.md`](020-identifiers.md)'s; the row that owns
an object, its isolation and its deletion are
[`025-structured-data.md`](025-structured-data.md)'s; the check before every
read is [`070-rbac.md`](070-rbac.md)'s; the jobs are [`057-jobs.md`](057-jobs.md)'s.

This document governs **the stored object**: a file a service keeps in an
object store — an upload, an export, a generated document, a firmware image.
It defines the protocol the store speaks, what a bucket is to a service, how
an object is keyed, what the application records about it, how it is read,
how it arrives, how it is scanned, and how it leaves. **What it does not define
is structured data, documents, or backup**: rows are
[`025-structured-data.md`](025-structured-data.md)'s, schema-per-document data
is [`027-document-storage.md`](027-document-storage.md)'s, and a bucket's
copies and their restoration are
[`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s.

## Why this exists

Every product stores a file eventually: an attachment on a record, a logo, an
export someone asked for. The need arrives one feature at a time, each time
with a cheapest answer, and each cheapest answer fails as a general property.

**A column of bytes in the relational database** puts every large object
through the connection pool, the transaction log, the backup and the replica,
so a table of receipts decides the restore time of the ledger beside it.
**A directory on the server's disk** makes the server stateful: the second
replica cannot see the first one's files and a redeploy loses data. **A
bucket with a public URL stored in the row** makes the URL the credential —
anyone who has seen it reads the object for as long as it exists — and
persists the bucket name and hostname in every row of every environment.
**Trusting the browser's `Content-Type`** stores whatever a client says it
sent, so a file declared as an image is whatever the uploader wanted the next
reader's browser to execute.

None of these is a failure of care. Each is what happens when the questions
have not been asked: what protocol the store speaks, whose the bucket is, what
a key is made of, what the application records, who decides a read and for
how long, how the server learns what arrived, and what deletes the bytes.

### The standards evaluated first, per PC2

**The S3 API is the storage protocol, adopted as a profile.** It is a de facto
standard with many independent server implementations — the originating
vendor's, every other major cloud's compatibility layer, several self-hosted
open-source servers — and one client per language that speaks to all of them.
It already defines what this document would otherwise invent: an object as a
key, bytes and a content type; a signature that can be handed to a third
party as a URL with an expiry; multipart upload; a checksum the store verifies
on write and reports on read; default encryption; lifecycle rules. BS1 pins
the options it leaves open. The alternatives were a filesystem abstraction,
with no signed-URL primitive and no lifecycle, and a vendor SDK's object
model, the framework problem of [`000-platform.md`](000-platform.md) PC1.

**Content-Disposition is [RFC 6266](https://www.rfc-editor.org/rfc/rfc6266)**
with `filename*` per [RFC 8187](https://www.rfc-editor.org/rfc/rfc8187),
because a non-ASCII filename is the ordinary case and the two together are
the only form every browser reads. **Sniffing follows the
[MIME Sniffing standard](https://mimesniff.spec.whatwg.org/)**, because that
is what the browser at the other end does with the bytes. **Errors are
[`050-http.md`](050-http.md) HA3's**, and tenancy, deletion and privacy
transfer from [`025-structured-data.md`](025-structured-data.md) SD6, SD12
and SD13 rather than being restated.

**What no standard covers** is the relationship between the bytes and the
application's data, and that is what this document invents: the object
reference and the rule that the row is the truth (BS4), the two-phase upload
with the server's own verification (BS6), the scan posture (BS7), and
deletion and purge through the outbox and a periodic job (BS8).

## The rules

### BS1. The S3 API is the storage protocol, behind a boundary module

**Every object a service stores is stored through the S3 API**, under this
profile, so that "we use S3" unpinned does not become one profile per
repository:

| Choice the API leaves open | This profile pins |
|---|---|
| Signing | Signature Version 4. A presigned URL is a SigV4 query-string signature with an explicit `X-Amz-Expires`. |
| Addressing | Endpoint, region, bucket and addressing style are configuration per [`030-service.md`](030-service.md) SC3 — `BLOB_ENDPOINT`, `BLOB_REGION`, `BLOB_BUCKET` — and appear in no code and no row. |
| Operations used | `PutObject`, `HeadObject`, `GetObject` (ranged), `DeleteObject`, the multipart set, `ListObjectsV2` for the purge job alone, and presigning of `PutObject` and `GetObject`. |
| Checksums | SHA-256, declared by the client at intent and signed onto the `PutObject` as `x-amz-checksum-sha256` so the store refuses a mismatching write; read back by `HeadObject` at confirm. |
| Consistency | Strong read-after-write for `HeadObject` after `PutObject` is required of the backing service, because BS6's confirm depends on it. |
| Bucket configuration | Default encryption (BS9), lifecycle rules (BS8) and the public-access block (BS2) are the platform's to set on the bucket, never the application's per request. |
| Not used | ACLs, anonymous-read policies, static website hosting, object tagging or `x-amz-meta-*` as a source of truth, and any operation outside the set above. |

**The client library lives behind one boundary module per service, and a
vendor type never appears in a domain signature.** The domain asks the module
for an intent, a presigned read, a head, a delete; the module speaks S3. This
is PC1's *contract, never a tool* at the storage boundary: a vendor swap is
configuration plus one module. A gate cannot check it without reading source
(PC4), so it is the review question on every diff that imports the client.

### BS2. One bucket per service per environment, private, never shared

**A bucket is a backing service** in the sense of
[factor IV](https://12factor.net/backing-services) and
[`000-platform.md`](000-platform.md#terms): attached by configuration, owned
by exactly one service, reached with a credential that is that service's and
present in no other service's deployables. [`025-structured-data.md`](025-structured-data.md)
SD13 states this for the database and the reasoning transfers whole: a bucket
two services write is a shared table with a different name. Two services that
need the same bytes exchange a message carrying an object id, and the consumer
asks the owning service's API for a presigned read (BS5).

**One bucket per environment.** Environments differ only in configuration
([factor X](https://12factor.net/dev-prod-parity)), and a bucket shared
between them is where a staging purge deletes a production object. The name
is `BLOB_BUCKET`; the key (BS3) never encodes the environment.

**Which images carry the credential** follows
[`035-workers.md`](035-workers.md) WK8: the server, which issues presigns and
confirms uploads, and the pool, which runs the scan, delete and purge jobs;
the migrate image never. Per [`010-ci.md`](010-ci.md) Principle 15 the
credential is a surface an image is cut on; no image contains one.

**The bucket is never public.** The public-access block is on; no ACL and no
policy grants anonymous read; website hosting is off. Every read is a
presigned GET issued after an authorization check (BS5). What a product
serves without a check — its bundle, its marketing images — is a release
artifact under [`010-ci.md`](010-ci.md), not an object under this one.

### BS3. The key is tenant, entity and object id, and carries nothing else

The grammar is [`key.schema.json`](../contracts/blob-storage/key.schema.json):
`<tenant public id>/<entity>/<object public id>`.

| Segment | Form | Why |
|---|---|---|
| tenant | The tenant's public id, any [`020-identifiers.md`](020-identifiers.md) IP2 format | Lifecycle rules and the purge sweep run per tenant, and a tenant leaving is a prefix. Omitted, with its slash, only where the service has no tenant level in its SD5 declaration. |
| entity | A `snake_case` noun in the form [`025-structured-data.md`](025-structured-data.md) SD10 gives table names — `invoice_attachments` | It names the upload policy entry that governs the object (BS6) and the owning table, in one spelling. |
| object id | A UUIDv7 per IP2, minted by the server at intent | Keys under one entity sort by creation, so a sweep is a keyset walk — SD1's paging argument applied to a bucket listing. |

**No filename, no extension, no date path, no personal data.** The uploader's
filename is `original_filename` on the reference (BS4) and builds
`Content-Disposition` at read time (BS5): in a key it is user-chosen bytes in
a storage address — usually personal data, often not unique — and a key is
immutable while a file can be renamed. An extension is a second, unverified
statement of the content type. A date path duplicates what the UUIDv7 already
orders. **The key never appears in an API**; the object id does, per IP3.

### BS4. The application stores a reference, and the row is the source of truth

**What a service records about an object is an object reference, shaped by
[`object-reference.schema.json`](../contracts/blob-storage/object-reference.schema.json),
in a row of its own database that owns the object.** The shape is closed, so
a URL, a bucket name or an endpoint cannot enter it under any name. It
carries: `id`, the object public id, equal to the key's final segment; `key`
and `tenant_id`, the latter equal to the key's first segment and the SD5
isolation column; `content_type`, one verified media type; `size_bytes` and
`checksum` as storage reports them — `sha256:<hex>`, or the multipart
composite `sha256-<n>:<hex>`; `original_filename`, display metadata and the
source of `Content-Disposition`, absent for a generated object; `status`,
`pending` then `stored`; `scan`, one of `not_required`, `pending`, `clean`,
`infected` (BS7); and `created_at` and `stored_at`, the second present
exactly when `stored`.

**Never a URL.** A presigned URL is a bearer credential with a lifetime, so a
stored one is expired or leaked. A plain bucket URL is a hostname and a bucket
name — BS2's configuration — persisted per row in every environment and every
backup. The server builds a URL from the key and the environment's
configuration at the moment one is needed, and discards it.

**The row is the truth.** An object with no row is an orphan and BS8 removes
it; a row whose object is absent is a pending upload inside its lifetime, or a
defect the purge job reports. Nothing reads the bucket to learn what a tenant
has; it reads the table. The key is bucket-agnostic for the same reason: a
database restored beside a copied bucket resolves every reference without
rewriting a row, which [`028-backup-and-recovery.md`](028-backup-and-recovery.md)
needs. Whether the reference is one `objects` table or columns on the owning
row is the repository's choice; that deleting the owner deletes the object
(BS8) and that the reference lives in the service's own database (SD13) are
not.

### BS5. Reads are short-lived presigned GETs issued after the authorization check

**A client reads an object through a URL the server signs for it, after
`check(subject, permission, scope)` on the owning entity has passed
([`070-rbac.md`](070-rbac.md) RB7) and the row's `tenant_id` matches the
request's tenant context (BS10).** Nothing is issued for a row that is not
`stored`, or whose scan is `pending` or `infected` (BS7). The endpoint is the
owning entity's under [`050-http.md`](050-http.md); it returns the URL and
its expiry as JSON, or `303 See Other` for a navigation; a refusal is an HA3
problem.

**The lifetime is the policy's `presign_get_ttl`, default fifteen minutes,
ceiling one hour**; a caller may ask for less and never for more. The URL is
a credential: whoever holds it reads, and its expiry is its only revocation.
Fifteen minutes covers a click and a page of thumbnails; an hour bounds what
a leaked URL is worth; a page open longer asks again, and the check runs
again, which is what a revoked grant needs.

**The server sets the response headers, never the store's guess.** The
presign carries `response-content-type` from the row and
`response-content-disposition` built from it: `attachment` by default,
`inline` only where the policy declared it over types a browser renders
without executing; `filename` as an ASCII fallback with non-ASCII, quotes and
backslashes replaced, `filename*` in RFC 8187 form, and the object id where
there is no filename. **The presigned URL is never logged, audited or
stored**; log lines and audit events carry the object id. An ordinary read is
not audited ([`080-audit.md`](080-audit.md) AE5); a bulk export delivered as
an object is on AE5's floor. Proxying bytes through the server is admitted
where a consumer cannot follow a redirect, stated in **Conventions**.

### BS6. Uploads are two-phase, and the server verifies what the client declared

**An upload is an intent, a direct write to storage, and a confirm.** Bytes
never pass through the server: a server that receives uploads holds each one
for its duration, times out on the large ones, and moves every byte twice.

1. **Intent.** The client `POST`s to the owning entity's endpoint with the
   declared `content_type`, `size_bytes`, `checksum` and `original_filename`.
   The server runs the create check under 070, reads the entity's entry in
   the upload policy, refuses a type outside the admitted set or a size above
   `max_size_bytes` with an HA3 problem, mints the object id, writes the
   `pending` row, and returns a presigned `PutObject` with the content type
   and checksum in its signed headers, expiring with the policy's `intent_ttl`
   (default one hour) — or, above `multipart_threshold_bytes`, a multipart
   upload: the upload id, the part size, a presigned `UploadPart` per part.
2. **Write.** The client writes to storage, which refuses a body whose SHA-256
   disagrees with the signed header.
3. **Confirm.** The client `POST`s the confirm. The server asks storage —
   `HeadObject` for the size and the checksum the store computed — and reads
   the object's first bytes itself to sniff the type. Size, checksum and type
   must each equal what the intent declared. A disagreement deletes the
   object, leaves the row `pending`, and answers `422` with a `type` naming
   which; the client may write again within the intent's lifetime. Agreement
   sets `stored` and `stored_at` and, where the policy requires a scan, writes
   `object.stored` to the outbox in the same transaction. A second confirm of
   a stored object returns the same answer.

**The server sniffs; it never trusts the declared type.** The declared type
becomes the `Content-Type` every later reader acts on: a PDF declared as an
image is stored under a lie every viewer believes, and HTML declared as
anything is script served from the product's storage. A text type is admitted
only where the bytes decode as text and match no binary signature; SVG and
HTML never pass through an entity whose policy names image types.
Disagreement is a refusal, never a silent correction: a corrected object is
one the client did not mean to send.

**Confirm is the signal because it is the portable one**: bucket event
notifications exist in several S3 implementations and in none the same way.
**The limits are declared per entity in
[`upload-policy.schema.json`](../contracts/blob-storage/upload-policy.schema.json)**,
committed, validated in CI, read at start; an entity absent from it accepts
no uploads, and wildcards are not admitted in the type set, for the reason
[`070-rbac.md`](070-rbac.md) RB6 gives.

### BS7. What one person uploads for another is scanned before it is served

**An entity whose audience is `others` declares `scan: true`, and its objects
are served only after the verdict is `clean`.** The policy schema holds the
posture — `others` without `scan` does not validate — so it is a fact in the
repository rather than a habit. An entity read only by its uploader may
decline: a profile photo shown to its owner is a vector to nobody.

**The mechanism is a job and a status.** Confirm writes `object.stored` to
the outbox (BS6); `object.scan` is a per-event, idempotent job the pool runs
([`057-jobs.md`](057-jobs.md) JB2, JB3), streaming the object to the scanner
and writing `clean` or `infected` on the row. The scanner is a backing
service or a library in the pool image — the repository's choice, and the
pool image's dependency closure is why it is not the server's
([`035-workers.md`](035-workers.md) WK2). `infected` deletes the object and
keeps the row, so a later read is refused for that reason, and the uploader
is told through the [`058-notifications.md`](058-notifications.md).
An unavailable scanner fails the job, retried under
[`055-messaging.md`](055-messaging.md) AM5; the object stays `pending`. The
verdict is never advisory: serve first and quarantine later has served the
file.

### BS8. Deleting the row deletes the object, and the purge job catches what slips

**Hard delete is the default**, as [`025-structured-data.md`](025-structured-data.md)
SD12 makes it for the row: *we do not hold data after its owner asked us not
to* has to be true of the bytes as well as the row that pointed at them.

**The mechanism is the outbox.** The transaction that deletes the owning row
writes `object.deleted` with the key to the outbox
([`055-messaging.md`](055-messaging.md) AM4); `object.delete` is a per-event,
idempotent job the pool runs — deleting what is gone is a no-op, the
exception JB2 names. The storage call is not inside the transaction because
SD11 forbids a network call there, and no ordering without the outbox loses
nothing: object first and a failed commit leaves a dangling row; row first
and the object after leaves an orphan on a crash between. The outbox is the
one construction in which the row and the intent to delete cannot separate.

**Retention past the row is the exception SD12 admits for soft delete, on the
same terms.** The entity's policy entry states `retention` with a reason and a
period; the row stays, scoped and erasable under the
[`082-data-subject-rights.md`](082-data-subject-rights.md). Object
lock is never on the working bucket, because this rule must be able to run.

**`object.purge` is a periodic job**, `single_flight`, `long`, `idempotent`,
with `stale_after` beside its schedule (JB8). It enumerates rather than
lists — the bucket by prefix in key order, the pending rows by `created_at` —
and acts on three findings:

| Finding | Action |
|---|---|
| A `pending` row older than `intent_ttl` | Delete the object if one arrived, then the row. |
| An object under a well-formed key with no row | Delete it, and count it: a client wrote to a presign whose intent never committed. |
| A row whose key prefix is not its `tenant_id` | Report it and touch nothing. It is a defect in the writer, not a job's to guess at. |
| An incomplete multipart upload | Invisible to `ListObjectsV2`, so a lifecycle rule on the bucket aborts it after a day: the one cleanup the job cannot do. |

### BS9. Encryption at rest is on, and versioning belongs to backup

**Every bucket has default encryption on**, under the platform's key
management, so the application sets no header and cannot opt an object out;
**every connection to the endpoint is TLS**, as SD9 requires of the database.

**Versioning is off by default.** Where a product turns it on it is a backup
mechanism, and [`028-backup-and-recovery.md`](028-backup-and-recovery.md)
governs what it retains and for how long. Two consequences hold here
regardless: the application reads only the current version and never exposes
a version id; and a `DeleteObject` on a versioned bucket leaves a delete
marker with the versions behind it, so BS8's hard delete completes only when
that standard's retention window has run — a window bounded by the erasure
obligations of [`080-audit.md`](080-audit.md) AE7.

### BS10. The key prefix is a convenience; the row and the check are the boundary

**The tenant boundary for an object is behavioural, proven the way
[`025-structured-data.md`](025-structured-data.md) SD6 proves it for rows: a
presign requested in one tenant's context is never issued for an object whose
row belongs to another, whatever the subject's grants elsewhere say.** The
server reads `tenant_id` from the row, compares it to the request's context,
and refuses on mismatch or on a missing context before it runs the permission
check. A platform-operator flag never bypasses; support access is consented,
time-boxed impersonation recorded per [`080-audit.md`](080-audit.md) AE2.

The prefix is not that boundary. It lets lifecycle and the purge sweep work
per tenant and makes an offboarding a prefix; a credential condition on it is
admitted as a backstop in the way SD6 admits row-level security, never as the
contract, because it is configuration outside the repository that nothing
here checks. A bucket per tenant is admitted where a product isolates by one
database per tenant, with the same costs. The gate enumerates: every tenant's
objects, each presign requested in every other tenant's context, all refused.

## The artifacts

Per PC3, under [`contracts/blob-storage/`](../contracts/blob-storage/):

- **`key.schema.json`** — BS3's grammar as `$defs`: the entity segment, the
  object id (a `$ref` into the identifiers contract's UUIDv7), the
  tenant-scoped and unscoped forms, and their union.
- **`object-reference.schema.json`** — BS4's reference, closed, with `$ref`s
  into the identifiers and observability contracts for ids, instants and the
  tenant id; the conditional rules that `stored` carries `stored_at` and a
  `pending` row carries no verdict; the media type and checksum grammars.
- **`upload-policy.schema.json`** — BS6's declaration: per entity the size
  ceiling, the closed type set, the audience, the scan flag, the disposition
  and an optional retention; per service the tenant scoping, the read
  lifetime bounded at the ceiling, the intent lifetime and the multipart
  threshold. The schema decides BS7's *others requires scan* and BS5's
  *inline only over inline-safe types*.
- **`corpus.json`** — five parts. `keys` and `policies` are schema-decided.
  `references` is schema-decided plus two equalities the schema cannot state:
  the key's final segment is the id, its first segment the tenant. `uploads`
  is a set of two-phase sequences with steps at stated seconds — a confirm
  without an upload; a size, a checksum and a type that disagree with
  storage; a late confirm; a scan refused until clean; an infected object
  deleted; an owner deleted through the outbox; an orphan; a multipart
  intent — with every step's result and the end state. `presign` is a set of
  read decisions: the lifetime issued, the `Content-Disposition` built, and
  the refusals for a pending object, a pending scan, an infected object, a
  missing permission, another tenant's row and a missing tenant context.

## Enforcement

Every BS rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. The
mechanically checkable parts, and therefore the first to move to a gate: the
key grammar and the reference shape against their schemas (BS3, BS4); the
upload policy against its schema, which decides the scan posture and the read
ceiling (BS5, BS6, BS7); and the `uploads` and `presign` corpus parts against
a running service under `job-contract-conformance`, where the two detectors
bite (BS6, BS7, BS10). The public-access block and default encryption are
configuration facts read from the platform (BS2, BS9). The review questions,
said so in the ledger row: that no vendor type crosses the boundary module
(BS1, a PC4 matter), that the row and the outbox message share a transaction
(BS8, as AM4), and that a `retention` reason is true.

## Decisions

- **The S3 API is the protocol, adopted as a profile** (2026-09-02). The one
  object-storage interface with many independent implementations and a client
  per language, already carrying the signed URL, multipart, the verified
  checksum and the lifecycle rule; the alternatives lack the primitive or are
  the framework problem.
- **One bucket per service per environment** (2026-09-02). Prefixes per
  service in a shared bucket make the credential boundary a policy condition
  outside the repository; a bucket shared across environments is where a
  staging job deletes production.
- **Tenant, entity and UUIDv7 in the key, and no filename** (2026-09-02). The
  filename is personal data, renameable and not unique; the extension is an
  unverified type claim; a date path duplicates what the UUIDv7 orders.
- **A reference and never a URL** (2026-09-02). A presigned URL is a
  credential and a plain one is configuration; both leak through the row.
- **Fifteen minutes default, one hour ceiling** (2026-09-02). The lifetime is
  a bearer URL's only revocation; fifteen minutes covers a click and a page,
  an hour bounds a leak, and a longer read is a page asking again. Refusing
  rather than clamping a longer request makes the assumption visible.
- **Two-phase upload with the server's own sniff; disagreement is a refusal**
  (2026-09-02). Direct-to-storage keeps bytes out of the request process; the
  intent row first keeps the row the truth from the first byte; the confirm
  is the one portable upload signal. The server sniffs because the declared
  type is what every later browser acts on, and refuses rather than corrects
  because a corrected object is one the client did not mean to send. An
  implementation that trusts the declaration passes every other case.
- **Scan posture follows the audience; the verdict gates the read**
  (2026-09-02). Scanning everything taxes the photo only its owner sees;
  scanning nothing serves malware between users. The gate is a status on the
  row, not a promise about latency, so an absent scanner fails closed.
- **Hard delete through the outbox, never inline and never storage-first**
  (2026-09-02). SD11 forbids the network call in the transaction, and each
  inline ordering loses something on a failure between its two steps.
- **Encryption on at the bucket; versioning is backup's** (2026-09-02). A
  bucket default is a rule nobody can forget; versioning retains what BS8
  deleted, a backup property with an erasure cost, owned by the standard that
  owns retention windows.
- **The prefix is a convenience; the row and the check are the boundary**
  (2026-09-02). A credential condition on a prefix is configuration nothing in
  the repository checks; SD6's reasoning that isolation is a behaviour proven
  by enumeration transfers unchanged.

## Out of scope, deliberately

- **Backup, restore and versioning retention.**
  [`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s; this document
  supplies the bucket-agnostic key a restored database resolves with.
- **Export and erasure endpoints.** The
  [`082-data-subject-rights.md`](082-data-subject-rights.md)'s;
  this document supplies the delete those jobs call and the presigned read an
  export is delivered through.
- **Documents.** [`027-document-storage.md`](027-document-storage.md)'s; a
  document over the size that standard sets is an object with a reference.
- **Public asset delivery.** Release artifacts under [`010-ci.md`](010-ci.md),
  served without a check; not user data, not this bucket. A derived object —
  a thumbnail — is an object with its own reference, produced by a per-event
  job under [`057-jobs.md`](057-jobs.md).
