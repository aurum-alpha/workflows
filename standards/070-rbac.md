# Authorization: the RBAC model, its operations, and its decision corpus

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard from its
roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier each rule below
actually holds. Artifacts: [`contracts/rbac/`](../contracts/rbac/).

This document defines **who may do what**, as an interface specification:
a data model, a set of operations with defined semantics, and a corpus of
decision cases any implementation in any language must reproduce. It picks up
where [`060-auth.md`](060-auth.md) AU6 stops — that document produces a trustworthy
subject and refuses an unknown one; this one decides what a known subject may do.

## Why this exists

This is the platform contract's worked example of *an interface specification,
not a library*. Three languages implement it; one corpus judges all three.

It is also not being invented from nothing. Two products in the portfolio have
built substantial RBAC systems independently, and **they agree on more than they
differ**: permissions as a closed set of `resource`-plus-`action` strings
declared in code, roles as named bundles of those permissions, grants scoped to
an organisational unit. That agreement is the standard answer, and most of this
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
standard in its shape and application-specific in its contents.** An
invoicing product has `invoice.approve` and a recruiting product does not. What
this standard fixes is the shape, the semantics and the operations — not the
vocabulary.

#### Why the set is code and cannot be data

The root reason, from which the rest follow: **a permission is one half of a
pair, and the other half is a line of code.** `invoice.approve` means nothing
unless somewhere a handler is guarded by
`check(subject, "invoice.approve", scope)`. The declaration and the call site are
the same fact written twice, and **you cannot add a permission at runtime because
you cannot add the code that honours it at runtime.**

Five consequences, each a failure that only appears when the set is data:

- **A permission added without its call site is inert, and inert silently.** An
  administrator grants it, believes access is conferred, and nothing changes.
  There is no error to see, because granting something nothing checks is
  indistinguishable from granting something correctly.
- **The two halves fall out of step per environment.** Code that checks a
  permission the database has not got denies everyone; a database holding one the
  code does not check grants nothing. When the set is compiled in, the check and
  the declaration ship as one artifact and cannot disagree.
- **A typo becomes a denial rather than a build failure.** Both prior
  implementations made the set a language enum for exactly this:
  `Permission.INVOICE_APPROVE` misspelled does not compile, while
  `'invoice.aprove'` in a row fails at check time and looks identical to a
  correct refusal. That property is the single most valuable one here and it
  evaporates the moment the set is data.
- **"Where is this enforced?" stops being answerable.** A permission that is a
  code symbol can be found by search, so an auditor can see every call site — and
  can find the opposite, a permission that is declared, grantable and never
  checked anywhere. A permission that is a string in a table can be neither
  found nor audited.
- **A new permission is a new capability, and that is a security review event.**
  Adding one expands what the system can be instructed to do. As a diff, someone
  approves it. As an `INSERT`, nobody does — and the set of things a system can
  authorize should not be editable by anyone holding database access or an admin
  screen.

### RB2. A permission is `resource.action`

Lowercase, `snake_case` within each segment, a single dot between them:
`invoice.approve`, `candidate_process.advance`, `purchase_order.void`.

**The dot rather than a colon, for a reason that is not taste.** Scope
references in RB5 are `type:id` — `tenant:acme`, `job:8fK2mQ`. Using a colon in
both would give one separator two meanings in one system, and the first
ambiguous string is the one nobody notices. Reserving `:` for scope and `.` for
permission keeps every identifier parseable on sight.

Two segments, never three. A three-part permission is a resource that has not
been named: `system.dashboard.view` is `system_dashboard.view`, and writing it
the second way keeps the check a simple equality rather than a prefix question.

### RB3. A role is a named set of permissions, and every permission in it is real

Roles may be **declared in code** (a closed enum, reviewable in a diff, no
migration to change) or **stored as data** (so a tenant can define its own).
Both are admitted; a repository states which in its **Conventions**, and most
products want some of each.

Whichever it is, one rule holds: **a role may contain only permissions from
RB1's declared set, and that is validated at write time.** A stored role with a
typo'd permission grants nothing and says nothing, and the failure surfaces
later as a person who cannot do something everyone believes they can.

#### Why data is safe here when it was not for permissions

The asymmetry is not a compromise, and it is worth stating because it looks like
one. **A role introduces no capability. It composes capabilities that already
exist and are already enforced.**

Creating *Regional Auditor* as `{report.read, report.export}` adds nothing the
system could not already do: both permissions were declared in code, both have
call sites, both were already grantable. The role is a shorthand for a set that
was reachable anyway.

So the blast radius of a role invented at runtime is bounded, exactly and by
construction, by the permission set — **and it is RB1 that does the bounding.
The code-defined permission set is precisely what makes runtime roles safe.**
Relax RB1 and this rule becomes indefensible with it.

