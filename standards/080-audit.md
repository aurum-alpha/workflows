# Audit events: who did what, when, to what

## Why this exists

When a client asks *who changed this, and when*, an answer exists only where
the product chose to keep one. Without a statement of what an audit event
*is*, each product answers structurally and each answers differently. The
cost lands on a client rather than on us, on the one record whose entire
value is being right about what happened. This standard says
what the event is: its shape, its floor, its storage discipline and its
retention.

**OCSF is the export target, not the record**. The [Open Cybersecurity Schema
Framework](https://github.com/ocsf/ocsf-schema) is a normalisation target for
security telemetry, and its class taxonomy is closed and security-shaped.
There is no class for `invoice.void`, and forcing one into API Activity throws
away the domain meaning a product's own history screen needs. So AE2's field
names map onto OCSF's dictionary where it has an equivalent (`actor`, `time`,
`status`, `metadata`). A product feeding a SIEM maps at that boundary.
Where audit events go on a bus, CloudEvents is the envelope and AE2 is the
payload.

## The rules

### AE1. An audit event is data, not a log line

An audit event and a log line are different things with different readers:

| | Log line (SC2) | Audit event |
|---|---|---|
| Reader | An engineer, during an incident | An administrator, an auditor, a client |
| Question | Why is this broken | Who did this, and when |
| Completeness | Best-effort; sampling and level filtering are legitimate | Complete, or it is not evidence |
| Lifetime | Days to weeks | The product's retention period (AE7) |
| Queried by | A human with a log search tool | **The application itself**, on a history screen |
| Owner | The execution environment | The application |

**Audit events are written to the application's own durable, queryable,
tenant-scoped storage**. They are business data that happens to resemble
telemetry. A product's "history of this record" panel is a query over them. An
administrator's access review is a query over them. A client's "show me last
year" request is a query over them. Data the application queries lives in the
application's datastore.

An implementation **is permitted to** emit the event to the log stream as well,
which is often convenient. But **the log stream is never the system of
record**. A product that writes audit events only to stdout relies on the
platform's log pipeline to retain them for the whole retention period. That
is three bets it cannot honour. Nothing samples; retention is set correctly and stays set; a
ten-month-old line is still queryable by tenant on a support call. Two of those
are outside the application's control entirely.

