# Feature flags: the evaluation contract, what a flag is not, and why every flag expires

## Why this exists

A flag separates deploying code from releasing it, and every product reaches
for one early. The cheap forms answer *what is the value* and never *what is
the flag*: no owner, no type, no expiry, no evaluation record.
So flags accumulate, become authorization, leak personal data into a
provider, and fail open when the provider is down. This standard fixes the
evaluation API, the declaration and its lifetime, the default, the boundary
with authorization, and the context vocabulary.

**OpenFeature is adopted whole as the evaluation API (FF1)**. The
[specification](https://openfeature.dev/specification/) defines the typed
calls, the evaluation context, the provider interface behind which any flag
system sits, and hooks around every evaluation. The OpenTelemetry
feature-flag semantic conventions supply the evaluation event (FF8).

## The rules

### FF1. OpenFeature is the evaluation API, and the provider is configuration

**Application code evaluates a flag through the OpenFeature evaluation API
and through nothing else**. The typed calls, the evaluation context and the
`Details` result are the interface. The provider behind them is set once at
process start, chosen by configuration (SC3), and never imported by domain
code. A vendor SDK is only ever a provider. A platform interface with the
same calls would leave every vendor SDK needing an adapter written here;
OpenFeature's provider model makes the vendor the adapter.

| Choice | This profile pins |
|---|---|
| Provider selection | From configuration at start; the startup line names the provider. With none configured the process runs the no-op provider: every flag is its declared default, and the startup line says so. |
| Evaluation | Typed. A provider value of another type is `TYPE_MISMATCH` and returns the default (FF4). |
| Reasons and error codes | The specification's own enumerations, unmodified: `STATIC`, `DEFAULT`, `TARGETING_MATCH`, `SPLIT`, `CACHED`, `DISABLED`, `STALE`, `ERROR`; `PROVIDER_NOT_READY`, `FLAG_NOT_FOUND`, `TYPE_MISMATCH`, `TARGETING_KEY_MISSING`, `INVALID_CONTEXT`, `PARSE_ERROR`, `PROVIDER_FATAL`, `GENERAL`. |
| Readiness | The provider is a dependency the service serves without (030 SC1 `degraded`): a provider down means defaults, never a `503`. |

One platform hook set is registered at start: the declaration check (FF2),
the context guard (FF6), the telemetry emission (FF8). Domain code registers
none. An evaluation never throws, per the specification.

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

**The OpenFeature CLI's flag manifest is the declaration's base, not its
whole**. The manifest carries a flag's type, default and description: what
code generation needs and nothing a lifecycle needs. The declaration carries
those three fields under the platform's names and adds owner, kind, expiry
and removal. A manifest is derivable from it, so generation still works. A
provider's flag-definition format describes **state** and is a provider's
input, never the declaration.

A name has the shape of a permission string (070 RB2) and is never one. The
two sets are disjoint, checkable by intersecting the declaration file with
the declared permission set. A name in both is a flag used as a permission
(FF5) or a permission toggled by a dashboard.

**An evaluation of an undeclared flag is a finding**. The platform hook
(FF1) sees a key with no declaration. It returns the call's default with
`FLAG_NOT_FOUND`, reports it once per process, and never asks the provider.
A flag that exists only in a dashboard is a value nobody in the repository
can see.

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
pays for it has no bounded life and no engineer permitted to turn it off.

A flag evaluation returns a value and a reason from a closed enumeration. So
it cannot say *denied because the plan lacks this, upgrade to that*, and it
has no notion of a numeric ceiling per billing period. An entitlement wearing
a flag's name is refused here and admitted there.

**`expires` is at most 180 days after `created`**. A release flag that plans
to live longer is an operational flag or a configuration value wearing a
release flag's name. The declaration says which. A repository is permitted to
lower either ceiling in its **Conventions** and is not permitted to raise it.

The kinds are disjoint. A flag that is a kill switch *and* a rollout has two
lifetimes and satisfies neither, so it is two flags.

**`review_by` is at most 365 days ahead of the day the declaration is read**,
and the two ceilings are measured differently on purpose. `expires` is
bounded from `created` because a release or an experiment has a **bounded
life**: the whole point is that the flag ends. `review_by` is bounded from
*today* because an operational flag can legitimately live for years. So what
is bounded is not its life but the **neglect** of it: the longest anyone can
go without looking at it again.

A ceiling measured from `created` would be satisfied once and never again.
One measured from the reading makes a distant date fail every day and every
extension a reviewed commit. An annual look matches how
recurring review is scheduled. A shorter cycle on a kill switch that is
working becomes a rubber stamp, a record of review nobody performed.

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
occurrence per flag at `warn`.

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
  AU6), or an argument to `check`. A flag there is 070 RB4's authorization
  input that is not a permission. The browser's evaluated set (FF7) is a
  separate document from `/me`.
- **Flag `true` and permission denied is a refusal**. An implementation that
  serves because the flag was on has made a dashboard the access-control
  system; the corpus carries the case.
- **Flag `false` and permission allowed is a capability not wired**. The
  route answers as if the code were not deployed, `404` per
  [`050-http.md`](050-http.md) HA3, so a dark feature is dark to enumeration.

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
of birth, or free text**. The schema rejects common personal-data key
spellings and any value containing `@`. *Would this attribute identify a
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

A flag the browser reads is still a flag the server enforces. The route
behind a hidden button evaluates the same flag and runs the same permission
check (FF5). The evaluated set is a document anyone can edit.

### FF8. Every evaluation is observable on the span, and none is a log line at volume

**The platform hook records every evaluation as the OpenTelemetry
[`feature_flag.evaluation` event](https://opentelemetry.io/docs/specs/semconv/feature-flags/feature-flags-logs/)
on the span of the request or job that evaluated it**. The event carries
`feature_flag.key`, `feature_flag.provider.name`, and
`feature_flag.context.id` (the targeting key). It carries
`feature_flag.result.value` for scalar types, `feature_flag.result.variant`
where the provider names one, `feature_flag.result.reason`, and `error.type`
on `ERROR`. The span already carries the trace and the tenant (040 OC1,
OC2), so a decision is attributable to a request without a second
correlation scheme.

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
the repository's **Conventions**. State lives in that service, and a change
takes effect at its propagation interval, without a deployment. That fits
every flag with a runtime life: rollouts, experiments, kill switches,
degraded modes. Which provider is
[`solutions/038-feature-flags.md`](../solutions/038-feature-flags.md)'s.

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
language in use. It also means a test suite for all of it. That is a solved
problem being solved again badly, and PC1's refusal exactly.

And **it is a second flag system**. A product running a file provider in one
service and a flag service in another has two answers to *where a flag value
lives*. That is the failure FF1 opens by preventing.

A product's first flag costs it a backing service. A product unwilling to
pay it does not have a cheaper flag; it has configuration, and must call it
that.

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
| Show the beta banner in staging only | `release` | `global` | An `environment` rule at the provider, in place of `if (env === "staging")` in code. |

## The artifacts

Per PC3, under [`contracts/feature-flags/`](../contracts/feature-flags/):

- **`flag-declaration.schema.json`**: FF2's declaration, with FF3's
  conditional requirements.
- **`evaluation-context.schema.json`**: FF6's closed context.
- **`evaluated-set.schema.json`**: FF7's document the browser receives.
- **`corpus.json`**: `declarations`, `contexts`, `evaluated_sets`,
  `evaluation`, `gating`, `experiments` and `expiry`.
