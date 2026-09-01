# Audit events: who did what, when, to what

One of the Aurum Alpha engineering standards, written under the platform
contract ([`platform.md`](platform.md)) — a per-capability standard from its
roster. Read [`enforcement.md`](enforcement.md) for the tier each rule below
actually holds. Artifacts: [`contracts/audit/`](../contracts/audit/). Id,
timestamp and money formats are [`identifiers.md`](identifiers.md)'s; the
context fields are [`observability.md`](observability.md)'s.

This document defines the record a product keeps of consequential acts: its
shape, what must produce one, how long it is kept, and what makes it worth
trusting. It does not define who is allowed to perform those acts — that is the
[RBAC standard](rbac.md)'s — and it does not define diagnostic logging, which is
[`service.md`](service.md) SC2's. AE1 is the boundary between the last two,
because conflating them is the failure this standard mostly exists to stop.

## Why this exists

When a client asks *who changed this, and when*, whether an answer exists
currently depends on which product they bought. Most of the fleet has no audit
trail at all. One product has one, and it is worth looking at closely, because
every way it goes wrong is a way the next one will go wrong by default.

`event-manager` carries `tenant_access_audit_log`: a table with `user_id`,
`action`, `organization_id`, `role_id`, `access_type`, `reason`, `ip_address`,
`user_agent`, `created_at`. It has a closed seven-value action enum with a
well-kept PHP enum class behind it, two considered indexes, and a sibling table
that was created, renamed, and later dropped.

**Nothing writes to it.** The only files in that repository that name the table
are the migrations that create and rename it, and a database diagram. The action
enum is referenced by nothing. It is a well-designed empty table, which is the
most expensive kind: it looks like the question was answered.

Four things are wrong with it beyond being empty, and each is instructive:

- **One `user_id` for two different people.** On a `grant` row, the column holds
  the person who received access. Nowhere does the table record the admin who
  granted it. The one question an access audit log exists to answer — *who gave
  them that* — is unanswerable by construction. Actor and target are two fields,
  and every implementation that fuses them discovers this on the day it matters.
- **Internal integer keys in a permanent record.** `user_id`, `organization_id`
  and `role_id` are storage keys, which [`identifiers.md`](identifiers.md) IP1
  says do not leave the service. An audit row is the extreme case of leaving: it
  outlives the row it points at, so a key-based reference degrades to a number
  that once meant something.
- **`TIMESTAMP DEFAULT CURRENT_TIMESTAMP`** — the exact column type IP4 names as
  a trap, ending in 2038 and converting through the session time zone, on the one
  table whose entire value is being right about when.
- **No trace or request context**, so an audit row cannot be joined to the logs
  of the request that produced it.

None of this is carelessness; it is what happens when each product invents the
table. The gap is not that the fleet lacks an audit library. It is that nobody
has said what an audit event *is*, so each product answers structurally and each
answers differently — the failure this whole repository exists to prevent, on a
capability where the cost lands on a client rather than on us.

### The standard evaluated first, per PC2

No wire standard covers application-level audit, and two candidates are close
enough that skipping them would be dishonest.

