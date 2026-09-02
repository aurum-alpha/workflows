# Structured data: the query language, migrations, and isolation

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/structured-data/`](../contracts/structured-data/). Id, timestamp
and money formats are [`020-identifiers.md`](020-identifiers.md)'s; this
document says how they are stored.

This document governs **structured data in a relational store**: how queries
are written, how the schema changes, how tenants are kept apart, and what the
running service is allowed to hold in its hand when it talks to the database.
Blob and file storage is the [blob storage
standard](000-platform.md#the-capability-roster)'s, and document stores are the
[document storage standard](000-platform.md#the-capability-roster)'s; neither is
covered here, and the rules below do not transfer to them by analogy.

## Why this exists

Eight repositories talk to a relational database and nothing says how. The
result is not chaos — it is eight reasonable local answers that disagree at
every seam a reviewer would want to check:

- **Five repositories ship a `db:push` script** — the schema tool's *make the
  database look like the code* command, which diffs and applies with no
  reviewable artifact, no ordering, and no down path. **Three of those five
  also carry a committed `migrations/` directory**, so the question *how does
  this repository change its schema* has two answers inside a single tree.
- **One repository's script named `migrate` runs `drizzle-kit push`.** The
  command called migrate does the thing a migration exists to prevent. That is
  not a violation anyone committed; it is what a word means when nobody has
  defined it.
- **Six repositories query through an ORM.** The SQL that reaches the database
  is generated at runtime from a builder chain, and appears nowhere in the
  repository. It cannot be read in review, pasted into a console, or profiled.
- **Seven of eight run Postgres**, and the identifiers standard wrote a storage
  profile for MySQL only, deferring every other engine to this document.

None of that is a failure of care. It is what happens when the questions
themselves have not been stated: what a migration *is*, what a query is
allowed to be, what a tenant boundary means at the row. Each product answered
those structurally, in the first week, by whatever its tooling defaulted to —
and each defaulted differently. This document states the questions and answers
them once, from the properties the answers must have, so that the next product
inherits the answers rather than the questions.

### The standard evaluated first, per PC2

There is no wire standard here to adopt; a database is not a boundary between
services, and SQL itself is the standard, adopted whole. The evaluation PC2
asks for is therefore about *tools* rather than protocols, and the answer is
the same one the platform contract gives for every tool: the fleet answer is
a set of properties an artifact must have — a migration is an ordered `.sql`
file, a query is authored text — and any tool that produces artifacts with
those properties is admitted. `goose`, `drizzle-kit`'s generator, `sqlc`, a
text editor: all fine, because the rule binds the file on disk and not the
hand that wrote it. A tool that *replaces* the artifact with itself — a
runtime query builder, a migration expressed as code — is what the rules
below exclude, and each says why.

## The rules

### SD1. SQL is the query language, and what runs is what was written

**A query is a complete SQL statement, written by a person, committed to the
repository as text.** What executes against the database is that text. A
library may execute it, bind its parameters, and map result rows onto a
language type; a library may **not** generate SQL at runtime from an object
model, a fluent builder, or a chain of method calls.

The argument is not about taste: *a query you cannot paste into a console and `EXPLAIN` as-is is one
nobody will profile.* The SQL is the review surface, the debugging surface and
the performance surface, and a builder chain hides the one thing every one of
those needs. Object-relational mapping also abstracts the engine as though it
were swappable, which trades the review surface for a portability the product
cannot use — the engine is pinned per repository, and moving it is a migration
project regardless of what the queries look like.

Three consequences that make the rule concrete:

- **Values bind through the driver's native placeholders, always.** A value
  never enters a SQL string by interpolation or concatenation. That is the
  injection boundary, and it is the one line in this document with no
  legitimate exception.
- **Dynamic shapes are explicit variants, not assembled fragments.** Optional
  filters use `coalesce($1, column)` or a second named query; a fragment that
  genuinely must vary comes from a compile-time allowlist. Runtime string
  assembly of SQL is SD1 broken by the back door.
- **Code generation from authored SQL is admitted and encouraged.** A tool that
  reads the `.sql` file and emits a typed function to call it — `sqlc` is the
  model — keeps the SQL as the source and adds type safety on top. The
  distinction is direction: SQL in, code out is fine; model in, SQL out at
  runtime is not.

A thin row mapper is not an ORM. Scanning a result row into a struct or a
record is the driver's job and is what "map result rows onto a language type"
means. The line is whether the library *wrote the query*.

**Pagination is keyset, never `OFFSET`.** [`050-http.md`](050-http.md) HA4
makes the wire form an opaque cursor; the storage form that makes that honest
is `WHERE key > $1 ORDER BY key LIMIT $2` over a key that is unique, indexed and
monotonic. `OFFSET n` fails on both counts that matter: it is O(n), because the
engine walks and discards n rows on every page, and it is unstable, because a
row inserted or deleted while a client pages makes the next page repeat or skip.
The key with all three properties already exists on every addressable row by
construction — the UUIDv7 public id of [`020-identifiers.md`](020-identifiers.md)
IP2 is time-ordered, unique and indexed, and time-ordering is precisely why IP2
chose v7 over v4. The internal identity key is also monotonic and serves keyset
paging *inside* the service, but never inside a cursor a client holds, because
IP1 says it never leaves — and a base64 wrapper is not opacity. A listing sorted
by something other than creation order keys on `(sort_column, public_id)`, the
id breaking ties so the order is total.

### SD2. A migration is an ordered `.sql` file, and never code

**A schema change outside local development is a migration**: a file of SQL,
in a single migrations directory, with a name that orders it, committed and
reviewed like any other change. Once merged its bytes never change — a
correction is a new migration, exactly as a ledger is corrected by a new entry.

**How the file is produced is unconstrained.** Written by hand, or generated
in development by a tool that diffs the desired schema against the current
one — both are fine, because the rule binds the artifact and not the authoring.
What lands on disk is SQL a reviewer reads, and the tool that helped write it
is not part of the contract.

**A migration is never code.** Not a `.ts` exporting an `up()` function, not a
Go file calling a builder, not a PHP class calling `$this->forge->addField()`.
Each of those puts a translation layer between the reviewer and the statement
that will run, which is SD1's objection arriving one directory over; and each
ties the migration history to a language runtime, so that a database cannot be
built or inspected without one. The migrations directory contains `*.sql` and
nothing else.

**`db:push` and its equivalents are local-development tools**, admitted only
where the target database is disposable. They are absent from any script a
deploy path can reach: not in a `Dockerfile`, not in a compose file that
starts a persistent database, not behind a script named `migrate`. A
repository that carries both a migrations directory and a reachable push
command has two answers to one question, and the second answer will be the
one used at the wrong moment.

Each migration applies in its own transaction where the engine allows it, so
a file's statements commit or roll back together and the version record is
written only on success. A statement that cannot run inside a transaction —
`CREATE INDEX CONCURRENTLY` — opts out explicitly in the file, and says so.

**Every migration converges.** Run against a database where it has already
applied — in whole, or in part after an interrupted run — a migration produces
the same end state and exits zero. `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF
NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `DROP … IF EXISTS`, and
`INSERT … ON CONFLICT DO NOTHING` for seed rows. Where the engine has no guard
for a statement — Postgres has none for `ADD CONSTRAINT`, MySQL has none for
`ADD COLUMN` — the statement is wrapped in a conditional that checks the catalog
first.

