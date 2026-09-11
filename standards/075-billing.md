# Billing: the catalog, the subscription ledger, and the entitlement check

## Why this exists

Three questions in a product each produce a yes or a no, which is the whole
reason they get confused. They are *is this code path live*, *did this
tenant's plan buy this*, and *is this person permitted to do this here*. They
differ on every axis that matters. A codebase that answers the second with the
machinery of the first or the third acquires a defect. No test written against
one tenant will show it.

**The test is to ask who flips it**. An engineer flips a flag. A payment flips
an entitlement. A tenant administrator flips a permission, for one person, by
granting a role.

| | Feature flag ([`038-feature-flags.md`](038-feature-flags.md)) | Capability entitlement (this document) | Permission ([`070-rbac.md`](070-rbac.md)) |
|---|---|---|---|
| The question | Is this code path live right now? | Did this tenant's plan buy this? | Is this person permitted to do this here? |
| Attached to | the deployment | the tenant's subscription | a user, through a role, within a scope |
| Flipped by | an engineer or operator | money: a plan change, or an administrator's override | a tenant administrator granting a role |
| Lifetime | bounded: it expires or is reviewed, then removed | as long as the product sells it | as long as the product has the function |
| Declared in | the flag declaration | the catalog | the permission set in code |
| Name | `area.flag`, one dot | `snake_case`, no dot | `resource.action`, one dot |
| Read through | the evaluation API | the entitlement check | the authorization check |
| Denied | `404`: the function does not exist | `403` with the `entitlement-required` problem type | `403` with the standard envelope |

## The rules

### BL1. The catalog is a file in the repository, and the provider is provisioned from it

**Every plan, price, interval, currency, trial length and entitlement the
product sells is declared in one versioned file in the repository**. That file
is validated against
[`catalog.schema.json`](../contracts/billing/catalog.schema.json) in CI and
built into the image. The billing provider's products and prices are created
*from* that file by a job. The provider's ids are stored against the catalog's
plan, interval and currency. A price that exists only in a vendor's console is
a price no pull request reviewed. A price typed into a page is a second source
that disagrees with the first the week it matters.

The catalog carries four closed sets and then the plans:

| Section | Carries |
|---|---|
| `capabilities` | Every capability the product can gate, each with an id and a description. A capability can be in no plan; it is still declared here, because the code that checks it exists whether or not anything sells it yet. |
| `metrics` | Every quota and allowance metric, each with a kind, a unit and a description. |
| `settings` | Every plan-fixed value the code reads as configuration. |
| `plans` | Prices per interval and currency, as [`020-identifiers.md`](020-identifiers.md) IP5 money; the trial length; the capabilities included; a value for **every** declared metric and setting; and display-only terms. |

The file also states the policies BL4 reads. They are the past-due grace
period in days, and the **suspended set**: the capabilities that remain when a
plan has stopped contributing. Both are policy, and a policy that lives in
code is a policy nobody reviews as a diff.

**Provisioning is a deployment job, `catalog.provision`**, under
[`057-jobs.md`](057-jobs.md): keyed by the release version (JB2), `idempotent`,
`single_flight`, blocking. It creates what the provider lacks, archives what
the catalog no longer carries, and never deletes or edits a live price. A price
is immutable once charged, so a changed amount is a new price object and a new
catalog version. The job writes the id mapping into the service's own database
(025 SD13), where the adapter of BL5 reads it.

**Prices are grandfathered; entitlements are current**. A tenant stays on the
price it signed at until it changes plan, for two reasons. The provider's
subscription references the price object it was sold, and the ledger row
records the catalog version it was priced under (BL2). What the plan
*entitles* is always the current catalog's definition. The code serving the
tenant is the current code and can honour only the capabilities it has. A
per-version entitlement set would make the function of BL4 hold every catalog
ever shipped.

A public surface that shows prices renders them from the catalog, and never
from content of its own. It reads the catalog as a declared build source, or
from a public, cacheable, unauthenticated read the product's OpenAPI document
names ([`050-http.md`](050-http.md) HA2).

