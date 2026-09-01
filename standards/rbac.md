# Authorization: the RBAC model, its operations, and its decision corpus

One of the Aurum Alpha engineering standards, written under the platform
contract ([`platform.md`](platform.md)) — a per-capability standard from its
roster. Read [`enforcement.md`](enforcement.md) for the tier each rule below
actually holds. Artifacts: [`contracts/rbac/`](../contracts/rbac/).

This document defines **who may do what**, as an interface specification:
a data model, a set of operations with defined semantics, and a corpus of
decision cases any implementation in any language must reproduce. It picks up
where [`auth.md`](auth.md) AU6 stops — that document produces a trustworthy
subject and refuses an unknown one; this one decides what a known subject may do.

## Why this exists

This is the platform contract's worked example of *an interface specification,
not a library*. Three languages implement it; one corpus judges all three.

It is also not being invented from nothing. Two products in the fleet have
built substantial RBAC systems independently, and **they agree on more than they
differ**: permissions as a closed set of `resource`-plus-`action` strings
declared in code, roles as named bundles of those permissions, grants scoped to
an organisational unit. That agreement is the fleet answer, and most of this
document is it, written down.

What they differ on is where the standard earns its keep. One keeps roles as a
closed enum in source; the other stores them as rows so a tenant can define its
own. One admits wildcards; the other does not. Those are real forks, and left
alone each new product picks one at random.

**And one of the two check implementations demonstrates, in working production
code, four failure shapes this document exists to prevent.** They are cited
below where each rule addresses one, because a rule with evidence behind it gets
followed and a rule asserted does not. Naming them is history, not a status
report — the migration is each repository's own work, in its own tracker.

## The rules

### RB1. Permissions are a closed set, declared in code

Every permission an application recognises is declared in one place in source —
an enum, a constant set, whatever the language offers — and that declaration is
the complete list. **A permission that is not in the set does not exist**, and a
check against an undeclared permission is an error rather than a denial.

Both existing implementations already do this and neither regrets it. The
property it buys is that *what can be granted* is answerable from the
repository, reviewable in a diff, and impossible to typo into existence.

The distinction that matters and is easy to lose: **the set of permissions is
fleet-standard in its shape and application-specific in its contents.** An
invoicing product has `invoice.approve` and a recruiting product does not. What
this standard fixes is the shape, the semantics and the operations — not the
vocabulary.

### RB2. A permission is `resource.action`

Lowercase, `snake_case` within each segment, a single dot between them:
`invoice.approve`, `candidate_process.advance`, `purchase_order.void`.

**The dot rather than a colon, for a reason that is not taste.** Scope
references in RB4 are `type:id` — `tenant:acme`, `job:8fK2mQ`. Using a colon in
both would give one separator two meanings in one system, and the first
ambiguous string is the one nobody notices. Reserving `:` for scope and `.` for
permission keeps every identifier parseable on sight.

Two segments, never three. A three-part permission is a resource that has not
been named: `system.dashboard.view` is `system_dashboard.view`, and writing it
the second way keeps the check a simple equality rather than a prefix question.

### RB3. A role is a named set of permissions, and every permission in it is real

Roles may be **declared in code** (a closed enum, reviewable in a diff, no
migration to change) or **stored as data** (so a tenant can define its own).
Both are admitted; a repository states which in its **Conventions**.

Whichever it is, one rule holds: **a role may contain only permissions from
RB1's declared set, and that is validated at write time.** A stored role with a
typo'd permission grants nothing and says nothing, and the failure surfaces
later as a person who cannot do something everyone believes they can.

**Roles do not nest and do not inherit.** A role that should have what another
role has lists the same permissions. Inheritance turns *what can this person do*
into a graph traversal, and the answer stops being readable from the role's own
definition.

### RB4. A grant binds a subject to a role within a scope

```
Grant { subject, role, scope }
```

**Scope is `global`, or a `type:id` pair** — `tenant:acme`, `company:8fK2mQ`,
`job:V1StGX`. The application declares which scope types exist and how they
contain one another; the standard fixes the shape and the containment
*algorithm*, not the hierarchy.

