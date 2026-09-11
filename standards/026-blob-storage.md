# Blob storage: the S3 profile, what a stored object is, and how it is served through the service

## Why this exists

Every product stores a file eventually: an attachment on a record, a logo, an
export someone asked for. The need arrives one feature at a time, each time
with a cheapest answer. Each cheapest answer fails as a general property.

**A column of bytes in the relational database** puts every large object
through the connection pool, the transaction log, the backup and the replica.
So a table of receipts decides the restore time of the ledger beside it. **A
directory on the server's disk** makes the server stateful. The second
replica cannot see the first one's files, and a redeploy loses data.

**A bucket with a public URL stored in the row** makes the URL the
credential. Anyone who has seen it reads the object for as long as it exists.
It also persists the bucket name and hostname in every row of every
environment.

**A presigned URL handed to the browser** is the same failure with a timer on
it. For its lifetime the URL is a bearer credential nothing can revoke. It
puts the store's hostname on the internet. It appears in every browser
history, proxy log and screenshot between the click and the expiry.
**Trusting the browser's `Content-Type`** stores whatever a client says it
sent. So a file declared as an image is whatever the uploader wanted the next
reader's browser to execute.

None of these is a failure of care. Each is what happens when the questions
have not been asked. The questions are: what protocol the store speaks,
whose the bucket is, what a key is made of, what the application records.
Also: who decides a read and executes it, how the server knows what arrived,
and what deletes the bytes.

### The standards evaluated first, per PC2

**The S3 API is the storage protocol, adopted as a profile.** It is a de facto
standard with many independent server implementations. They are the
originating vendor's, every other major cloud's compatibility layer, and
several self-hosted open-source servers. There is one client per language
that speaks to all of them. It already defines what this document would
otherwise invent. The API defines an object as a key, bytes and a content
type; a streamed, ranged read; and multipart upload. It also defines a
checksum the store verifies on write and reports on read, default
encryption, and lifecycle rules.

BS1 pins the options it leaves open, and BS1 also names the one primitive of
the API this profile never uses. The alternatives were a filesystem
abstraction, with no verified checksum and no lifecycle, and a vendor SDK's
object model. The second is the framework problem of
[`000-platform.md`](000-platform.md) PC1.

