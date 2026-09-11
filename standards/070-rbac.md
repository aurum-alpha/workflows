# Authorization: the RBAC model, its operations, and its decision corpus

## Why this exists

RBAC systems built independently **agree on more than they differ**.
Permissions are a closed set of `resource`-plus-`action` strings declared in
code, roles are named bundles of them, and grants are scoped to an
organisational unit. Where they differ, roles in code or in rows and wildcards admitted or
not, each new product left alone picks at random. This document writes the
agreement down, settles the forks, and states the failure each rule
prevents. Any language can implement it, and one corpus judges them all.

## The rules

### RB1. Permissions are a closed set, declared in code

Every permission an application recognises is declared in one place in source.
That place is an enum, a constant set, or whatever the language offers, and
that declaration is the complete list. **A permission that is not in the set
does not exist**, and a check against an undeclared permission is an error
rather than a denial.

The property it buys is that *what can be granted* is answerable from the
repository, reviewable in a diff, and impossible to typo into existence.

The distinction that matters and is easy to lose: **the set of permissions is
standard in its shape and application-specific in its contents**. An
invoicing product has `invoice.approve` and a recruiting product does not. What
this standard fixes is the shape, the semantics and the operations, not the
vocabulary.

#### Why the set is code and cannot be data

The root reason, from which the rest follow: **a permission is one half of a
pair, and the other half is a line of code**. `invoice.approve` means nothing
unless somewhere a handler is guarded by
`check(subject, "invoice.approve", scope)`. The declaration and the call site are
the same fact written twice. **You cannot add a permission at runtime because
you cannot add the code that honours it at runtime**.

Three consequences, each a failure that only appears when the set is data:

- **The declaration and the call site drift apart, silently**. A permission
  added without its call site is inert: an administrator grants it and
  nothing changes, with no error to see. Code that checks a permission the
  database has not got denies everyone. When the set is compiled in, the
  check and the declaration ship as one artifact and cannot disagree.
- **A typo becomes a denial rather than a build failure**. A language enum
  is the form that catches it. `Permission.INVOICE_APPROVE` misspelled does
  not compile. `'invoice.aprove'`
  in a row fails at check time and looks identical to a correct refusal. A
  code symbol can also be found by search, so an auditor sees every call
  site and every permission declared and never checked.
- **A new permission is a new capability, and that is a security review event**.
  Adding one expands what the system can be instructed to do. As a diff, someone
  approves it. As an `INSERT`, nobody does. The set of things a system can
  authorize must not be editable by anyone holding database access or an admin
  screen.

### RB2. A permission is `resource.action`

Lowercase, `snake_case` within each segment, a single dot between them:
`invoice.approve`, `candidate_process.advance`, `purchase_order.void`. A name
matches `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`.

**The dot rather than a colon, for a reason that is not taste**. Scope
references in RB5 are `type:id`, such as `tenant:acme` and `job:8fK2mQ`. Using
a colon in both would give one separator two meanings in one system, and the
first ambiguous string is the one nobody notices. Reserving `:` for scope and
`.` for permission keeps every identifier parseable on sight.

Two segments, never three. A three-part permission is a resource that has not
been named: `system.dashboard.view` is `system_dashboard.view`. Writing it the
second way keeps the check a simple equality rather than a prefix question.

### RB3. A role is a named set of permissions, and every permission in it is real

Roles can be **declared in code** or **stored as data**. Code means a closed
enum, reviewable in a diff, with no migration to change. Data means a tenant
can define its own. Both are admitted. A repository states which in its **Conventions**, and most
products want some of each.

Whichever it is, one rule holds: **a role can contain only permissions from
RB1's declared set, and that is validated at write time**. A stored role with a
typo'd permission grants nothing and says nothing. The failure surfaces later
as a person who cannot do something everyone believes they can.

