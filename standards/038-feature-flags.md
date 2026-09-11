# Feature flags: the evaluation contract, what a flag is not, and why every flag expires

## Why this exists

A flag is the cheapest way to separate deploying code from releasing it, and
every product reaches for one early. The cheapest ways to build one share a
defect: they answer *what is the value* and never *what is the flag*. An `if`
on an environment variable is a flag with no owner, no type, no expiry and no
record that it was evaluated. A row in a settings table is a flag whose
existence nobody can read from the repository. A vendor SDK called from
domain code is a flag whose evaluation API is the vendor's.

Three failures follow, each a general property. **Flags accumulate**. A flag
that shipped a feature is still there two years later because nothing asked
whether it could go. The code has 2ⁿ paths of which one was tested.

**Flags become authorization**. A flag that hides a button is one refactor
from being the only thing that stops the request. A provider's state is
edited from a dashboard by people who are not reviewing a permission change.

**Flags leak**. The provider is a backing service that stores what it
receives as targeting context. An email address sent to make a rule readable
is personal data in a third system with its own retention.

The cheap answers fail again at evaluation. A provider that is down turns
every flag into whatever the client's error path returns. The common error
path returns *enabled*, because the code was written while the feature was
being turned on. A flag evaluated in the browser hands the provider's
credential and every rule to anyone who opens developer tools.

This standard makes those decisions once. The evaluation API is a standard's,
the declaration is a file with a schema, and the default is fixed by rule.
The boundary with authorization is drawn, the context vocabulary is closed,
and every flag carries the date it stops existing.

### The standards evaluated first, per PC2