### BL2. The subscription is a projection of an append-only ledger

**One subscription per tenant, and it is a projection: it is written only by
applying a ledger row**. The ledger is the truth. The projection is the
current answer, kept so that a request reads one row rather than folding a
history. Both are shaped by
[`subscription.schema.json`](../contracts/billing/subscription.schema.json).

| Structure | Cardinality | Carries |
|---|---|---|
| Subscription | one per tenant | Plan, status, the current period's start and end, the trial end, the provider's customer and subscription ids, the catalog version the tenant is priced under, and **at most one pending change**. |
| Ledger row | many per tenant, append-only | When it was recorded and when it takes effect; from and to plan; from and to status; the kind of change; the actor; the provider event that caused it, where one did; the catalog version it was priced under. |
| Override | zero or more per tenant | One capability, quota, allowance or setting; the value; the reason; who granted it; when it expires. Written only by an internal administrator, with a permission, and always as a ledger row of kind `override_granted`. |

Three sets are closed, and a transition outside them is a schema failure
rather than a new row:

- **Status:** `trialing` · `active` · `past_due` · `cancelled`.
- **Ledger kind:** `trial_started` · `trial_converted` · `trial_expired` ·
  `upgraded` · `downgraded` · `cancelled` · `reactivated` · `payment_failed` ·
  `payment_recovered` · `override_granted` · `override_revoked`. A sign-up onto
  a paid plan with no trial is `upgraded` from no plan; an expired trial is a
  cancellation that never paid.
- **Actor:** `user` · `internal_admin` · `provider_webhook` · `job`.

**Every row has a recorded time and an effective time, and the two are what
make history and scheduling one mechanism**. A row whose effective time is
later than its recorded time is the subscription's pending change. That is a
downgrade or a cancellation that takes effect at period end, and it is the
*only* form a pending change takes. Rows are applied in recorded order. A row
recorded while another is still pending supersedes it, and the superseded row
never takes effect. The ledger keeps it, because the ledger keeps everything,
and its successor is its explanation.

That is what bounds the projection to one pending change without a second
table. It is also what lets the function of BL4 be asked about any instant,
past or future.

**Append-only means the writes are the only writes**, in the sense
[`080-audit.md`](080-audit.md) AE6 gives it. The service's grant on the ledger
carries `INSERT` and `SELECT`, and the code has no update or delete path. A
correction is a new row with a reason. The ledger is a financial record, so it
is one of the tables a product names under
[`025-structured-data.md`](025-structured-data.md) SD12's retention exception.
Its retention is stated there.

The period boundaries are the one field the projection takes from the
provider rather than from a row. The period is when the provider charges,
which is money truth, and a renewal changes neither plan nor status. They
arrive in the provider's events under BL6 and the projection mirrors them.

### BL3. An entitlement is one of four kinds, and nothing is per user

**What separates the kinds is what the code does with the value**. That is why
the set is closed and four rather than three or seven.

| Kind | Value | What the code does with it | Denial |
|---|---|---|---|
| **capability** | yes or no | Gates whether a function is available to the tenant. | `403 entitlement-required`. |
| **quota** | a ceiling on what can **exist at once** | Compared against the domain's own count when something is created. | `403 entitlement-required`, at creation only. |
| **allowance** | a ceiling on what can be **consumed per billing period** | Compared against a usage record the domain writes and that resets on the period boundary. | `403 entitlement-required`, or overage where the plan sells it. |
| **setting** | a value the plan fixes | Read as configuration. Never checked. | None; there is nothing to deny. |

**Quota and allowance look alike and are not**. A quota is held: the seats
exist until removed, and a downgrade below the count needs a policy, which BL7
states. An allowance is consumed: it resets each period, and it needs a usage
record the domain writes. It is the only kind that can connect to metered
billing. A product with no metered feature has no allowances, and the kind
stays empty.

