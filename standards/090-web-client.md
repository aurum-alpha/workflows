# The web client: what a browser holds, fetches, sends and reports

## Why this exists

Every other standard in this repository governs a server process. That was
defensible while these standards were about services. It stopped being
defensible the moment a browser client had to claim compliance with them. A
frontend that "follows the standards" was following nothing written about it.

The roster's own rule makes this sharper than an omission. *A capability's
absence from that table is a claim that we have considered it and declined*.
Five browser-side decisions were sitting in that gap. Each one was real, and
each one was otherwise made independently by whoever started a frontend first.
They are what the page can hold as a credential, how a bundle learns which API
to call, and who parses the error envelope. They are also whose time zone a
timestamp renders in, and what a client-side crash report contains.

Two of those are not merely unowned but actively hazardous to get wrong.
**What the page holds is a security decision**, and the industry answer
changed. The guidance that produced a generation of single-page apps keeping
tokens in `localStorage` has been superseded.

**Client configuration collides with [factor
III](https://12factor.net/config)** in a way no server does. A browser bundle
is built once and served to many, so there is no process environment to read
at start. A product that discovers that on its own usually resolves it by
baking the API URL into the bundle at build time. That quietly breaks
build-once, and nothing fails when it does.

One document rather than five, deliberately. These decisions are entangled:
what the page can hold determines how the API client presents itself. That
determines what the runtime configuration document has to carry, which
determines what a browser can be told at all. Split across five standards,
each would be mostly cross-reference. This follows the shape of the [service
contract](030-service.md), which bundles health, logging, config, shutdown and
provenance for the same reason. They are one process's obligations, and these
are one client's.

## The rules

### WC1. The browser holds no tokens, and is not part of the authentication exchange

A browser cannot keep a secret. Everything the bundle contains is readable by
anyone who opens developer tools. Any script running in the page, including
one that arrived through a compromised dependency, runs with the application's
full authority. Every rule here follows from that one fact.

**The browser's only credential is a session cookie it cannot read**. No
access token, no refresh token, no ID token is ever held by JavaScript, and
the page never talks to the identity provider directly. Authentication happens
entirely in front of the application. The browser's part in it is to be
redirected and to come back holding a cookie.

Three consequences, and they are the whole of this rule:

- **Nothing is stored in `localStorage`, `sessionStorage` or IndexedDB**.
  All three are readable by any script in the origin. So one cross-site
  scripting flaw anywhere in the page, or in anything the page imports, is a
  credential exfiltration. A short expiry does not redeem it: a stolen token
  is used immediately.
- **No credential that authenticates to the identity provider is compiled
  into the bundle**. No client secret, no provider credential, nothing that
  would let the page complete an exchange on its own. WC2 already forbids
  environment values in the bundle for a different reason. This is the
  security reason, and it is the harder of the two.
- **On a `401`, the client navigates to the login path from its runtime
  configuration** (WC2) and does nothing else. It never attempts a token
  exchange, never refreshes a token, never parses one. A client that finds
  itself needing to do any of those has been given a token, which is the
  thing this rule prevents.

**Everything else about authentication belongs to the [authentication and
authorization standard](060-auth.md), not here**. That is which component is
the identity provider's client, and the session cookie's attributes and
lifetime. It is refresh and revocation, and what identity crosses from that
component to the backend. Those decisions are not browser decisions: they
apply identically to a server-rendered application with no JavaScript at all.
A rule that is true of a non-browser case does not belong in this document.
What survives here is only what is true *because* the client is a browser.

### WC2. Configuration is fetched at load, never baked into the bundle

**The build produces one artifact, and that artifact is
environment-agnostic**. No API URL, no tenant, no provider hostname, no
feature toggle is compiled in. The bundle that was tested in staging is the
bundle that reaches production, byte for byte.

At load, the client fetches a small **bootstrap document** from the origin
that served it, shaped by
[`contracts/web-client/runtime-config.schema.json`](../contracts/web-client/runtime-config.schema.json).
That origin renders it from *its own* environment.

**The delivery is pinned, because the document is the one thing every surface
fetches before it can do anything else**. It is served at `/config.json` on
the origin that served the bundle, as `application/json` with `Cache-Control:
no-store`. The bundle awaits it before first render. The path is fixed so that
a front door on a static host, a product behind a proxy and an internal tool
are bootstrapped identically. `no-store` is what lets a deployment change a
value without a rebuild or a cache purge. How the origin renders it is the
origin's business.

A serving process substitutes from its environment at request time. A static
host's **deploy step writes the file into the artifact directory** from the
deployment's environment. The build never touches it, so the artifact stays
identical across environments.

The document carries, and carries only:

| Field | What it is | Present for |
|---|---|---|
| `schema_version` | the shape's version, `3` | every surface |
| `environment` | `development` · `test` · `staging` · `production` | every surface |
| `surface_class` | `front_door` · `product` · `internal`, per the [web estate standard](091-web-estate.md) WE1 | every surface |
| `api_origin` | the origin the API client (WC3) calls: scheme, host, port | product and internal; absent on a front door |
| `login_path` · `logout_path` | where a top-level navigation begins a session, and the path that ends it server-side | product and internal; absent on a front door |
| `global_flags` | the anonymous, global subset of the evaluated flag set ([`038-feature-flags.md`](038-feature-flags.md) FF7) | optional |
| `surface_settings` | per-surface, per-environment scalars (a booking link, a form endpoint) under keys **the repository declares** in a schema its CI validates the served document against | optional |

Every field is named for what it is, and there is no wrapper object and no
free-form bag. A name that says less than the value (`url` for an origin) or
nothing at all (`auth` around two paths) costs every reader a lookup. A map
with undeclared keys is where a secret arrives without anyone deciding that it
does. `surface_settings` is the one open map, and it is open only to keys the
repository has declared. That is what makes an undeclared key a finding rather
than a feature.

**Three things are involved and only the middle one is this document**.
Conflating them produces a config that cannot be correct in every topology:

| | Where it comes from | Changes when |
|---|---|---|
| **Build provenance** | compiled into the bundle by the bundler | the frontend is rebuilt |
| **Bootstrap** | the origin that served the bundle, from its environment | that host is deployed |
| **Application config** | `GET /api/config` from the backend | the backend is deployed or reconfigured |

The bootstrap exists because of an ordering problem that has no other answer:
**the client cannot ask the API where the API is**. The API origin cannot be
compiled in. That is environment-specific, and the build-once violation this
rule exists to stop. So it has to arrive from the host that served the page.
Everything else the backend knows about itself belongs on `/api/config` and
not here. That includes its own version and whatever the frontend needs to
interact correctly with *that* deployment.

Where one origin serves both (the default topology) the two can be answered by
one endpoint. Keeping them distinct is what makes the split-origin topology
work without a special case.

**This is not a departure from [factor III](https://12factor.net/config)**. It
reads like one, and stating it as an exception would be wrong. Factor III
requires configuration to live in the environment rather than in the code, and
here it does. It lives in the serving process's environment, exactly where the
rest of this portfolio keeps it. What changes is only that the browser reads
it one hop away, over HTTP, because a browser has no environment of its own to
read.

The naive translation of the factor, *put it in the bundle at build time*, is
what actually violates it, twice over. Config becomes code. And one artifact
per environment breaks the build-once separation [factor
V](https://12factor.net/build-release-run) and the [CI standard](010-ci.md)
both require.

**Build provenance is compiled in, and is not fetched at all**. The
application version and the commit describe the *build* rather than the
environment, so baking them breaks nothing. And no server can supply them,
because under a split origin the backend has no idea which frontend build a
given browser is running. The bundler writes them at build time (`define` in
Vite and its equivalents). That is the browser's half of the runtime
provenance rule ([`030-service.md`](030-service.md) SC5), and WC5 requires it
in error reports.

**Nothing secret goes in either document**. Both are served to every visitor
who loads the page, the bootstrap to anonymous ones, so both are public by
construction. A value that must not be public belongs behind the server, where
the browser can use its effect without ever seeing it.

The authenticated application configuration's `flags` member is the evaluated
set of [`038-feature-flags.md`](038-feature-flags.md) FF7, shaped by
`contracts/feature-flags/evaluated-set.schema.json`. The browser renders from
it and evaluates nothing. The bootstrap's `global_flags` is the anonymous
subset of the same set: global scope, boolean, declared `served_to_client`.
The bootstrap is served before anyone is known, and a tenant- or user-scoped
value cannot exist yet.

### WC3. One API client module, generated, owning the boundary rules

Calls to an Aurum Alpha service go through **one client module**, not `fetch`
scattered across components. The rule is not tidiness. Every cross-cutting
obligation the service interfaces standard places on a consumer needs exactly
one home. A codebase with forty call sites has forty places for one of them to
be missing:

- **Types are generated from the committed OpenAPI document**
  ([`050-http.md`](050-http.md) HA2), never hand-written. A hand-maintained
  interface mirroring an API is a copy that drifts. It drifts silently
  because nothing compares them.
- **Errors are parsed as problem+json** (HA3). The client branches on
  `type`, which is the contract, and shows `detail` to a human, which is the
  courtesy. It never branches on `detail`'s prose.
- **Mutating requests carry an `Idempotency-Key`** (HA6), generated by the
  client, and **the same key is reused on retry**. A fresh key on the retry
  defeats the entire mechanism and duplicates the charge.
- **Retries are bounded, jittered, and only for requests that are safe**
  (HA7): idempotent by method, or carrying the key above. `Retry-After`,
  when present, wins over the client's own backoff.
- **Collections are paged by the returned `next_cursor` until it is null**
  (HA4), never by constructing an offset.
- **The client sends the session cookie and attaches no `Authorization`
  header**. Under WC1 it has nothing to put in one. That means requests go
  to an origin the cookie is scoped to, so the client never needs
  cross-origin credential handling.

A repository can generate this module, hand-write it, or wrap a generated
core. What it is not permitted to do is spread these six obligations across a
component tree.

A file download is a request to the service's own API by object id
([`026-blob-storage.md`](026-blob-storage.md) BS5), through this module like
every other request. The client never holds a URL to a store.

### WC4. Presentation is the client's job, and it is done with `Intl`

The [identifiers standard](020-identifiers.md) rules that the server speaks
base representations, and that presentation is the UI's job. The base
representations are RFC 3339 UTC instants, integer minor units with an ISO
4217 code, and opaque public ids. This rule is the other half of that
sentence. Without it the first half is an instruction with no addressee.

**The viewer's locale and time zone come from the viewer**. An explicit user
preference wins where the product has one. Otherwise the browser's own
resolution (`Intl.DateTimeFormat().resolvedOptions()`) is authoritative.
Neither is ever inferred server-side from an IP address. That is a guess about
geography answering a question about preference. It is wrong for every
traveller, every VPN user, and everyone whose language does not match their
country.

**Formatting uses the platform's `Intl` API**, not a bundled formatting
library carrying its own copy of the locale data. The browser's data is
maintained, complete, and already downloaded.

Two specifics, because both are got wrong in the same way: by assuming the
developer's own locale is the general case.

- **Money is not divided by 100**. The server sends minor units and a
  currency code (IP5). The exponent belongs to the currency, and JPY has
  zero of them while several currencies have three. `Intl.NumberFormat`
  with `style: "currency"` knows this. Hardcoding two decimal places is a
  bug that will not surface until the product is sold abroad.
- **An instant is not a date**. The server sends UTC. The calendar day a
  given instant falls on depends on the viewer's zone. So a timestamp
  rendered as a bare date without converting first is off by one for a
  predictable fraction of users every day.

**The server never sends a pre-formatted string**, and a client never asks for
one. That would push one viewer's locale into a shared response, and turn
every other consumer's correct rendering into a parsing job.

### WC5. The browser does not originate the server's trace, and reports errors with the request id

A browser is not a service. The observability standard's propagation rule
([`040-observability.md`](040-observability.md) OC1) already answers this case
without naming it. An inbound request without a valid `traceparent` starts a
new trace at the receiving service's edge. That is the correct default here.
The trace begins at the edge, not in the page.

**The client's correlation handle is the request id the server returns**. It
is already required in every error envelope (HA3 `request_id`), which is the
moment correlation is actually needed. It costs the client nothing to capture.
A support report quoting a request id turns a screenshot into a log query.

A **client error report** takes the shape
[`contracts/web-client/error-report.schema.json`](../contracts/web-client/error-report.schema.json)
defines. What it must and must not carry follows the same reasoning the
service standard applies to log lines:

- **It states a specific reason**: which operation, against which endpoint,
  with which request id. A report saying only that an error occurred is the
  [`030-service.md`](030-service.md) SC2 failure on a new surface. It is a
  class of problem with no occurrence in it.
- **It carries the application version and commit** from WC2. A stack trace
  against unknown source is unreadable, and browsers hold stale bundles
  longer than servers hold stale builds.
- **It never carries the session cookie, an access token, or personal
  data**. An error reporter is a pipe to a third party, and a report is
  written from the one context that holds everything the user typed.

Whether a client emits telemetry beyond error reports is a repository's
choice, stated in its **Conventions**. Where one runs full browser RUM and
wants a single trace across the page and the backend, it is permitted to send
`traceparent`. The server then continues it **as telemetry only**. Nothing
derived from a browser-supplied trace is ever a trusted input. The reason is
the one the observability standard gives about `tenant_id`: it arrives from a
caller who can put anything in it.

## The artifacts

Per PC3, under [`contracts/web-client/`](../contracts/web-client/):

- **`runtime-config.schema.json`**: the document WC2 requires the origin to
  serve at `/config.json` and the client to fetch, at schema version 3. It
  carries the surface class and the environment. It carries the API origin
  and session paths a product or internal surface needs and a front door
  must not carry.
- **`error-report.schema.json`**: the client error report of WC5. It
  uses `$ref` to the identifiers contract for its timestamp, and to the
  observability contract for the request id. So one spelling covers the
  browser and the server.
- **`corpus.json`**: validity cases for both shapes, plus behavioural cases
  a live client and its server must satisfy.

## Decisions

- **Schema version 3: every field named for what it is, one contract for
  three surfaces, and the path pinned** (2026-09-08). The second version
  worked for a product behind a proxy and for nothing else. A front door has
  no API and no session. So a required `api_base_url` and `auth` object made
  the contract unusable for the one surface that most needs an
  environment-specific document. The names themselves under-described their
  values: `url` for what was always an origin, `auth` around two paths that
  say what they are on their own.

  Version 3 renames (`api_origin`, `login_path`, `logout_path`,
  `global_flags`). It adds `surface_class` so the conditional requirement
  can follow the [web estate standard](091-web-estate.md)'s classes. It adds
  `surface_settings` for the scalars a front door's pages need, under keys
  the repository declares. It pins `/config.json` with `no-store`, so a
  static host's deploy step and a serving process satisfy the same rule.
  Renames are breaking under PC6. The deprecation window is nil because no
  implementation consumed version 2.
- **WC1 carries the browser's half only; the architecture is the
  authentication standard's** (2026-09-01). The first draft of this rule
  chose the Backend-For-Frontend pattern, pinned the session cookie's
  attributes, and required refresh-token rotation. Every one of those is a
  decision the [authentication and authorization standard](060-auth.md)
  states as its own. Each is equally true of a server-rendered application
  with no JavaScript, which is the test that shows they are not browser
  rules.

  Deciding them here would have been this repository's own two-answers
  failure, committed in the standard written to close a gap. What is left is
  the part that survives that test. Web storage holds nothing, no provider
  credential is in the bundle, and a `401` is answered by navigating, not by
  exchanging.
- **One document, five rules, five roster rows** (2026-08-31). The
  capabilities are entangled through what the page can hold, so five
  standards would each be mostly a link to the others. The roster still
  gains a row per capability, so the table keeps its property that absence
  means declined.
- **Build provenance is compiled in, not served** (2026-09-01). The first
  version of this rule put the frontend's version and commit inside the
  served document and required them. That is wrong wherever the bundle and
  the API come from different origins, and the split-origin topology is
  admitted. The serving backend there has no idea which frontend build a
  given browser is running.

  Three things were being conflated: build provenance (compiled in), the
  bootstrap (from the bundle's origin), and application config (from the
  backend). Removing a required field is breaking under PC6, so the contract
  moves to schemaVersion 2. The deprecation window is stated as nil, because
  no implementation consumed version 1.
- **Client config is factor III honoured, not departed from** (2026-08-31).
  This is stated deliberately, because the charter requires a departure to
  be declared and this one would have been declared wrongly. The browser
  reads a configuration that lives in an environment; it is simply the
  server's environment. What breaks the factor is the build-time bake, which
  also breaks build-once.
- **The browser does not start the server's trace** (2026-08-31). A unified
  browser-to-backend trace is genuinely useful, and it is admitted for
  repositories running real RUM. It is not the default, for two reasons. The
  default must work for a client that ships no telemetry SDK at all. And
  OC1's existing edge-starts-the-trace rule already covers the case
  correctly. Correlation by request id needs nothing installed.
- **`Intl` over a formatting library** (2026-08-31). The usual argument for
  a library is consistency across environments, which mattered when browser
  locale data was patchy. It is not patchy now, and a bundled copy of CLDR
  is a large download that ages.