Three further reasons data is the *right* answer for most roles, not merely a
tolerated one:

- **Roles are organisational structure, and that is the customer's, not ours.**
  One tenant splits Approver into two grades; another merges them. Requiring a
  deploy for a customer's internal reporting lines is requiring a deploy for
  something we have no opinion about.
- **Multi-tenancy makes code-only roles impossible, not merely awkward.** Tenant
  A's roles are not tenant B's, and the alternatives are a source enum holding
  the union of every customer's org chart, or a build per tenant. Neither is a
  real option.
- **The rates of change differ by orders of magnitude.** Permissions change when
  features change: slow, deliberate, tied to a release. Roles change when people
  change jobs: fast, frequent, and by administrators who are not engineers. Two
  things changing at those two rates should not share a release cycle.

#### Which roles still belong in code, and why

Some roles are declared in source, and **the reason is seeding, never checking**
— RB4 forbids code from consulting a role name at all. A product declares system
roles so that it ships working and can be recovered, not so that anything can
branch on them.

Four cases:

- **Bootstrap.** A fresh database has no roles and no administrators. Something
  must grant the first person their access, and it cannot be a role that does not
  exist yet. This is a chicken-and-egg problem with exactly one solution.
- **Recovery.** If every administrative role is data, deleting or misconfiguring
  them locks everyone out with no path back that does not involve raw SQL against
  production. A code-declared role is a floor nobody can remove.
- **A sane default.** A product should arrive with a small set of workable roles
  rather than an empty list and an instruction to invent one. Minimal is the
  target: enough to run the system, not a catalogue.
- **Roles that cross tenants.** A platform administrator or a support engineer
  belongs to no tenant, so no tenant may define or edit them. Code is where a
  tenant administrator cannot reach.

Two rules follow, and both are enforceable:

- **A system role is not editable or deletable by a tenant.** It is the recovery
  floor, and a floor a tenant can remove is not one.
- **A tenant-defined role may not take the name of a system role**, or a lookup
  by name stops having one answer — and seeding, migration and display all do
  look roles up by name.

### RB4. Code never branches on a role name

**The authorization system does not know what roles are called and must not
learn.** No conditional, no route guard, no feature check, no report filter asks
*is this subject an administrator*. Every one of them asks
`check(subject, permission, scope)`.

A role name appears in code in exactly two places, and neither is a decision:
the **seed definition** of a system role, and **display** — showing a person what
they are. Anywhere else, the name has become an authorization input and RB1
through RB3 have been routed around.

This is the rule most likely to be broken by accident, because `if role ==
"admin"` is the shortest thing to type and it works on the day it is written.
Five things it breaks:

- **It asks the wrong question.** A role is a bundle of capabilities, not a
  capability. *Is this person an administrator* is a question about how they came
  to hold a permission; the code only ever needs to know whether they hold it.
- **It denies people who plainly qualify.** A tenant defines its own role
  carrying every permission the operation needs, and the branch refuses it
  anyway — because the name does not match. The permission model said yes and the
  name check said no.
- **It makes editing a role's permissions do nothing.** The whole point of a
  role as a set is that changing the set changes what its holders may do. A
  name branch is not reading the set, so an administrator edits the role, sees
  the change saved, and the behaviour does not move.
- **It makes `permissionsFor` untrue, exactly as a wildcard does.** A gate that
  is not a permission gate does not appear in the list, so the `/me` document of
  [`060-auth.md`](060-auth.md) AU6 describes a subject who can do more or less than it
  says, and the interface renders the wrong screen. This is the same failure as
  RB6's wildcard, arriving by a different door.
- **It is invisible to the corpus.** [`decisions.json`](../contracts/rbac/decisions.json)
  evaluates `check`. A role-name branch is an authorization decision the corpus
  cannot see, so an implementation can reproduce all seventeen cases and still
  have ungoverned gates.

And where roles are tenant-editable data, a name branch is **code depending on a
row a customer can rename or delete.**

#### The cases that look like exceptions

*"But I need to notify the billing contact."* That is not a role check, and
treating it as one is how the anti-pattern arrives wearing a reasonable face. It
is one of two things:

- A **permission** — `billing.receive_notices` — if any number of people may hold
  it, or
- an **explicit assignment** on the tenant record, a `billing_contact` field
  naming one user, if exactly one person holds it.

Both are better than a role lookup, and the second is better than inventing a
permission for a singleton. The test is whether you are asking *may this person
do X* (a permission) or *who is our X* (a field).

*"The admin screen lists roles to assign."* That is data being rendered, not a
branch. Fine.

*"Migrations and seeds reference role names."* Setup, not a runtime decision.
Fine.