**Nothing is per user**. What one person can do inside a tenant is a
permission under [`070-rbac.md`](070-rbac.md), and a per-seat price is a quota
on the seat count. A per-user entitlement is an authorization input that is
not a permission. It is edited outside the grant path, invisible to
`permissionsFor`, and it is the failure RB4 describes arriving with a price
tag. **Terms**, such as a support tier or an SLA, appear in the catalog so a
pricing page can render them, and no code checks them.

**Ids are `snake_case` with no dot**, matching `^[a-z][a-z0-9_]*$`, and unique
across capabilities, metrics and settings within a catalog. A permission
always has exactly one dot (RB2); a flag name always has one (038 FF2); a
capability never does. No identifier can be mistaken for the wrong kind by a
reader or by a linter. A refusal can name what was missing without saying
which kind it was.

Three shapes are refused by this rule, and each is the same mistake in a
different table:

- **A role named after a plan**: an upgrade would mean reassigning roles to
  every user in the tenant.
- **A permission that encodes a plan**: the permission set is what the product
  *can* do, and the catalog is what a tenant *bought*.
- **A flag kept on because a customer pays for it**. A flag has a bounded life
  and an engineer flips it. This one would never expire, and money flips it.
  So it is an entitlement wearing a flag's name, and 038 has no kind for it
  to be.

### BL4. The check is a pure function, run in a fixed order, and its decision carries a reason

```
entitlementsFor(catalog, subscription, ledger[], overrides[], at) → EntitlementSet
```

**The derivation is a pure function of its arguments**, mirroring
[`070-rbac.md`](070-rbac.md) RB7: the same catalog, ledger, overrides and
instant produce the same set every time. Nothing ambient enters it: not the
clock, not a session, not the provider. Purity is what makes the corpus of
this document writable and a cache safe. It is also why BL2 requires effective
times: the function can be asked about any instant.

#### The operations

| Operation | Semantics |
|---|---|
| `entitled(tenant, capability, at) → Decision` | The primitive for capabilities. |
| `quotaFor(tenant, metric, at) → { value, source }` | The ceiling, or no ceiling. |
| `allowanceFor(tenant, metric, at) → { value, period_start, period_end, source }` | The ceiling and the period it resets on. |
| `settingFor(tenant, setting, at) → { value, source }` | Read as configuration. |
| `withinQuota(tenant, metric, current, at) → Decision` | Allowed when one more fits: `current` is the domain's own count, passed in. |
| `withinAllowance(tenant, metric, used, at) → Decision` | Allowed when `used` is below the ceiling: `used` is the domain's usage record, passed in. |
| `entitlementsFor(tenant, at) → EntitlementSet` | The true, complete, derived set with the source of each value. Feeds `/me`. |
| `override(tenant, kind, id, value, reason, expires_at)` / `revokeOverride(tenant, override_id)` | Administrative. Both are ledger rows, and both are audited events. |

`at` defaults to now. A check against a capability, metric or setting the
catalog does not declare is an **error, not a denial**, for RB1's reason. A
denial is indistinguishable from a correct refusal and hides the typo forever.

**Usage is the domain's**. `withinQuota` and `withinAllowance` take the count
as an argument because the check keeps no counter of its own. A second counter
is a second truth that drifts, and the domain already has to know how many
seats exist to render the page.

#### Status decides what the plan contributes

| Status | The plan contributes |
|---|---|
| `trialing`, `active` | The full plan. |
| `past_due` | The full plan for the catalog's stated grace period from the `payment_failed` row's effective time; then the **suspended set**. |
| `cancelled` | The `cancelled` row takes effect at period end, so the full plan until then, and the suspended set from then. An expired trial is `cancelled` from the moment it expires. |

**The suspended set** is the catalog's named capabilities and nothing else.
Every quota and allowance is zero, so nothing new is created. Every setting
keeps the plan's value. A setting such as how long history is kept is exactly
what governs a tenant that has stopped paying. Reading what exists and
reaching the billing settings are ordinary routes under permissions and were
never capabilities. A product that has put either behind one names it in the
suspended set.

