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
| Lifetime | Days to weeks | A year at minimum (AE7) |
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
platform's log pipeline to retain them for a year. That is three bets it cannot
honour. Nothing samples; retention is set correctly and stays set; a
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
| `auth.access_denied` | An authenticated subject was refused, including [`060-auth.md`](060-auth.md) AU6's unknown-subject refusal. |

A product does not add to this namespace; `auth.*` is this standard's. Everything
else a product audits is one of its own declared permissions.

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
  by a reversing entry and never by an eraser.
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
3. **Identity lifecycle**: the four operations of [`060-auth.md`](060-auth.md)
   AU4. A person invited, app access granted, app access revoked, the local
   record removed.
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
has no update or delete to begin with. Retention deletion (AE7) runs under a
separate, narrower credential and by policy, never as a capability the request
path holds.

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

### AE7. Retention has a floor, a ceiling, and survives erasure

**Audit events are tenant-scoped data**, held under the same isolation rules as
any other tenant data: the [structured-data standard](025-structured-data.md)'s.
A query that can read another tenant's audit rows is the same defect as one
that can read their invoices. It is worse in disclosure terms, because audit
rows are a map of who does what inside that organisation.

**The retention floor is one year**. It is the shortest window that covers an
annual audit cycle and the ordinary contractual clause asking for records
covering the prior year. Below that, the first time a client asks, the honest
answer is that it is gone. Products under a specific regime (financial, health,
a client contract naming a period) set longer in their **Conventions**. They
say which obligation set it.

**There is a ceiling too**. Audit rows are a detailed record of identified
people's behaviour, so keeping them forever is an accumulating liability rather
than diligence. A product states its retention period and deletes on it, by
policy. "We never delete" is a decision to hold personal data indefinitely, and
it must be made on purpose if it is made at all.

**Erasure and audit do not conflict**. When a data subject's erasure request is
honoured, the **event survives and the identifying content is removed**.
`actor.id` and `target.id` remain; `display`, `ip`, `user_agent` and any
personal values inside `changes` are replaced with a tombstone marker. What is
kept is *"subject 01923e8a-… voided invoice `inv_9Kd…` on 2026-03-04"*: the
shape of the trail, the sequence, the accountability. What is lost is the
identification, which is what was asked for.

This is the one modification permitted against AE4's append-only rule. It is a
defined operation with its own audit event, not an `UPDATE` available to
application code. The request that triggers it is
[`082-data-subject-rights.md`](082-data-subject-rights.md)'s. The redaction is
re-applied after any restore by the erasure ledger's replay
([`028-backup-and-recovery.md`](028-backup-and-recovery.md) BR6). So a restore
from a copy taken before the request does not undo it.

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

## The artifacts

Per PC3, under [`contracts/audit/`](../contracts/audit/):

- **`event.schema.json`**: the AE2 event as JSON Schema 2020-12, carrying the
  AE3 action pattern, the reserved `auth.*` set, and AE2's conditional rules.
- **`corpus.json`**: `validity` cases for whole events, `floor` cases per AE5
  category, and `redaction` cases for AE7's erasure.