**Roles do not nest and do not inherit.** A role that should have what another
role has lists the same permissions. Inheritance turns *what can this person do*
into a graph traversal, and the answer stops being readable from the role's own
definition.

### RB5. A grant binds a subject to a role within a scope

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

A subject may hold many grants. They are evaluated together, and RB6 says how.

### RB6. Deny by default, additive only, and no permission means "everything"

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
the `/me` document of [`060-auth.md`](060-auth.md) AU6 tells the client something untrue
and the interface renders the wrong screen.

A role that should have everything **enumerates everything**. `hiring-tracker`'s
`SUPER_ADMIN` does exactly this — ninety-odd lines listing every permission it
holds. That is verbose and it is honest, and the verbosity is a feature: adding a
permission to the system does not silently add it to the superuser.

**A wildcard is not a valid permission string anywhere.** Not in a declaration,
not in a stored role, not as an argument to `check`, and not as authoring
shorthand a tool expands later. There is no place in the system where `*`,
`system.*` or `invoice.*` is accepted.

RB4's role-name branch is the same failure through another door: both create a
gate that grants or refuses without a permission behind it, and both make
`permissionsFor` describe a subject who is not the one the system will actually
serve.

Authoring shorthand is the tempting exception and it is refused for the reason
the paragraph above gives. A role authored as "every permission on `invoice`"
either re-expands on load, and silently gains whatever was added to the code
since — the superuser problem, returned by another door — or freezes at
definition and quietly stops meaning what it says. Neither is legible, and the
authored form is what a reviewer reads in a diff. **A rule that admits an
implicit form has an implicit form**, and the only version of this rule that
holds is the flat one.

### RB7. `check` is a pure function of its arguments

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
of RB9 writable at all: *given these grants, this check returns deny* has no
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

### RB8. A decision carries its reason

`check` returns a **Decision**, not a boolean: the outcome, and *why* — which
grant and which role satisfied it, or that none did.

A denial that cannot say why is the reason-giving failure of
[`030-service.md`](030-service.md) SC2, on the surface where it matters most. It is also
the difference between an audit trail worth keeping and a log of the word
`false`.

The reason is what an application logs and what an administrator reads on a
support call. It is never returned to an unauthorised caller: the
[`050-http.md`](050-http.md) HA3 envelope that reaches the client says the request was
refused, and the reason stays in the log.

### RB9. A cached decision is keyed by everything the decision depends on

Caching authorization is normal and often necessary. Two rules make it safe.

**The cache key includes the subject, the permission and the scope** — every
argument of RB7's function, because a key missing one of them returns another
subject's or another tenant's answer. This is the failure quoted in RB7, stated
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
  polyglot standard enforceable from one source, and it is why RB7 requires a
  pure function. Three implementations, one judge.

## Enforcement

Every rule is review-only today, with gates named per rule in
[`999-enforcement.md`](999-enforcement.md). **This standard is the most gateable one in
the repository**, and that is the point of writing authorization as an interface
specification rather than as prose.

- **RB6, RB7 and RB5's containment are decided entirely by the decision
  corpus.** An implementation loads the grants, runs the checks, and either
  reproduces every expected decision or names the case it failed. No running
  service, no browser, no network — the corpus is data and the check is a
  function.
- **RB2's format is a static check** over the declared permission set: every
  entry matches `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`, which also catches the
  three-segment permissions RB2 forbids.
- **RB3's validation is testable** by attempting to store a role containing an
  undeclared permission and requiring a refusal.
- **RB9's cache key resists a static checker** and is caught by a corpus case
  instead: check a permission in one scope, then the same permission in another
  where it is not granted, and require deny. A cache keyed without scope fails
  it. This is the one gate that would have caught the production defect quoted
  in RB7.
- **RB1 and RB8 stay review questions.** That a declaration is genuinely the
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
- **No wildcards anywhere, not merely at check time** (2026-09-01): the
  strongest rule here, and the one most likely to be argued with, because `*` is
  convenient. It is rejected because it defeats every other rule silently and
  because it makes `permissionsFor` untrue, which the client contract now
  depends on. An earlier draft of this rule banned wildcards only at check time
  and permitted them as authoring shorthand — which was inconsistent with this
  same rule's argument for an enumerated superuser, since an authored `invoice.*`
  either re-expands and silently grows or freezes and silently stops meaning what
  it says. The flat denial is the only version that holds.
- **No role inheritance** (2026-09-01): considered, because it removes
  duplication between similar roles. Rejected because it converts *what can this
  person do* from a lookup into a traversal, and because the duplication it
  removes is duplication a reviewer can see.
- **`check` takes scope as an argument** (2026-09-01): the alternative is the
  ambient-context design one implementation already has, which is convenient at
  every call site and produced a cross-tenant cache defect. Purity is what the
  corpus needs, and the corpus is what makes this standard enforceable.