**OCSF** (the [Open Cybersecurity Schema
Framework](https://github.com/ocsf/ocsf-schema)) is the serious one: an active,
vendor-backed schema with an Application Activity category (Web Resources
Activity, Application Lifecycle, API Activity) and an Identity & Access
Management category, and it is what a SIEM wants to be fed. It is **not adopted
as the record**, for one reason that is about shape rather than quality: OCSF is
a *normalization target for security telemetry*, and its own project says the
focus is cybersecurity events. Its class taxonomy is closed and
security-shaped — there is no class for `invoice.void`, and forcing one into
API Activity throws away the domain meaning that makes the record useful on a
product's own history screen. Its required `class_uid` / `category_uid` /
`activity_id` machinery is meaningful to a SIEM and meaningless to the admin
reading a support ticket.

So OCSF is the **export target, not the record**: AE2's field names are chosen
to map onto OCSF's dictionary where OCSF has an equivalent (`actor`, `time`,
`status`, `metadata`), and a product feeding a SIEM maps at that boundary rather
than deforming its own store. The mapping is an integration, which is where a
normalization schema belongs.

**Security Event Token** ([RFC 8417](https://www.rfc-editor.org/info/rfc8417/))
with the OpenID Shared Signals Framework and CAEP is the second, and it is
solving a genuinely different problem: statements of fact from one issuer to
another *cooperating peer* about a security subject — session revoked,
credential changed — so the receiver can react. It is a signalling protocol
between domains, not a record kept within one. The fleet already meets it in the
right place: [`auth.md`](auth.md) AU5 adopts OIDC Back-Channel Logout, which is
that family. It is not an audit trail and does not claim to be.

**CloudEvents** is an envelope, not a content schema, and is already the
candidate the async messaging capability evaluates. Where a product ships audit
events onto a bus, it is the envelope and AE2 is the payload; that is
composition, not competition.

The invention is therefore scoped the way PC2 requires: the fleet defines the
**event's content**, and everything around it stays standard — trace context is
W3C, ids and timestamps are the identifiers contract's, transport is the async
envelope's, export is OCSF's.

## The rules

### AE1. An audit event is data, not a log line

This is the rule everything else rests on, and the one most often lost by
accident, because an audit event and a log line look identical in a terminal.

They are different things with different readers:

| | Log line (SC2) | Audit event |
|---|---|---|
| Reader | An engineer, during an incident | An administrator, an auditor, a client |
| Question | Why is this broken | Who did this, and when |
| Completeness | Best-effort; sampling and level filtering are legitimate | Complete, or it is not evidence |
| Lifetime | Days to weeks | A year at minimum (AE7) |
| Queried by | A human with a log search tool | **The application itself**, on a history screen |
| Owner | The execution environment | The application |

**Audit events are written to the application's own durable, queryable,
tenant-scoped storage.** They are business data that happens to resemble
telemetry. A product's "history of this record" panel is a query over them; an
administrator's access review is a query over them; a client's "show me last
year" request is a query over them. Data the application queries lives in the
application's datastore.

An implementation **may additionally** emit the event to the log stream — it is
often convenient — but **the log stream is never the system of record.** A
product that writes audit events only to stdout and relies on the platform's log
pipeline to retain them for a year has made three bets it cannot honour: that
nothing samples, that retention is set correctly and stays set, and that a
ten-month-old line is still queryable by tenant on a support call. Two of those
are outside the application's control entirely.

*On [factor XI](https://12factor.net/logs), because the objection is the obvious
one:* factor XI says an application must not concern itself with the routing or
storage of **its log stream**, and [`service.md`](service.md) SC2 adopts that
whole. This rule is not a departure from it, because an audit event is not a log
line — it is application data, and its store is an attached resource in the sense
of [factor IV](https://12factor.net/backing-services), named by config and
swappable per deploy, exactly like every other table the product owns. Reading
factor XI as covering audit records would make it say that an application must
not store its own data, which is the opposite of what it says.

### AE2. One event shape, and actor is not target

Every audit event in the fleet is the same object, whatever produced it:

| Field | Meaning |
|---|---|
| `schema_version` | Per PC6. |
| `event_id` | The event's own public id (UUIDv7, IP2). What a support ticket quotes and what makes a replayed delivery deduplicable. |
| `occurred_at` | When the act happened, from a clock, RFC 3339 UTC per IP4. **Not** when the row was written — those differ for queued and retried work, and the difference is the interesting one. |
| `action` | What was done, per AE3. |
| `outcome` | `success` or `failure`. A refused act is auditable and is usually the more interesting row. |
| `actor` | **Who did it.** |
| `target` | **What it was done to.** |
| `tenant_id` | The tenant the act happened in, per OC2. |
| `trace_id`, `request_id`, `span_id` | The request that produced it, per OC2 and OC4 — so an audit row joins to the logs of its own request. |
| `changes` | Optional. What the act altered, as before/after per field. |
| `reason` | Optional free text: the justification an administrator typed, or the decision reason from RBAC's RB8 on a refusal. |

**`actor` and `target` are separate objects and neither is optional**, which is
the `event-manager` lesson stated as a rule. Each carries a `type`, the
application's own **public id** (never an internal key, IP1), and a `display`
string captured at write time (AE4).

```
actor:  { type: "user",     id: "01923e8a-…", display: "Dana Okoye <dana@…>",
          ip: "…", user_agent: "…", impersonator: { … } }
target: { type: "user",     id: "01923f10-…", display: "Sam Reyes <sam@…>" }
action: "user.grant_role"
```

That row answers *who gave Sam that role*. The table in the Why section cannot.

`actor.type` is one of `user`, `service`, `system` (a scheduled or maintenance
job with no human behind it) or `anonymous`. **`anonymous` means the application
has no local record to point at**, and it appears on both sides for different
reasons: as an actor on a refused authentication and on AU6's
authenticated-but-unknown subject, which are the only two acts where no
identified actor can exist; as a target on a failed login naming an account that
does not exist, where the attempted identifier is carried as `display` and
nothing else. An anonymous actor anywhere else is an implementation that failed
to resolve the actor and wrote a placeholder, so the schema admits it only on
those two actions. Where the attempted account *does* exist, the target is that
user with their real public id — which is the more useful row, because failed
attempts per account is a question somebody eventually asks.

`actor.impersonator` is present, and
required, whenever a support or admin feature let one person act as another —
the act is recorded as the impersonated user because that is what happened, and
the impersonator is recorded because that is who is accountable. An
impersonation feature whose audit rows do not distinguish the two is an
accountability hole with a support ticket attached.

### AE3. The action names the permission that authorized it

`action` is `resource.verb`, matching the RBAC permission format exactly —
`^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`, the same pattern [`rbac.md`](rbac.md) RB2
pins.

**Where an act was authorized by a permission, the action string *is* that
permission.** Not a paraphrase of it, not a past-tense rendering of it — the
same bytes. Two things follow, and both are worth the small grammatical
awkwardness of an imperative in a record of the past:

- *"Show me everything anyone did under `invoice.void` last quarter"* is one
  query against one column, rather than a mapping table somebody has to maintain
  between two vocabularies for the same concept.
- **AE5's floor becomes mechanically checkable.** A checker can enumerate the
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
| `auth.session_revoked` | The session was ended by something other than the user — back-channel logout, an administrator, an expiry. |
| `auth.access_denied` | An authenticated subject was refused, including [`auth.md`](auth.md) AU6's unknown-subject refusal. |

A product does not add to this namespace; `auth.*` is the fleet's. Everything
else a product audits is one of its own declared permissions.

### AE4. An audit event is self-contained, immutable, and outlives its subject

An audit row is read years after it is written, by which time the user has been
deleted, the record renamed, the role redefined, and the tenant offboarded.
**A row that must join to living tables to be legible is not an audit trail; it
is a report that stops working.**

So:

- **Human-readable identity is denormalized at write time.** `actor.display` and
  `target.display` hold the values *as they were then*, not a foreign key
  resolved at read time. Both are carried alongside the public id, never instead
  of it: the id is the durable identity, the display is what makes the row
  readable.
- **Events are append-only.** No `UPDATE`, no `DELETE`, no correcting a row. A
  mistaken event is followed by another event, exactly as a ledger is corrected
  by a reversing entry and never by an eraser.
- **Deleting the target never deletes its events.** The history of a deleted
  invoice is the part you most need, and cascade-delete on a foreign key to the
  audit table is how it goes away silently. The audit store holds public ids
  precisely so that no foreign-key constraint can reach into it.
- **`changes` records values, not references.** A before/after entry holds the
  values as serialized under the identifiers contract, so the row still says what
  changed after the code that produced it has been rewritten twice.

`changes` never carries a secret, a credential, or a raw authentication factor.
A changed password is audited as *the password changed*, with no value on either
side; the same holds for tokens, keys and recovery codes. This is
[`service.md`](service.md) SC2's rule about what a log line may carry, applied to
the store that keeps things longest.

### AE5. The floor: what must emit an event

An act is auditable when a person, later, could reasonably need to know it
happened. That is a judgment, so the standard states a floor that is not:

1. **Authentication and session lifecycle** — every reserved action in AE3.
2. **Authorization changes** — `grant` and `revoke`, which
   [`rbac.md`](rbac.md) RB7 already calls audited events; a role's permission
   set changing; a role being created, renamed or deleted.
3. **Identity lifecycle** — the four operations of [`auth.md`](auth.md) AU4:
   a person invited, app access granted, app access revoked, the local record
   removed.
4. **Destructive and irreversible writes** — delete, void, cancel, refund,
   publish, and anything a user cannot undo from the interface.
5. **Security-posture configuration changes** — session lifetimes, allowed
   origins, provider configuration, anything that changes who can get in.
6. **Bulk export of personal data**, which is a read but is the read that gets
   asked about.

**Reads are otherwise not audited.** Auditing every `GET` converts the audit
store into a log store — unqueryable, expensive, and with the six categories
above buried inside it. Where a specific regulatory obligation requires read
auditing of a specific dataset, the product states which dataset and why in its
own **Conventions**, and audits that one rather than everything.

The review question this puts on a diff, stated so a reviewer can ask it in
those words: **this route destroys something — where is the audit event?**

### AE6. Append-only discipline is required; hash chaining is not

The integrity question deserves a decision rather than whatever a framework
ships, so: **the fleet requires append-only storage discipline, and does not
require tamper-evidence.**

Append-only discipline means the writes are the only writes: the application's
database grant on the audit table carries `INSERT` and `SELECT` and not `UPDATE`
or `DELETE`, where the engine allows that separation, and the code path has no
update or delete to begin with. Retention deletion (AE7) runs under a separate,
narrower credential and by policy — never as a capability the request path holds.

Hash chaining — each row carrying a hash of its predecessor — is **not required,
and the reasoning matters because it is the intuitive answer**. A chain is only
tamper-*evident* against someone who cannot recompute it. Where the chain lives
in the same database as the rows, and the application holds credentials to both,
an attacker with those credentials rewrites the row and the chain together and
the verification passes. What the chain does buy in that configuration is
detection of accidental modification, at the cost of a single-tailed
serialization point every writer contends on. That is a real throughput cost for
a property that has not been obtained.

Tamper-evidence that means something requires the verifier to be somewhere the
writer cannot reach. So where a product has a **stated** obligation for it, the
answer is one of:

- **export to an append-only external store** — object storage with an object
  lock, or a SIEM the application cannot write backwards into (OCSF at that
  boundary, per the evaluation above); or
- **signing with a key the application cannot use to re-sign history**.

Either of those may be *combined* with a hash chain, and then the chain is worth
having, because the anchor is out of reach. A product doing this says so in its
**Conventions** and names which of the two it did. A chain with no external
anchor is ceremony, and this standard would rather a product spend the effort on
AE8.

### AE7. Retention has a floor, a ceiling, and survives erasure

**Audit events are tenant-scoped data**, held under the same isolation rules as
any other tenant data — the [data-layer
standard](platform.md#the-capability-roster)'s, when it lands. A query that can
read another tenant's audit rows is the same defect as one that can read their
invoices, and worse in disclosure terms, because audit rows are a map of who
does what inside that organisation.

**The retention floor is one year**, and the number has a reason rather than
being a round one: it is the shortest window that covers an annual audit cycle
and the ordinary contractual clause asking for records covering the prior year.
Below that, the first time a client asks, the honest answer is that it is gone.
Products under a specific regime — financial, health, a client contract naming a
period — set longer in their **Conventions** and say which obligation set it.

**There is a ceiling too, and it is deliberate.** Audit rows are a detailed
record of identified people's behaviour, so keeping them forever is an
accumulating liability rather than diligence. A product states its retention
period and deletes on it, by policy. "We never delete" is a decision to hold
personal data indefinitely, and it should be made on purpose if it is made.

**Erasure and audit do not actually conflict**, though they are usually
presented as if they do. When a data subject's erasure request is honoured, the
**event survives and the identifying content is removed**: `actor.id` and
`target.id` remain, `display`, `ip`, `user_agent` and any personal values inside
`changes` are replaced with a tombstone marker. What is kept is *"subject
01923e8a-… voided invoice `inv_9Kd…` on 2026-03-04"* — the shape of the trail,
the sequence, the accountability — and what is lost is the identification, which
is what was asked for. This is the one modification permitted against AE4's
append-only rule; it is a defined operation with its own audit event, not an
`UPDATE` available to application code. The request that triggers it belongs to
the [data-subject-rights
standard](platform.md#the-capability-roster).

### AE8. The event is written with the change, or the failure is loud

The value of an audit trail is the inference *nothing happened, because there is
no event*. That inference is only sound if a change cannot commit without its
event.

**Where the change and the audit event share a datastore, they share a
transaction.** Both land or neither does. This is cheap, it is available in every
engine the fleet runs, and it converts the audit trail from a best-effort
side-channel into a property of the write.

Where they genuinely cannot — the change is in an external system, or the audit
store is separate infrastructure — the fallback is stated rather than left to
each implementation:

- The event is written **after** the change succeeds, never before, so the record
  cannot claim something that did not happen.
- A failed audit write is logged at `error` with the **entire event payload
  inline**, per [`service.md`](service.md) SC2, so the record exists somewhere a
  human can recover it from.
- The operation's own outcome states what happened. Silently swallowing the audit
  failure and returning `200` is the one response that is never acceptable, because
  it produces exactly the gap the inference above assumes cannot exist.

**Audit writes are never fire-and-forget.** An unawaited promise, an unchecked
error return, or a queue publish nobody confirms all produce a trail with holes
that nothing reports — and a trail with unreported holes is worse than no trail,
because it is trusted.

## The artifacts

Per PC3, under [`contracts/audit/`](../contracts/audit/):

- **`event.schema.json`** — the AE2 event as JSON Schema 2020-12, `$ref`-ing the
  identifiers primitives for ids and timestamps and the observability context
  defs for the id vocabulary, rather than restating either. Carries the AE3
  action pattern, the reserved `auth.*` set, and the conditional rules that make
  AE2 more than a field list: `actor.type: anonymous` only on the actions where
  no actor can exist, `impersonator` well-formed where present, `changes` entries
  shaped as before/after.
- **`corpus.json`** — `validity` cases for whole events, accepted and rejected
  with a stated reason; `floor` cases mapping each AE5 category to the event an
  implementation must produce for a described act; and `redaction` cases carrying
  an event before and after AE7's erasure, so an implementation's erasure is
  checked against the same file as its emission.

## Enforcement

Registered in [`enforcement.md`](enforcement.md) under "Audit standard". Every
rule lands review-only, as the charter requires, and the gates named below are
commitments.

- **AE2, AE3 and AE4's shape rules are corpus-decided** under
  `job-contract-conformance`: an implementation emits events for the corpus's
  described acts and every one validates, or the case that failed is named. The
  actor/target separation is checked by the schema itself, since both are
  required and typed.
- **AE3's second half gets a static check.** Because the action vocabulary and
  the permission vocabulary are one vocabulary (that is the rule's whole point),
  a checker can read a product's declared permission set and assert every action
  string emitted is either a declared permission or a reserved `auth.*` action.
  Cheap, and it catches the paraphrase drift that otherwise arrives one action
  at a time.
- **AE5 gets the generative gate, and it is the one worth the most here** —
  the enumerate-don't-list pattern: enumerate the routes guarded by a
  destructive permission, exercise each, assert an event carrying that
  permission as its action. A list of routes to audit rots the day someone adds
  a route; an enumeration cannot.
- **AE6's discipline is partly a schema fact**: that the audit table's grant
  excludes `UPDATE` and `DELETE` is readable once the data-layer standard gives
  a checker a schema to read. That the code path has no update is a review
  question.
- **AE8 resists a checker and stays a review question**, honestly — whether a
  write shares the change's transaction is a fact about a call graph, not about
  a boundary, and PC4 forbids a gate that reads the implementation. The corpus
  reaches the observable half: an act that fails produces no event, and an act
  that succeeds produces exactly one.
- **AE1 and AE7 stay review questions.** That a store is the system of record
  rather than a convenience, and that a retention period was chosen rather than
  defaulted, are judgments about intent.

## Decisions

- **OCSF is the export target, not the record** (2026-09-01): the strongest
  candidate and the one worth the most words, because rejecting it outright
  would be wrong and adopting it whole would deform every product's own history
  screen into SIEM shape. Its taxonomy is closed and security-shaped; a fleet
  event carries domain meaning OCSF has no class for. Mapping at the SIEM
  boundary keeps both — which is what PC2 means by scoping an invention.
- **Actor and target are two required fields** (2026-09-01): the fleet's one
  existing audit table fused them and cannot answer who granted access. This is
  the single most consequential field-level decision in the document, and it was
  made by reading a table rather than by reasoning from first principles.
- **The action string is the permission string** (2026-09-01): the alternative
  is a past-tense audit vocabulary alongside the imperative permission
  vocabulary — two names for one concept, a mapping table between them, and no
  mechanical way to ask whether a permission's use is audited. The grammatical
  cost of `invoice.void` in a record of the past is worth what it buys.
- **Append-only discipline required, hash chaining not** (2026-09-01): a chain
  whose anchor sits in the same database the writer can rewrite detects
  accidents and nothing adversarial, while serializing every write on one tail.
  Where tamper-evidence is genuinely required, the property comes from an
  anchor outside the writer's reach, and the chain is then worth adding on top.
- **Reads are not audited by default** (2026-09-01): the opposite default turns
  the audit store into a log store and buries the six categories that matter.
  Read auditing is admitted per-dataset with a stated obligation.
- **Erasure redacts the event rather than deleting it** (2026-09-01): the
  supposed conflict between an erasure right and an audit obligation dissolves
  once the row is split into the parts that identify a person and the parts that
  record an act. The second survives; the first does not.
- **The event is written in the change's transaction** (2026-09-01): the
  inference an audit trail exists to support — *no event, therefore it did not
  happen* — is unsound under any weaker rule, and a trail that cannot support
  that inference is decoration.
