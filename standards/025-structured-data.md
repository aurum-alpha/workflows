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

### SD3. Migrations ship in the image and run as a step before rollout

A migration is in the repository, and the repository is not present where the
service runs. So the question *how is a migration applied* has one answer that
is consistent with [`010-ci.md`](010-ci.md)'s BUILD ONCE: **the migrations are
in the image.** Go embeds them in the binary; Node and PHP copy them into the
image; either way the artifact that ships the service is the artifact that
carries the schema it needs.

**The image exposes a `migrate` command** — the same image, a different
argument. It applies every pending migration in order and exits zero, or
stops at the first failure and exits non-zero having applied nothing further.
It is idempotent: a second run applies nothing and exits zero. This is
[factor XII](https://12factor.net/admin-processes) made literal — the admin
process runs in an identical environment to the service because it *is* the
service's image — and it answers the operator's question in the same breath:
migrations are run by `docker run <image> migrate`, against any release, with
nothing but the image reference. A pipeline step and a person at a keyboard
run the identical command.

**It runs as a discrete step before rollout, never at service boot.** Two
replicas starting together and each applying migrations is a race; a process
that migrates before it serves is not disposable per
[factor IX](https://12factor.net/disposability); and a failed migration must
fail the step rather than leave a half-ready process answering health checks.
The serve command assumes the schema is current and refuses to start if it is
not — that refusal is the backstop, not the mechanism.

**The migration credential is not the runtime credential.** The service's
database role cannot alter the schema; the migrate step's can. This is the
least-privilege split [`080-audit.md`](080-audit.md) AE6 already asks for on
one table, generalised to all of them.

Where a product isolates by **one database per tenant** (SD6), the `migrate`
command iterates every tenant database, and a failure in one is reported by
name and does not stop the others. That iteration, and the from-previous-release
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

## The artifacts

Per PC3, under [`contracts/structured-data/`](../contracts/structured-data/):

- **`storage-profiles.json`** — SD7's table as data: for each admitted engine,
  the column type per primitive, so a schema checker reads it rather than a
  human re-deriving it from prose.
- **`corpus.json`** — two parts. `migrations`: given a migrations directory as
  a listing of names and contents, the expected findings — a non-`.sql` file,
  an unordered name, an expand-only violation with and without its marker, a
  `db:push` in a reachable script. `isolation`: given a declared hierarchy, a
  set of tables with their columns, and a set of queries each issued in a
  stated context, the expected findings and the expected visibility of each
  row. Both are pure functions of their inputs, which is what makes them
  writable as data and runnable in any language.

## Enforcement

Registered in [`999-enforcement.md`](999-enforcement.md) under "Structured
data standard". Every rule lands review-only with its gate named, and this
standard is unusual in how many of those gates are cheap:

- **SD2's shape is two greps with no false positives**: nothing but `*.sql` in
  the migrations directory, and no merged migration's bytes changed — the
  second is reachable from history. The `db:push` reachability check is a third.
- **SD4's gate is a regular expression** over each file's up section for the
  three statement kinds and the marker. It is small enough that the corpus is
  most of the design, and the corpus already covers the violation, the marker,
  and the marker with no release named.
- **SD3's live gate is the from-empty and from-previous-release run**: apply
  the image's migrations to an empty database, then apply the current image's
  to a database the previous release's image migrated. `job-image-starts`
  already runs the image; this is a sibling job with a database beside it.
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
- **Migrations ship in the image and run as a discrete step** (2026-09-02):
  the only answer consistent with BUILD ONCE and factor XII at once. The
  alternatives — migrate at boot, migrate from a source checkout — each fail
  a rule this repository already has.
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