**OpenFeature suffices as the evaluation contract**. The
[OpenFeature specification](https://openfeature.dev/specification/) defines
the three things an application needs at the boundary. The first is an
evaluation API: `getBooleanValue`, `getStringValue`, `getNumberValue`,
`getObjectValue`, each with a `Details` form returning value, variant, reason
and error code. The second is an **evaluation context**, a targeting key plus
attributes. The third is a **provider interface** behind which any flag
system sits. It also defines hooks around every evaluation and a tracking API
for exposure.

It is a CNCF specification with SDKs in every language the portfolio writes.
A vendor SDK is delivered as a provider for it rather than as a competitor.
FF1 adopts it whole.

**The OpenTelemetry feature-flag semantic conventions suffice for
observability**. The
[`feature_flag.evaluation` event](https://opentelemetry.io/docs/specs/semconv/feature-flags/feature-flags-logs/)
names what an evaluation records: `feature_flag.key`, `provider.name`,
`context.id`, `result.value`, `result.variant`, `result.reason`, and
`error.type` on failure. FF8 adopts them.

**The OpenFeature CLI's flag manifest is adopted as the declaration's base,
not its whole**. It carries a flag's type, default and description. That is
what code generation needs and nothing a lifecycle needs: no owner, kind,
expiry or removal condition. FF2's declaration carries those three fields
under the platform's names and adds the lifecycle. A manifest is derivable
from it, so generation still works. A provider's flag-definition format
(flagd's, a vendor's export) describes **state** and is a provider's input,
never the declaration.

**What no standard covers** is what this document invents. That is the
declaration and its lifecycle (FF2, FF3, FF11), the default rule (FF4), and
the boundary with authorization (FF5). It is also the closed context
vocabulary (FF6), where OpenFeature defines the shape and this document pins
the keys. And it is the rule that a browser receives an evaluated set (FF7).

## The rules

### FF1. OpenFeature is the evaluation API, and the provider is configuration

**Application code evaluates a flag through the OpenFeature evaluation API
and through nothing else**. The typed calls, the evaluation context and the
`Details` result are the interface. The provider behind them is set once at
process start, chosen by configuration (SC3), and never imported by domain
code. A vendor SDK is only ever a provider.

Whether a provider arrives as a package or is written here is a question
this contract does not ask. What binds is the API and the corpus rather than
the package (PC4). **Which shapes are admitted at all is FF9's**, and it
admits writing one for exactly one narrow case.

| Choice | This profile pins |
|---|---|
| Provider selection | From configuration at start; the startup line names the provider. With none configured the process runs the no-op provider: every flag is its declared default, and the startup line says so. |
| Evaluation | Typed. A provider value of another type is `TYPE_MISMATCH` and returns the default (FF4). |
| Reasons and error codes | The specification's own enumerations, unmodified: `STATIC`, `DEFAULT`, `TARGETING_MATCH`, `SPLIT`, `CACHED`, `DISABLED`, `STALE`, `ERROR`; `PROVIDER_NOT_READY`, `FLAG_NOT_FOUND`, `TYPE_MISMATCH`, `TARGETING_KEY_MISSING`, `INVALID_CONTEXT`, `PARSE_ERROR`, `PROVIDER_FATAL`, `GENERAL`. |
| Readiness | The provider is a dependency the service serves without (030 SC1 `degraded`): a provider down means defaults, never a `503`. |

One platform hook set is registered at start: the declaration check (FF2),
the context guard (FF6), the telemetry emission (FF8). Domain code registers
none. An evaluation never throws. That is the specification's own rule,
restated because it is the one a hand-written client breaks first.

### FF2. Every flag is declared in the repository, and the declaration says what exists

**A flag exists because a declaration for it is committed beside the code
that evaluates it**. The declaration is validated against
[`flag-declaration.schema.json`](../contracts/feature-flags/flag-declaration.schema.json)
and built into the image with the code (010, BUILD ONCE). So the set of flags
a release can evaluate is a fact about the release.

| Field | Values | What it decides |
|---|---|---|
| `name` | `<area>.<flag>`, lowercase `snake_case` segments, exactly two | The key passed to the evaluation API, the `feature_flag.key` on the span, the name in the sweep's finding. |
| `type` | `boolean` · `string` · `number` · `object` | Which typed call evaluates it. |
| `default` | A value of `type` | FF4. What every evaluation returns when the provider does not answer. |
| `kind` | `release` · `operational` · `experiment` | FF3. Which lifetime fields are required and how long it can live. |
| `scope` | `global` · `tenant` · `user` | Which id is the targeting key; a scoped flag evaluated without it returns the default with `TARGETING_KEY_MISSING`. |
| `description` | text | What `true`, or each variant, turns on. |
| `owner` | a team or role handle | Who is asked when the sweep finds it overdue. |
| `created` | RFC 3339 `full-date` (IP4) | The start of the lifetime FF3 bounds. |
| `expires` | `full-date` | `release` and `experiment` only; required there. |
| `review_by` | `full-date` | `operational` only; required there. |
| `removal` | text | `release` and `experiment` only; required there: the condition under which the flag and its call sites are deleted. |
| `variants` | list of admitted values | `experiment` requires two or more; admitted on any `string` or `number` flag. |
| `served_to_client` | boolean, default `false` | FF7. Whether the browser's evaluated set carries it. |

A name has the shape of a permission string (070 RB2) and is never one. The
two sets are disjoint, checkable by intersecting the declaration file with
the declared permission set. A name in both is a flag used as a permission
(FF5) or a permission toggled by a dashboard.

**An evaluation of an undeclared flag is a finding**. The platform hook
(FF1) sees a key with no declaration. It returns the call's default with
`FLAG_NOT_FOUND`, reports it once per process, and never asks the provider.
A flag that exists only in a dashboard is a value nobody in the repository
can see. That is the settings-table failure, returning through the vendor.

### FF3. A flag has one of three kinds, and every kind has an end

| Kind | It is for | Lives until | Lifetime field | Removal |
|---|---|---|---|---|
| `release` | Shipping code dark and turning it on: a dark launch, a rollout, a per-tenant preview. | The feature is on everywhere or abandoned. | `expires`, required | The flag and both code paths go; the surviving path is the code. |
| `experiment` | Measuring: two or more variants assigned to subjects, with a decision at the end. | The decision. | `expires`, required | The winning variant becomes the code; the exposure record is kept. |
| `operational` | An intervention without a deployment: a kill switch, a degraded mode, a rate cap. | An operator could still need it. | `review_by`, required | At review, kept with a new date or removed. |

**What a tenant has bought is not a kind of flag**. A plan tier, a contract
term, a seat count: each is an entitlement, derived from the tenant's
subscription under the [billing standard](075-billing.md) BL3. That
standard's own operation (BL4) checks it beside the 070 permission. The test
that separates the two is *who flips it*: an engineer or an operator flips a
flag; a payment flips an entitlement. A flag that stays on because a customer
pays for it has no bounded life and no engineer permitted to turn it off. So
it is an entitlement wearing a flag's name, refused here and admitted there.

**`expires` is at most 180 days after `created`**. A release flag that plans
to live longer is an operational flag or a configuration value wearing a
release flag's name. The declaration says which. A repository is permitted to
lower the ceiling in its **Conventions** and is not permitted to raise it.
The day after `expires` or `review_by`, the flag is a finding. FF11's sweep
and the CI check that reads the same file raise it, naming the flag, its
owner and its removal condition.

The kinds are disjoint. A flag that is a kill switch *and* a rollout has two
lifetimes and satisfies neither, so it is two flags.

**`review_by` is at most 365 days ahead of the day the declaration is read**,
and the two ceilings are measured differently on purpose. `expires` is
bounded from `created` because a release or an experiment has a **bounded
life**: the whole point is that the flag ends. `review_by` is bounded from
*today* because an operational flag can legitimately live for years. So what
is bounded is not its life but the **neglect** of it: the longest anyone can
go without looking at it again.

A ceiling measured from `created` would be satisfied once and never again. A
required field with no ceiling at all is satisfied by typing a date in the
next century. That is the accumulation failure FF3 exists to prevent,
arriving through the one kind that never expires.

Measured forward from the reading, neither is possible. A distant date fails
the day it is written and every day after. Extension is always available and
always a commit somebody reviews. A flag kept for a decade is kept by ten
deliberate acts rather than by one forgotten one. A repository is permitted
to lower either ceiling in its **Conventions** and is not permitted to raise
it.

The number is a judgment, like 180. An annual look matches how recurring
review is actually scheduled. A shorter cycle on a kill switch that is
working correctly becomes a rubber stamp. That is worse than a longer one
that is honoured, because it produces a record of review nobody performed.

### FF4. Every boolean flag defaults to `false`, and evaluation failure returns the default

**The default is the value under which the new thing is absent, and for a
boolean flag that value is `false`, always**. The flag is named for what
`true` turns on: `invoicing.pdf_renderer_v2`, `search.degraded_mode`,
`payments.fraud_bypass`. A kill switch is named for the intervention and
defaults to off. So a provider outage leaves the system in its normal state
rather than its emergency one. For a `string` or `number` flag the default
is the variant the code shipped with; that half is the review question.

**The call site's default is the declared default**. The evaluation API
requires a default argument at every call, a second copy of a value the
declaration holds. A repository removes the duplication in one of two ways.
It generates typed accessors from the declaration, or a hook reports a
mismatch as a finding. The manifest FF2 derives is what the OpenFeature CLI
consumes. Either is admitted.

**Every failure returns the declared default and says so**. Provider not
ready, flag not found, type mismatch, missing targeting key: each returns the
default with `reason: ERROR` and the specification's error code. The hook
emits the span event with `error.type`, and the process logs the first
occurrence per flag at `warn`. **An implementation that returns `true` on
failure for a flag that defaults to `false` is the one the corpus exists to
catch**. It passes every test written while the provider was up.

### FF5. A flag is not authorization

**A flag decides whether a capability is shown or wired. It never decides
whether a subject is allowed**. The server's `check(subject, permission,
scope)` under 070 runs on every request that reaches a guarded handler,
whatever any flag evaluated to. Nor does a flag decide what a tenant has
bought. That is the [billing standard](075-billing.md)'s entitlement check,
which runs beside the permission (BL4).

The order a guarded handler asks is fixed: the release flag, then the
permission, then the entitlement. Each answers a different question, and a
denial has to name which one said no.

- **A flag never appears where a permission is expected**. Not in a grant, a
  role, the `/me` document's `permissions` list ([`060-auth.md`](060-auth.md)
  AU6), or an argument to `check`. The browser's evaluated set (FF7) is a
  separate document from `/me`.
- **Flag `true` and permission denied is a refusal**. An implementation that
  serves because the flag was on has made a dashboard the access-control
  system; the corpus carries the case.
- **Flag `false` and permission allowed is a capability not wired**. The
  route answers as if the code were not deployed, `404` per
  [`050-http.md`](050-http.md) HA3, so a dark feature is dark to enumeration.

The reasoning is 070 RB4's through a different door. A flag set per subject
to grant access is an authorization input that is not a permission. It is
edited outside review and invisible to `permissionsFor`.

### FF6. The evaluation context is the platform's id vocabulary, and nothing personal travels in it

**What an application sends to a provider as targeting context is stored by
the provider**. The provider is a backing service in the
[factor IV](https://12factor.net/backing-services) sense with its own
retention. So the context is closed, shaped by
[`evaluation-context.schema.json`](../contracts/feature-flags/evaluation-context.schema.json):

| Key | Value | Role |
|---|---|---|
| `targeting_key` | The public id the flag's `scope` names: the user's for `user`, the tenant's for `tenant`; absent for `global`. | OpenFeature's targeting key; `feature_flag.context.id` on the span; the input to an experiment's assignment. |
| `tenant_id` | The tenant public id, per 040 OC2. | Tenant rules. |
| `user_id` | The user public id, per 020 IP1. | User rules; never an internal key. |
| `environment` | `development` · `test` · `staging` · `production`, as WC2's document spells them. | Environment rules, in place of the environment detection SC3 forbids in code. |
| `release_version` | The repository's SemVer version (010, Principle 15). | Rules that turn on at a release. |
| `service` | The service's logical name. | Rules scoped to one service in a repository holding several. |
| `attributes` | A flat map of declared, non-personal attributes: a plan tier, a region code, a device class. Keys `snake_case`; values short scalars. | Whatever else a rule needs that is not a person. |

**Never an email, a name, a phone number, an address, an IP address, a date
of birth, or free text**. The schema rejects the common spellings of those
keys, nested objects, and any string value containing `@`. That catches what
people type and not the property. So *would this attribute identify a
person if the provider were breached* stays the review question on every new
attribute. A rule that targets one person targets a public id, which
identifies nobody outside the service that minted it (IP3).

The platform hook builds the context from the request's authenticated
identity and the process's configuration; domain code adds attributes and
never constructs the ids. Tenant context is established by 070's own
mechanism and copied here, never read from a header a caller controls.

### FF7. Flags are evaluated by the server, and the browser receives an evaluated set

**A browser holds no provider credential and evaluates no targeting rule**.
It receives the values decided for its session, as the `flags` member of
the application configuration fetched at load
([`090-web-client.md`](090-web-client.md) WC2's third row, `GET /api/config`).
[`evaluated-set.schema.json`](../contracts/feature-flags/evaluated-set.schema.json)
shapes it: flag name to value, plus the instant of evaluation. The server
evaluates the set with the session's subject as context, and it carries only
flags declared `served_to_client`.

The anonymous bootstrap carries only global flags. WC2's `features` map is
rendered before there is a subject, so it holds `scope: global` booleans and
nothing scoped. A change during a session takes effect on the next load. Or
it takes effect on a refresh the client performs on a trigger stated in the
repository's **Conventions**.

The browser never subscribes to the provider directly, because that is a
credential in the bundle, which WC1 forbids. A flag the browser reads is
still a flag the server enforces. The route behind a hidden button evaluates
the same flag and runs the same permission check (FF5). The evaluated set is
a document anyone can edit.

### FF8. Every evaluation is observable on the span, and none is a log line at volume

**The platform hook records every evaluation as the OpenTelemetry
`feature_flag.evaluation` event on the span of the request or job that
evaluated it**. The event carries `feature_flag.key`,
`feature_flag.provider.name`, and `feature_flag.context.id` (the targeting
key). It carries `feature_flag.result.value` for scalar types,
`feature_flag.result.variant` where the provider names one,
`feature_flag.result.reason`, and `error.type` on `ERROR`. The span already
carries the trace and the tenant (040 OC1, OC2), so a decision is
attributable to a request without a second correlation scheme.

**Evaluation is never a log line per call**. A flag evaluated on every
request, logged each time, carries nothing the span event does not and costs
storage per request. Three things are logged, with the flag's name in a
field. They are the provider selected at start, and the first errored
evaluation per flag per process (FF4, at `warn`). The third is a
provider-pushed change of a flag's value.

The evaluation context is never logged. Evaluations are counted by
`feature_flag.key` and `feature_flag.result.reason`, so a provider outage is
a step in `ERROR`.

### FF9. Flag state lives with the provider, and the provider is attached by configuration

**Values live in the provider; existence lives in the declaration (FF2)**.
The provider is named by configuration (factor IV). It is **a flag service
taken off the shelf**, ours or a vendor's, self-hosted or hosted, named in
the repository's **Conventions**:

| Provider | State lives | Changes take effect | Fit |
|---|---|---|---|
| A flag service, ours or a vendor's, taken off the shelf | In that service | At its propagation interval, without a deployment | Every flag with a runtime life: rollouts, experiments, kill switches, degraded modes. |

An earlier version of this table had a second row, a thin adapter over the
product's own tables for entitlements. It went when entitlements stopped
being a kind of flag (FF3). With no entitlement to read, there is nothing in
the product's tables a flag provider has any business reading. A provider
over domain data was a second read path to a question the [billing
standard](075-billing.md) answers with one.

**A flag whose value ships in the release is not admitted**, and neither is
the bespoke machinery that would make one work. The tempting third shape is
flag values in a committed file, overridden per environment by variables. It
is refused on three grounds.

**A value that cannot change without a deployment is not a flag**. The
entire reason this capability exists is to separate deploying code from
releasing it. So a value that needs a deployment to move is configuration,
and SC3 already owns it in full.

**Building it means specifying it**. That means a file format, an override
grammar, a precedence order, a reload rule, and a typed accessor package per
language the portfolio writes. It also means a test suite for all of it.
That is a solved problem being solved again badly, and PC1's refusal
exactly.

And **it is a second flag system**. A product running a file provider in one
service and a flag service in another has two answers to *where a flag value
lives*. That is the failure FF1 opens by preventing.

So the honest consequence, stated rather than hidden: **a product's first
flag costs it a backing service**. That price is the rule working. A product
unwilling to pay it does not have a cheaper flag; it has configuration, and
must call it that.

No process holds a provider credential that is not its own service's (000
Terms, *credential*). A shared flag service is shared the way a mail relay
is, each service attaching with its own credential.

### FF10. An experiment assigns deterministically, records exposure once, and ends with a decision

**Assignment is a pure function of the flag name and the targeting key**.
The same subject sees the same variant on every evaluation, every replica,
and after every deployment. The bucket is a hash of the two and nothing
else. Random assignment per evaluation is a coin flip whose results cannot
be analysed.

**Exposure is recorded once per subject per experiment**, the first time the
subject is served a variant, and never per evaluation. It is an
`experiment.exposed` event under [`055-messaging.md`](055-messaging.md) AM1,
produced through the outbox with the subject's public id and the variant.
The OpenFeature tracking API is the call site; the analysis store is a
consumer.

**An experiment expires with a decision written in its `removal` field**,
and the decision is a code change. The winning variant becomes the code, and
the flag and its `variants` go. Extending an experiment is a new declaration
with a new `created`, reviewed as one.

### FF11. A flag is removed in one change, and the sweep that finds an overdue one is a job

**Removal is the completion of a flag**, and it is one change. The
declaration, every call site, and the code path the surviving value made
dead go together. So the repository never holds a declaration nothing
evaluates or a call site nothing declares.

**The sweep is a periodic job**, `flags.sweep`, declared under
[`057-jobs.md`](057-jobs.md) JB3 as `periodic` · `single_flight` · `short` ·
`idempotent`. It has `stale_after` per JB8, so a sweep that stops running is
itself a finding. It reads the declaration file the process was built with,
and compares `expires` and `review_by` to the current date.

It reports each overdue flag by name, owner and removal condition. The report
goes to the log at `warn` and to the repository's tracker where one is
configured. The same comparison runs as a CI check on every pull request
that touches the file. So an overdue flag fails the change that could have
removed it. Neither removes anything: the finding turns a silent
accumulation into a named piece of work for its owner.

## Classifying a flag

| Proposed flag | Kind | Scope | Why |
|---|---|---|---|
| Turn the new PDF renderer on for one tenant, then all | `release` | `tenant` | Two code paths until the old one goes; expires with the rollout. |
| Ten percent of users see the redesigned checkout; measure conversion | `experiment` | `user` | Assignment by hash of the user id; exposure recorded once; expires with the decision. |
| Stop calling the fraud provider if it degrades | `operational` | `global` | An operator's intervention; `payments.fraud_bypass` defaults `false`; reviewed yearly. |
| Enterprise tenants get the audit export | refused | — | An entitlement under the [billing standard](075-billing.md): what the tenant bought is derived from its subscription and checked beside `audit.export` the permission. A payment flips it, so it is not a flag. |
| Show the beta banner in staging only | `release` | `global` | An `environment` rule at the provider, in place of `if (env === "staging")` in code. |
| The API base URL | refused | — | Configuration under SC3: one value per environment, no subject. |
| `feature_enabled`, default `true`, so a provider outage keeps the feature on | refused | — | FF4: the default is off and the flag is named for what `true` turns on. An outage returns the system to normal, never to the feature. |

## The artifacts

Per PC3, under [`contracts/feature-flags/`](../contracts/feature-flags/):

- **`flag-declaration.schema.json`**: FF2's declaration, with FF3's
  conditional requirements. `release` and `experiment` carry `expires` and
  `removal` and never `review_by`. `operational` carries `review_by` and
  never `expires`. An `experiment` carries two or more `variants`. A boolean
  flag's `default` is `false` (FF4). Dates `$ref` the identifiers contract.
- **`evaluation-context.schema.json`**: FF6's closed context. The id keys
  `$ref` the identifiers and observability contracts. `attributes` is flat,
  its keys reject the common personal-data spellings, and its string values
  reject `@`.
- **`evaluated-set.schema.json`**: FF7's document the browser receives:
  flag name to scalar value, and the instant of evaluation.
- **`corpus.json`**: six parts. `declarations`, `contexts` and
  `evaluated_sets`: cases the schemas accept and reject, each rejection
  naming its rule. `evaluation`: given declarations, a provider state and a
  context, the value, reason and error code returned. It includes the
  provider-down case that separates fail-closed from fail-open, and the
  undeclared-flag case that separates consulting the declaration from asking
  the provider first. `gating`: a flag and a permission decision together,
  including the case that separates a flag from an authorization check.
  `experiments` and `expiry`: assignment and exposure; a date and the
  sweep's findings.

## Decisions

- **OpenFeature is the evaluation API, adopted whole** (2026-09-02). A
  platform interface with the same three calls would be a second answer to a
  solved question. It would leave every vendor SDK needing an adapter we
  write. OpenFeature's provider model already makes the vendor an adapter,
  and its hooks are where FF2, FF6 and FF8 attach without touching a call
  site.
- **The declaration is a platform schema, not the OpenFeature manifest**
  (2026-09-02). The manifest carries what generation needs and nothing a
  lifetime needs. Extending it in place would make a generated file the
  source of truth for owners and dates. The declaration is the source and
  the manifest is derived.
- **Every kind has a lifetime field, and no flag is without one**
  (2026-09-02). An optional expiry is the accumulation failure with a field
  that permits it. An operational flag does not expire, so it
  carries a review date; the invariant is a date after which every flag is a
  finding. (This entry said *four kinds* when written; see the entry of
  2026-09-08 for why it is three.)
- **Every boolean defaults to `false`; the flag is named for what `true`
  turns on** (2026-09-02). A per-flag safe default makes the safe value a
  judgment at every declaration. The fail-open outage, a provider down
  turning every kill switch on, is exactly the judgment that gets made
  wrong. Fixing the default fixes the naming.
- **An entitlement is not a flag; the billing standard owns the check**
  (2026-09-08, reversing the entry of 2026-09-02). The earlier entry admitted
  an `entitlement` kind so that *what a tenant bought* would not be forced
  into the authorization model. That half of the argument still holds: it is
  not a permission either. What the flag shape could not carry became clear
  once entitlements were specified in full.

  A flag evaluation returns a value and a reason from a closed enumeration.
  So it cannot say *denied because the plan lacks this, upgrade to that*, and
  it has no notion of a numeric ceiling per billing period. A thin adapter
  over the product's tables made two read paths for one question. That is
  the one-way principle broken in the standard written to serve it. The kind
  is removed, and the [billing standard](075-billing.md) defines the
  entitlement check with its own decision, reason and corpus. What survives
  here is the ordering rule in FF5: a flag is asked first, a permission
  second, an entitlement third, and none decides for another.
- **One provider shape, and the flag values never ship in the release**
  (2026-09-04; the adapter shape withdrawn 2026-09-08 with the entitlement
  kind). An earlier draft admitted a third shape, flag values in a committed
  file, overridden per environment. It was the cheap starting point for a
  product with no runtime toggling need. It is refused, and the refusal
  removes a rung rather than adding one. A value that needs a deployment to
  move is not a flag but configuration, which SC3 already owns.

  Building the shape properly would mean specifying a file format, an
  override grammar, a precedence order, and a reload rule. It would also
  mean a typed accessor package per language. That is a solved problem re-solved
  worse and PC1's refusal exactly. A product running it beside a real flag
  service has two answers to where a flag value lives. The consequence is
  stated rather than hidden: the first flag costs a backing service. A
  product unwilling to pay that has configuration, not a cheaper flag.
- **The browser receives values, never rules** (2026-09-02). A client-side
  SDK evaluating targeting needs the provider's credential and ships every
  rule to every visitor. The evaluated set costs one field on a document the
  client already fetches.
- **The 180-day ceiling on `expires`** (2026-09-02). A judgment stated so it
  can be argued with; without one the required field is satisfied by a date
  in the next decade. Repositories are permitted to lower it and not to
  raise it.
- **`review_by` is bounded 365 days ahead of the reading date, not from
  `created`** (2026-09-03). The ceiling on `expires` was written and the
  matching one on `review_by` was not. That left the standard bounding the
  flags already on their way out and leaving unbounded the two kinds most
  likely to sit for a decade. That is the exact inversion of what FF3 is
  for. A ceiling measured from `created` is the obvious fix and the wrong
  one. It is satisfied once, and it wrongly reports a flag that has been
  legitimately reviewed every year since.

  Measuring forward from the reading makes a distant date fail on the day it
  is written. It makes extension always available and always a reviewed
  commit, and makes a decade of keeping a flag cost ten deliberate acts.
  Both weakenings are in the corpus as detectors so neither can return
  quietly.
- **Exposure is an event through the outbox, once per subject**
  (2026-09-02). Per evaluation is FF8's volume failure in a second channel;
  nothing makes the experiment unanalysable. Once per subject at first
  exposure is the minimum an analysis needs. The outbox is how a service
  emits a fact reliably (055 AM4).

## Out of scope, deliberately

- **Configuration**. [`030-service.md`](030-service.md) SC3, in full. A
  value with no subject is a variable. So is a value that cannot change
  without a deployment, whatever it is called (FF9).
- **Authorization and entitlements**. [`070-rbac.md`](070-rbac.md) owns
  whether a subject is allowed to act; the [billing standard](075-billing.md)
  owns what a tenant has bought and the check that reads it. A flag decides
  neither and is asked before both.
- **The provider's internals**. Targeting-rule syntax, percentage rollouts,
  segment definitions and dashboards are the provider's, behind the
  interface. This document binds what crosses it.
