# Security baseline: pinned images, scanned dependencies, the response header set, and disclosure

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/security-baseline/`](../contracts/security-baseline/). The words
*image*, *release*, *deployment*, *credential* and *backing service* are used
in the senses [`000-platform.md`](000-platform.md#terms) defines. The pinning
and vulnerability-acceptance disciplines and the image jobs this document
extends are [`010-ci.md`](010-ci.md)'s; the error envelope and the
backpressure response are [`050-http.md`](050-http.md)'s; the cookie posture
is [`060-auth.md`](060-auth.md) AU7's; what a browser may hold is
[`090-web-client.md`](090-web-client.md) WC1's.

This document governs **the security posture every deployed service has
before its domain is considered**: what an image is built from, what is
scanned and how an exception is recorded, which headers every response
carries, where TLS is required, how abuse of an open route is refused, how
input is bounded, how a finder reports a vulnerability, and what a release
says about its contents. **What it does not define is the secret**: delivery,
what never enters a repository, and leak response are
[`032-secrets.md`](032-secrets.md)'s, and this document points there wherever
a secret appears.

## Why this exists

Every service ships with a security posture whether or not anyone chose one:
the base image is whatever tag the first Dockerfile named, the headers are
whatever the framework's middleware emits, scanning runs where somebody wired
it, and the disclosure channel is whichever inbox a finder guesses. None of
these is a domain decision — an invoicing system is not better at invoicing
for a stricter `Content-Security-Policy` — so each is decided by default, per
repository, differently, and the differences are invisible until one of them
is the incident.

The cheapest answers fail as general properties. **A tag is a mutable
pointer**: `FROM node:22` names whatever the registry says it names at build
time, so an upstream rebuild or a registry compromise changes the bytes under
a name nobody changed. **A scan that can be skipped is skipped exactly when
it hurts**, because the day it finds something is the day it is inconvenient,
and an exemption with no expiry is a permanent decision made in a hurry.
**Framework defaults differ**, so four languages ship four header postures
and a reviewer cannot tell a deliberate omission from an unconsidered one.
**An unstated disclosure channel is a public one**: a finder who cannot find
an address posts the finding where they can.

The remedy is the shape the rest of these standards take: each property
stated once as a contract at a boundary a checker can watch — a line in a
Dockerfile, a response header, a file at a fixed path, an artifact attached
to a release — with the value pinned and the reason beside it. What remains
for a repository is the domain, and every rule holds equally after handover,
because each is a property of the code rather than of a job it calls.

### The standards evaluated first, per PC2

Most of this document is a profile over things already specified.

**Image references are the OCI distribution specification's.** A digest
reference (`<name>@sha256:<64 hex>`) is content-addressed and immutable by
the specification; a tag is not. SB1 adds only that the human-readable
version travel beside it, as [`010-ci.md`](010-ci.md) requires of action pins.

**Vulnerability identifiers and the scanner's own exemption file are adopted,
not replaced.** Advisories are named by their [OSV](https://osv.dev/)
identifiers, and an exemption lives in the scanner's native configuration
beside the lockfile, as 010 already requires. SB2 adds the shape an entry must
have, an expiry above all, because the native files admit entries without one.

**The header values are the current browser-security consensus**, checked
against the [OWASP Secure Headers Project](https://owasp.org/www-project-secure-headers/)
and the MDN reference for each header; the strict `Content-Security-Policy`
is the nonce-plus-`'strict-dynamic'` form CSP Level 3 was designed around.
SB3 adds the split into response classes and the exact values. **TLS
configuration is Mozilla's intermediate profile**, from the
[Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/), which
maintains a protocol and cipher list against real client populations; SB4
pins the profile rather than a list that would be stale within a year.

**Backpressure is RFC 9110's `Retry-After`**, already profiled by 050 HA7; the
IETF `RateLimit` header fields draft is admitted and not required, because it
is a draft and `Retry-After` alone tells a client what to do. **Disclosure is
RFC 9116**: `security.txt` is the machine-readable form, and `SECURITY.md` is
the human document its `Policy` field points at.

**The SBOM is CycloneDX**, an ECMA standard (ECMA-424) with a JSON form,
generators for every ecosystem in the portfolio, and a VEX profile that
carries an SB2 acceptance downstream. SPDX is an ISO standard too; its centre
of gravity is licence provenance and its security profile is less tooled.

**What no standard covers**, and this document invents: the response-class
split asserted by the start check (SB3), and the acceptance entry's expiry
and maximum window (SB2).

## The rules

### SB1. Base images are pinned by digest, and the checker reads `FROM`

**Every `FROM` line names its image by digest and states its version beside
it.** The canonical form is the in-band one:

```dockerfile
FROM node:22.6.0-bookworm-slim@sha256:3f8d…64 hex…9a2b
```

The runtime resolves the digest and ignores the tag, so the tag is a version
comment the build tool happens to parse and the digest is the pin. The
alternative, a bare digest with a trailing comment — `FROM node@sha256:… #
22.6.0` — is admitted; the in-band form is canonical because an update tool
maintains both halves as one edit, where a comment is a second place that
drifts. A digest with neither is a finding: a correct pin nobody can read,
whose next update is a diff nobody can review.

The reasoning is [`010-ci.md`](010-ci.md)'s action-pinning reasoning applied
to the artifact that actually runs. A tag's bytes change when upstream
rebuilds, a registry is compromised, or a maintainer re-tags, and nothing in
the repository changes when they do; an unpinned base image is a release
whose contents a third party decides at build time — BUILD ONCE broken one
layer down.

What the grammar exempts, so the checker has no false positives: `FROM
scratch`, the empty image with no digest; `FROM <stage>` where `<stage>` was
declared by an earlier `AS <stage>` in the same file; and the `--platform=`
flag. What it refuses: `FROM ${BASE}` and any reference the checker cannot
read without evaluating the build. The rule binds every `FROM` line in every
Dockerfile, build stages included — a build stage decides what the runtime
stage copies — and every image the build run produces, the migrate and worker
images under [`035-workers.md`](035-workers.md) WK2 as much as the server.
Pins move by an update tool configured for the container ecosystem, the class
of tool 010 requires for actions, so an upstream patch is a reviewable pull
request that bumps digest and tag together.

### SB2. Every repository scans its dependencies and its images, and an acceptance expires

**Three scans, each a shared job, each failing when it cannot run.**

| Scan | Reads | Catches | Job |
|---|---|---|---|
| Lockfile | every lockfile in every ecosystem the repository has | known advisories in declared dependencies, transitive included | `job-osv-scan` ([`010-ci.md`](010-ci.md)) |
| Reachability | Go call graphs | advisories in code the binary actually reaches | `job-go-govulncheck`, Go only |
| Image | the OCI manifest `job-image-build` pushed by digest | OS packages and bundled runtimes in the base image, which no lockfile lists | `job-image-scan` (proposed), between build and start |

The image scan exists because the lockfile scan cannot see the base image: a
fully patched application on an unpatched `libssl` is a vulnerable service,
and only a scanner that reads layers knows. It runs on the digest the build
pushed — the manifest `job-image-starts` starts and `job-image-publish`
promotes — so the thing scanned is the thing that ships. **A scan that cannot
run is a failure, not a skip**: a missing lockfile, a crashed scanner, a
refused pull are each the scan not happening, and no configuration may let
*could not look* read as *nothing to find*.

**Accepting a finding is a declaration with an expiry.** 010 admits two
instruments — an id list, or a rollout stage a repository can defend — and
this rule binds the id list's entries, validated against
[`acceptance.schema.json`](../contracts/security-baseline/acceptance.schema.json):

| Field | Required | What it decides |
|---|---|---|
| `id` | yes | The OSV identifier of the advisory, never a package name or a pattern. |
| `reason` | yes | Why this advisory does not apply, or is tolerated, here: the defect is unreachable, the function is not called, no fix is released. |
| `expires` | yes | A calendar date after which the entry is a finding again. **No acceptance is permanent.** |
| `accepted_on` | recommended | When the decision was made; with it, the checker bounds the window. |
| `retire_when` | recommended | The condition that removes the entry early: an upstream release, a dependency dropped. |

**The window is at most ninety days.** A longer one is a decision to stop
looking, and that decision is made by moving the repository into a stage 010
describes rather than by a date far enough away to forget. An entry past its
`expires` is a finding whether or not the advisory still reports. The entry
lives in the scanner's native file — 010's `osv-scanner.toml`, the image
scanner's equivalent — and a checker validates each file's entries against
the schema: the native field names are the rendered form, the schema is the
contract. **New findings block from day one; existing findings have a stage
with a deadline**, 010's `fail_on_new`/`fail_on_existing` split on every scan.

### SB3. Every response carries the header set for its class, and the start check asserts it

**There are three response classes, and each has a fixed header set.** A
**document** is anything a browser renders as a page: the web client's shell,
a server-rendered view, an error page. An **API** response is a
representation a program consumes: JSON, problem+json, an event stream. An
**asset** is a static file the document loads: a hashed bundle chunk, a font.
The set is data in
[`response-headers.json`](../contracts/security-baseline/response-headers.json).

| Header | Document | API | Asset | Why |
|---|---|---|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | same | same | A browser that has seen it never sends the first request in clear again. `includeSubDomains` is required because a cookie set on the apex is sent to every subdomain, and one unprotected subdomain is a cookie in clear. `preload` is added when the registrable domain's owner submits it — a decision per domain, effectively irreversible, and a client's to make for a client's domain — and is never sent on a domain that has not been submitted. A year is the preload list's floor and the rule's. |
| `Content-Security-Policy` | `default-src 'self'; script-src 'self' 'nonce-<nonce>' 'strict-dynamic'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'` | `default-src 'none'; frame-ancestors 'none'; sandbox` | — | The document policy is the strict CSP: scripts run only when carrying this response's nonce, and scripts they load are trusted transitively through `'strict-dynamic'`, so an injected `<script>` runs nowhere. `'unsafe-inline'` and `'unsafe-eval'` never appear in `script-src`; nor does a host or scheme allow-list, because every allow-list of a CDN has been bypassed through something that CDN hosts. The API policy exists because a browser navigated to a JSON URL renders it: nothing may load, nothing may frame it, and `sandbox` makes it inert. Extending `connect-src` to the API origin under 060 AU7's topology B, `img-src` to `data:`, and `style-src` to a nonce are ordinary; `'unsafe-inline'` in `style-src` is admitted with a **Conventions** entry naming the framework that needs it. `frame-ancestors` is widened only by naming the origins allowed to frame. |
| `X-Content-Type-Options` | `nosniff` | `nosniff` | `nosniff` | Content sniffing turns a user upload served as text into a script. |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | `no-referrer` | — | A document's URL may carry an id; a cross-origin navigation gets the origin only. An API URL is never a referrer anyone needs. |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), payment=(), usb=()` at minimum | — | — | Features the product does not use are denied to every frame, the product's own included, so a compromised dependency cannot open them. A product that uses one names it `(self)` with a **Conventions** entry. |
| `Cross-Origin-Opener-Policy` | `same-origin` | — | — | Severs the window reference a cross-origin opener would otherwise hold, a class of side channel closed by one header. |
| `Cross-Origin-Resource-Policy` | `same-origin` | `same-origin`, or `same-site` under topology B | `same-origin` or `same-site` | A response may be embedded only by the origin, or site, that owns it. |
| `Cache-Control` | `no-store` | `no-store` unless the OpenAPI document declares the endpoint public and cacheable | `public, max-age=31536000, immutable` | A nonced document is uncacheable by construction: a cached copy carries a nonce the next response's policy does not accept. An authenticated API response is one person's data and never enters a shared cache. An asset is cacheable forever only because its name is its content hash; an asset without a hashed name gets `no-cache`. 030 SC1 already requires `no-store` on the health endpoints. |