That split is deliberate. One existing implementation has a two-level scope
(system, organisation) and the other effectively has three (platform, agency,
company) with agencies containing companies. A standard that named the levels
would have fitted neither.

**Containment: a grant at a containing scope satisfies a check at a contained
one.** A grant at `tenant:acme` satisfies a check at `job:V1StGX` when the
application declares that job as within that tenant. `global` contains
everything.

A subject may hold many grants. They are evaluated together, and RB5 says how.

### RB5. Deny by default, additive only, and no permission means "everything"

Three semantics, and every one of them is a place implementations diverge unless
pinned.

**Deny by default.** No grant means deny. There is no "allow unless denied."

**Grants are additive, and there are no negative grants.** A subject's
permissions at a scope are the union of every grant that applies there. Deny
rules make the outcome depend on evaluation order, which makes two correct-looking
implementations disagree — and makes the corpus below impossible to write, since
there would be no single right answer to compare against.

To remove access, remove the grant.

**No wildcard is expanded at check time, and no permission grants any other.**
This is the rule with the most evidence behind it. `event-manager`'s check
short-circuits on `system.admin`, on `system.*` and on `*`, tested in three
places with slightly different conditions — three ways to say "everything", any
one of which silently defeats every other rule in this document.

The cost of that is not only the bypass. It makes `permissionsFor` **lie**: a
subject holding `*` has every permission and the list enumerates none of them, so
the `/me` document of [`auth.md`](auth.md) AU6 tells the client something untrue
and the interface renders the wrong screen.

A role that should have everything **enumerates everything**. `hiring-tracker`'s
`SUPER_ADMIN` does exactly this — ninety-odd lines listing every permission it
holds. That is verbose and it is honest, and the verbosity is a feature: adding a
permission to the system does not silently add it to the superuser.

Expansion is permitted at *definition* time. A role may be authored as "every
permission on `invoice`" and stored expanded. What must not happen is a wildcard
surviving into the check.

### RB6. `check` is a pure function of its arguments

```
check(subject, permission, scope) → Decision
```

**The scope is an argument, never ambient state.** The same subject, permission
and scope produce the same decision every time, given the same grants.

This is the rule that carries the most weight, and again there is evidence.
`event-manager`'s check reads an *active context* — the organisation the user
last selected — from session state rather than taking it as an argument. Two
consequences follow, and both are the kind that survive a long time:

- **The answer depends on where the user last clicked.** The same call, for the
  same user and permission, returns differently depending on session state that
  the caller did not pass and cannot see.
- **The permission cache keys on `userId` and the permission alone**, with no
  scope in the key. A permission cached as allowed in one organisation is
  returned as allowed in the next. That is a cross-tenant authorization result,
  produced by a cache key, and no test that exercises one tenant at a time will
  ever show it.

A pure `check` makes the second impossible by construction, and makes the corpus
of RB8 writable at all: *given these grants, this check returns deny* has no
meaning if the answer also depends on state the case cannot state.

#### The operations

| Operation | Semantics |
|---|---|
| `check(subject, permission, scope) → Decision` | The primitive. Deny by default. |
| `checkAny(subject, permissions[], scope) → Decision` | Allowed if any one is. |
| `checkAll(subject, permissions[], scope) → Decision` | Allowed only if every one is. |
| `permissionsFor(subject, scope) → permission[]` | The true, complete, enumerated set. Feeds `/me`. |
| `rolesFor(subject, scope) → role[]` | For display, and for an admin screen. |
| `grant(subject, role, scope)` / `revoke(subject, role, scope)` | Administrative. Both are audited events. |

`checkAny` and `checkAll` exist because both prior implementations grew them
independently, which is good evidence that a codebase without them writes the
loop by hand and gets it wrong somewhere.

### RB7. A decision carries its reason

`check` returns a **Decision**, not a boolean: the outcome, and *why* — which
grant and which role satisfied it, or that none did.