**Roles do not nest and do not inherit**. A role that needs what another role
has lists the same permissions. Inheritance turns *what can this person do*
into a graph traversal, and the answer stops being readable from the role's own
definition. The duplication it would remove is duplication a reviewer can see.

#### Why data is safe here when it was not for permissions

**A role introduces no capability. It composes capabilities that already
exist and are already enforced**. So the blast radius of a role invented at
runtime is bounded, exactly and by construction, by the permission set. **It
is RB1 that does the bounding. The code-defined permission set is precisely
what makes runtime roles safe**. Relax RB1 and this rule becomes indefensible
with it.

- **Multi-tenancy makes code-only roles impossible, not merely awkward**. Tenant
  A's roles are not tenant B's, and roles are the customer's organisational
  structure. The alternatives are a source enum holding the union of every
  customer's org chart, or a build per tenant. Neither is a real option.

#### Which roles still belong in code, and why

Some roles are declared in source, and **the reason is seeding, never checking**.
RB4 forbids code from consulting a role name at all. A product declares system
roles so that it ships working and can be recovered, not so that anything can
branch on them.

- **Bootstrap and recovery**. A fresh database has no roles and no
  administrators, and something must grant the first person their access. If
  every administrative role is data, deleting or misconfiguring them locks
  everyone out. A code-declared role is a floor nobody can remove.
- **A sane default**. A product ships with a small set of workable roles rather
  than an empty list and an instruction to invent one.
- **Roles that cross tenants**. A platform administrator or a support engineer
  belongs to no tenant, so no tenant is permitted to define or edit them. Code
  is where a tenant administrator cannot reach.

Two rules follow, and both are enforceable:

- **A system role is not editable or deletable by a tenant**. It is the recovery
  floor, and a floor a tenant can remove is not one.
- **A tenant-defined role is not permitted to take the name of a system role**.
  Otherwise a lookup by name stops having one answer, and seeding, migration
  and display all do look roles up by name.

### RB4. Code never branches on a role name

**The authorization system does not know what roles are called and must not
learn**. No conditional, no route guard, no feature check, no report filter asks
*is this subject an administrator*. Every one of them asks
`check(subject, permission, scope)`.

A role name appears in code in exactly two places, and neither is a decision.
They are the **seed definition** of a system role, and **display**, showing a
person what they are. Anywhere else, the name has become an authorization input
and RB1 through RB3 have been routed around.

`if role == "admin"` is the shortest thing to type and it works on the day it
is written. Three things it breaks:

- **It asks the wrong question, and denies people who plainly qualify**. A
  role is a bundle of capabilities, not a capability; the code only ever needs
  to know whether the subject holds the permission. A tenant defines its own
  role carrying every permission the operation needs, and the branch refuses
  it anyway, because the name does not match.
- **It makes editing a role's permissions do nothing**. The whole point of a
  role as a set is that changing the set changes what its holders can do. A
  name branch is not reading the set. So an administrator edits the role, sees
  the change saved, and the behaviour does not move.
- **It makes `permissionsFor` untrue, exactly as a wildcard does, and the
  corpus cannot see it**. A gate that is not a permission gate does not appear
  in the list. So the `/me` document of [`060-auth.md`](060-auth.md) AU6
  describes a subject who can do more or less than it says.
  [`decisions.json`](../contracts/rbac/decisions.json) evaluates `check`, and
  a role-name branch is an authorization decision it cannot judge.

And where roles are tenant-editable data, a name branch is **code depending on a
row a customer can rename or delete**.

#### The cases that look like exceptions

A feature flag is not one of them. A flag decides whether a capability is
wired or shown, never whether a subject is allowed
([`038-feature-flags.md`](038-feature-flags.md) FF5).

*"But I need to notify the billing contact."* That is not a role check.
Treating it as one is how the anti-pattern arrives wearing a reasonable face.
It is one of two things:

- A **permission**, `billing.receive_notices`, if any number of people can
  hold it, or
- an **explicit assignment** on the tenant record, a `billing_contact` field
  naming one user, if exactly one person holds it.

