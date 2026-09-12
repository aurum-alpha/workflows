# Acceptable solutions: feature flags

Register for [`standards/038-feature-flags.md`](../standards/038-feature-flags.md).

## What adopting anything does and does not do for you

A flag system implements one rule and part of two others; the remaining eight
are the repository's work whatever is adopted.

| Rule | What an adopted thing supplies | What is yours regardless |
|---|---|---|
| FF1 | The **OpenFeature SDK for the language** supplies almost all of it: the typed calls, the `Details` result, the reason and error enumerations unmodified, the hook mechanism, and the no-op provider that FF1 makes the unconfigured default. A **provider** supplies only the connection to state. | Provider selection from configuration (SC3), the startup line, the platform hook set, readiness `degraded` when the provider is down. |
| FF2 | Nothing. A provider's flag-definition format describes **state**, never the declaration. | The declaration file, its validation, the `FLAG_NOT_FOUND` hook, flag names disjoint from permissions. |
| FF3 | Nothing. No provider models three kinds with a lifetime field. | All of it. |
| FF4 | The SDK's default argument returns the declared default on every failure path, so the fail-closed half is free unless the evaluation boundary intercepts errors and substitutes its own answer. | The `false` rule, the naming rule, the call site's default equal to the declaration's. |
| FF5 | Nothing, and an adopted system makes it easier to break: per-user targeting in a dashboard is one refactor from being the only thing stopping a request. | The 070 check and the 075 entitlement check on every guarded handler. |
| FF6 | The SDK supplies the context shape. Where the provider runs decides what leaves your network, which is where the rows below differ on risk. | The closed vocabulary, the guard hook, the judgment on each new attribute. |
| FF7 | A **server-side** SDK, plus the configuration route the web client already fetches. | Evaluating and shaping the set; no provider credential in the browser. |
| FF8 | The OpenFeature contrib repositories carry OpenTelemetry hooks for several languages, emitting the semantic conventions FF8 adopts. Verify one exists for yours at the version you pin. | Registering it; no log line per evaluation. |
| FF9 | The service FF9 requires. | Naming it in **Conventions**; attaching with the service's own credential. |
| FF10 | A percentage rollout, **admitted only if assignment is a hash of the flag name and the targeting key**; check the vendor's bucketing input, because a provider that re-randomises per evaluation cannot be analysed. The OpenFeature tracking API is the exposure call site. | The exposure event through the outbox, once per subject; the decision at expiry. |
| FF11 | Nothing. A vendor's stale-flag dashboard is a second inventory, not the sweep. | The `flags.sweep` job, the CI check over the declaration, removal as one change. |

## The two routes to FF1, and why one is preferred

**Route A: a provider package for each language.** The vendor ships an
adapter; you configure it. What to verify before adopting: that a provider
exists for *every* language the repository writes, server side, at the SDK
specification version you pin. Also who maintains it. A community-maintained
provider is a dependency with a bus factor, and its lag behind a specification
version becomes your defect.

**Route B: OFREP, the OpenFeature Remote Evaluation Protocol.** The backend
speaks a standard HTTP contract and a community OFREP provider talks to it.
Such a provider exists for several of the SDK languages, so confirm yours. No
vendor adapter enters the dependency tree at all. **Prefer this route wherever
the candidate supports it.** It is the only one that makes FF1's "the provider
is configuration" literally true. Changing vendor becomes a URL and a
credential rather than a package swap in every service. It also collapses
Route A's whole verification burden, which is the burden that dates fastest.

## The default route

**If a product needs feature flags at all, it takes an off-the-shelf flag
service.** That is the whole answer. The register's job is only to say which
ones are known to work.

FF9 refuses the small start, values in a file with overrides, because that is
a bespoke flag system with the specification work still owed.

So the decision a repository actually faces is not *how small can we start*.
It is a prior question with two honest answers:

- **This product does not need flags.** Most do not. It has configuration
  under SC3, it says so, and it stops. Nothing here applies.
- **This product needs flags.** Then it runs a flag service from the table
  below.