A denial that cannot say why is the reason-giving failure of
[`service.md`](service.md) SC2, on the surface where it matters most. It is also
the difference between an audit trail worth keeping and a log of the word
`false`.

The reason is what an application logs and what an administrator reads on a
support call. It is never returned to an unauthorised caller: the
[`http.md`](http.md) HA3 envelope that reaches the client says the request was
refused, and the reason stays in the log.

### RB8. A cached decision is keyed by everything the decision depends on

Caching authorization is normal and often necessary. Two rules make it safe.

**The cache key includes the subject, the permission and the scope** — every
argument of RB6's function, because a key missing one of them returns another
subject's or another tenant's answer. This is the failure quoted in RB6, stated
as a rule so it is caught in review rather than in production.

**Every path that changes a grant invalidates.** Granting, revoking, editing a
role's permissions, deactivating a subject. `event-manager` has learned this and
carries the invalidation surface to prove it —
`clearPermissionCache(userId)`, `clearCacheForUsersWithRole(roleId)` and
`clearAllPermissionCaches(reason)` with the reason recorded for audit. That
shape is worth copying: per-subject, per-role and global, because a role's
permission list changing affects every subject holding it and there is no
cheaper correct answer.

A stated maximum TTL bounds what invalidation misses. It is a backstop, not the
mechanism.

## The artifacts

Per PC3, under [`contracts/rbac/`](../contracts/rbac/):

- **`model.schema.json`** — permission, role, grant and scope shapes.
- **`decisions.json`** — **the corpus that matters**: a set of grants, then a
  list of checks with their expected decisions. This is the file that makes a
  polyglot standard enforceable from one source, and it is why RB6 requires a
  pure function. Three implementations, one judge.

## Enforcement

Every rule is review-only today, with gates named per rule in
[`enforcement.md`](enforcement.md). **This standard is the most gateable one in
the repository**, and that is the point of writing authorization as an interface
specification rather than as prose.

- **RB5, RB6 and RB4's containment are decided entirely by the decision
  corpus.** An implementation loads the grants, runs the checks, and either
  reproduces every expected decision or names the case it failed. No running
  service, no browser, no network — the corpus is data and the check is a
  function.
- **RB2's format is a static check** over the declared permission set: every
  entry matches `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`, which also catches the
  three-segment permissions RB2 forbids.
- **RB3's validation is testable** by attempting to store a role containing an
  undeclared permission and requiring a refusal.
- **RB8's cache key resists a static checker** and is caught by a corpus case
  instead: check a permission in one scope, then the same permission in another
  where it is not granted, and require deny. A cache keyed without scope fails
  it. This is the one gate that would have caught the production defect quoted
  in RB6.
- **RB1 and RB7 stay review questions.** That a declaration is genuinely the
  complete set, and that a reason is genuinely informative, are judgments about
  content rather than shape.

## Decisions

- **The dot for permissions, the colon for scopes** (2026-09-01): the two prior
  implementations split on this and neither had a reason. The reason chosen is
  that scope references need a separator too, and one separator with two meanings
  is where ambiguity starts.
- **Roles may be code-declared or data-stored; permissions may not**
  (2026-09-01): the fork between the two implementations was real and both sides
  had a case — type safety against tenant-defined roles. Admitting both while
  closing the permission set keeps what each was actually protecting.
- **No wildcards at check time** (2026-09-01): the strongest rule here, and the
  one most likely to be argued with, because `*` is convenient. It is rejected
  because it defeats every other rule silently and because it makes
  `permissionsFor` untrue, which the client contract now depends on.
- **No role inheritance** (2026-09-01): considered, because it removes
  duplication between similar roles. Rejected because it converts *what can this
  person do* from a lookup into a traversal, and because the duplication it
  removes is duplication a reviewer can see.
- **`check` takes scope as an argument** (2026-09-01): the alternative is the
  ambient-context design one implementation already has, which is convenient at
  every call site and produced a cross-tenant cache defect. Purity is what the
  corpus needs, and the corpus is what makes this standard enforceable.