The version record is not a substitute for this, because the record and the
schema can disagree. A migration interrupted after its first statement leaves
the schema changed and the version row unwritten — and on MySQL every DDL
statement commits on its own, so an interrupted multi-statement migration there
is *always* half-applied. The next run cannot skip it, because it is not
recorded, and if its statements error on what already exists it cannot apply it
either. The migrate step is now stuck, and the way out is a person editing a
version table by hand at exactly the moment nobody should be. A migration whose
statements converge turns that into a re-run that succeeds. The same holds for
a database restored from a backup taken between apply and record, for a
per-tenant iteration that stopped on the seventh tenant, and for a development
database someone changed by hand. The version record gives ordering and speed;
convergence gives recovery. Both are required, because each covers the failure
the other cannot.

### SD3. Migrations ship in their own image and run as a step before rollout

A migration is in the repository, and the repository is not present where the
service runs. So the question *how is a migration applied* has one answer:
**the migrations ship in an image built from the same repository, in the same
build run, at the same version as the service.** That image is the migration
runner and the `.sql` files and nothing else — not the listener, not a worker
— because an image does one thing, and because the migration credential then
has exactly one home: the runtime image never holds it, and the migrate image
holds nothing but it. Two rules of [`010-ci.md`](010-ci.md) bind the two
images. BUILD ONCE: the build job is the only compiler in the run, each
artifact is compiled exactly once and stored, and the migrate image is
assembled from what that job stored — never recompiled at image build.
Versioning the repository rather than the artifact: that one build job builds
every artifact the repository ships, every time, so the migrate image and the
service image at one version carry one schema by construction, because they
came out of one run that compiled and tested them together.