**An override is not the plan's contribution and is not subject to the status
policy**. It applies from its grant until it expires or is revoked, at any
status. It is a deliberate act by a named administrator with a stated expiry.
A function that silently discarded such an act would make the administrator's
screen untrue. An administrator who wants it gone revokes it. Where an
override and the plan both speak, the override wins.

#### The order of checks

Every handler that is under more than one gate asks them in this order, and
each answers only its own question:

1. **Authenticated?** No: `401`, per [`060-auth.md`](060-auth.md).
2. **Release flag on?** No: `404`, the function does not exist (038 FF5), so
   that a dark feature is dark to enumeration.
3. **Permission held?** No: `403` with the standard envelope, the reason
   logged (070 RB8).
4. **Capability bought?** No: `403` with the `entitlement-required` problem
   type below.
5. **The domain operation**, where a quota or allowance is compared against
   the domain's own count and refused with the same problem type.

Permission runs before capability. The permission answer concerns the
subject and reveals nothing about the tenant's plan. An upgrade prompt shown
to a person who could not use the function after upgrading is a wrong answer
dressed as a helpful one. The plan is information the tenant's administrators
decide who sees.

#### The denial

A refused entitlement is `403` with a distinct problem type under
[`050-http.md`](050-http.md) HA3, in the form HA3 pins:
`https://errors.aurumalpha.dev/<service>/entitlement-required`. Beyond the
envelope's required members it carries two extension members, shaped in
`subscription.schema.json`. `entitlement` carries the kind, the id, and for a
quota or allowance the limit. `plan` carries the tenant's current plan. That
is what a client needs to render *this needs the business plan* without a
second request. It is a statement about the tenant, not about the person, so
it crosses the boundary where RB8's reason does not.

**Not `402`**. RFC 9110 reserves `402 Payment Required` for future use and
defines no semantics for it. Intermediaries and client libraries handle it
inconsistently, some collapsing it to a generic failure and some retrying it.
`403` says exactly what is true: the request is understood and refused. HA3
already makes `type`, not the status code, the thing a client branches on.

#### The cache, the client, and the provider

**A cached set is keyed by the tenant, the catalog version and the
subscription's last ledger row**. It also carries the instant it stops being
valid. The first three are every input of the function that a row or a deploy
can change. So every ledger row and every catalog release invalidates by
construction, as RB9 requires of a permission cache.

The fourth exists because this function also depends on time. A grace period
ends, a period ends, a trial ends, an override expires, or a pending row takes
effect. No new row announces any of them. So the set states `valid_until`,
the earliest such boundary, and the cache honours it. A TTL is the backstop,
not the mechanism.

**The `/me` document of [`060-auth.md`](060-auth.md) AU6 carries an
`entitlements` block beside `permissions`**, in the `EntitlementSet` shape, so
the client can show and hide for display. It is advisory exactly as
`permissions` is: the server enforces on every request, and a `403` is the
signal to refetch once.

**The provider is never on the request path**. No entitlement is decided by
asking the billing provider. The ledger is the truth for entitlements and the
provider is the truth for money. Asking it per request couples the product's
availability to a vendor's and answers the wrong question anyway.

### BL5. One provider adapter, chosen by configuration

**Every billing provider is an adapter behind one interface, selected by an
environment variable under [`030-service.md`](030-service.md) SC3. Domain code
imports no vendor SDK. No server image holds a provider credential that the
pool and jobs images do not need more**. This is the shape
[`058-notifications.md`](058-notifications.md) NF11 gives a notification
provider, for the same reasons. A vendor swap becomes configuration, and the
domain stays testable against an interface rather than a network. Which
providers are known to satisfy this rule is
[`solutions/075-billing.md`](../solutions/075-billing.md)'s to say.

```
provisionCatalog(catalog)                       -> { plan, interval, currency -> provider price id }
createCheckout(tenant, plan, interval, promo?)  -> { redirect_url } | PromoInvalid
changePlan(subscription, plan, interval, when)  -> { effective_at }        when: now | period_end
cancel(subscription, when) / reactivate(subscription)
portalUrl(customer)                             -> { url }
invoices(customer, cursor)                      -> page of { id, issued_at, total, status, document }
verify(raw_body, headers)                       -> ProviderEvent { id, kind, occurred_at,
                                                    customer_id, subscription_id, detail }
   kind: trial_converted | payment_failed | payment_recovered | subscription_cancelled
       | period_renewed | subscription_changed
```