Both are better than a role lookup, and the second is better than inventing a
permission for a singleton. The test is whether you are asking *is this person
permitted to do X* (a permission) or *who is our X* (a field).

### RB5. A grant binds a subject to a role within a scope

```
Grant { subject, role, scope }
```

**Scope is `global`, or a `type:id` pair**: `tenant:acme`, `company:8fK2mQ`,
`job:V1StGX`. The application declares which scope types exist and how they
contain one another. The standard fixes the shape and the containment
*algorithm*, not the hierarchy.

That split is deliberate. A product serving one organisation at a time has a
two-level scope (system, organisation). A platform serving agencies that each
hold companies has three (platform, agency, company), with agencies containing
companies. A standard that named the levels would fit one and force a fiction
on the other.

**Containment: a grant at a containing scope satisfies a check at a contained
one**. A grant at `tenant:acme` satisfies a check at `job:V1StGX` when the
application declares that job as within that tenant. `global` contains
everything.

A subject can hold many grants. They are evaluated together, and RB6 says how.

### RB6. Deny by default, additive only, and no permission means "everything"

**Deny by default**. No grant means deny. There is no "allow unless denied."

**Grants are additive, and there are no negative grants**. A subject's
permissions at a scope are the union of every grant that applies there. Deny
rules make the outcome depend on evaluation order, which makes two
correct-looking implementations disagree. They also make the corpus below
impossible to write, since there would be no single right answer to compare
against.

To remove access, remove the grant.

**No wildcard is expanded at check time, and no permission grants any other**.
The failure has a recognisable shape: a check that short-circuits on
`system.admin`, on `system.*` and on `*`, tested in three places with slightly
different conditions. That is three ways to say "everything", any one of which
silently defeats every other rule in this document.

The cost of that is not only the bypass. It makes `permissionsFor` **lie**: a
subject holding `*` has every permission and the list enumerates none of them.
So the `/me` document of [`060-auth.md`](060-auth.md) AU6 tells the client
something untrue, and the interface renders the wrong screen.

A role that needs everything **enumerates everything**. A `SUPER_ADMIN` role
written this way runs to many lines, listing every permission it holds. That
is verbose and it is honest. The
verbosity is a feature: adding a permission to the system does not silently add
it to the superuser.

**A wildcard is not a valid permission string anywhere**. Not in a declaration,
not in a stored role, not as an argument to `check`, and not as authoring
shorthand a tool expands later. There is no place in the system where `*`,
`system.*` or `invoice.*` is accepted.

Authoring shorthand is the tempting exception. A role authored as "every
permission on `invoice`" has two possible behaviours. Either it re-expands on
load, and silently gains whatever was added to the code since, which is the
superuser problem returned by another door. Or it freezes at definition and
quietly stops meaning what it says. **A rule that admits an implicit form has
an implicit form**, and the only version of this rule that holds is the flat
one.

### RB7. `check` is a pure function of its arguments

```
check(subject, permission, scope) → Decision
```

**The scope is an argument, never ambient state**. The same subject, permission
and scope produce the same decision every time, given the same grants.

The failure it prevents has a shape: a check that reads an *active context*
from session state rather than taking it as an argument. That context is the
organisation the user last selected. Two consequences follow, and both are the
kind that survive a long time:

- **The answer depends on where the user last clicked**. The same call, for the
  same user and permission, returns differently depending on session state that
  the caller did not pass and cannot see.
- **The permission cache keys on `userId` and the permission alone**, with no
  scope in the key. A permission cached as allowed in one organisation is
  returned as allowed in the next. That is a cross-tenant authorization result,
  produced by a cache key. No test that exercises one tenant at a time will
  ever show it.

A pure `check` makes the second impossible by construction. It also makes the
[`decisions.json`](../contracts/rbac/decisions.json) corpus writable at all.
*Given these grants, this check returns deny* has no meaning if the answer also
depends on state the case cannot state.