**The migrate image runs to completion and exits.** It applies every pending
migration in order and exits zero, or stops at the first failure and exits
non-zero having applied nothing further. It is idempotent at two levels: the
runner skips what the version record says has applied, and each file converges
if run regardless (SD2) — so a second run against a current database applies
nothing and exits zero, and a run against a half-migrated one finishes the job
rather than refusing it. This is
[factor XII](https://12factor.net/admin-processes) met in its own terms — the
admin process carries the service's provenance because it was built beside the
service from the same commit — and it answers the operator's question in the
same breath: migrations are run by `docker run <service>-migrate:<version>`,
against any release, with nothing but the image reference. A pipeline step and
a person at a keyboard run the identical command.

**It runs as a discrete step before rollout, never at service boot.** Two
replicas starting together and each applying migrations is a race; a process
that migrates before it serves is not disposable per
[factor IX](https://12factor.net/disposability); and a failed migration must
fail the step rather than leave a half-ready process answering health checks.
The service assumes the schema is current and refuses to start if it is not —
that refusal is the backstop, not the mechanism.

**The migration credential is not the runtime credential**, and the separate
image is what makes that enforceable rather than remembered. The service's
database role cannot alter the schema; the migrate image's can; and because the
service image contains no migration runner, there is nothing in it that could
use the stronger credential if it were leaked to it. This is the
least-privilege split [`080-audit.md`](080-audit.md) AE6 already asks for on
one table, generalised to all of them.

Where a product isolates by **one database per tenant** (SD6), the migrate
image iterates every tenant database, and a failure in one is reported by name
and does not stop the others. That iteration, and the from-previous-release
gate running once per tenant, is the cost of that isolation pattern, stated
here so it is chosen with the price known.

### SD4. Migrations expand; contraction is a later release

**A migration may add. It may not drop or retype anything the previous release
reads.** Removing a column takes three releases: add the new shape and write
both; move reads to the new shape; drop the old one a release later.

This rule is the entire reason rollback works. Redeploying the previous image
against a schema the current release has migrated forward succeeds because
that schema is a *superset* of what the previous release needs. Without it,
*rollback is a data-loss event wearing a tag change*, and it is discovered at
the worst possible moment, because rollback is what one reaches for when
something is already wrong.

A migration containing `DROP COLUMN`, `DROP TABLE`, or `ALTER … TYPE` fails
review and the gate unless it carries a marker on the same line or the line
before — `-- expand-only-ok: <the release that stopped reading the old shape>`
— naming the release after which the statement became safe. The marker is a
reason, not a permission; a marker with no release named is a violation with
a comment on it.

**Down migrations exist for local iteration and are never trusted in
production.** A down migration for a dropped column restores the column and
not the data; the down path is a convenience for a developer's disposable
database, and nothing in a deploy path runs one.

**A backfill is a job, not a migration.** A migration that rewrites fifty
million rows holds a lock for the duration, and the deploy step times out with
the table half-written. A data change that touches many rows is therefore three
artifacts, not one: a migration that adds the column nullable; a batched job —
bounded batches, resumable, observable — that fills it while the service keeps
serving; and a later migration that adds `NOT NULL` once the job reports the
column full. The migration changes shape, the job moves data, and the shape
change is what SD3's step applies at rollout, in seconds. How the job itself is
built, registered and run is the [maintenance jobs
standard](000-platform.md#the-capability-roster)'s; what this rule fixes is that
rows do not move inside `migrate`.

### SD5. Isolation levels are declared, and they are the RBAC scope types

**This standard does not fix how many isolation levels a product has.**
Products differ here for structural reasons, not stylistic ones: a practice
that serves client organisations has a level beneath the tenant that a
single-tenant tool does not have at all, and a platform that hosts many
practices has one above it. A standard that named the levels would fit the
products it was written from and force a fiction on the rest — an empty
middle level, or two things called by one name.

What it fixes is that **a product declares its levels, once, and the
declaration is the same one its authorization uses.** [`070-rbac.md`](070-rbac.md)
RB5 already requires the application to declare its scope types and how they
contain one another; the isolation levels *are* those scope types. A table
scoped to `tenant` carries `tenant_id`; a table scoped to `client_org` carries
`client_org_id` **and** `tenant_id`, because containment is declared upward and
the row must be addressable at every level that contains it. One hierarchy,
declared in one place, read by both the authorization layer and the storage
layer — a product with two hierarchies has two answers to *who is this row
inside of*, and they will disagree.

**Every scoped table carries the column for every level that contains it,
denormalized, deliberately.** The columns are redundant by design: the
client-organisation row already knows its tenant, so `tenant_id` on every row
below it repeats a fact. It is repeated so that **every isolation predicate is
a single joinless comparison** — `tenant_id = current_tenant()` — on the table
being queried. A predicate that has to join upward to find the tenant is a
predicate that is slower, that is easy to get subtly wrong, and that a policy
engine cannot apply. The redundancy is the price of the predicate being trivially
right.

**Name the levels, and never use one to mean another.** The middle and
innermost levels are the ones that blur, because ordinary speech has one word
for both — *the customer* is the practice to the platform and the client
organisation to the practice. A codebase that lets the word drift ends up with
a query scoped at the wrong level, and that is a cross-tenant read with a
plausible variable name. So the declaration fixes the vocabulary as well as
the columns: one name per level, used for that level and nothing else, in
code, schema and documentation alike.

### SD6. Isolation is a behaviour, proven by enumeration

**The contract is the behaviour: a query issued in one isolation context never
returns, modifies or counts a row belonging to another.** That is what the
gate proves, and per PC4 it proves it at the boundary — issue the query, look
at the rows — without caring how the product achieved it.

Three mechanisms are admitted, and the choice depends on the isolation level
and the security posture the product actually needs. Each is stated with its
cost:

| Mechanism | What it is | What it costs |
|---|---|---|
| **Row-level security** | The engine enforces the predicate on every statement, from a context the connection binds per request. Application scoping remains; RLS is the backstop that makes a missed `WHERE` clause a denied row rather than a leak. | Postgres has it; MySQL does not. The per-request binding (`SET LOCAL`) is a discipline the code must make structural — for instance by making the bound transaction the only handle a query method will accept, so an unbound query cannot be written. |
| **One database per tenant** | The strongest boundary: the tenant is a connection string, and there is no query that can cross it. | Migrations apply per tenant (SD3), the from-previous-release gate runs per tenant, and connection pools multiply. Correct for a small number of high-assurance tenants; wrong for thousands of small ones. |
| **Application-layer scoping** | Every query carries the isolation predicate, and the check is in the code path. Ownership checks on individual rows are the authorization layer's, per RB5. | No backstop. A missed predicate is a cross-tenant read that no test exercising one tenant at a time will show — which is why the enumeration gate below exists, and why this mechanism leans on it hardest. |

Whichever mechanism, two rules hold across all three:

- **A missing isolation context denies.** A request that resolved no tenant —
  the platform host, an unauthenticated path, a background job with no tenant
  bound — sees no scoped rows, by construction. Under row-level security this
  falls out of the predicate's shape — `has_tenant(NULL)` is false, so an
  unbound connection matches nothing; an application-layer implementation
  achieves it by refusing to run a scoped query with a null scope rather than
  by omitting the predicate.
- **No bypass role on scoped tables.** The platform operator's predicate never
  appears in a policy on a tenant-scoped table, and a platform-admin flag never
  short-circuits an application-layer scope check. Support access happens
  through consented, time-boxed impersonation, which satisfies the tenant
  membership check like any real membership — and which
  [`080-audit.md`](080-audit.md) AE2 records with the impersonator named. This
  is [`070-rbac.md`](070-rbac.md) RB4 applied to the storage layer: the code
  does not branch on who you are, it checks what you hold.

**The gate enumerates; it never lists.** Scoped tables are discovered from the
engine's catalog — every table carrying a declared isolation column — and each
is asserted to carry the column for every containing level, with the right
type and foreign key, and to be covered by the product's mechanism. Because the
suite enumerates, a table added tomorrow is covered the day it lands, and a
table added *without* the columns is the finding. A list of tables to check
rots the day someone adds a table; that is how a fixture becomes a scoreboard.

### SD7. Identifiers and primitives in storage, per engine

[`020-identifiers.md`](020-identifiers.md) says what an id, an instant, a date
and a money value look like on the wire. This rule says what column they land
in, and it is where that standard's deferrals resolve.

**IP1 in schema form**: an externally addressable table carries an internal
key that never leaves the service *and* a separate public id column — unique,
indexed, immutable — in an admitted IP2 format. The public id is not the
primary key, so the format can change without a foreign-key migration
rippling through the schema. This is the check
[`020-identifiers.md`](020-identifiers.md) said was buildable once a standard
gave a checker a schema to read; this is that standard.

**The storage profile is per admitted engine.** This document does not
mandate an engine — seven of eight products run Postgres and one runs MySQL,
and both are admitted — but it does say, for each, what column type each
primitive takes, because the wrong column type is how the identifiers rules
fail silently:

| Primitive | Postgres | MySQL | Why the obvious alternative is wrong |
|---|---|---|---|
| UUIDv7 public id | `uuid` | `BINARY(16)`, or `CHAR(36)` where readability outweighs the index cost | A `text` UUID indexes at twice the width for no benefit |
| nanoid / prefixed handle | `text` with a `CHECK` on the IP2 pattern | `VARCHAR(n)` with the same check | An unconstrained text column admits anything |
| Instant (IP4) | `timestamptz(3)` | `DATETIME(3)` holding UTC | Postgres `timestamp` *without* time zone stores a wall-clock reading and silently reinterprets it under a session zone; MySQL `TIMESTAMP` ends in 2038 and converts through the session zone. Both are the exact trap IP4 names |
| Calendar date (IP4) | `date` | `DATE` | An instant at midnight is off by a day for half the planet |
| Money (IP5) | `bigint` amount + `char(3)` currency, both `NOT NULL` | `BIGINT` + `CHAR(3)` | `numeric` invites fractional cents; `float` is the whole argument against floats |
| Internal key | `bigint generated always as identity` | `BIGINT AUTO_INCREMENT` | A UUID primary key on a high-insert table fragments the index; the internal key is for joins and is never exposed |

A repository pinning six-digit precision per IP4 uses `timestamptz(6)` /
`DATETIME(6)` and says so in its **Conventions**. An engine not in this table
is admitted by adding its column to it, in its own change, with the fourth
column filled in.

**Time zone is the session's problem, never the column's.** Every connection
sets the session time zone to UTC at open, so that the engine's own casts and
`now()` agree with the profile. A product that relies on the server default is
one configuration change from silently shifting every timestamp it stores.

### SD8. Seed data is a migration; fixture data is never a production row

Two kinds of rows are not user data, and they are governed differently:

**Seed data** — reference rows the application cannot run without: the system
roles [`070-rbac.md`](070-rbac.md) RB3 keeps in code, a currency table, a
default configuration row. Seeds are **idempotent SQL applied through the same
migrate path**, so a database built from migrations alone is a database the
application can start against. A seed that is not idempotent is a migration
that fails the second time it runs.

**Fixture data** — the rows a test or a demo needs. Fixtures live with the
tests, are created by the tests, and **are never applied to a database that
holds real data.** No fixture is a migration, no fixture carries real personal
data, and no deploy path can reach the command that loads one. The failure
this prevents is the one where a demo tenant, a test user with a known
password, or a placeholder email address is found in production, and nobody
can say when it arrived.

### SD9. The database is an attached resource, reached with the least the service needs

The database is a backing service in the sense of
[factor IV](https://12factor.net/backing-services): named by configuration,
swappable per deploy, and never assumed to be local. Four rules follow, each
short because a longer version would be restating a factor:

- **The connection string comes from the environment** per
  [factor III](https://12factor.net/config) and
  [`030-service.md`](030-service.md) SC3, and the credential inside it is a
  secret delivered as the [secrets standard](000-platform.md#the-capability-roster)
  says. Nothing in the repository contains one.
- **The runtime role is the least the service needs.** It cannot create or
  alter tables (SD3), cannot bypass isolation (SD6), and holds only the
  privileges on the tables it reads and writes. A service running as the
  database superuser has made every other rule in this document advisory.
- **The connection is encrypted in transit**, and the pool is **bounded and
  sized from configuration**. An unbounded pool converts a traffic spike into
  a database outage; a pool that cannot obtain a connection surfaces that in
  readiness ([`030-service.md`](030-service.md) SC1) rather than in a request
  that hangs.
- **SQL parameters never reach a log, span or metric.** The statement text may
  be logged; the values bound to it — which are user data, and under SD6 are
  tenant data — may not. This is the [observability
  standard](040-observability.md)'s rule about what a line may carry, at the
  point where it is most often broken, because a driver's debug mode logs
  everything and someone will turn it on in production once.

Backup, restore and recovery objectives are deliberately not here. They span
every kind of storage a product has — structured, blob and document — and a
rule stated for one would be restated for the others; they belong to the
[backup and recovery standard](000-platform.md#the-capability-roster). What this
document holds is the one dependency: a restore lands the schema at some past
migration state, and SD2's convergence is what makes running `migrate` against
it safe.

### SD10. The schema carries its invariants

Code paths multiply. A rule enforced in one of them — the write handler, the
import job, the admin script, the backfill — is a rule enforced in the paths
someone remembered. The database is the one place every write goes through, so
**an invariant of the data is declared in the schema, and code is the second
line, never the only one.**

- **`NOT NULL` is the default; nullable is a decision.** A column admits `NULL`
  because the domain genuinely has an absent case, stated in the migration that
  adds it — never because the author did not decide. A sentinel standing in for
  absence (an empty string, a zero, a date in 1970) is a `NULL` that lies about
  itself, and every query that touches it has to know the lie.
- **Foreign keys are declared.** A reference the code promises to honour is
  honoured in the paths that remember to; a declared constraint is honoured in
  all of them, including the one that runs at three in the morning. **And every
  foreign-key column is indexed** — the engine does not do this for you, and an
  unindexed foreign key turns every delete of a parent row into a scan of the
  child table, which is a table lock in a trench coat.
- **Uniqueness and domain rules are `UNIQUE` and `CHECK` constraints.** An email
  unique per tenant is `UNIQUE (tenant_id, email)`, not a `SELECT` before the
  `INSERT`, which races. A status that takes four values is a `CHECK`, not a
  comment.
- **No native `ENUM` types.** A `CHECK` constraint or a lookup table instead. A
  native enum cannot have a value removed, cannot have one added inside a
  transaction on the majority engine, and turns a rename into an exercise nobody
  wants; the `CHECK` does the same job and migrates like any other constraint.
- **A JSON column holds what the application does not query by field.** A
  per-tenant configuration blob, an external payload kept verbatim — fine,
  because nothing filters or joins on their insides. A field the application
  filters, joins, sorts or indexes on is a column, and a `jsonb` column that
  accumulates such fields is a schema someone did not want to write, carrying
  none of the invariants above.
- **Isolation columns lead the composite index** on every scoped table (SD5).
  The joinless predicate is only fast if the index starts where the predicate
  does; an index on `(created_at)` alone makes `WHERE tenant_id = $1 ORDER BY
  created_at` a scan of every tenant's rows.
- **Every table carries `created_at` and `updated_at`**, both `NOT NULL`, both
  instants per IP4, `updated_at` maintained on every write — by the write or by a
  trigger, decided once per repository. They are the two questions asked of
  every row on every support call.

**Identifiers are `snake_case`, decided once.** The argument
[`050-http.md`](050-http.md) HA8 made for the wire is sharper in the schema: an
unquoted SQL identifier case-folds *silently*, so `createdAt` becomes
`createdat` in one reference and stays `createdAt` in a quoted one, and they are
two columns until they are the same one. Table names are plural nouns
(`invoices`, `tenants`); a foreign key is the singular of the referenced table
plus `_id` (`tenant_id`), which is the form SD5 already assumes. None of these
three choices is better than its alternative in any way that matters — which is
exactly why each is made here, once, rather than per repository.

### SD11. One request, one transaction, and nothing waits inside it

**A request's writes commit or vanish together.** One handler opens one
transaction, does its work, and commits or rolls back once. Two writes that
must agree — the change and its audit event, per [`080-audit.md`](080-audit.md)
AE8; the order and its lines — are one transaction, or they are a bug waiting
for the failure between them.

**A transaction never spans a network call or a human.** Not an HTTP request to
another service, not a queue publish, not a wait for the user's next click. A
transaction holds locks and a pooled connection for its lifetime; one that
waits on the network holds them for the network's worst case, and one that
waits on a person holds them until the person comes back from lunch. Gather the
external inputs first, then open the transaction, then commit.

**`READ COMMITTED` is the default isolation level; `SERIALIZABLE` is opted into
per transaction where the domain needs it, with a retry.** The default should
be the one that does not surprise a developer with a failure mode they did not
write for, and `READ COMMITTED` is that: it never aborts a transaction for a
conflict the developer did not know could happen. `SERIALIZABLE` is the correct
choice where two concurrent transactions must not both succeed — a balance that
must not go negative, a seat that must not be sold twice — and it is chosen
deliberately there, with the serialization-failure retry written alongside,
because a `SERIALIZABLE` transaction without a retry fails a small fraction of
the time for no reason a user can see.

**A statement timeout is set on the runtime role.** A query that runs for
minutes holds a pooled connection for minutes, and under load the pool is the
resource that runs out first. The timeout is the ceiling a request may spend in
the database, set in configuration, and a query that hits it is a defect to fix
rather than a limit to raise. This is the half of SD9's bounded pool that bounds
it in time as well as in count.

**The migrate step takes an advisory lock for its run.** SD3 keeps
migration out of the serve process to avoid the replica race; two deploy steps
overlapping — a retried pipeline, a person and a pipeline — is the same race
one layer up. One lock held for the run means the second invocation waits and
then finds nothing to do, which SD2's convergence guarantees is safe.

### SD12. A deleted row is gone

**Hard delete is the default.** When a user deletes a thing, the row is
removed. When a user leaves, their data is removed. The argument is compliance
and security before it is engineering: *we do not hold data after its owner
asked us not to* is a sentence a product can defend to a regulator, an auditor
and a client, and *we mark it deleted and keep it* is a sentence that has to be
followed by an explanation. Data that is not held cannot leak, cannot be
compelled, and cannot be the subject of an erasure request that the interface
already told the user was granted.

**Soft delete is the exception, and it needs a domain reason.** Some things must
be retained past the user's intent to remove them: a financial record inside
its statutory period, a message the other party still holds, an object whose
history other rows reference. Where that is so, the product says which tables
and why in its **Conventions**, and three rules hold on them:

- **A soft-deleted row is still isolation-scoped.** It carries its isolation
  columns like any other row and SD6's predicate still applies. Deleted is not
  a fourth level.
- **A soft-deleted row is still personal data.** An erasure request reaches it
  as it reaches any other row, in the redaction shape [`080-audit.md`](080-audit.md)
  AE7 defines and under the [data-subject-rights
  standard](000-platform.md#the-capability-roster). Soft delete defers deletion;
  it does not exempt from it.
- **Ordinary queries exclude it in the query text**, per SD1 — a
  `WHERE deleted_at IS NULL` a reviewer can see, never a global filter a library
  applies invisibly.

What survives a hard delete is the audit trail, by construction:
[`080-audit.md`](080-audit.md) AE4 requires the audit row to carry the deleted
target's public id and display text and to be unreachable by cascade. *The
invoice is gone and the record that it was voided on the fourth is not* is the
intended state, and it is what makes hard delete safe as the default.

### SD13. The database is private to its service, and is tested as the real thing

**One service, one schema, one writer.** No other service reads this service's
tables, and no other service holds a credential to them. Integration happens
through the service's interface — its API per [`050-http.md`](050-http.md), or
the events of the [messaging standard](055-messaging.md) — never through a shared
database. A table read by two services is an interface with no contract, no
version and no owner: the moment one service changes a column the other breaks
at runtime, and neither has a test that could have shown it. The database is an
attached resource of exactly one process, in the sense
[factor IV](https://12factor.net/backing-services) means it.

**Tests run against the engine the product runs.** Postgres in a container,
MySQL in a container, never SQLite standing in for either. This follows from
SD1: the query text is the contract, and that text is engine-specific — its
placeholders, its `RETURNING`, its `ON CONFLICT`, its date arithmetic. A query
proven against a different dialect is a different query proven. A test suite
that cannot obtain a real engine does not run the data-access tests; it does
not run them against a substitute and report green.

## The artifacts

Per PC3, under [`contracts/structured-data/`](../contracts/structured-data/):

- **`storage-profiles.json`** — SD7's table as data: for each admitted engine,
  the column type per primitive, so a schema checker reads it rather than a
  human re-deriving it from prose.
- **`corpus.json`** — three parts. `migrations`: given a migrations directory as
  a listing of names and contents, the expected findings — a non-`.sql` file,
  an unordered name, an expand-only violation with and without its marker, a
  `db:push` in a reachable script. `isolation`: given a declared hierarchy, a
  set of tables with their columns, and a set of queries each issued in a
  stated context, the expected findings and the expected visibility of each
  row. `schema`: given a declared schema — tables, columns with types and
  nullability, indexes, foreign keys, declared types — the SD10 findings a
  checker must report. All three are pure functions of their inputs, which is
  what makes them writable as data and runnable in any language.

## Enforcement

Registered in [`999-enforcement.md`](999-enforcement.md) under "Structured
data standard". Every rule lands review-only with its gate named, and this
standard is unusual in how many of those gates are cheap:

- **SD2's shape is two greps with no false positives**: nothing but `*.sql` in
  the migrations directory, and no merged migration's bytes changed — the
  second is reachable from history. The `db:push` reachability check is a third.
  Convergence gets a fourth, static and partial: the unguarded common forms —
  `CREATE TABLE`, `CREATE INDEX`, `ADD COLUMN`, `DROP …`, a seed `INSERT` — with
  the guard absent. It catches the ordinary mistake and not the exotic one; the
  live replay below is the proof.
- **SD4's gate is a regular expression** over each file's up section for the
  three statement kinds and the marker. It is small enough that the corpus is
  most of the design, and the corpus already covers the violation, the marker,
  and the marker with no release named.
- **SD3's live gate is the from-empty and from-previous-release run**: apply
  the image's migrations to an empty database, then apply the current image's
  to a database the previous release's image migrated; then **replay every
  file against the migrated database, bypassing the version record**, and
  require exit zero and an unchanged schema. That replay is the convergence
  check, and it is the only test that proves SD2's guarantee rather than
  assuming it. `job-image-starts` already runs the image; this is a sibling job
  with a database beside it.
- **SD6's gate is the generative isolation suite**, and it is the one worth the
  most, in the same way AE5's enumeration is: it discovers scoped tables from
  the catalog, so a table added tomorrow is covered the day it lands.
- **SD7's column-type check** reads the catalog against `storage-profiles.json`
  and is the check IP1 has been waiting for.
- **SD1 resists a clean gate**, honestly. Checking which library is imported
  would be checking the implementation, which PC4 forbids; the boundary gate is
  a driver-level capture in the conformance job asserting every executed
  statement matches committed text, and it does not exist yet. Until it does,
  SD1 is the review question on every data-access diff: *can I paste this into
  a console?*
- **SD5, SD8 and SD9 are review questions**: whether the declared hierarchy is
  the one authorization uses, whether a fixture could reach production, and
  whether a role is genuinely least-privilege are judgments about intent,
  stated as questions rather than left as assumptions.
- **SD10 is mostly catalog facts**, and the `schema` corpus decides them: a
  foreign-key column with no index leading on it, a table without its two
  timestamps, a native enum type, an identifier that is not `snake_case`, a
  scoped table with no index led by its outermost isolation column. `NOT NULL`
  by default and the JSON rule are intent, and stay review questions.
- **SD11's timeout and lock are configuration facts**; that a transaction spans
  no network call is a review question on every handler, and one worth asking
  in those words.
- **SD12's default is a review question** on every delete path; that a
  soft-deleted table is declared in Conventions with a reason is a grep.
- **SD13's privacy is a credential fact** — no second service holds a role on
  this database — and its real-engine rule is a CI fact: the test job starts
  the engine the product runs, or the data-access tests do not run.

## Decisions

- **SQL is the query language; no runtime generation** (2026-09-02): the most
  consequential rule here. Decided because the alternative hides
  the review, debugging and performance surface behind a notation that is
  worse than the thing it abstracts, and because the portability it buys is
  one no product here can use. Code generation *from* authored SQL is the
  admitted shape, and the recommended one.
- **A migration is a `.sql` file and never code; authoring is unconstrained**
  (2026-09-02): an earlier draft of this rule also excluded migrations
  generated by a schema-diff tool, on the grounds that the SQL was derived from
  an ORM's model. That was wrong, and it was wrong in a way PC4 predicts: it
  bound the authoring instead of the artifact. What matters is that an ordered
  `.sql` file is on disk for a reviewer to read; how it got there is the
  developer's business.
- **Every migration converges, and the version record is not a substitute**
  (2026-09-02): the record answers *has this applied* and the schema answers *is
  this present*, and there are ordinary events — an interrupted run on an engine
  whose DDL cannot roll back, a restore from between apply and record, a
  per-tenant iteration that stopped partway — after which they give different
  answers. A migration that errors on what already exists turns each of those
  into a stuck deploy that a person must unstick by hand. Guards cost a clause
  per statement; the alternative costs the one property a migrate step must
  have, which is that running it again is always safe.
- **Migrations ship in their own image and run as a discrete step**
  (2026-09-02): the only answer consistent with BUILD ONCE and factor XII at
  once, and a separate image rather than a subcommand of the service because an
  image does one thing and the migration credential then has exactly one home.
  The alternatives — migrate at boot, migrate from a source checkout, a
  `migrate` mode inside the service image — each fail a rule this repository
  already has.
- **Expand-only, with contraction one release later** (2026-09-02): the
  rollback argument is the whole justification. A forward-migrated schema must
  be a superset of what the previous release reads, or redeploying that release
  destroys data — and rollback is reached for precisely when something is
  already wrong. Three releases per removal is the price of that being true
  without anyone having to reason about it under pressure.
- **No fixed number of isolation levels; the levels are the RBAC scope types**
  (2026-09-02): products differ in depth for structural reasons, and a fixed
  number would fit some by forcing a fiction on the rest. Tying the declaration
  to RB5's makes one hierarchy serve both layers, which is the point.
- **Isolation is a behaviour with three admitted mechanisms, and RLS is not
  required** (2026-09-02): row-level security is the strongest backstop
  available on the majority engine and it is not available on the other; a
  requirement would have made conformance a property of the engine rather than
  of the design. The
  behaviour is what the gate proves, and each mechanism is admitted with its
  cost written down so the choice is made with the price known.
- **Per-engine storage profile, no mandated engine** (2026-09-02): the
  identifiers standard deferred every engine but MySQL here; this resolves the
  deferral for Postgres and leaves the table open for the next engine, which
  is admitted by filling in its column rather than by an argument about
  whether it should exist.
- **Hard delete is the default; soft delete is the exception** (2026-09-02):
  the reverse was considered — soft by default, hard only for security — and
  rejected because the default should be the one that is easiest to defend
  without explanation. *We do not hold data after its owner asked us not to* is
  that sentence. Soft delete stays available where a domain reason exists, and
  the three rules on it keep a retained row scoped, erasable and visibly
  excluded.
- **`READ COMMITTED` by default, `SERIALIZABLE` by choice** (2026-09-02): the
  default is the level that never fails a transaction for a reason the
  developer did not write for; the stricter level is chosen where two
  concurrent successes would be wrong, and the retry it demands is written in
  the same change.
- **No native enums; `CHECK` or a lookup table** (2026-09-02): the enum's
  only advantage is brevity, and its costs — no removal, no transactional add
  on the majority engine, a painful rename — are all paid at migration time,
  which is when nobody wants a surprise.
- **Plural table names, `<singular>_id` foreign keys, `snake_case` throughout**
  (2026-09-02): none of the three is better than its alternative, and that is
  the whole reason to decide them here once. The `snake_case` half has a
  technical argument as well — unquoted identifiers case-fold silently — and
  it is the same argument HA8 made for the wire.
- **Backfills are jobs, backups are elsewhere** (2026-09-02): a backfill moves
  rows and a migration changes shape, and conflating them is how a deploy step
  times out holding a lock. Backup and recovery span every kind of storage and
  get their own document rather than a paragraph here that would be restated
  twice.