**Card data never touches our servers**. Payment is collected by the provider's
hosted checkout or by its tokenised fields rendered in the browser. The product
receives a token or a redirect, never a number. That is the difference between
a product that is in scope for card-handling compliance and one that is not.
It is not a choice a repository makes. Tax, invoicing, revenue recognition and
dunning cadence are the provider's, behind the adapter.

The provider's browser-side key, where tokenised fields need one, is public by
the provider's design. It reaches the page through the runtime configuration
of [`090-web-client.md`](090-web-client.md) WC2, never compiled into the
bundle.

A **promotion code** is non-personal context, so a public surface is permitted
to carry one in the hand-off to sign-up. Its validity is decided here, at
checkout, and nowhere earlier. Invoices and the billing portal are read
through the adapter and served by the product.

### BL6. Provider events arrive as webhooks and are reconciled by a job

**Everything the provider tells the product arrives as a webhook handled per
[`055-messaging.md`](055-messaging.md) AM8. That means verified over the raw
body inside the adapter, re-enveloped with the provider's event id, recorded
durably, acknowledged, and only then processed**. The consumer maps each
`ProviderEvent` to a ledger row with actor `provider_webhook` and the provider
event id on the row. A redelivered event is then a repeat under AM3 and never
a second row. A period renewal updates the projection's period fields and
writes no row (BL2).

**Reconciliation is a periodic job, `billing.reconcile`**, declared under
[`057-jobs.md`](057-jobs.md) JB3 with `stale_after` (JB8): `single_flight`,
`idempotent`, `short`. For every subscription it compares the projection with
the provider's record: plan and price, status, period, whether cancellation is
scheduled. **A disagreement is a finding, never a silent write**. The job
records what it found on its run record (JB5) and alerts. It does not write a
ledger row to make the two agree, because which side is wrong is a judgment. A
person decides, and the correction is a ledger row by an `internal_admin` with
a reason.

The provider is polled by this job and by nothing else.

### BL7. Plan changes are made in the product, under stated policies

**A plan changes through the product's own routes, and never in the provider's
dashboard. An internal tool changes it by calling those routes over
[`050-http.md`](050-http.md) with a [`070-rbac.md`](070-rbac.md) permission**.
A change made at the provider moves the money truth and not the entitlement
truth. BL6's job turns it into a finding.

The policies, stated once so that no product decides them at a call site:

| Change | Timing | Ledger |
|---|---|---|
| **Upgrade** | Immediate, with proration by the provider. Entitlements change the moment the row is applied. | `upgraded`, effective at recording. |
| **Downgrade** | At period end. The tenant keeps what it paid for until then. | `downgraded`, effective at period end: the pending change. |
| **Cancellation** | At period end, then the suspended set. | `cancelled`, effective at period end: the pending change to no plan. |
| **Reactivation** | Immediate. | `reactivated`, effective at recording; supersedes a pending row. |
| **On a customer's behalf** | As above, by an `internal_admin`, with the reason on the row. | The same kinds; the actor differs. |

**Above a new quota, nothing is deleted and nothing new is created**. A tenant
that downgrades to three seats while holding seven keeps seven. The eighth is
refused until the count is under the ceiling. Deleting a customer's data to
fit a plan is a destructive act nobody asked for. Refusing creation is a state
the interface can explain.

A comp, a discount or a manual extension is an override or a plan change. The
staff member is the actor, the reason is on the row, and it is audited under
BL10. Staff never act through a customer's session.

### BL8. A trial is a subscription state with an end date

**A trial is the status `trialing` with `trial_end` on the projection and a
`trial_started` row in the ledger**. It is domain state, not a flag and not a
timer. The banner reads the projection, the entitlement function treats
`trialing` as the full plan, and the end is an instant the function already
knows.