**What is not sent.** `X-Frame-Options` is superseded by `frame-ancestors`
and never substitutes for it; `DENY` beside `frame-ancestors 'none'` is
harmless duplication, but a response carrying `X-Frame-Options` and no
`frame-ancestors` has relied on the header browsers consult second.
`X-XSS-Protection` is never sent: every browser has removed the auditor, and
`1; mode=block` introduced leaks of its own. `X-Powered-By` is never sent.
`Server`, where the edge insists on one, carries a product token and never a
version. `Cross-Origin-Embedder-Policy` is not required — it breaks every
cross-origin embed — and a product that needs it says so.

**The nonce is per response**: at least 128 bits from a cryptographic source,
base64, never reused, on every `<script>` the document carries. The web
client's shell is rendered per response for this reason; the bundle's files
are static and load through the nonced shell under `'strict-dynamic'`. A
`Content-Security-Policy-Report-Only` header does not satisfy this rule.

**The start check asserts the set.** `job-image-starts` already requests
`/readyz` from the running image; the same request asserts the API-class set,
and a service that serves documents gets one request to `/` asserting the
document-class set. A header set by the edge is one the start check cannot
see, so a repository that delegates any header to the edge says which in its
**Conventions** and the assertion moves to a live check against the deployed
environment. The cookie attributes and CORS headers of 060 AU7 are asserted
under that rule.