#### The operations

| Operation | Semantics |
|---|---|
| `check(subject, permission, scope) → Decision` | The primitive. Deny by default. |
| `checkAny(subject, permissions[], scope) → Decision` | Allowed if any one is. |
| `checkAll(subject, permissions[], scope) → Decision` | Allowed only if every one is. |
| `permissionsFor(subject, scope) → permission[]` | The true, complete, enumerated set. Feeds `/me`. |
| `rolesFor(subject, scope) → role[]` | For display, and for an admin screen. |
| `grant(subject, role, scope)` / `revoke(subject, role, scope)` | Administrative. Both are audited events. |

`checkAny` and `checkAll` exist because a codebase without them writes the
loop by hand and gets it wrong somewhere.

### RB8. A decision carries its reason

`check` returns a **Decision**, not a boolean. It carries the outcome, and
*why*: which grant and which role satisfied it, or that none did.

A denial that cannot say why is the reason-giving failure of
[`030-service.md`](030-service.md) SC2, on the surface where it matters most. It
is also the difference between an audit trail worth keeping and a log of the
word `false`.

The reason is what an application logs and what an administrator reads on a
support call. It is never returned to an unauthorised caller. The
[`050-http.md`](050-http.md) HA3 envelope that reaches the client says the
request was refused, and the reason stays in the log.

### RB9. A cached decision is keyed by everything the decision depends on

Caching authorization is normal and often necessary. Two rules make it safe.

**The cache key includes the subject, the permission and the scope**, which is
every argument of RB7's function. A key missing one of them returns another
subject's or another tenant's answer. This is the failure RB7 describes, stated
as a rule so it is caught in review rather than in production.

**Every path that changes a grant invalidates**. Granting, revoking, editing a
role's permissions, deactivating a subject. The invalidation surface has three
entry points: per subject, per role, and global with the reason recorded for
audit. A role's permission list changing affects every subject holding it, and
there is no cheaper correct answer.

A stated maximum TTL bounds what invalidation misses. It is a backstop, not the
mechanism.

### RB10. The scope of a request comes from the authenticated session, never from the request

RB7 makes scope an argument. This rule says where the argument comes from.
**The tenant a request is checked against is read from the authenticated
identity, and never from anything the client sent**. That identity is the
session the [authentication standard](060-auth.md) bound to exactly one tenant
at login (AU8). Not a header, not a query parameter, not a body field, and not
the hostname the request arrived on. The rule is stated that generally so that
the next plausible-looking source is already refused.

The reason is that every one of those is the caller's to choose. A scope taken
from a header is a scope the caller selected. A `check` whose scope argument
the subject supplies is a check the subject can pass. They name a tenant they
hold a grant in and a resource they do not. The session's tenant is the one
value the caller cannot pick after authenticating, which is what makes it fit
to be the argument.

Two things remain legitimate and are not exceptions:

- **A resource's own tenant is compared against the session's**. A request
  for `/invoices/inv_42` resolves the invoice's tenant from the row and
  refuses when it differs from the session's, per 025's isolation rule. That
  is the scope being *checked*, not *chosen*.
- **A narrower scope inside the tenant can come from the path**. A project
  under a tenant is named by the route, and RB5's containment decides whether
  the tenant-level grant covers it. The path is permitted to narrow the scope
  the session fixed. It is never permitted to widen it or change the tenant.

Where a product gives tenants their own hostnames, the hostname's role stops
at routing and at an agreement check. The
[tenant hostnames standard](092-tenant-hostnames.md) says so. The scope still
comes from here.

## The artifacts

Per PC3, under [`contracts/rbac/`](../contracts/rbac/):

- **`model.schema.json`**: permission, role, grant and scope shapes.
- **`decisions.json`**: a set of grants, then a list of checks with their
  expected decisions. One corpus judges every implementation, which is why
  RB7 requires a pure function.
