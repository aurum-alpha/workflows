# The web client: browser authentication, configuration and the API boundary

One of the Aurum Alpha engineering standards, written under the platform
contract ([`platform.md`](platform.md)) — a per-capability standard from its
roster. Read [`enforcement.md`](enforcement.md) for the tier each rule below
actually holds. Artifacts: [`contracts/web-client/`](../contracts/web-client/).

This document governs code that runs in a browser: how it authenticates
(WC1), where its configuration comes from (WC2), how it talks to an Aurum
Alpha service (WC3), what it does with the values that service sends (WC4),
and what it reports when something breaks (WC5).

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
first: where an access token lives, how a bundle learns which API to call,
who parses the error envelope, whose time zone a timestamp renders in, and
what a client-side crash report contains.

Two of those are not merely unowned but actively hazardous to get wrong.
**Token storage is a security decision**, and the industry answer changed —
the guidance that produced a generation of SPAs holding tokens in
`localStorage` has been superseded. **Client configuration collides with
[factor III](https://12factor.net/config)** in a way no server does, because
a browser bundle is built once and served to many, so there is no process
environment to read at start. A product that discovers that on its own
usually resolves it by baking the API URL into the bundle at build time,
which quietly breaks build-once — and nothing fails when it does.

One document rather than five, deliberately. These decisions are entangled:
the authentication pattern determines whether the API client sends a cookie
or a header, which determines what the runtime config document must carry,
which determines what a browser may be told at all. Split across five
standards each would be mostly cross-reference. This follows the shape of
the [service contract](service.md), which bundles health, logging, config,
shutdown and provenance for the same reason — they are one process's
obligations, and these are one client's.

## The rules

### WC1. The browser is not a confidential client, and the default is a Backend-For-Frontend

A browser cannot keep a secret. Everything the bundle contains is readable
by anyone who opens developer tools, and any script running in the page —
including one that arrived through a compromised dependency — runs with the
application's full authority.

**The fleet default is the Backend-For-Frontend (BFF) pattern**: a
server-side component is the OAuth client, holds the tokens, and proxies the
browser's API calls. The browser's credential is a session cookie, and no
access or refresh token ever reaches JavaScript.

This follows [RFC 10017 / BCP 212](https://www.rfc-editor.org/rfc/rfc10017.html),
*OAuth 2.0 for Browser-Based Applications*, which defines three patterns —
BFF, token-mediating backend, and browser-based OAuth client — and says of
the BFF that it is **"strongly recommended for business applications,
sensitive applications, and applications that handle personal data."** That
is a description of essentially everything this organisation builds, so
adopting it as the default is the profile PC2 asks for rather than a
preference.

The session cookie is `HttpOnly`, `Secure`, `SameSite=Lax`, and carries the
`__Host-` prefix. Each of those is load-bearing: `HttpOnly` is what puts the
credential out of reach of injected script, `__Host-` pins the cookie to
exactly one origin with no `Domain` attribute so a sibling subdomain cannot
set or read it, and **`Lax` rather than `Strict` because the OIDC provider
returns the user by a top-level navigation** — `Strict` withholds the cookie
on exactly that hop and produces a login loop that looks like a provider
fault.

The other two patterns are admitted where a repository states the reason in
its **Conventions**, and the reason has to survive the question *what does
this product do with personal data*. Where a browser-based client is used
anyway, two things are not optional, because the RFC states them as
requirements: **refresh tokens are rotated on each use or sender-constrained**,
and they carry a bounded maximum lifetime.

**Tokens are never written to `localStorage` or `sessionStorage`.** Both are
readable by any script in the origin, which means one cross-site scripting
flaw anywhere in the page — or in anything the page imports — is a token
exfiltration. This is the specific practice the current guidance exists to
end, and it is not made acceptable by a short expiry: a stolen token is used
immediately.

### WC2. Configuration is fetched at load, never baked into the bundle

**The build produces one artifact, and that artifact is
environment-agnostic.** No API URL, no tenant, no provider hostname, no
feature toggle is compiled in. The bundle that was tested in staging is the
bundle that reaches production, byte for byte.

At load, the client fetches a small **runtime configuration document** from
the server that served it, shaped by
[`contracts/web-client/runtime-config.schema.json`](../contracts/web-client/runtime-config.schema.json).
The server renders that document from *its own* environment.

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

Two things may be compiled in, because both describe the *build* rather than
the environment: the application version and the commit it was built from.
That is the browser's half of the runtime provenance rule
([`service.md`](service.md) SC5), and WC5 requires it in error reports.

**Nothing secret goes in the runtime config document.** It is served to
every anonymous visitor who loads the page, so it is public by construction.
A value that must not be public belongs behind the BFF, where the browser
can use its effect without ever seeing it.

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
- **Credentials mode matches WC1**: with a BFF, requests are same-origin
  and send the session cookie; the client attaches no `Authorization`
  header, because under WC1 it has nothing to put in one.

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
- **WC1's cookie attributes are observable from outside**: a login response's
  `Set-Cookie` either carries `HttpOnly; Secure; SameSite=Lax` and the
  `__Host-` prefix or it does not. That is a live gate, and the more valuable
  half of WC1.
- **WC1's central claim resists a checker entirely.** Proving no token
  reaches JavaScript means proving a negative about a program's runtime, and
  a gate that tried would be reading the implementation, which PC4 forbids.
  The review question is stated instead: *where does this application's
  access token live, and who can read it.*
- **WC3 and WC4 stay review questions.** A checker cannot tell a generated
  client from a hand-written one that happens to be correct, and per PC4 it
  should not try; a checker that failed a build for calling `fetch` directly
  would be enforcing an implementation choice rather than a boundary.

## Decisions

- **BFF as the default, not one option among three** (2026-08-31): the
  alternative was to describe all three RFC 10017 patterns neutrally and let
  each product choose. That is what "we use OIDC" unpinned looks like, and
  PC2 exists to stop it. The RFC's own recommendation language settles which
  one is the default for the kind of software this organisation writes.
- **One document, five rules, five roster rows** (2026-08-31): the
  capabilities are entangled through the authentication choice, so five
  standards would each be mostly a link to the others. The roster still
  gains a row per capability, so the table keeps its property that absence
  means declined.
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