### SB4. TLS on every hop that leaves a private network, and the platform holds the certificate

**Every connection that crosses a network boundary the service does not own
is TLS.** Between the client and the edge, always. Between the edge and the
server, always, unless the two share a network segment no other tenant of the
infrastructure can reach, and a repository claiming that records where in its
**Conventions**. Between a process and a backing service, always: each is
reached over a network, and [`025-structured-data.md`](025-structured-data.md)
SD9 already requires it of the database.

**TLS 1.2 is the floor and TLS 1.3 is preferred**, with the protocol and
cipher list of Mozilla's intermediate profile at the version current when the
service is configured; 1.0 and 1.1 are offered nowhere. Intermediate rather
than modern because a public edge's clients include devices the modern
profile refuses, and refusing a user over a cipher suite is a decision a
product makes in its **Conventions**, not by default.

**Certificates come from the platform and are never in the image.** The edge
terminates with a certificate the platform issues and renews — an ACME client,
a cloud certificate manager, a mesh's identity — and a server that terminates
TLS itself receives its certificate and key as a secret file at process start
under [`032-secrets.md`](032-secrets.md). An image carrying a private key has
a credential in a build artifact, which 010 and the secrets standard forbid,
and it expires on a schedule the image cannot follow. A mutual-TLS client
certificate is a credential in the Terms' sense and travels the same way.

