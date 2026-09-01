# The web client: what a browser holds, fetches, sends and reports

One of the Aurum Alpha engineering standards, written under the platform
contract ([`platform.md`](platform.md)) — a per-capability standard from its
roster. Read [`enforcement.md`](enforcement.md) for the tier each rule below
actually holds. Artifacts: [`contracts/web-client/`](../contracts/web-client/).

This document governs code that runs in a browser: what it may hold as a
credential (WC1), where its configuration comes from (WC2), how it talks to
an Aurum Alpha service (WC3), what it does with the values that service
sends (WC4), and what it reports when something breaks (WC5).

**It does not decide how authentication works.** That belongs to the
[authentication and authorization standard](platform.md#the-capability-roster),
and the boundary is drawn deliberately: a rule that is equally true of a
server-rendered application with no JavaScript is not a browser rule. WC1
carries only what is true *because* the client is a browser.

## Why this exists

Every other standard in this repository governs a server process. That was
defensible while the fleet's standards were about services, and it stopped
being defensible the moment a browser client had to claim compliance with
them — because a frontend that "follows the fleet standards" was following
nothing written about it.

The roster's own rule makes this sharper than an omission. *A capability's
absence from that table is a claim that the fleet has considered it and
declined.* Five browser-side decisions were sitting in that gap, each one
real, each one otherwise made independently by whoever started a frontend
first: what the page may hold as a credential, how a bundle learns which
API to call, who parses the error envelope, whose time zone a timestamp
renders in, and what a client-side crash report contains.

Two of those are not merely unowned but actively hazardous to get wrong.
**What the page holds is a security decision**, and the industry answer
changed — the guidance that produced a generation of single-page apps
keeping tokens in `localStorage` has been superseded. **Client
configuration collides with
[factor III](https://12factor.net/config)** in a way no server does, because
a browser bundle is built once and served to many, so there is no process
environment to read at start. A product that discovers that on its own
usually resolves it by baking the API URL into the bundle at build time,
which quietly breaks build-once — and nothing fails when it does.

One document rather than five, deliberately. These decisions are entangled:
what the page may hold determines how the API client presents itself, which
determines what the runtime configuration document has to carry, which
determines what a browser may be told at all. Split across five standards
each would be mostly cross-reference. This follows the shape of the
[service contract](service.md), which bundles health, logging, config,
shutdown and provenance for the same reason — they are one process's
obligations, and these are one client's.

## The rules

### WC1. The browser holds no tokens, and is not part of the authentication exchange

A browser cannot keep a secret. Everything the bundle contains is readable
by anyone who opens developer tools, and any script running in the page —
including one that arrived through a compromised dependency — runs with the
application's full authority. Every rule here follows from that one fact.

**The browser's only credential is a session cookie it cannot read.** No
access token, no refresh token, no ID token is ever held by JavaScript, and
the page never talks to the identity provider directly. Authentication
happens entirely in front of the application, and the browser's part in it
is to be redirected and to come back holding a cookie.

Three consequences, and they are the whole of this rule:

- **Nothing is stored in `localStorage`, `sessionStorage` or IndexedDB.**
  All three are readable by any script in the origin, so one cross-site
  scripting flaw anywhere in the page — or in anything the page imports —
  is a credential exfiltration. A short expiry does not redeem it: a stolen
  token is used immediately.
- **No credential that authenticates to the identity provider is compiled
  into the bundle.** No client secret, no provider credential, nothing that
  would let the page complete an exchange on its own. WC2 already forbids
  environment values in the bundle for a different reason; this is the
  security reason, and it is the harder of the two.
- **On a `401`, the client navigates to the login path from its runtime
  configuration** (WC2) and does nothing else. It never attempts a token
  exchange, never refreshes a token, never parses one. A client that finds
  itself needing to do any of those has been given a token, which is the
  thing this rule prevents.

**Everything else about authentication belongs to the [authentication and
authorization standard](platform.md#the-capability-roster), not here** —
which component is the identity provider's client, the session cookie's
attributes and lifetime, refresh and revocation, and what identity crosses
from that component to the backend. Those decisions are not browser
decisions: they apply identically to a server-rendered application with no
JavaScript at all, and a rule that is true of a non-browser case does not
belong in this document. What survives here is only what is true *because*
the client is a browser.

### WC2. Configuration is fetched at load, never baked into the bundle

**The build produces one artifact, and that artifact is
environment-agnostic.** No API URL, no tenant, no provider hostname, no
feature toggle is compiled in. The bundle that was tested in staging is the
bundle that reaches production, byte for byte.

At load, the client fetches a small **bootstrap document** from the origin that
served it, shaped by
[`contracts/web-client/runtime-config.schema.json`](../contracts/web-client/runtime-config.schema.json).
That origin renders it from *its own* environment.

**Three things are involved and only the middle one is this document**, because
conflating them produces a config that cannot be correct in every topology:

| | Where it comes from | Changes when |
|---|---|---|
| **Build provenance** | compiled into the bundle by the bundler | the frontend is rebuilt |
| **Bootstrap** | the origin that served the bundle, from its environment | that host is deployed |
| **Application config** | `GET /api/config` from the backend | the backend is deployed or reconfigured |

The bootstrap exists because of an ordering problem that has no other answer:
**the client cannot ask the API where the API is.** The API origin cannot be
compiled in — that is environment-specific, and the build-once violation this
rule exists to stop — so it has to arrive from the host that served the page.
Everything else the backend knows about itself, including its own version and
whatever the frontend needs to interact correctly with *that* deployment, belongs
on `/api/config` and not here. Where one origin serves both (the default
topology) the two may be answered by one endpoint; keeping them distinct is what
makes the split-origin topology work without a special case.

**This is not a departure from [factor III](https://12factor.net/config).**
It reads like one, and stating it as an exception would be wrong. Factor III
requires configuration to live in the environment rather than in the code,
and here it does — in the serving process's environment, exactly where the
rest of this fleet keeps it. What changes is only that the browser reads it
one hop away, over HTTP, because a browser has no environment of its own to
read. The naive translation of the factor — *put it in the bundle at build
time* — is what actually violates it, twice over: config becomes code, and
one artifact per environment breaks the build-once separation
[factor V](https://12factor.net/build-release-run) and the
[CI standard](ci.md) both require.

**Build provenance is compiled in, and is not fetched at all.** The application
version and the commit describe the *build* rather than the environment, so
baking them breaks nothing — and no server can supply them, because under a
split origin the backend has no idea which frontend build a given browser is
running. The bundler writes them at build time (`define` in Vite and its
equivalents). That is the browser's half of the runtime provenance rule
([`service.md`](service.md) SC5), and WC5 requires it in error reports.

**Nothing secret goes in either document.** Both are served to every visitor
who loads the page — the bootstrap to anonymous ones — so both are public by
construction. A value that must not be public belongs behind the server, where
the browser can use its effect without ever seeing it.

### WC3. One API client module, generated, owning the boundary rules

Calls to an Aurum Alpha service go through **one client module**, not
`fetch` scattered across components. The rule is not tidiness. Every
cross-cutting obligation the service interfaces standard places on a
consumer needs exactly one home, and a codebase with forty call sites has
forty places for one of them to be missing:

- **Types are generated from the committed OpenAPI document**
  ([`http.md`](http.md) HA2), never hand-written. A hand-maintained
  interface mirroring an API is a copy that drifts, and it drifts silently
  because nothing compares them.
- **Errors are parsed as problem+json** (HA3). The client branches on
  `type`, which is the contract, and shows `detail` to a human, which is the
  courtesy. It never branches on `detail`'s prose.
- **Mutating requests carry an `Idempotency-Key`** (HA6), generated by the
  client, and **the same key is reused on retry** — a fresh key on the
  retry defeats the entire mechanism and duplicates the charge.
- **Retries are bounded, jittered, and only for requests that are safe**
  (HA7): idempotent by method, or carrying the key above. `Retry-After`,
  when present, wins over the client's own backoff.
- **Collections are paged by the returned `next_cursor` until it is null**
  (HA4), never by constructing an offset.
- **The client sends the session cookie and attaches no `Authorization`
  header** — under WC1 it has nothing to put in one. Which means requests
  go to an origin the cookie is scoped to, so the client never needs
  cross-origin credential handling.

A repository may generate this module, hand-write it, or wrap a generated
core. What it may not do is spread these six obligations across a component
tree.

### WC4. Presentation is the client's job, and it is done with `Intl`

The [identifiers standard](identifiers.md) rules that the server speaks base
representations — RFC 3339 UTC instants, integer minor units with an ISO
4217 code, opaque public ids — and that presentation is the UI's job. This
rule is the other half of that sentence, and without it the first half is an
instruction with no addressee.

**The viewer's locale and time zone come from the viewer.** An explicit user
preference wins where the product has one; otherwise the browser's own
resolution (`Intl.DateTimeFormat().resolvedOptions()`) is authoritative.
Neither is ever inferred server-side from an IP address, which is a guess
about geography answering a question about preference — and is wrong for
every traveller, every VPN user, and everyone whose language does not match
their country.

**Formatting uses the platform's `Intl` API**, not a bundled formatting
library carrying its own copy of the locale data. The browser's data is
maintained, complete, and already downloaded.

Two specifics, because both are got wrong in the same way — by assuming the
developer's own locale is the general case:

- **Money is not divided by 100.** The server sends minor units and a
  currency code (IP5); the exponent belongs to the currency, and JPY has
  zero of them while several currencies have three. `Intl.NumberFormat`
  with `style: "currency"` knows this. Hardcoding two decimal places is a
  bug that will not surface until the product is sold abroad.
- **An instant is not a date.** The server sends UTC; the calendar day a
  given instant falls on depends on the viewer's zone, so a timestamp
  rendered as a bare date without converting first is off by one for a
  predictable fraction of users every day.

**The server never sends a pre-formatted string**, and a client never asks
for one. That would push one viewer's locale into a shared response and
turn every other consumer's correct rendering into a parsing job.

### WC5. The browser does not originate the server's trace, and reports errors with the request id

A browser is not a service, and the observability standard's propagation
rule ([`observability.md`](observability.md) OC1) already answers this case
without naming it: an inbound request without a valid `traceparent` starts a
new trace at the receiving service's edge. That is the correct default here.
The trace begins at the edge, not in the page.

**The client's correlation handle is the request id the server returns.** It
is already required in every error envelope (HA3 `request_id`), which is the
moment correlation is actually needed, and it costs the client nothing to
capture: a support report quoting a request id turns a screenshot into a log
query.

A **client error report** takes the shape
[`contracts/web-client/error-report.schema.json`](../contracts/web-client/error-report.schema.json)
defines, and what it must and must not carry follows the same reasoning the
service standard applies to log lines:

- **It states a specific reason** — which operation, against which endpoint,
  with which request id. A report saying only that an error occurred is the
  [`service.md`](service.md) SC2 failure on a new surface: a class of
  problem with no occurrence in it.
- **It carries the application version and commit** from WC2, because a
  stack trace against unknown source is unreadable, and browsers hold stale
  bundles longer than servers hold stale builds.
- **It never carries the session cookie, an access token, or personal
  data.** An error reporter is a pipe to a third party, and a report is
  written from the one context that holds everything the user typed.

Whether a client emits telemetry beyond error reports is a repository's
choice, stated in its **Conventions**. Where one runs full browser RUM and
wants a single trace across the page and the backend, it may send
`traceparent` — and then the server continues it **as telemetry only**.
Nothing derived from a browser-supplied trace is ever a trusted input, for
the same reason the observability standard gives about `tenant_id`: it
arrives from a caller who can put anything in it.

## The artifacts

Per PC3, under [`contracts/web-client/`](../contracts/web-client/):

- **`runtime-config.schema.json`** — the document WC2 requires the server to
  serve and the client to fetch, including the provenance fields WC5 needs.
- **`error-report.schema.json`** — the client error report of WC5,
  `$ref`-ing the identifiers contract for its timestamp and the observability
  contract for the request id, so one spelling covers the browser and the
  server.
- **`corpus.json`** — validity cases for both shapes, plus behavioural cases
  a live client and its server must satisfy.

## Enforcement

Every rule here is review-only today, with gates named per rule in
[`enforcement.md`](enforcement.md). Two are cheaply and honestly gateable,
and the rest are not, which is worth being direct about: **this is the least
gateable standard in the repository so far**, because its subject runs on
someone else's machine.

- **WC2 is statically decidable and is the one to build first.** A checker
  greps the built bundle for the values that must not be in it — the API
  origin, the provider hostname, anything from the runtime config document's
  own property list. A bundle is a file in the build output, so this needs
  no browser and no running service.
- **The config document validates**, as an ordinary schema check against a
  running server, in the shape `job-image-starts` already provides.
- **WC1's storage half is observable**: the corpus reads `localStorage`,
  `sessionStorage` and IndexedDB after a login and asserts nothing
  credential-shaped is there. The cookie's own attributes are a live gate
  too, but they belong to the [authentication and authorization
  standard](platform.md#the-capability-roster), which sets them.
- **WC1's central claim resists a checker entirely.** Proving no token
  reaches JavaScript means proving a negative about a program's runtime, and
  a gate that tried would be reading the implementation, which PC4 forbids.
  The review question is stated instead: *what credential does this page
  hold, and what could read it.*
- **WC3 and WC4 stay review questions.** A checker cannot tell a generated
  client from a hand-written one that happens to be correct, and per PC4 it
  should not try; a checker that failed a build for calling `fetch` directly
  would be enforcing an implementation choice rather than a boundary.

## Decisions

- **WC1 carries the browser's half only; the architecture is the
  authentication standard's** (2026-09-01): the first draft of this rule
  chose the Backend-For-Frontend pattern, pinned the session cookie's
  attributes, and required refresh-token rotation. Every one of those is a
  decision the [authentication and authorization
  standard](platform.md#the-capability-roster) states as its own — and each
  is equally true of a server-rendered application with no JavaScript,
  which is the test that shows they are not browser rules. Deciding them
  here would have been this repository's own two-answers failure, committed
  in the standard written to close a gap. What is left is the part that
  survives that test: web storage holds nothing, no provider credential is
  in the bundle, and a `401` is answered by navigating, not by exchanging.
- **One document, five rules, five roster rows** (2026-08-31): the
  capabilities are entangled through what the page may hold, so five
  standards would each be mostly a link to the others. The roster still
  gains a row per capability, so the table keeps its property that absence
  means declined.
- **Build provenance is compiled in, not served** (2026-09-01): the first
  version of this rule put the frontend's version and commit inside the served
  document and required them. That is wrong wherever the bundle and the API come
  from different origins, because the serving backend has no idea which frontend
  build a given browser is running — and the split-origin topology is admitted.
  Three things were being conflated: build provenance (compiled in), the
  bootstrap (from the bundle's origin), and application config (from the
  backend). Removing a required field is breaking under PC6, so the contract
  moves to schemaVersion 2 and the deprecation window is stated as nil, because
  no implementation consumed version 1.
- **Client config is factor III honoured, not departed from** (2026-08-31):
  stated deliberately, because the charter requires a departure to be
  declared and this one would have been declared wrongly. The browser reads
  a configuration that lives in an environment; it is simply the server's
  environment. What breaks the factor is the build-time bake, which also
  breaks build-once.
- **The browser does not start the server's trace** (2026-08-31): a unified
  browser-to-backend trace is genuinely useful, and it is admitted for
  repositories running real RUM. It is not the default because the default
  must work for a client that ships no telemetry SDK at all, and because
  OC1's existing edge-starts-the-trace rule already covers the case
  correctly. Correlation by request id needs nothing installed.
- **`Intl` over a formatting library** (2026-08-31): the usual argument for
  a library is consistency across environments, which mattered when browser
  locale data was patchy. It is not patchy now, and a bundled copy of CLDR
  is a large download that ages.