**A job ends or converts it: `trial.expire`**, periodic under 057 with
`stale_after`, `single_flight`, `idempotent`. For every `trialing` subscription
past its `trial_end` it writes one of two rows. It writes `trial_converted`
where the provider has taken payment; usually the provider's webhook has
already written it, and the job finds nothing to do. Otherwise it writes
`trial_expired`, which is `cancelled` with no plan from that instant. The
warnings before the end are [`058-notifications.md`](058-notifications.md)
notifications in a declared category. The fact of the transition reaches a
CRM or anything else through the outbox (055 AM4) like every other ledger row.

**Free tier against trial is a declared per-product policy**. A free tier is
a plan in the catalog with a zero price and no trial; a trial is `trial_days`
on a paid plan. A product can have either or both, and states which in its
**Conventions**. The answer is written once, in the catalog, where the pricing
page and the sign-up flow both read it.

### BL9. Sign-up creates the tenant, its first administrator and its subscription in one transaction

**Sign-up runs in the product**. A public surface offers the plans and hands
the visitor across with nothing but non-personal context. That is the plan and
a campaign source as query parameters, and a promotion code at most. It never
renders a form that collects a name or an email for sign-up.

In the product, one transaction writes the tenant, its first user with the
administrative grant, and the subscription projection with its first ledger
row. That row is `trial_started` where the plan carries a trial, and
`upgraded` from no plan otherwise. The same transaction writes the outbox
events that announce the tenant, and the audit events. The identity is created
at the identity provider by the application, per [`060-auth.md`](060-auth.md)
AU4, through the idempotent `ensureIdentity`. The provider customer is created
through BL5's adapter with the tenant's public id as the idempotency key. The
projection's provider ids are absent until the provider confirms them.

Both calls cross a boundary on a key the product chose, which is what lets the
local transaction be retried without a second tenant. A tenant with no
subscription is one the entitlement function cannot answer for, and a
subscription with no tenant is a row nothing owns.

### BL10. Money events are audit events, and billing history is exportable

**Every ledger row emits an [`080-audit.md`](080-audit.md) event in the same
transaction** (AE8). The action is the product's declared `subscription.*`
permission that authorizes that kind of change (AE3). The actor is the user or
staff member for `user` and `internal_admin` rows, `service` for
`provider_webhook` rows and `system` for `job` rows, per AE2. The target is the
tenant. Cancellation and refund are already on AE5's floor as destructive
writes. This rule extends the floor to every row, because *who changed this
tenant's plan and why* is the question that gets asked.

Audit is a consequence of the ledger, never its source. The ledger row is the
domain fact and the audit event is the record that it happened.

**A tenant's billing history is part of its export** under
[`082-data-subject-rights.md`](082-data-subject-rights.md) DR3. The ledger and
the overrides are entries in the personal-data inventory (DR1) that export,
with the provider's ids withheld as another system's identifiers. On
cancellation, what is kept, for how long, and how the subject gets it back or
erased is [`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s and
082's business. The ledger sits under a `retain` treatment with a named basis
and an expiry (DR5), and everything else under the product's stated retention.
It is stated to the tenant up front.

## The artifacts

Per PC3, under [`contracts/billing/`](../contracts/billing/):

- **`catalog.schema.json`**: BL1's file: the closed sets, the plan shape,
  the grace period and the suspended set.
- **`subscription.schema.json`**: BL2's projection, ledger row and override;
  BL4's decision, entitlement set and the `entitlement-required` extension
  members.
- **`entitlements.json`**: the corpus: a catalog, subscriptions, a ledger,
  overrides, a fixed `now`, and checks with the decisions an implementation
  must reproduce.

## Decisions

- **An `entitlement` flag kind in 038, instead of a check of this document's
  own**. A flag returns a value and a closed reason enumeration. It cannot say
  which plan refused, carry a limit with a period, or answer for a past date.
  Money flips an entitlement and an engineer flips a flag, and a flag
  answering the same question is a second read path for one fact.