### SB5. Unauthenticated and authentication routes are rate limited, and the refusal is HA7's

**Every route reachable without a session, and every route that
authenticates, is rate limited**, at the edge where the edge can do it and in
the server otherwise. An authenticated route is bounded by the account behind
it and by [`070-rbac.md`](070-rbac.md)'s check; an unauthenticated route is
bounded by nothing until this rule.

| Route class | Keyed by | Default |
|---|---|---|
| Unauthenticated, any | client address | 60 requests per minute |
| Authentication: login, credential reset, token and code endpoints | client address, and separately the account identifier presented | 10 per minute per address; 5 per minute per identifier |
| Health and readiness (030 SC1) | exempt from the per-address limit for the platform's probes | — |

The defaults are a floor a product tightens in its **Conventions** and never
loosens without a reason stated there. The per-identifier limit is what turns
a credential-stuffing run into a slow one; the per-address limit alone does
not, because the addresses are many. Authentication under
[`060-auth.md`](060-auth.md) AU1 sits in a tier in front of the application,
and the rule binds whichever process serves the route. **The refusal is 050
HA7's**: `429` with `Retry-After`, always both, and a body that is the RFC
9457 envelope of 050 HA3; a bare status or an HTML page has left the error
contract on the one route a client most needs to handle mechanically.

### SB6. Input is validated by schema at the boundary and bounded in size

**A request body is validated against the OpenAPI document before a handler
runs**, and a body that fails is refused with the RFC 9457 envelope carrying
the `errors` array of 050 HA3, one entry per rejected field. 050 HA2 requires
the document; this rule requires that the running service enforce it, because
a description the service does not enforce describes what it hopes to
receive. Query and path parameters are validated the same way, an id-typed
path parameter against the format [`020-identifiers.md`](020-identifiers.md)
IP2 admits, before anything looks it up.

**Unknown request fields are refused.** The client is generated from the same
document (090 WC3), so a field the server does not know is a typo or an
attack, and a request silently accepted with a misspelled field did something
other than what was asked. Additive evolution under PC6 governs what a server
*emits* and a client tolerates; it does not license a server to ignore what
it was sent. A request whose `Content-Type` is not one the endpoint declares
is refused with `415`.

**Size is bounded at the edge and in the server.** A JSON body is limited to
1 MiB by default and an endpoint raises it in the OpenAPI document with a
reason; anything larger is a blob under
[`026-blob-storage.md`](026-blob-storage.md)'s upload contract. JSON nesting
is bounded (32 levels), the query string is bounded (8 KiB), and a request
over any bound is refused with `413` or `414` in the same envelope before the
body is parsed — the parse is the attack surface the bounds protect.