**Content-Disposition is [RFC 6266](https://www.rfc-editor.org/rfc/rfc6266)**
with `filename*` per [RFC 8187](https://www.rfc-editor.org/rfc/rfc8187). A
non-ASCII filename is the ordinary case, and the two together are the only
form every browser reads. **Range requests are
[RFC 9110 §14](https://www.rfc-editor.org/rfc/rfc9110#section-14)**, passed
through to the store's ranged `GetObject`. A video seek and a resumed
download are ordinary reads. **Sniffing follows the
[MIME Sniffing standard](https://mimesniff.spec.whatwg.org/)**, because that
is what the browser at the other end does with the bytes. **Errors are
[`050-http.md`](050-http.md) HA3's**, and tenancy, deletion and privacy
transfer from [`025-structured-data.md`](025-structured-data.md) SD6, SD12
and SD13 rather than being restated.

**What no standard covers** is the relationship between the bytes and the
application's data, and that is what this document invents. It invents the
object reference and the rule that the row is the truth (BS4). It invents
the read the server executes after its own check (BS5), and the upload the
server verifies as it streams (BS6). It invents the scan posture (BS7), and
deletion and purge through the outbox and a periodic job (BS8).

## The rules

### BS1. The S3 API is the storage protocol, behind a boundary module

**Every object a service stores is stored through the S3 API**, under this
profile. Otherwise "we use S3" unpinned becomes one profile per repository:

| Choice the API leaves open | This profile pins |
|---|---|
| Signing | Signature Version 4, in request headers, by the service's own processes. **No query-string signature (a presigned URL) is ever produced**, for any operation, for any lifetime. |
| Addressing | Endpoint, region, bucket and addressing style are configuration per [`030-service.md`](030-service.md) SC3 (`BLOB_ENDPOINT`, `BLOB_REGION`, `BLOB_BUCKET`) and appear in no code, no row and no response. |
| Operations used | `PutObject`, `HeadObject`, `GetObject` (ranged), `DeleteObject`, the multipart set, and `ListObjectsV2` for the purge job alone. |
| Checksums | SHA-256, declared by the client with the upload and sent on the `PutObject` as `x-amz-checksum-sha256` so the store refuses a mismatching write; computed again by the server over the stream (BS6). |
| Consistency | Strong read-after-write for `HeadObject` after `PutObject` is required of the backing service, because BS6's verification depends on it. |
| Bucket configuration | Default encryption (BS9), lifecycle rules (BS8) and the public-access block (BS2) are the platform's to set on the bucket, never the application's per request. |
| Not used | Presigned URLs, ACLs, anonymous-read policies, static website hosting, object tagging or `x-amz-meta-*` as a source of truth, and any operation outside the set above. |

**The client library lives behind one boundary module per service, and a
vendor type never appears in a domain signature**. The domain asks the module
to put a stream, head, get a stream with an optional range, or delete; the
module speaks S3. The module has no operation that returns a URL, so a
presigned one cannot be issued by accident from a domain that never asked.
This is PC1's *contract, never a tool* at the storage boundary: a vendor swap
is configuration plus one module. A gate cannot check it without reading
source (PC4), so it is the review question on every diff that imports the
client.

### BS2. One bucket per service per environment, private, reachable from the service alone

**A bucket is a backing service** in the sense of
[factor IV](https://12factor.net/backing-services) and
[`000-platform.md`](000-platform.md#terms). It is attached by configuration
and owned by exactly one service. It is reached with a credential that is
that service's and present in no other service's deployables.
[`025-structured-data.md`](025-structured-data.md) SD13 states this for the
database and the reasoning transfers whole: a bucket two services write is a
shared table with a different name. Two services that need the same bytes
exchange a message carrying an object id. The consumer asks the owning
service's API for the object, which serves it (BS5).

**One bucket per environment.** Environments differ only in configuration
([factor X](https://12factor.net/dev-prod-parity)). A bucket shared between
them is where a staging purge deletes a production object. The name is
`BLOB_BUCKET`; the key (BS3) never encodes the environment.

**Which images carry the credential** follows
[`035-workers.md`](035-workers.md) WK8. The server carries it, because it
serves reads and receives uploads. The pool carries it, because it runs the
scan, delete and purge jobs. The migrate image never carries it. Per
[`010-ci.md`](010-ci.md) Principle 15 the credential is a surface an image is
cut on; no image contains one.

**The store is reachable from the service's processes and from nothing
else**. The public-access block is on; no ACL and no policy grants anonymous
read; website hosting is off. The endpoint sits on the service's private
network or behind an endpoint policy that admits the service's credential
alone. A client never connects to it, because a client is never given
anything to connect with. Every read is a request the server answers with the
bytes after an authorization check (BS5). Every write is a request the server
receives and forwards (BS6).

What a product serves without a check is a release artifact under
[`010-ci.md`](010-ci.md), not an object under this one. Its bundle and its
marketing images are examples.

### BS3. The key is tenant, entity and object id, and carries nothing else

The grammar is [`key.schema.json`](../contracts/blob-storage/key.schema.json):
`<tenant public id>/<entity>/<object public id>`.

| Segment | Form | Why |
|---|---|---|
| tenant | The tenant's public id, any [`020-identifiers.md`](020-identifiers.md) IP2 format | Lifecycle rules and the purge sweep run per tenant, and a tenant leaving is a prefix. Omitted, with its slash, only where the service has no tenant level in its SD5 declaration. |
| entity | A `snake_case` noun in the form [`025-structured-data.md`](025-structured-data.md) SD10 gives table names, for example `invoice_attachments` | It names the upload policy entry that governs the object (BS6) and the owning table, in one spelling. |
| object id | A UUIDv7 per IP2, minted by the server when the upload begins | Keys under one entity sort by creation, so a sweep is a keyset walk: SD1's paging argument applied to a bucket listing. |

**No filename, no extension, no date path, no personal data**. The uploader's
filename is `original_filename` on the reference (BS4) and builds
`Content-Disposition` at read time (BS5). In a key it is user-chosen bytes in
a storage address, usually personal data, often not unique. A key is
immutable while a file can be renamed. An extension is a second, unverified
statement of the content type. A date path duplicates what the UUIDv7 already
orders.

**The key never appears in an API**; the object id does, per IP3. The server
is the only thing that resolves one to the other.

### BS4. The application stores a reference, and the row is the source of truth

**What a service records about an object is an object reference, shaped by
[`object-reference.schema.json`](../contracts/blob-storage/object-reference.schema.json),
in a row of its own database that owns the object**. The shape is closed, so
a URL, a bucket name or an endpoint cannot enter it under any name. It
carries these fields:

- `id`, the object public id, equal to the key's final segment.
- `key` and `tenant_id`, the latter equal to the key's first segment and the
  SD5 isolation column.
- `content_type`, one verified media type.
- `size_bytes` and `checksum` as the server verified them: `sha256:<hex>`, or
  the multipart composite `sha256-<n>:<hex>`.
- `original_filename`, display metadata and the source of
  `Content-Disposition`, absent for a generated object.
- `status`, `pending` then `stored`.
- `scan`, one of `not_required`, `pending`, `clean`, `infected` (BS7).
- `created_at` and `stored_at`, the second present exactly when `stored`.

**Never a URL.** There is no URL for an object, anywhere: not in the row,
not in a response, not in a log line. A plain bucket URL is a hostname and a
bucket name, BS2's configuration, persisted per row in every environment and
every backup. A presigned one is a bearer credential, and BS5 issues none.
The only handle that exists outside the server is the object id, and it
means nothing without the row. The indirection is the security property.

**The row is the truth.** An object with no row is an orphan and BS8 removes
it. A row whose object is absent is an upload still in flight, or a defect
the purge job reports. Nothing reads the bucket to learn what a tenant has;
it reads the table.

The key is bucket-agnostic for the same reason. A database restored beside a
copied bucket resolves every reference without rewriting a row, which
[`028-backup-and-recovery.md`](028-backup-and-recovery.md) needs. Whether the
reference is one `objects` table or columns on the owning row is the
repository's choice. That deleting the owner deletes the object (BS8) and
that the reference lives in the service's own database (SD13) are not.

### BS5. Reads are served by the server, by object id, after the authorization check

**A client reads an object by requesting it from the owning entity's endpoint
under [`050-http.md`](050-http.md), by object id, and the server answers with
the bytes**. In order, on every request:

1. The server resolves the public id to its row in the service's own
   database; an id with no row is `404`.
2. It compares the row's `tenant_id` to the request's tenant context and
   refuses on mismatch or on a missing context (BS10).
3. It runs `check(subject, permission, scope)` on the owning entity
   ([`070-rbac.md`](070-rbac.md) RB7).
4. It refuses a row that is not `stored`, or whose scan is `pending` or
   `infected` (BS7), each as an HA3 problem naming which.
5. Only then does it call `GetObject` under the row's key and stream the body
   to the response.

**The response is the bytes, `200`, or `206` for a satisfied `Range`**. It is
never `302`, never a JSON body carrying a location, never anything a client
could use to reach the store without the server.

**The server streams; it does not buffer.** The object body is piped from
the store to the response as it arrives. So a gigabyte read costs the server
a connection and not a gigabyte of memory. A `Range` header is passed to
`GetObject` and the store's `Content-Range` is returned. That is what a
resumed download and a video seek need.

**The server sets the response headers from the row, never from the store's
guess**. `Content-Type` is the row's verified type. `Content-Length` is the
row's size or the range's.

`Content-Disposition` is built per RFC 6266. It is `attachment` by default,
and `inline` only where the policy declared it over types a browser renders
without executing. `filename` is an ASCII fallback with non-ASCII, quotes and
backslashes replaced, and `filename*` is in RFC 8187 form. The object id is
used where there is no filename. `Cache-Control` is `private, no-store`,
because the response was authorized for this subject at this moment and a
shared cache would serve it to the next one.

**Every read is a request the server saw**. The check runs at the moment of
the read, so a revoked grant is refused on the next request and not after a
timer. There is nothing to leak, because nothing was issued. The request log
carries the object id and the subject, which is an audit trail a URL in a
browser history is not. An ordinary read is not audited
([`080-audit.md`](080-audit.md) AE5); a bulk export delivered as an object is
on AE5's floor. The key never appears in a log line, an audit event or a
response.

**Another service reads the same way**. A consumer holding an object id from
a message (BS2) requests it from the owning service's API. It does so under
that API's own authentication, and receives the bytes. It never receives the
owning service's credential, a key, or a URL into the owning service's
bucket.

### BS6. Uploads pass through the server, which verifies what the client declared

**An upload is one request to the owning entity's endpoint. It carries the
declared `content_type`, `size_bytes`, `checksum` and `original_filename`
with the bytes, and the server writes the bytes to the store itself**. A
client never writes to the store, for the same reason it never reads from
it. There is nothing to write to that a client can reach.

1. **Before the first byte of the body**. The server runs the create check
   under 070 and reads the entity's entry in the upload policy. It refuses a
   type outside the admitted set or a declared size above `max_size_bytes`
   with an HA3 problem. At that point nothing has been written, and no row
   exists. It mints the object id and commits the `pending` row in its own
   transaction. So the row exists before any byte reaches the store, and the
   row is the truth from the first byte.
2. **As the body streams.** The server forwards the bytes to `PutObject`
   under the row's key, and above `multipart_threshold_bytes` as parts of a
   multipart upload. Meanwhile it computes the SHA-256, counts the bytes, and
   sniffs the first ones for the type. The declared checksum is sent as
   `x-amz-checksum-sha256`, so the store is a second verifier. A stream that
   passes `max_size_bytes`, or the declared size, is aborted there: the
   partial object or multipart upload is deleted and the request refused.
   The endpoint's body limit is the entity's `max_size_bytes`, not a
   framework default.
3. **At the end of the body.** Size, checksum and sniffed type must each
   equal what was declared. Agreement sets `stored` and `stored_at` and,
   where the policy requires a scan, writes `object.stored` to the outbox in
   the same transaction. The response is `201` with the reference's public
   fields (id, content type, size, filename, status, scan) and no key.
   Disagreement deletes the object, deletes the pending row, and answers
   `422` with a `type` naming which; the client uploads again, as a new
   object. A request repeated with the same `Idempotency-Key`
   ([`050-http.md`](050-http.md) HA6) returns the first request's answer.

**A body too large for one request arrives in ranges, to the same server**.
Where a client cannot hold one request open for the whole body, it sends the
body as ordered ranges to the upload endpoint. A mobile client and a
multi-gigabyte firmware image are the cases. Each range is a request the
server appends as a multipart part under the same `pending` row. A final
request completes it, at which point step 3 runs over the whole.

The row stays `pending` between ranges, and the purge job (BS8) removes it if
the client never finishes. The parts go to the store from the server and
from nowhere else.

**The server sniffs; it never trusts the declared type.** The declared type
becomes the `Content-Type` every later reader acts on. A PDF declared as an
image is stored under a lie every viewer believes. HTML declared as anything
is script served from the product's own origin.

A text type is admitted only where the bytes decode as text and match no
binary signature. SVG and HTML never pass through an entity whose policy
names image types. Disagreement is a refusal, never a silent correction: a
corrected object is one the client did not mean to send.

**The limits are declared per entity in
[`upload-policy.schema.json`](../contracts/blob-storage/upload-policy.schema.json)**,
committed, validated in CI, read at start. An entity absent from it accepts
no uploads. Wildcards are not admitted in the type set, for the reason
[`070-rbac.md`](070-rbac.md) RB6 gives.

**The cost is paid on purpose.** The server holds the connection for the
upload's duration and moves each byte twice, in and out. That is the price
of every byte the product stores having passed through a process the product
controls. The policy is enforced on the bytes rather than on a client's
promise, and no client can reach the store. A product whose upload volume
makes the server the bottleneck scales the server. The server is stateless
and scales by replica ([`030-service.md`](030-service.md)); the product does
not open the store.

### BS7. What one person uploads for another is scanned before it is served

**An entity whose audience is `others` declares `scan: true`, and its objects
are served only after the verdict is `clean`**. The policy schema holds the
posture: `others` without `scan` does not validate. So it is a fact in the
repository rather than a habit. An entity read only by its uploader is
permitted to decline: a profile photo shown to its owner is a vector to
nobody.

**The mechanism is a job and a status.** The upload's final transaction
writes `object.stored` to the outbox (BS6). `object.scan` is a per-event,
idempotent job the pool runs ([`057-jobs.md`](057-jobs.md) JB2, JB3). It
streams the object to the scanner and writes `clean` or `infected` on the
row. The scanner is a backing service or a library in the pool image, the
repository's choice. The pool image's dependency closure is why it is not the
server's ([`035-workers.md`](035-workers.md) WK2). `infected` deletes the
object and keeps the row, so a later read is refused for that reason.

The uploader is told through the
[`058-notifications.md`](058-notifications.md). An unavailable scanner fails
the job, retried under [`055-messaging.md`](055-messaging.md) AM5; the object
stays `pending`. The verdict is never advisory: serve first and quarantine
later has served the file.

### BS8. Deleting the row deletes the object, and the purge job catches what slips

**Hard delete is the default**, as [`025-structured-data.md`](025-structured-data.md)
SD12 makes it for the row. *We do not hold data after its owner asked us not
to* must be true of the bytes. It is not enough that it is true of the row
that pointed at them.

**The mechanism is the outbox.** The transaction that deletes the owning row
writes `object.deleted` with the key to the outbox
([`055-messaging.md`](055-messaging.md) AM4). `object.delete` is a per-event,
idempotent job the pool runs. Deleting what is gone is a no-op, the exception
JB2 names.

The storage call is not inside the transaction because SD11 forbids a
network call there. No ordering without the outbox loses nothing. Object
first and a failed commit leaves a dangling row. Row first and the object
after leaves an orphan on a crash between. The outbox is the one construction
in which the row and the intent to delete cannot separate.

**Retention past the row is the exception SD12 admits for soft delete, on the
same terms**. The entity's policy entry states `retention` with a reason and
a period. The row stays, scoped and erasable under the
[`082-data-subject-rights.md`](082-data-subject-rights.md). Object lock is
never on the working bucket, because this rule must be able to run.

**`object.purge` is a periodic job**, `single_flight`, `long`, `idempotent`,
with `stale_after` beside its schedule (JB8). It enumerates rather than
lists: the bucket by prefix in key order, the pending rows by `created_at`.
It acts on four findings:

| Finding | Action |
|---|---|
| A `pending` row older than `upload_ttl` | An upload the client never finished or a server that died mid-stream. Delete the object or abort the multipart upload if one exists, then the row. |
| An object under a well-formed key with no row | Delete it, and count it: a write outran a row transaction that never committed, which is a defect in the writer's ordering (BS6 step 1). |
| A row whose key prefix is not its `tenant_id` | Report it and touch nothing. It is a defect in the writer, not a job's to guess at. |
| An incomplete multipart upload with no row | Invisible to `ListObjectsV2`, so a lifecycle rule on the bucket aborts it after a day: the one cleanup the job cannot do. |

### BS9. Encryption at rest is on, and versioning belongs to backup

**Every bucket has default encryption on**, under the platform's key
management. So the application sets no header and cannot opt an object out.
**Every connection to the endpoint is TLS**, as SD9 requires of the database.

**Versioning is off by default**. Where a product turns it on it is a backup
mechanism, and [`028-backup-and-recovery.md`](028-backup-and-recovery.md)
governs what it retains and for how long. Two consequences hold here
regardless. The application reads only the current version and never exposes
a version id. A `DeleteObject` on a versioned bucket leaves a delete marker
with the versions behind it. So BS8's hard delete completes only when that
standard's retention window has run, a window bounded by the erasure
obligations of [`080-audit.md`](080-audit.md) AE7.

### BS10. The key prefix is a convenience; the row and the check are the boundary

**The tenant boundary for an object is behavioural, proven the way
[`025-structured-data.md`](025-structured-data.md) SD6 proves it for rows. A
read requested in one tenant's context is never served for an object whose
row belongs to another, whatever the subject's grants elsewhere say**. The
server reads `tenant_id` from the row and compares it to the request's
context. It refuses on mismatch or on a missing context before it runs the
permission check. A platform-operator flag never bypasses; support access is
consented, time-boxed impersonation recorded per
[`080-audit.md`](080-audit.md) AE2.

The prefix is not that boundary. It lets lifecycle and the purge sweep work
per tenant and makes an offboarding a prefix. A credential condition on it is
admitted as a backstop in the way SD6 admits row-level security, never as the
contract. It is configuration outside the repository that nothing here
checks. A bucket per tenant is admitted where a product isolates by one
database per tenant, with the same costs. The gate enumerates: every tenant's
objects, each requested in every other tenant's context, all refused.

## The artifacts

Per PC3, under [`contracts/blob-storage/`](../contracts/blob-storage/):

- **`key.schema.json`** is BS3's grammar as `$defs`. It holds the entity
  segment, the object id (a `$ref` into the identifiers contract's UUIDv7),
  the tenant-scoped and unscoped forms, and their union.
- **`object-reference.schema.json`** is BS4's reference, closed, with `$ref`s
  into the identifiers and observability contracts for ids, instants and the
  tenant id. It carries the conditional rules that `stored` carries
  `stored_at` and a `pending` row carries no verdict, and the media type and
  checksum grammars.
- **`upload-policy.schema.json`** is BS6's declaration. Per entity it holds
  the size ceiling, the closed type set, the audience, the scan flag, the
  disposition and an optional retention. Per service it holds the tenant
  scoping, the upload lifetime and the multipart threshold. The schema
  decides BS7's *others requires scan* and BS5's *inline only over
  inline-safe types*.
- **`corpus.json`** has five parts.
  - `keys` and `policies` are schema-decided.
  - `references` is schema-decided plus two equalities the schema cannot
    state: the key's final segment is the id, its first segment the tenant.
  - `uploads` is a set of sequences with steps at stated seconds, with every
    step's result and the end state. The sequences are a complete upload
    served, and a size, a checksum and a type that disagree with the
    declaration. They include a type and a size refused before any byte, and
    a body past the declared size aborted. They include an upload the client
    abandoned and one the server died in, both purged. They include a scan
    refused until clean, an infected object deleted, an owner deleted
    through the outbox, an orphan, and a multipart upload.
  - `reads` is a set of decisions the server makes for a request by object
    id. The decisions are the status, `Content-Type` and
    `Content-Disposition` it answers with, and a range satisfied as `206`.
    They are also the refusals: a pending object, a pending scan, an
    infected object, a missing permission, another tenant's row, a missing
    tenant context. Every served case expects the bytes in the
    response; an implementation that answers a redirect or a location fails
    all of them.

## Decisions

- **The S3 API is the protocol, adopted as a profile** (2026-09-02). It is
  the one object-storage interface with many independent implementations and
  a client per language. It already carries the streamed ranged read,
  multipart, the verified checksum and the lifecycle rule. The alternatives
  lack the primitive or are the framework problem.
- **One bucket per service per environment** (2026-09-02). Prefixes per
  service in a shared bucket make the credential boundary a policy condition
  outside the repository. A bucket shared across environments is where a
  staging job deletes production.
- **Tenant, entity and UUIDv7 in the key, and no filename** (2026-09-02). The
  filename is personal data, renameable and not unique. The extension is an
  unverified type claim, and a date path duplicates what the UUIDv7 orders.
- **A reference and never a URL** (2026-09-02). A presigned URL is a
  credential and a plain one is configuration; both leak through the row.
- **No presigned URL, ever; every read and write passes through the server**
  (2026-09-03). This supersedes the short-lived presigned read the first draft
  admitted. A presigned URL is a bearer credential whose only revocation is a
  timer and whose leakage is undetectable. No lifetime short enough changes
  either. It also puts the store's hostname on the internet, which makes the
  store an attack surface of every product that uses it.

  Served through the server, a read is authorized at the moment it happens
  and refused the moment a grant is revoked. The store is reachable from the
  service's network alone, and the only handle a client holds is an id that
  resolves through the row. The cost is that the server moves every byte and
  holds the connection for an upload. It is paid with replicas, not with the
  store's exposure. There is no exception for large files, for other
  services, for exports, or for a consumer that cannot follow a redirect.
  None of them was ever given a redirect to follow.
- **Upload through the server with the server's own sniff; disagreement is a
  refusal** (2026-09-03). The pending row first keeps the row the truth from
  the first byte. Hashing, counting and sniffing the stream as it passes
  means the verification costs no second read. The server sniffs because the
  declared type is what every later browser acts on. It refuses rather than
  corrects because a corrected object is one the client did not mean to send.
  An implementation that trusts the declaration passes every other case.
- **Scan posture follows the audience; the verdict gates the read**
  (2026-09-02). Scanning everything taxes the photo only its owner sees;
  scanning nothing serves malware between users. The gate is a status on the
  row, not a promise about latency, so an absent scanner fails closed.
- **Hard delete through the outbox, never inline and never storage-first**
  (2026-09-02). SD11 forbids the network call in the transaction, and each
  inline ordering loses something on a failure between its two steps.
- **Encryption on at the bucket; versioning is backup's** (2026-09-02). A
  bucket default is a rule nobody can forget. Versioning retains what BS8
  deleted, a backup property with an erasure cost, owned by the standard that
  owns retention windows.
- **The prefix is a convenience; the row and the check are the boundary**
  (2026-09-02). A credential condition on a prefix is configuration nothing in
  the repository checks. SD6's reasoning that isolation is a behaviour proven
  by enumeration transfers unchanged.

## Out of scope, deliberately

- **Backup, restore and versioning retention.**
  [`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s; this document
  supplies the bucket-agnostic key a restored database resolves with.
- **Export and erasure endpoints.** The
  [`082-data-subject-rights.md`](082-data-subject-rights.md)'s; this document
  supplies the delete those jobs call and the served read an export is
  delivered through.
- **JSON documents.** [`027-json-document-storage.md`](027-json-document-storage.md)'s;
  a document over the size that standard sets is an object with a reference.
- **Public asset delivery.** Release artifacts under [`010-ci.md`](010-ci.md),
  served without a check; not user data, not this bucket. A derived object,
  such as a thumbnail, is an object with its own reference, produced by a
  per-event job under [`057-jobs.md`](057-jobs.md).
- **A CDN in front of the server**. Where a product puts a cache in front of
  its own API, the cache is the product's. It authenticates to nothing but
  the server, and honours `no-store`. It is never a cache in front of the
  bucket.