**Where the choice is genuinely open**, and the register takes no side, is
self-hosted against hosted. Self-hosted keeps FF6's evaluation context inside
the network. Hosted buys a dashboard non-engineers can use and an operational
burden somebody else carries. Both are in the table.

## The register

Per-language provider coverage is the fastest-moving fact on this page. Check
the [OpenFeature ecosystem catalogue](https://openfeature.dev/ecosystem/) for
the languages you write before adopting any row.

| Option | FF9 shape | OFREP | Provider maintained by | Notes against 038 |
|---|---|---|---|---|
| **flagd** | Flag service | Yes | The OpenFeature project itself | The project's own flag daemon, so it tracks the specification rather than following it. Its state is fed from files or over gRPC, and it is a running service either way — the file is the operator's input to the daemon, never flag values shipped inside a release, which FF9 refuses. |
| **GO Feature Flag** | Flag service | Yes | Vendor | Self-hosted relay with broad first-party provider coverage when checked. |
| **Flipt** | Flag service | Yes | Vendor | Self-hosted or hosted; an early OFREP implementer. |
| **Flagsmith** | Flag service | Verify | Vendor | Self-hostable or hosted; an OpenFeature founding member, so the provider is unlikely to be an afterthought. |
| **GrowthBook** | Flag service | Verify | Vendor | Self-hostable; experimentation is the reason to reach for it (FF10), not flagging alone. |
| **Unleash** | Flag service | Verify | **Community** | Self-hostable. The weakest first-party commitment in the set when checked: the providers are community work, which is rule-4 exposure on a page like this. |
| **LaunchDarkly** | Flag service (hosted) | Verify | Vendor | Provider coverage is materially narrower than its native SDK coverage, and skewed server-side. Verify your languages first; FF7 means the missing browser provider costs you nothing. |
| **ConfigCat** | Flag service (hosted) | Verify | Vendor | Providers moved from community to official maintenance before it was checked. |
| **DevCycle** | Flag service (hosted) | Yes | Vendor | Server, client and OFREP support. |
| **Split** | Flag service (hosted) | Verify | Vendor | Providers across several languages; verify yours. |

"Verify" in the OFREP column means the protocol was not confirmed for that
option when checked, not that it is absent. Check before letting it
decide.

## Routes 038 refuses, and the rule that refuses them

| Route | Refused by |
|---|---|
| A client-side vendor SDK evaluating targeting rules in the browser | **FF7** — the browser receives values, never rules — and **090 WC1**, because it puts a provider credential in the bundle. |
| A vendor SDK imported and called from domain code | **FF1**. A vendor SDK is only ever a provider, behind the evaluation API. |
| A flag that exists in the vendor's dashboard and in no declaration | **FF2**. It is answered `FLAG_NOT_FOUND` from the declared default and reported, whatever the provider holds. |
| A vendor's per-user targeting used to decide whether a subject may act | **FF5**. The 070 check runs whatever the flag said. |
| An email address or name sent as a targeting attribute so a rule reads nicely | **FF6**. The context is closed, and the schema rejects it. |
| An adopted system's stale-flag dashboard in place of the sweep | **FF11**. The finding has to reach the owner and the repository's tracker, from the declaration the release was built with. |
| A flag, in any provider, that stands for what a tenant has bought | **FF3**, and the [billing standard](../standards/075-billing.md) BL3: a payment flips an entitlement, not an engineer, so it has no flag lifetime and is checked by that standard's own operation beside the permission. |

## Choosing, in order

1. **Does it speak OFREP?** If yes, Route B, and questions 2 and 3 mostly stop
   mattering.
2. **Does a provider exist for every language this repository writes, server
   side?** FF7 removes the browser from the question, where coverage is
   thinnest.
3. **Who maintains that provider, and against which specification version?**
4. **Where does the evaluation context go?** Self-hosted keeps FF6's exposure
   inside the network. Hosted does not, and the review question on every
   attribute gets sharper.
5. **What does assignment hash?** Only if FF10 is in play. A rollout that
   re-randomises per evaluation is unanalysable.