### SB7. `SECURITY.md` and `security.txt` state the channel, the commitment and the scope

**Every repository carries `SECURITY.md` at its root**, and every served
origin answers `/.well-known/security.txt` per RFC 9116. The markdown is what
a person reads; the text file is what a finder's tool reads, and its `Policy`
field points at the published policy. What `SECURITY.md` must state, validated
in structured form against
[`security-md.schema.json`](../contracts/security-baseline/security-md.schema.json):

| Section | States |
|---|---|
| **Reporting** | The channel: an address, a form, or a platform's private advisory mechanism. At least one, and it is monitored. What a report should contain. Where an encryption key is, if one is offered. |
| **Response** | Two numbers: the acknowledgement time (three business days is the ceiling) and the triage time by which the finder is told whether the report is accepted and its severity (fourteen days is the ceiling). A commitment without a number is not a commitment. |
| **Scope** | Which systems and repositories the policy covers, and what is out: third-party services, denial of service, social engineering. |
| **Safe harbour** | That good-faith research within scope will not be pursued, in plain words. A finder who fears the report will not send it. |
| **Disclosure** | Whether and when the finder may publish, and that the report is credited if they wish. |

`security.txt` carries `Contact`, `Expires` (no more than a year out and
renewed before it passes, because an expired file tells a finder the policy
may be abandoned), `Policy` and `Preferred-Languages`; `Canonical` where the
origin is not the policy's home. **A handed-over repository keeps the file
with the channel changed to the client's**: a `SECURITY.md` naming a channel
the new owner does not read is worse than none, for the reason
[`../AGENTS.md`](../AGENTS.md) gives for a dead link to this repository.

### SB8. Every release carries a CycloneDX SBOM per image

**The build run generates a CycloneDX 1.6 JSON SBOM for every image it
produces, and the release attaches them.** From the built image, not the
source tree, because a source SBOM omits the base image's packages, which are
exactly what SB2's image scan finds. In the build run because that is the run
whose artifacts the release publishes ([`010-ci.md`](010-ci.md): a release
publishes what main already gated and builds nothing), so the SBOM has the
provenance of the bytes it describes. It is attached as a release asset under
a fixed name per image (`<image>.cdx.json`) and, where the registry supports
OCI referrers, pushed as a referrer of the image digest. An SB2 acceptance
travels downstream as a CycloneDX VEX statement on the same advisory id. An
SBOM answers *which of our releases contains this* in minutes, from a file.

### SB9. Least privilege is already stated, and the process in the image runs unprivileged

Least privilege is the property several standards already hold, and this rule
points at each so a reader has one list: one credential per backing service,
the migration credential separate (000 Terms, [`032-secrets.md`](032-secrets.md));
an image carries only what its jobs declare ([`035-workers.md`](035-workers.md)
WK8); the runtime database role can neither alter the schema nor reach
another service's database ([`025-structured-data.md`](025-structured-data.md)
SD3, SD9, SD13); the audit table's writer cannot update it
([`080-audit.md`](080-audit.md) AE6); a client holds no credential to any
service's state (000 Terms).

**The one property none of them states: the process in the image does not run
as root.** Every Dockerfile that produces a runnable image sets `USER` to an
unprivileged user before its entrypoint, and the filesystem is writable only
where the process declares it needs to write. A container escape from an
unprivileged process is a bounded event; from root it is the host. The
checker that reads `FROM` reads `USER` in the same pass; it is stated here
because it belongs to no other standard's boundary.

### SB10. Security events are audited and notified under the standards that own them

What must be recorded when a security-relevant act happens is
[`080-audit.md`](080-audit.md) AE5's floor, and what must be told to the
person it happened to is the [notifications standard](058-notifications.md)'s
security floor. A leaked secret's response, the audit event it emits included,
is [`032-secrets.md`](032-secrets.md)'s. This rule adds nothing to them; it
exists so that a reader asking *where is the security logging rule* is sent
to the right document, and a change to a floor is made in the one that owns it.

## The artifacts

Per PC3, under [`contracts/security-baseline/`](../contracts/security-baseline/):

- **`base-image.schema.json`** — SB1's grammar as `$defs`: a digest, a pinned
  reference, and a pinned `FROM` line in both admitted forms.
