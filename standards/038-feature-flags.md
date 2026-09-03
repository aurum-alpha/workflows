# Feature flags: the evaluation contract, what a flag is not, and why every flag expires

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/feature-flags/`](../contracts/feature-flags/); what is known to
satisfy these rules, and when that was last checked, is
[`solutions/038-feature-flags.md`](../solutions/038-feature-flags.md), which
states no rule of its own. Configuration is
[`030-service.md`](030-service.md) SC3's; the authorization check a flag never
replaces is [`070-rbac.md`](070-rbac.md)'s; what a browser is told is
[`090-web-client.md`](090-web-client.md) WC2's; the ids in an evaluation
context are [`020-identifiers.md`](020-identifiers.md)'s and the attributes
on the span are [`040-observability.md`](040-observability.md)'s; the sweep
that finds an overdue flag is a job under [`057-jobs.md`](057-jobs.md).

This document governs **the feature flag**: a named, typed value a running
process asks for at a decision point, whose answer may differ by environment,
tenant or user without a new release. It defines how a flag is evaluated,
declared, defaulted, bounded, observed and removed. **What it does not define
is configuration, authorization, or entitlement data.** A value that is the
same for every request in an environment is configuration under SC3; whether
a subject may do something is a permission under 070; what a tenant has
bought is domain data in the service's own database. A flag may read the
last of those and may gate the first two, and the rules say how far.

## Why this exists

A flag is the cheapest way to separate deploying code from releasing it, and
every product reaches for one early. The cheapest ways to build one share a
defect: they answer *what is the value* and never *what is the flag*. An `if`
on an environment variable is a flag with no owner, no type, no expiry and no
record that it was evaluated. A row in a settings table is a flag whose
existence nobody can read from the repository. A vendor SDK called from
domain code is a flag whose evaluation API is the vendor's.

Three failures follow, each a general property. **Flags accumulate.** A flag
that shipped a feature is still there two years later because nothing asked
whether it could go, and the code has 2ⁿ paths of which one was tested.
**Flags become authorization.** A flag that hides a button is one refactor
from being the only thing that stops the request, and a provider's state is
edited from a dashboard by people who are not reviewing a permission change.
**Flags leak.** The provider is a backing service that stores what it
receives as targeting context; an email address sent to make a rule readable
is personal data in a third system with its own retention.

The cheap answers fail again at evaluation. A provider that is down turns
every flag into whatever the client's error path returns, and the common
error path returns *enabled*, because the code was written while the feature
was being turned on. A flag evaluated in the browser hands the provider's
credential and every rule to anyone who opens developer tools. This standard
makes those decisions once: the evaluation API is a standard's, the
declaration is a file with a schema, the default is fixed by rule, the
boundary with authorization is drawn, the context vocabulary is closed, and
every flag carries the date it stops existing.

### The standards evaluated first, per PC2

**OpenFeature suffices as the evaluation contract.** The
[OpenFeature specification](https://openfeature.dev/specification/) defines
the three things an application needs at the boundary: an evaluation API
(`getBooleanValue`, `getStringValue`, `getNumberValue`, `getObjectValue`,
each with a `Details` form returning value, variant, reason and error code),
an **evaluation context** (a targeting key plus attributes), and a **provider
interface** behind which any flag system sits, plus hooks around every
evaluation and a tracking API for exposure. It is a CNCF specification with
SDKs in every language the portfolio writes, and a vendor SDK is delivered as
a provider for it rather than as a competitor. FF1 adopts it whole.

**The OpenTelemetry feature-flag semantic conventions suffice for
observability.** The
[`feature_flag.evaluation` event](https://opentelemetry.io/docs/specs/semconv/feature-flags/feature-flags-logs/)
names what an evaluation records — `feature_flag.key`, `provider.name`,
`context.id`, `result.value`, `result.variant`, `result.reason`, and
`error.type` on failure. FF8 adopts them.

**The OpenFeature CLI's flag manifest is adopted as the declaration's base,
not its whole.** It carries a flag's type, default and description — what
code generation needs and nothing a lifecycle needs: no owner, kind, expiry
or removal condition. FF2's declaration carries those three fields under the
platform's names and adds the lifecycle; a manifest is derivable from it, so
generation still works. A provider's flag-definition format (flagd's, a
vendor's export) describes **state** and is a provider's input, never the
declaration.

**What no standard covers** is what this document invents: the declaration
and its lifecycle (FF2, FF3, FF11), the default rule (FF4), the boundary with
authorization (FF5), the closed context vocabulary (FF6, where OpenFeature
defines the shape and this document pins the keys), and the rule that a
browser receives an evaluated set (FF7).

## The rules

### FF1. OpenFeature is the evaluation API, and the provider is configuration

**Application code evaluates a flag through the OpenFeature evaluation API
and through nothing else.** The typed calls, the evaluation context and the
`Details` result are the interface; the provider behind them is set once at
process start, chosen by configuration (SC3), and never imported by domain
code. A vendor SDK is only ever a provider. A repository that writes its own
provider — over a file, a table, an internal service — is conformant, because
the contract is the API and the corpus, not the package (PC4).

| Choice | This profile pins |
|---|---|
| Provider selection | From configuration at start; the startup line names the provider. With none configured the process runs the no-op provider: every flag is its declared default, and the startup line says so. |
| Evaluation | Typed. A provider value of another type is `TYPE_MISMATCH` and returns the default (FF4). |
| Reasons and error codes | The specification's own enumerations, unmodified: `STATIC`, `DEFAULT`, `TARGETING_MATCH`, `SPLIT`, `CACHED`, `DISABLED`, `STALE`, `ERROR`; `PROVIDER_NOT_READY`, `FLAG_NOT_FOUND`, `TYPE_MISMATCH`, `TARGETING_KEY_MISSING`, `INVALID_CONTEXT`, `PARSE_ERROR`, `PROVIDER_FATAL`, `GENERAL`. |
| Readiness | The provider is a dependency the service serves without (030 SC1 `degraded`): a provider down means defaults, never a `503`. |

One platform hook set is registered at start — the declaration check (FF2),
the context guard (FF6), the telemetry emission (FF8) — and domain code
registers none. An evaluation never throws: the specification's own rule,
restated because it is the one a hand-written client breaks first.

### FF2. Every flag is declared in the repository, and the declaration says what exists

**A flag exists because a declaration for it is committed beside the code
that evaluates it**, validated against
[`flag-declaration.schema.json`](../contracts/feature-flags/flag-declaration.schema.json)
and built into the image with the code (010, BUILD ONCE), so the set of flags
a release can evaluate is a fact about the release.

| Field | Values | What it decides |
|---|---|---|
| `name` | `<area>.<flag>`, lowercase `snake_case` segments, exactly two | The key passed to the evaluation API, the `feature_flag.key` on the span, the name in the sweep's finding. |
| `type` | `boolean` · `string` · `number` · `object` | Which typed call evaluates it. |
| `default` | A value of `type` | FF4. What every evaluation returns when the provider does not answer. |
| `kind` | `release` · `operational` · `experiment` · `entitlement` | FF3. Which lifetime fields are required and how long it may live. |
| `scope` | `global` · `tenant` · `user` | Which id is the targeting key; a scoped flag evaluated without it returns the default with `TARGETING_KEY_MISSING`. |
| `description` | text | What `true`, or each variant, turns on. |
| `owner` | a team or role handle | Who is asked when the sweep finds it overdue. |
| `created` | RFC 3339 `full-date` (IP4) | The start of the lifetime FF3 bounds. |
| `expires` | `full-date` | `release` and `experiment` only; required there. |
| `review_by` | `full-date` | `operational` and `entitlement` only; required there. |
| `removal` | text | `release` and `experiment` only; required there: the condition under which the flag and its call sites are deleted. |
| `variants` | list of admitted values | `experiment` requires two or more; admitted on any `string` or `number` flag. |
| `served_to_client` | boolean, default `false` | FF7. Whether the browser's evaluated set carries it. |

A name has the shape of a permission string (070 RB2) and is never one: the
two sets are disjoint, checkable by intersecting the declaration file with
the declared permission set, and a name in both is a flag used as a
permission (FF5) or a permission toggled by a dashboard.

**An evaluation of an undeclared flag is a finding.** The platform hook
(FF1) sees a key with no declaration, returns the call's default with
`FLAG_NOT_FOUND`, reports it once per process, and never asks the provider.
A flag that exists only in a dashboard is a value nobody in the repository
can see — the settings-table failure, returning through the vendor.

### FF3. A flag has one of four kinds, and every kind has an end

| Kind | It is for | Lives until | Lifetime field | Removal |
|---|---|---|---|---|
| `release` | Shipping code dark and turning it on: a dark launch, a rollout, a per-tenant preview. | The feature is on everywhere or abandoned. | `expires`, required | The flag and both code paths go; the surviving path is the code. |
| `experiment` | Measuring: two or more variants assigned to subjects, with a decision at the end. | The decision. | `expires`, required | The winning variant becomes the code; the exposure record is kept. |
| `operational` | An intervention without a deployment: a kill switch, a degraded mode, a rate cap. | An operator could still need it. | `review_by`, required | At review, kept with a new date or removed. |
| `entitlement` | A capability a tenant has or has not: a plan tier, a contract term, a beta programme. | The product sells it. | `review_by`, required | At review, kept with a new date or promoted to domain data. |

**`expires` is at most 180 days after `created`.** A release flag that plans
to live longer is an operational flag or a configuration value wearing a
release flag's name, and the declaration says which. A repository may lower
the ceiling in its **Conventions** and may not raise it. The day after
`expires` or `review_by`, the flag is a finding, raised by FF11's sweep and
by the CI check that reads the same file, naming the flag, its owner and its
removal condition. The kinds are disjoint: a flag that is a kill switch *and*
a rollout has two lifetimes and satisfies neither, so it is two flags.

### FF4. Every boolean flag defaults to `false`, and evaluation failure returns the default

**The default is the value under which the new thing is absent, and for a
boolean flag that value is `false`, always.** The flag is named for what
`true` turns on: `invoicing.pdf_renderer_v2`, `search.degraded_mode`,
`payments.fraud_bypass`. A kill switch is named for the intervention and
defaults to off, so a provider outage leaves the system in its normal state
rather than its emergency one. For a `string` or `number` flag the default
is the variant the code shipped with; that half is the review question.

**The call site's default is the declared default.** The evaluation API
requires a default argument at every call, a second copy of a value the
declaration holds. A repository removes the duplication by generating typed
accessors from the declaration (the manifest FF2 derives is what the
OpenFeature CLI consumes) or by a hook that reports a mismatch as a finding;
either is admitted.

**Every failure returns the declared default and says so.** Provider not
ready, flag not found, type mismatch, missing targeting key: each returns the
default with `reason: ERROR` and the specification's error code, the hook
emits the span event with `error.type`, and the process logs the first
occurrence per flag at `warn`. **An implementation that returns `true` on
failure for a flag that defaults to `false` is the one the corpus exists to
catch**, because it passes every test written while the provider was up.

### FF5. A flag is not authorization

**A flag decides whether a capability is shown or wired. It never decides
whether a subject is allowed.** The server's `check(subject, permission,
scope)` under 070 runs on every request that reaches a guarded handler,
whatever any flag evaluated to. An `entitlement` flag is evaluated *in
addition to* a permission, never instead of one: the flag says whether the
capability is offered to this tenant, the permission whether this subject may
use it, and both must say yes.

- **A flag never appears where a permission is expected.** Not in a grant, a
  role, the `/me` document's `permissions` list ([`060-auth.md`](060-auth.md)
  AU6), or an argument to `check`. The browser's evaluated set (FF7) is a
  separate document from `/me`.
- **Flag `true` and permission denied is a refusal.** An implementation that
  serves because the flag was on has made a dashboard the access-control
  system; the corpus carries the case.
- **Flag `false` and permission allowed is a capability not wired.** The route
  answers as if the code were not deployed — `404` per
  [`050-http.md`](050-http.md) HA3 — so a dark feature is dark to enumeration.

The reasoning is 070 RB4's through a different door: a flag set per subject
to grant access is an authorization input that is not a permission, edited
outside review and invisible to `permissionsFor`.

### FF6. The evaluation context is the platform's id vocabulary, and nothing personal travels in it

**What an application sends to a provider as targeting context is stored by
the provider**, a backing service in the
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
of birth, or free text.** The schema rejects the common spellings of those
keys, nested objects, and any string value containing `@`; that catches what
people type and not the property, so *would this attribute identify a
person if the provider were breached* stays the review question on every new
attribute. A rule that targets one person targets a public id, which
identifies nobody outside the service that minted it (IP3).

The platform hook builds the context from the request's authenticated
identity and the process's configuration; domain code adds attributes and
never constructs the ids. Tenant context is established by 070's own
mechanism and copied here, never read from a header a caller controls.

### FF7. Flags are evaluated by the server, and the browser receives an evaluated set

**A browser holds no provider credential and evaluates no targeting rule.**
It receives the values already decided for its session, as the `flags`
member of the application configuration fetched at load
([`090-web-client.md`](090-web-client.md) WC2's third row, `GET /api/config`),
shaped by
[`evaluated-set.schema.json`](../contracts/feature-flags/evaluated-set.schema.json):
flag name to value, plus the instant of evaluation. The server evaluates the
set with the session's subject as context, and it carries only flags declared
`served_to_client`.

The anonymous bootstrap carries only global flags: WC2's `features` map is
rendered before there is a subject, so it holds `scope: global` booleans and
nothing scoped. A change during a session takes effect on the next load, or
on a refresh the client performs on a trigger stated in the repository's
**Conventions**. The browser never subscribes to the provider directly,
because that is a credential in the bundle, which WC1 forbids. And a flag
the browser reads is still a flag the server enforces: the route behind a
hidden button evaluates the same flag and runs the same permission check
(FF5), because the evaluated set is a document anyone can edit.

### FF8. Every evaluation is observable on the span, and none is a log line at volume

**The platform hook records every evaluation as the OpenTelemetry
`feature_flag.evaluation` event on the span of the request or job that
evaluated it**: `feature_flag.key`, `feature_flag.provider.name`,
`feature_flag.context.id` (the targeting key), `feature_flag.result.value`
for scalar types, `feature_flag.result.variant` where the provider names one,
`feature_flag.result.reason`, and `error.type` on `ERROR`. The span already
carries the trace and the tenant (040 OC1, OC2), so a decision is
attributable to a request without a second correlation scheme.

**Evaluation is never a log line per call.** A flag evaluated on every
request, logged each time, carries nothing the span event does not and costs
storage per request. What is logged, with the flag's name in a field: the
provider selected at start, the first errored evaluation per flag per process
(FF4, at `warn`), and a provider-pushed change of a flag's value; never the
evaluation context. Evaluations are counted by `feature_flag.key` and
`feature_flag.result.reason`, so a provider outage is a step in `ERROR`.

### FF9. Flag state lives with the provider, and the provider is attached by configuration

**Values live in the provider; existence lives in the declaration (FF2).**
The provider is named by configuration (factor IV); three shapes are
admitted, and a repository says which in its **Conventions**:

| Provider | State lives | Changes take effect | Fit |
|---|---|---|---|
| A flag service, ours or a vendor's | In that service | At its propagation interval, without a deployment | Operational flags, rollouts, experiments. |
| The service's own database, behind a provider the repository writes | In a table the service owns (025 SD13) | On the next evaluation or cache expiry | Entitlements, where the value is domain data the product already stores. |
| The declaration file itself | In the release, overridden per environment by configuration | At the next deployment or restart | A product with no runtime toggling need. |

For the file provider, an environment's override of a default is
configuration under SC3, named `FLAG_<AREA>_<FLAG>`, read at start and logged
as SC3 requires of every optional variable. A product that needs a flag to
move without a restart has outgrown the file provider and chooses another
row. Whichever shape, no process holds a provider credential that is not its
own service's (000 Terms, *credential*): a shared flag service is shared the
way a mail relay is, each service attaching with its own credential.

### FF10. An experiment assigns deterministically, records exposure once, and ends with a decision

**Assignment is a pure function of the flag name and the targeting key.**
The same subject sees the same variant on every evaluation, every replica,
and after every deployment, because the bucket is a hash of the two and
nothing else. Random assignment per evaluation is a coin flip whose results
cannot be analysed.

**Exposure is recorded once per subject per experiment**, the first time the
subject is served a variant, as an `experiment.exposed` event under
[`055-messaging.md`](055-messaging.md) AM1 produced through the outbox with the
subject's public id and the variant — never per evaluation. The OpenFeature
tracking API is the call site; the analysis store is a consumer.

**An experiment expires with a decision written in its `removal` field**,
and the decision is a code change: the winning variant becomes the code and
the flag and its `variants` go. Extending an experiment is a new declaration
with a new `created`, reviewed as one.

### FF11. A flag is removed in one change, and the sweep that finds an overdue one is a job

**Removal is the completion of a flag**, and it is one change: the
declaration, every call site, and the code path the surviving value made
dead go together, so the repository never holds a declaration nothing
evaluates or a call site nothing declares. **The sweep is a periodic job**,
`flags.sweep`, declared under
[`057-jobs.md`](057-jobs.md) JB3 as `periodic` · `single_flight` · `short` ·
`idempotent`, with `stale_after` per JB8, so a sweep that stops running is
itself a finding. It reads the declaration file the process was built with,
compares `expires` and `review_by` to the current date, and reports each
overdue flag by name, owner and removal condition — to the log at `warn` and
to the repository's tracker where one is configured. The same comparison runs
as a CI check on every pull request that touches the file, so an overdue flag
fails the change that could have removed it. Neither removes anything: the
finding turns a silent accumulation into a named piece of work for its owner.

## Classifying a flag

| Proposed flag | Kind | Scope | Why |
|---|---|---|---|
| Turn the new PDF renderer on for one tenant, then all | `release` | `tenant` | Two code paths until the old one goes; expires with the rollout. |
| Ten percent of users see the redesigned checkout; measure conversion | `experiment` | `user` | Assignment by hash of the user id; exposure recorded once; expires with the decision. |
| Stop calling the fraud provider if it degrades | `operational` | `global` | An operator's intervention; `payments.fraud_bypass` defaults `false`; reviewed yearly. |
| Enterprise tenants get the audit export | `entitlement` | `tenant` | What the tenant bought, evaluated beside `audit.export` the permission, never instead of it. |
| Show the beta banner in staging only | `release` | `global` | An `environment` rule at the provider, in place of `if (env === "staging")` in code. |
| The API base URL | refused | — | Configuration under SC3: one value per environment, no subject. |
| `feature_enabled`, default `true`, so a provider outage keeps the feature on | refused | — | FF4: the default is off and the flag is named for what `true` turns on. An outage returns the system to normal, never to the feature. |

## The artifacts

Per PC3, under [`contracts/feature-flags/`](../contracts/feature-flags/):

- **`flag-declaration.schema.json`** — FF2's declaration, with FF3's
  conditional requirements: `release` and `experiment` carry `expires` and
  `removal` and never `review_by`; `operational` and `entitlement` carry
  `review_by` and never `expires`; an `experiment` carries two or more
  `variants`; a boolean flag's `default` is `false` (FF4). Dates `$ref` the
  identifiers contract.
- **`evaluation-context.schema.json`** — FF6's closed context: the id keys
  `$ref` the identifiers and observability contracts; `attributes` is flat,
  its keys reject the common personal-data spellings, its string values
  reject `@`.
- **`evaluated-set.schema.json`** — FF7's document the browser receives:
  flag name to scalar value, and the instant of evaluation.
- **`corpus.json`** — six parts. `declarations`, `contexts` and
  `evaluated_sets`: cases the schemas accept and reject, each rejection
  naming its rule. `evaluation`: given declarations, a provider state and a
  context, the value, reason and error code returned — including the
  provider-down case that separates fail-closed from fail-open, and the
  undeclared-flag case that separates consulting the declaration from asking
  the provider first. `gating`: an entitlement flag and a permission decision
  together, including the case that separates a flag from an authorization
  check. `experiments` and `expiry`: assignment and exposure; a date and the
  sweep's findings.

## Enforcement

Every FF rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. The
mechanically checkable parts, and therefore the first to move to a gate: the
declaration file validates and every flag in it is in date (FF2, FF3, FF11 —
a static check over one committed file, no false positives), the boolean
default (FF4, schema-decided), the disjointness of flag names and permission
strings (FF2, FF5 — an intersection of two committed sets), the context shape
(FF6), and the evaluation corpus against a repository's evaluation boundary
(FF4, FF5). The parts that stay review questions, said so in the ledger row:
whether domain code imports a provider (FF1 — a gate reading source would be
the PC4 violation), whether a non-boolean default is the shipped variant
(FF4), whether an attribute would identify a person (FF6), and whether a
declaration still has a call site (FF11).

## Decisions

- **OpenFeature is the evaluation API, adopted whole** (2026-09-02). A
  platform interface with the same three calls would be a second answer to a
  solved question and would leave every vendor SDK needing an adapter we
  write. OpenFeature's provider model already makes the vendor an adapter,
  and its hooks are where FF2, FF6 and FF8 attach without touching a call
  site.
- **The declaration is a platform schema, not the OpenFeature manifest**
  (2026-09-02). The manifest carries what generation needs and nothing a
  lifetime needs; extending it in place would make a generated file the
  source of truth for owners and dates. The declaration is the source and
  the manifest is derived.
- **Four kinds, each with a lifetime field, and no flag without one**
  (2026-09-02). An optional expiry is the accumulation failure with a field
  that permits it. Operational and entitlement flags do not expire, so they
  carry a review date; the invariant is a date after which every flag is a
  finding.
- **Every boolean defaults to `false`; the flag is named for what `true`
  turns on** (2026-09-02). A per-flag safe default makes the safe value a
  judgment at every declaration, and the fail-open outage — a provider down
  turning every kill switch on — is exactly the judgment that gets made
  wrong. Fixing the default fixes the naming.
- **An entitlement is a flag, evaluated beside a permission** (2026-09-02).
  Refusing the kind would put *what a tenant bought* into a system built for
  *what a subject may do* and make every plan change a grant change. It is
  admitted with FF5's rule that it never stands alone.
- **The browser receives values, never rules** (2026-09-02). A client-side
  SDK evaluating targeting needs the provider's credential and ships every
  rule to every visitor; the evaluated set costs one field on a document the
  client already fetches.
- **The 180-day ceiling on `expires`** (2026-09-02). A judgment stated so it
  can be argued with; without one the required field is satisfied by a date
  in the next decade. Repositories may lower it and may not raise it.
- **Exposure is an event through the outbox, once per subject**
  (2026-09-02). Per evaluation is FF8's volume failure in a second channel;
  nothing makes the experiment unanalysable. Once per subject at first
  exposure is the minimum an analysis needs, and the outbox is how a service
  emits a fact reliably (055 AM4).

## Out of scope, deliberately

- **Configuration.** [`030-service.md`](030-service.md) SC3, in full. A
  value with no subject is a variable, and the file provider's overrides are
  SC3 variables.
- **Authorization and entitlement data.** [`070-rbac.md`](070-rbac.md) owns
  the check; the service's database owns what a tenant bought. A flag reads
  the second and yields to the first.
- **The provider's internals.** Targeting-rule syntax, percentage rollouts,
  segment definitions and dashboards are the provider's, behind the
  interface. This document binds what crosses it.