*On [factor XI](https://12factor.net/logs)*: it says an application must not
concern itself with routing or storing **its log stream**, and
[`030-service.md`](030-service.md) SC2 adopts that whole. An audit event is
not a log line. It is application data, and its store is an attached resource
in the sense of [factor IV](https://12factor.net/backing-services). It is
named by config and swappable per deploy, like every other table the product
owns.

### AE2. One event shape, and actor is not target

Every audit event is the same object, whatever produced it:

| Field | Meaning |
|---|---|
| `schema_version` | Per PC6. |
| `event_id` | The event's own public id (UUIDv7, IP2). What a support ticket quotes and what makes a replayed delivery deduplicable. |
| `occurred_at` | When the act happened, from a clock, RFC 3339 UTC per IP4. **Not** when the row was written. Those differ for queued and retried work, and the difference is the interesting one. |
| `action` | What was done, per AE3. |
| `outcome` | `success` or `failure`. A refused act is auditable and is usually the more interesting row. |
| `actor` | **Who did it.** |
| `target` | **What it was done to.** |
| `tenant_id` | The tenant the act happened in, per OC2. |
| `trace_id`, `request_id`, `span_id` | The request that produced it, per OC2 and OC4, so an audit row joins to the logs of its own request. |
| `changes` | Optional. What the act altered, as before/after per field. |
| `reason` | Optional free text: the justification an administrator typed, or the decision reason from RBAC's RB8 on a refusal. |
| `decision` | Optional. The permission the act was decided under and the capacity that satisfied it, per RB6 and RB8. |

**`actor` and `target` are separate objects and neither is optional**. An
audit table that fuses them into one `user_id` cannot say who granted the
access it records. Each carries a `type`, the application's own **public id**
(never an internal key, IP1), and a `display` string captured at write time
(AE4).

```
actor:  { type: "user",     id: "01923e8a-…", display: "Dana Okoye <dana@…>",
          ip: "…", user_agent: "…", impersonator: { … } }
target: { type: "user",     id: "01923f10-…", display: "Sam Reyes <sam@…>" }
action: "user.grant_role"
```

That row answers *who gave Sam that role*.

`actor.type` is one of `user`, `service`, `system` (a scheduled or maintenance
job with no human behind it) or `anonymous`. **`anonymous` means the application
has no local record to point at**, and it appears on both sides for different
reasons.

As an actor it appears on a refused authentication and on AU6's
authenticated-but-unknown subject. Those are the only two acts where no
identified actor can exist. As a target it appears on a failed login naming an
account that does not exist. The attempted identifier is then carried as
`display` and nothing else. An anonymous actor anywhere else is an
implementation that failed to resolve the actor and wrote a placeholder. So the
schema admits it only on those two actions.

Where the attempted account *does* exist, the target is that user with their
real public id. That is the more useful row, because failed attempts per
account is a question somebody eventually asks.

`actor.impersonator` is present, and required, whenever a support or admin
feature let one person act as another. The act is recorded as the impersonated
user because that is what happened, and the impersonator is recorded because
that is who is accountable. An impersonation feature whose audit rows do not
distinguish the two is an accountability hole with a support ticket attached.

**`decision` states the capacity an act was done in.** It carries the
permission, the grant that satisfied it, and the scope the check asked about.
Where RB11 decided it, it also carries the object and the condition. On a
refusal it carries the denial instead of the grant. RB6 says an act names the
capacity it was done in, and this member is where that name is queryable.

### AE3. The action names the permission that authorized it

`action` is `resource.verb`, matching the RBAC permission format exactly:
`^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`, the same pattern
[`070-rbac.md`](070-rbac.md) RB2 pins.

**Where an act was authorized by a permission, the action string *is* that
permission**. Not a paraphrase of it, not a past-tense rendering of it: the
same bytes. Two things follow, and both are worth the small grammatical
awkwardness of an imperative in a record of the past:

- *"Show me everything anyone did under `invoice.void` last quarter"* is one
  query against one column. It is not a mapping table somebody has to maintain
  between two vocabularies for the same concept.
- **AE5's floor becomes mechanically checkable**. A checker can enumerate the
  permissions a product declares, select the destructive ones, and assert an
  audit event exists carrying each. That is only possible while the two
  vocabularies are one vocabulary.

Some auditable acts have no permission behind them, because they happen before
or outside authorization. Those come from a small reserved namespace this
standard owns, so that every product spells them identically:

| Reserved action | Emitted when |
|---|---|
| `auth.login` | A session was established. |
| `auth.login_failed` | Authentication was attempted and refused. `actor.type` is `anonymous`; the account that was aimed at is the `target`. |
| `auth.logout` | The user ended the session. |
| `auth.session_revoked` | The session was ended by something other than the user: back-channel logout, an administrator, an expiry. |
| `auth.access_denied` | An authenticated subject was refused with no permission in play: [`060-auth.md`](060-auth.md) AU6's unknown subject, a host the session is not in, a session with no grant. |
| `auth.grant_activated` | A session bound to a grant, or changed which grant it acts in. It carries the grant activated, and the previous grant where there was one. |

**`auth.grant_activated` is one action for both acts**. There is no second
action for the change. A session acts in one grant
([`070-rbac.md`](070-rbac.md) RB5), and binding to a grant and rebinding to
another are the same act on the same record. The event's fields say which one
happened, because the previous grant is present on a change and absent on the
first binding. Two actions for one act make *when did this person's capacity
change* a query that needs a union.

A product does not add to this namespace; `auth.*` is this standard's. Everything
else a product audits is one of its own declared permissions.

**A refusal by a permission guard is recorded under that permission.** The
outcome is `failure`, and `reason` and `decision.denial` carry the RB8
denial. `auth.access_denied` is never used for it. One query over
a permission then returns what was done under it and what was refused.

### AE4. An audit event is self-contained, immutable, and outlives its subject

An audit row is read years after it is written. By then the user has been
deleted, the record renamed, the role redefined, and the tenant offboarded.
**A row that must join to living tables to be legible is not an audit trail; it
is a report that stops working**.

So:

- **Human-readable identity is denormalized at write time**. `actor.display` and
  `target.display` hold the values *as they were then*, not a foreign key
  resolved at read time. Both are carried alongside the public id, never instead
  of it. The id is the durable identity, and the display is what makes the row
  readable.
- **Events are append-only**. No `UPDATE`, no `DELETE`, no correcting a row. A
  mistaken event is followed by another event, exactly as a ledger is corrected
  by a reversing entry and never by an eraser. Retention (AE7) is the only
  removal, and redaction (AE11) the only change.
- **Removing a person changes nothing in their history**. A person who leaves,
  or whose account is deleted, still did what the events say they did. That
  is why the display is captured at write time: the trail stays legible after
  the person is gone. A building keeps its door log when an employee leaves,
  for the same reason.
- **Deleting the target never deletes its events**. The history of a deleted
  invoice is the part you most need. Cascade-delete on a foreign key to the
  audit table is how it goes away silently. The audit store holds public ids
  precisely so that no foreign-key constraint can reach into it.
- **`changes` records values, not references**. A before/after entry holds the
  values as serialized under the identifiers contract. So the row still says
  what changed after the code that produced it has been rewritten twice.

`changes` never carries a secret, a credential, or a raw authentication factor.
A changed password is audited as *the password changed*, with no value on either
side; the same holds for tokens, keys and recovery codes. This is
[`030-service.md`](030-service.md) SC2's rule about what a log line is permitted
to carry, applied to the store that keeps things longest.

### AE5. The floor: what must emit an event

An act is auditable when a person, later, could reasonably need to know it
happened. That is a judgment, so the standard states a floor that is not:

1. **Authentication and session lifecycle**: every reserved action in AE3.
2. **Authorization changes**: `grant` and `revoke`, which
   [`070-rbac.md`](070-rbac.md) RB7 already calls audited events; a role's
   permission set changing; a role being created, renamed or deleted.
3. **Identity lifecycle**: the five operations of [`060-auth.md`](060-auth.md)
   AU4. A person invited, app access granted, app access revoked, the local
   record removed, a login email changed.
4. **Destructive and irreversible writes**: delete, void, cancel, refund,
   publish, and anything a user cannot undo from the interface.
5. **Security-posture configuration changes**: session lifetimes, allowed
   origins, provider configuration, anything that changes who can get in.
6. **Bulk export of personal data**, which is a read but is the read that gets
   asked about.

**Reads are otherwise not audited**. Auditing every `GET` converts the audit
store into a log store: unqueryable, expensive, and with the six categories
above buried inside it. Where a specific regulatory obligation requires read
auditing of a specific dataset, the product states which dataset and why in its
own **Conventions**. It audits that one rather than everything.

The review question this puts on a diff, in the words a reviewer asks it:
**this route destroys something; where is the audit event?**

### AE6. Append-only discipline is required; hash chaining is not

**This standard requires append-only storage discipline, and does not require
tamper-evidence**.

Append-only discipline means the writes are the only writes. The application's
database grant on the audit table carries `INSERT` and `SELECT` and not
`UPDATE` or `DELETE`, where the engine allows that separation. The code path
has no update or delete to begin with. Retention deletion (AE7) runs under the
schema owner's credential and by policy, never as a capability the request
path holds.

**The application role has one name and one origin**. It is the product's
name in snake case followed by `_app`. A migration creates it and grants it
every table, so a database built from migrations alone has it. The deployment
sets its password from the secret named for the product, `<PRODUCT>_DB_APP_PASSWORD`.
The owner runs the migrations; the application role never does.

Hash chaining, where each row carries a hash of its predecessor, is **not
required**, though it is the intuitive answer. A chain is only tamper-*evident*
against someone who cannot recompute it. Suppose the chain lives in the same
database as the rows, and the application holds credentials to both. An
attacker with those credentials rewrites the row and the chain together, and
the verification passes. What the chain does buy in that configuration is
detection of accidental modification, at the cost of a single-tailed
serialization point every writer contends on. That is a real throughput cost
for a property that has not been obtained.

Tamper-evidence that means something requires the verifier to be somewhere the
writer cannot reach. So where a product has a **stated** obligation for it, the
answer is one of:

- **export to an append-only external store**: object storage with an object
  lock, or a SIEM the application cannot write backwards into. That boundary
  is where OCSF applies; or
- **signing with a key the application cannot use to re-sign history**.

Either of those can be *combined* with a hash chain, and then the chain is
worth having, because the anchor is out of reach. A product doing this says so
in its **Conventions** and names which of the two it did. A chain with no
external anchor is ceremony, and this standard would rather a product spend the
effort on AE8.

### AE7. The product sets its retention period, and one operation applies it

**Audit events are tenant-scoped data**, held under the same isolation rules as
any other tenant data: the [structured-data standard](025-structured-data.md)'s.
A query that can read another tenant's audit rows is the same defect as one
that can read their invoices. It is worse in disclosure terms, because audit
rows are a map of who does what inside that organisation.

**The retention period is the product's choice, and it is set in code**. The
product passes it to the platform's audit module, and the module applies the
value it is given. Where the product passes none, the module's default is 400
days. The product states its period, and the reason for it, in its
**Conventions**. No environment variable sets it, because a period a
deployment can change is a trail a deployment can empty.

**Retention is one operation with one name**. `audit-retain` is a subcommand
of the product image's own entry point, and the platform's audit module
implements it. It deletes the events older than the period, and nothing else.
It connects with the schema owner's credential, read from `DATABASE_URL`,
because the application role holds no `DELETE` (AE6).

**The product's part is the connection and the period**. The module opens no
connection of its own. So the product opens one from `DATABASE_URL`, and
hands it to the module with its period. A product writes no other retention
code.

**The deployment runs it daily, as `audit-retain --daily`**. The module's
command then runs once, waits a day after a success or an hour after a
failure, and runs again. A product never schedules its own retention. So every
product's trail is maintained the same way, and a product that lacks the
subcommand fails visibly in its own deployment.

### AE8. The event is written with the change, or the failure is loud

The value of an audit trail is the inference *nothing happened, because there is
no event*. That inference is only sound if a change cannot commit without its
event.

**Where the change and the audit event share a datastore, they share a
transaction**. Both land or neither does. This is cheap, and it is available in
every admitted engine. It converts the audit trail from a best-effort
side-channel into a property of the write.

Sometimes they genuinely cannot: the change is in an external system, or the
audit store is separate infrastructure. Then the fallback is fixed:

- The event is written **after** the change succeeds, never before, so the record
  cannot claim something that did not happen.
- A failed audit write is logged at `error` with the **entire event payload
  inline**, per [`030-service.md`](030-service.md) SC2. The record then exists
  somewhere a human can recover it from.
- The operation's own outcome states what happened. Silently swallowing the
  audit failure and returning `200` is the one response that is never
  acceptable. It produces exactly the gap the inference above assumes cannot
  exist.

**Audit writes are never fire-and-forget**. An unawaited promise, an unchecked
error return, or a queue publish nobody confirms all produce a trail with holes
that nothing reports. A trail with unreported holes is worse than no trail,
because it is trusted.

### AE9. An audit event is produced by the service, and a client produces none

A browser or a native client never writes an audit event. It has no clock the
service trusts, no actor it can prove, and no transaction to share. The service
records the act at the moment it performs it, with the actor it authenticated.
A client error report ([`090-web-client.md`](090-web-client.md) WC5) is
telemetry with a closed shape, and it is not an audit event. No route accepts
an audit event from a caller. A history screen renders what a service route
reads from the audit store, under a declared permission.

### AE10. `actor.ip` is the socket peer unless a declared proxy forwarded it

A forwarding header is the caller's to write unless a trusted hop wrote it.
The service reads one only when the connection peer is a proxy the product
declared. Otherwise `actor.ip` is the address the connection arrived from. The
declaration names the header and the proxy addresses, in configuration and
never in code. The same posture governs the client-error limiter's key under
WC5.

**The declaration is one variable, `TRUSTED_PROXY`**. Its value is the header,
a space, then comma-separated CIDR prefixes, such as
`X-Real-IP 172.16.0.0/12`. The header is `X-Real-IP`, which the edge
overwrites with the client's address on every request. A product reads no
other variable for it, and the platform's audit module parses it.

### AE11. Redaction is a rare exception a product builds in code

**By default no event is ever changed** (AE4). Redaction is the one
exception. It blanks the identification of one named person in events that
name them, and keeps the event. A product turns it on only by a code change
that calls the platform's audit module, never by configuration or a document.

Redaction has a narrow reach:

- **The target, never the actor.** A person who acted in a role, as an
  employee, an administrator or an operator, stays named. That record is the
  accountability the trail exists for.
- **What it blanks.** The target's `display`, and the personal values inside
  `changes`. The ids, the action, the outcome and the instant remain.
- **Where it applies.** A person who was acted on and was never a user, such
  as a candidate or a lead. Or a regime or a client contract that names it.
  The product names which in its **Conventions**.
- **How it runs.** The module's redaction operation, under the schema owner's
  credential, outside the request path. It stamps `erased_at` and
  `erased_subjects`, and records its own event.

A product with no such case does not build it. Most products never need it,
because the record of who did what is what the trail is for. Data kept for
accountability and for legal claims is commonly exempt from erasure requests.
A product under a regime that says otherwise confirms it with counsel first.

## The artifacts

Per PC3, under [`contracts/audit/`](../contracts/audit/):

- **`event.schema.json`**: the AE2 event as JSON Schema 2020-12, carrying the
  AE3 action pattern, the reserved `auth.*` set, the `decision` block, and
  AE2's conditional rules.
- **`corpus.json`**: `validity` cases for whole events, `floor` cases per AE5
  category, and `redaction` cases for AE11's exception.
- **`table.postgres.sql`, `table.mysql.sql`, `table.sqlite.sql`**: the table
  every product applies, one column per AE2 member, with the AE6 grant block
  where the engine has roles. A product's migration carries the file verbatim.

## Decisions

- **A guard refusal under `auth.access_denied`.** One reserved action for every
  refusal was weighed and not taken. A refusal of `invoice.void` would then not
  be found by a query over `invoice.void`. The permission vocabulary and the
  action vocabulary would fork on the rows that matter most.
- **The capacity as text in `reason`.** Not taken. A capacity is a thing a
  query asks for, and free text is not a key. Three implementations would
  spell it three ways.
- **A client-emitted event through a signed request.** Not taken. The service
  is the only witness with a clock it trusts, a verified actor and a
  transaction to share.
- **Trusting a forwarding header unconditionally.** Not taken. The address in
  the record is then the caller's to choose, and so is the limiter's key.
- **One JSON column per event instead of a table shape.** Not taken.
  Retention, redaction and the indexes on action, actor, target and tenant then
  become a query each product writes for itself.
- **Redacting on every erasure request.** Not taken. It rewrites the record of
  who did what each time a person leaves. That record is what the trail is
  for, and it is commonly exempt from erasure.
- **A retention floor and ceiling enforced by the module.** Not taken. The
  period is the product's policy, and the module applies the value it is given.
- **The retention period in an environment variable.** Not taken. A value one
  edit away in a deployment can empty the trail, and a policy belongs in
  reviewed code.
- **A product's own retention command or schedule.** Not taken. Each product
  then maintains one table its own way, and each way fails differently.