- **`acceptance.schema.json`** — SB2's acceptance entry and the file holding
  a list of them: the OSV id grammar, the required reason and expiry, the
  recommended `accepted_on` and `retire_when`.
- **`response-headers.json`** — SB3's set as data: per class, each required
  header with its value or directive requirements, the forbidden headers, and
  the superseded one.
- **`security-md.schema.json`** — SB7's required content in structured form,
  extracted from the markdown by section, plus the `security.txt` fields.
- **`corpus.json`** — four parts. `headers`: header sets per class, each
  rejection naming its findings, with two detectors: `X-Frame-Options`
  without `frame-ancestors`, and HSTS without `includeSubDomains`.
  `from-lines`: Dockerfiles as line arrays with the findings SB1's checker
  must report, with a detector whose second stage is the unpinned one.
  `scan-acceptance`: entries the schema must accept and reject, and entries
  judged against a date. `security-md`: policies the schema must accept and
  reject.

## Enforcement

Every SB rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. The
mechanically checkable parts, and therefore the first to move to a gate: the
`FROM` and `USER` lines of every Dockerfile (SB1, SB9), an extension of the
checker that already reads `uses:` lines, with no false positives once the
grammar's exemptions are honoured; the acceptance entries in every scanner's
native file (SB2); the header set on the `/readyz` and `/` responses of the
started image (SB3), one more assertion in a job every repository calls; the
sections of `SECURITY.md` and an SBOM asset on every release (SB7, SB8). What
stays a review question, said so in the ledger row: whether an acceptance's
reason is true (SB2), whether an edge-delegated header is set (SB3), whether a
hop declared private is private (SB4), whether the limits were chosen (SB5),
and whether the enforced schemas are the published ones (SB6).

## Decisions

- **The in-band tag is the canonical pin form, and every `FROM` line is
  bound** (2026-09-02). `image:tag@digest` and `image@digest # tag` pin the
  same bytes; the in-band form is one token an update tool maintains as one
  edit, and the comment form is admitted so a Dockerfile written the way
  action pins are written is not a finding. Build stages are included because
  a checker reading only the last `FROM` would pass exactly the multi-stage
  file most likely to be wrong.
- **Acceptances expire, and the window is ninety days** (2026-09-02). An
  entry with no expiry is a permanent decision made under time pressure; an
  unbounded list re-reviewed on a schedule was rejected because nothing fails
  when the review is skipped, and a date fails on its own.
- **Three response classes, asserted by the start check** (2026-09-02). A
  document needs a script policy and a JSON response needs to be inert; one
  set would burden the API with a nonce it cannot use or leave the document
  with a policy that allows nothing, and an uncacheable policy on an immutable
  asset defeats the reason the file has a hash in its name. The start check
  asserts them because it already talks to the running image, and a new job
  would be a second place that knows how to start it.
- **No CSP fallbacks for pre-`'strict-dynamic'` browsers** (2026-09-02). The
  compatibility form carries `'unsafe-inline'` and a scheme source that
  modern browsers ignore and old ones honour, so the fallback would be a
  permission granted only to the clients least able to defend themselves.
- **CycloneDX, from the image, in the build run** (2026-09-02). Both SBOM
  standards are international standards; CycloneDX was designed around the
  vulnerability and VEX use case SB2 and SB8 need, and its JSON form is
  generated natively by the toolchains in use. From the image because a
  source SBOM omits the base image; in the build run because an SBOM made at
  release time describes bytes the release did not build.

## Out of scope, deliberately

- **Secrets.** [`032-secrets.md`](032-secrets.md), in full: delivery, naming,
  rotation, leak response, what never enters a repository.
- **Authentication, the session cookie, authorization, and what a browser
  may hold.** [`060-auth.md`](060-auth.md) AU5 and AU7;
  [`070-rbac.md`](070-rbac.md); [`090-web-client.md`](090-web-client.md) WC1
  and WC2. A rate limit is not a permission check, a header is not a scope,
  and SB3's nonce is where this document and the web client's touch.
- **The audit and notification floors.** [`080-audit.md`](080-audit.md) AE5
  and the [notifications standard](058-notifications.md); SB10 only points.
- **Upload limits and content validation for stored objects.**
  [`026-blob-storage.md`](026-blob-storage.md); SB6 stops at the API body.
- **Penetration testing and vendor assessment.** Per-engagement commitments.
