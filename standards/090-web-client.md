# The web client: what a browser holds, fetches, sends and reports

## Why this exists

Every other standard here governs a server process, and a browser client
cannot claim compliance with rules written about a process. Five browser-side
decisions are entangled. What the page can hold decides how the API client
presents itself, and that decides what the runtime configuration document
carries. What the page holds is a security decision. The naive translation of
factor III bakes the API URL into the bundle, which breaks build-once and
nothing fails when it does. This is one document for one client's
obligations, as [`030-service.md`](030-service.md) is for one process's.

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

**Everything else about authentication belongs to
[`060-auth.md`](060-auth.md)**: which component is the identity provider's
client, the cookie's attributes, refresh and revocation. A backend-for-frontend
owning the session and rotating refresh tokens is not chosen here, because
each of those holds for a server-rendered application with no JavaScript. Only what is true *because* the client is a browser belongs in
this document.

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

Every field is named for what it is, with no wrapper object and no free-form
bag. `surface_settings` is the one open map, open only to keys the repository
declares, because a map with undeclared keys is where a secret arrives
unnoticed.

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

**This is not a departure from [factor III](https://12factor.net/config)**.
Factor III requires configuration to live in the environment rather than in
the code, and here it does. It lives in the serving process's environment,
where every other standard keeps it. What changes is only that the browser
reads it one hop away, over HTTP, because a browser has no environment of its
own to read. The naive translation, *put it in the bundle at build time*, is
the violation. Config becomes code, and one artifact per environment breaks
the build-once separation of [factor V](https://12factor.net/build-release-run).

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
base representations and that presentation is the UI's job; this rule is the
UI's half.

**The viewer's locale and time zone come from the viewer**. An explicit user
preference wins where the product has one. Otherwise the browser's own
resolution (`Intl.DateTimeFormat().resolvedOptions()`) is authoritative.
Neither is ever inferred server-side from an IP address. That is a guess about
geography answering a question about preference. It is wrong for every
traveller, every VPN user, and everyone whose language does not match their
country.

**Formatting uses the platform's `Intl` API**, not a bundled formatting
library carrying its own copy of the locale data. The browser's data is
maintained, complete, and already downloaded. A bundled copy of CLDR is a
large download that ages, for a consistency the platform's data already gives.

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

- **`runtime-config.schema.json`**: WC2's bootstrap document at schema
  version 3, with the surface class, the environment, and the fields only a
  product or internal surface carries.
- **`error-report.schema.json`**: WC5's client error report, with `$ref`s to
  the identifiers contract for its timestamp and the observability contract
  for the request id.
- **`corpus.json`**: validity cases for both shapes, plus behavioural cases
  a live client and its server must satisfy.
