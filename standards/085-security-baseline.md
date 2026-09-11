# Security baseline: pinned images, scanned dependencies, the response header set, and disclosure

## Why this exists

Every service ships with a security posture whether or not anyone chose one.
The base image is whatever tag the first Dockerfile named, and the headers are
whatever the framework's middleware emits. None of these is a domain decision,
so each is decided by default, per repository, differently. The differences
are invisible until one of them is the incident. Each property here is stated
once as a contract at a boundary a checker can watch. That is a line in a
Dockerfile, a response header, a file at a fixed path, or an artifact attached
to a release.

## The rules

### SB1. Base images are pinned by digest, and the checker reads `FROM`

**Every `FROM` line names its image by digest and states its version beside
it**. The canonical form is the in-band one:

```dockerfile
FROM node:22.6.0-bookworm-slim@sha256:3f8d…64 hex…9a2b
```

The runtime resolves the digest and ignores the tag. So the tag is a version
comment the build tool happens to parse, and the digest is the pin. The
alternative is a bare digest with a trailing comment, `FROM node@sha256:… #
22.6.0`, and it is admitted. The in-band form is canonical because an update
tool maintains both halves as one edit, where a comment is a second place that
drifts. A digest with neither is a finding: a correct pin nobody can read,
whose next update is a diff nobody can review.

The reasoning is [`010-ci.md`](010-ci.md)'s action-pinning reasoning applied
to the artifact that actually runs. A tag's bytes change when upstream
rebuilds, a registry is compromised, or a maintainer re-tags. Nothing in the
repository changes when they do. An unpinned base image is a release whose
contents a third party decides at build time: BUILD ONCE broken one layer
down.

The grammar exempts three forms, so the checker has no false positives. They
are `FROM scratch`, the empty image with no digest; `FROM <stage>` where an
earlier `AS <stage>` in the same file declared it; and the `--platform=` flag.
What it refuses: `FROM ${BASE}` and any reference the checker cannot read
without evaluating the build.

The rule binds every `FROM` line in every Dockerfile, build stages included,
because a build stage decides what the runtime stage copies. It binds every
image the build run produces: the migrate and worker images under
[`035-workers.md`](035-workers.md) WK2 as much as the server. Pins move by an
update tool configured for the container ecosystem, the class of tool 010
requires for actions. So an upstream patch is a reviewable pull request that
bumps digest and tag together.

### SB2. Every repository scans its dependencies and its images, and an acceptance expires

**Three scans, each a shared job, each failing when it cannot run**.

| Scan | Reads | Catches | Job |
|---|---|---|---|
| Lockfile | every lockfile in every ecosystem the repository has | known advisories in declared dependencies, transitive included | `job-osv-scan` ([`010-ci.md`](010-ci.md)) |
| Reachability | Go call graphs | advisories in code the binary actually reaches | `job-go-govulncheck`, Go only |
| Image | the OCI manifest `job-image-build` pushed by digest | OS packages and bundled runtimes in the base image, which no lockfile lists | `job-image-scan` (proposed), between build and start |

The image scan exists because the lockfile scan cannot see the base image. A
fully patched application on an unpatched `libssl` is a vulnerable service,
and only a scanner that reads layers knows. It runs on the digest the build
pushed, the manifest `job-image-starts` starts and `job-image-publish`
promotes. So the thing scanned is the thing that ships.

**A scan that cannot run is a failure, not a skip**. A missing lockfile, a
crashed scanner and a refused pull are each the scan not happening. No
configuration is permitted to let *could not look* read as *nothing to find*.

**Accepting a finding is a declaration with an expiry**. Standard 010 admits
two instruments: an id list, or a rollout stage a repository can defend. This
rule binds the id list's entries, validated against
[`acceptance.schema.json`](../contracts/security-baseline/acceptance.schema.json):

| Field | Required | What it decides |
|---|---|---|
| `id` | yes | The OSV identifier of the advisory, never a package name or a pattern. |
| `reason` | yes | Why this advisory does not apply, or is tolerated, here: the defect is unreachable, the function is not called, no fix is released. |
| `expires` | yes | A calendar date after which the entry is a finding again. **No acceptance is permanent.** |
| `accepted_on` | recommended | When the decision was made; with it, the checker bounds the window. |
| `retire_when` | recommended | The condition that removes the entry early: an upstream release, a dependency dropped. |

**The window is at most ninety days**. A longer one is a decision to stop
looking. That decision is made in a stage 010 describes, not by a date far
enough away to forget. An unbounded list re-reviewed on a schedule is refused
because nothing fails when the review is skipped; a date fails on its own. An
entry past its
`expires` is a finding whether or not the advisory still reports. The entry
lives in the scanner's native file: 010's `osv-scanner.toml`, or the image
scanner's equivalent, and a checker validates each file's entries against the
schema.

**New findings block from day one; existing findings have a stage with a
deadline**, 010's `fail_on_new`/`fail_on_existing` split on every scan.

### SB3. Every response carries the header set for its class, and the start check asserts it

**There are three response classes, and each has a fixed header set**. A
**document** is anything a browser renders as a page: the web client's shell,
a server-rendered view, an error page. An **API** response is a representation
a program consumes: JSON, problem+json, an event stream. An **asset** is a
static file the document loads: a hashed bundle chunk, a font. The set is data
in
[`response-headers.json`](../contracts/security-baseline/response-headers.json).
The values are the browser-security consensus of the [OWASP Secure Headers
Project](https://owasp.org/www-project-secure-headers/) and the MDN reference
for each header.

| Header | Document | API | Asset | Why |
|---|---|---|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | same | same | A browser that has seen it never sends the first request in clear again. `includeSubDomains` is required because a cookie set on the apex is sent to every subdomain, and one unprotected subdomain is a cookie in clear. `preload` is added when the registrable domain's owner submits it. That is a decision per domain, effectively irreversible, and a client's to make for a client's domain. It is never sent on a domain that has not been submitted. A year is the preload list's floor and the rule's. |
| `Content-Security-Policy` | `default-src 'self'; script-src 'self' 'nonce-<nonce>' 'strict-dynamic'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'` | `default-src 'none'; frame-ancestors 'none'; sandbox` | — | The document policy is the strict CSP: scripts run only when carrying this response's nonce, and scripts they load are trusted transitively through `'strict-dynamic'`, so an injected `<script>` runs nowhere. `'unsafe-inline'` and `'unsafe-eval'` never appear in `script-src`. Nor does a host or scheme allow-list, because every allow-list of a CDN has been bypassed through something that CDN hosts. The API policy exists because a browser navigated to a JSON URL renders it: nothing is permitted to load, nothing is permitted to frame it, and `sandbox` makes it inert. Extending `connect-src` to the API origin under 060 AU7's topology B, `img-src` to `data:`, and `style-src` to a nonce are ordinary. `'unsafe-inline'` in `style-src` is admitted with a **Conventions** entry naming the framework that needs it. `frame-ancestors` is widened only by naming the origins allowed to frame. |
| `X-Content-Type-Options` | `nosniff` | `nosniff` | `nosniff` | Content sniffing turns a user upload served as text into a script. |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | `no-referrer` | — | A document's URL can carry an id; a cross-origin navigation gets the origin only. An API URL is never a referrer anyone needs. |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), payment=(), usb=()` at minimum | — | — | Features the product does not use are denied to every frame, the product's own included, so a compromised dependency cannot open them. A product that uses one names it `(self)` with a **Conventions** entry. |
| `Cross-Origin-Opener-Policy` | `same-origin` | — | — | Severs the window reference a cross-origin opener would otherwise hold, a class of side channel closed by one header. |
| `Cross-Origin-Resource-Policy` | `same-origin` | `same-origin`, or `same-site` under topology B | `same-origin` or `same-site` | Only the origin, or site, that owns a response is permitted to embed it. |
| `Cache-Control` | `no-store` | `no-store` unless the OpenAPI document declares the endpoint public and cacheable | `public, max-age=31536000, immutable` | A nonced document is uncacheable by construction: a cached copy carries a nonce the next response's policy does not accept. An authenticated API response is one person's data and never enters a shared cache. An asset is cacheable forever only because its name is its content hash; an asset without a hashed name gets `no-cache`. 030 SC1 already requires `no-store` on the health endpoints. |

**What is not sent**. `X-Frame-Options` is superseded by `frame-ancestors` and
never substitutes for it. `DENY` beside `frame-ancestors 'none'` is harmless
duplication. But a response carrying `X-Frame-Options` and no
`frame-ancestors` has relied on the header browsers consult second.
`X-XSS-Protection` is never sent: every browser has removed the auditor, and
`1; mode=block` introduced leaks of its own. `X-Powered-By` is never sent.

`Server`, where the edge insists on one, carries a product token and never a
version. `Cross-Origin-Embedder-Policy` is not required, because it breaks
every cross-origin embed. A product that needs it says so.

**The nonce is per response**: at least 128 bits from a cryptographic source,
base64, never reused, on every `<script>` the document carries. The web
client's shell is rendered per response for this reason. The bundle's files
are static and load through the nonced shell under `'strict-dynamic'`. A
`Content-Security-Policy-Report-Only` header does not satisfy this rule.

**No fallback is sent for browsers without `'strict-dynamic'`**. The
compatibility form carries `'unsafe-inline'` and a scheme source that modern
browsers ignore and old ones honour. So the fallback would be a permission
granted only to the clients least able to defend themselves.

**The start check asserts the set**. `job-image-starts` already requests
`/readyz` from the running image, and the same request asserts the API-class
set. A service that serves documents gets one request to `/` asserting the
document-class set.

A header set by the edge is one the start check cannot see. So a repository
that delegates any header to the edge says which in its **Conventions**. The
assertion then moves to a live check against the deployed environment. The
cookie attributes and CORS headers of 060 AU7 are asserted under that rule.

### SB4. TLS on every hop that leaves a private network, and the platform holds the certificate

**Every connection that crosses a network boundary the service does not own is
TLS**. Between the client and the edge, always. Between the edge and the
server, always, with one exception: the two share a network segment no other
tenant of the infrastructure can reach. A repository claiming that exception
records where in its **Conventions**. Between a process and a backing service,
always. Each is reached over a network, and
[`025-structured-data.md`](025-structured-data.md) SD9 already requires it of
the database.

**TLS 1.2 is the floor and TLS 1.3 is preferred**. The protocol and cipher
list are Mozilla's intermediate profile, at the version current when the
service is configured. The [Mozilla SSL Configuration
Generator](https://ssl-config.mozilla.org/) maintains that list against real
client populations, so the rule pins the profile, not a list stale within a
year. TLS 1.0 and 1.1 are offered nowhere. The profile is
intermediate rather than modern because a public edge's clients include
devices the modern profile refuses. Refusing a user over a cipher suite is a
decision a product makes in its **Conventions**, not by default.

**Certificates come from the platform and are never in the image**. The edge
terminates with a certificate the platform issues and renews: an ACME client,
a cloud certificate manager, a mesh's identity. A server that terminates TLS
itself receives its certificate and key as a secret file at process start
under [`032-secrets.md`](032-secrets.md). An image carrying a private key has
a credential in a build artifact, which 010 and the secrets standard forbid.
And the key expires on a schedule the image cannot follow. A mutual-TLS client
certificate is a credential in the Terms' sense and travels the same way.

### SB5. Unauthenticated and authentication routes are rate limited, and the refusal is HA7's

**Every route reachable without a session, and every route that authenticates,
is rate limited**. The limit is at the edge where the edge can do it, and in
the server otherwise. An authenticated route is bounded by the account behind
it and by [`070-rbac.md`](070-rbac.md)'s check. An unauthenticated route is
bounded by nothing until this rule.

| Route class | Keyed by | Default |
|---|---|---|
| Unauthenticated, any | client address | 60 requests per minute |
| Authentication: login, credential reset, token and code endpoints | client address, and separately the account identifier presented | 10 per minute per address; 5 per minute per identifier |
| Health and readiness (030 SC1) | exempt from the per-address limit for the platform's probes | — |

The defaults are a floor a product tightens in its **Conventions**, and never
loosens without a reason stated there. The per-identifier limit is what turns
a credential-stuffing run into a slow one. The per-address limit alone does
not, because the addresses are many. Authentication under
[`060-auth.md`](060-auth.md) AU1 sits in a tier in front of the application,
and the rule binds whichever process serves the route. **The refusal is 050
HA7's**: `429` with `Retry-After`, always both, and a body that is the RFC
9457 envelope of 050 HA3. A bare status or an HTML page has left the error
contract on the one route a client most needs to handle mechanically.

### SB6. Input is validated by schema at the boundary and bounded in size

**A request body is validated against the OpenAPI document before a handler
runs**. A body that fails is refused with the RFC 9457 envelope carrying the
`errors` array of 050 HA3, one entry per rejected field. Rule 050 HA2 requires
the document. This rule requires that the running service enforce it, because
a description the service does not enforce describes what it hopes to receive.
Query and path parameters are validated the same way. An id-typed path
parameter is validated against the format
[`020-identifiers.md`](020-identifiers.md) IP2 admits, before anything looks
it up.

**Unknown request fields are refused**. The client is generated from the same
document (090 WC3), so a field the server does not know is a typo or an
attack. A request silently accepted with a misspelled field did something
other than what was asked. Additive evolution under PC6 governs what a server
*emits* and a client tolerates. It does not license a server to ignore what it
was sent. A request whose `Content-Type` is not one the endpoint declares is
refused with `415`.

**Size is bounded at the edge and in the server**. A JSON body is limited to 1
MiB by default, and an endpoint raises it in the OpenAPI document with a
reason. Anything larger is a blob under
[`026-blob-storage.md`](026-blob-storage.md)'s upload contract. JSON nesting
is bounded (32 levels), and the query string is bounded (8 KiB). A request
over any bound is refused with `413` or `414` in the same envelope before the
body is parsed. The parse is the attack surface the bounds protect.

### SB7. `SECURITY.md` and `security.txt` state the channel, the commitment and the scope

**Every repository carries `SECURITY.md` at its root**, and every served
origin answers `/.well-known/security.txt` per RFC 9116. The markdown is what
a person reads. The text file is what a finder's tool reads, and its `Policy`
field points at the published policy. `SECURITY.md` must state the following,
validated in structured form against
[`security-md.schema.json`](../contracts/security-baseline/security-md.schema.json):

| Section | States |
|---|---|
| **Reporting** | The channel: an address, a form, or a platform's private advisory mechanism. At least one, and it is monitored. What a report needs to contain. Where an encryption key is, if one is offered. |
| **Response** | Two numbers: the acknowledgement time (three business days is the ceiling) and the triage time by which the finder is told whether the report is accepted and its severity (fourteen days is the ceiling). A commitment without a number is not a commitment. |
| **Scope** | Which systems and repositories the policy covers, and what is out: third-party services, denial of service, social engineering. |
| **Safe harbour** | That good-faith research within scope will not be pursued, in plain words. A finder who fears the report will not send it. |
| **Disclosure** | Whether and when the finder is permitted to publish, and that the report is credited if they wish. |

`security.txt` carries `Contact`, `Expires`, `Policy` and
`Preferred-Languages`, and `Canonical` where the origin is not the policy's
home. `Expires` is no more than a year out, and is renewed before it passes.
An expired file tells a finder the policy might be abandoned. **A handed-over
repository keeps the file with the channel changed to the client's**. A
`SECURITY.md` naming a channel the new owner does not read is worse than none.
The reason is the one [`../AGENTS.md`](../AGENTS.md) gives for a dead link to
this repository.

### SB8. Every release carries a CycloneDX SBOM per image

**The build run generates a CycloneDX 1.6 JSON SBOM for every image it
produces, and the release attaches them**. It is generated from the built
image, not the source tree, because a source SBOM omits the base image's
packages. Those packages are exactly what SB2's image scan finds. It is
generated in the build run because that is the run whose artifacts the release
publishes. [`010-ci.md`](010-ci.md) says a release publishes what main already
gated and builds nothing, so the SBOM has the provenance of the bytes it
describes.

It is attached as a release asset under a fixed name per image
(`<image>.cdx.json`). Where the registry supports OCI referrers, it is also
pushed as a referrer of the image digest. An SB2 acceptance travels downstream
as a CycloneDX VEX statement on the same advisory id. SPDX is an ISO standard
too, but its centre of gravity is licence provenance and its security profile
is less tooled. An SBOM answers *which of our releases contains this* in
minutes, from a file.

### SB9. Least privilege is already stated, and the process in the image runs unprivileged

Least privilege is already held by [`032-secrets.md`](032-secrets.md) and the
000 Terms, [`035-workers.md`](035-workers.md) WK8,
[`025-structured-data.md`](025-structured-data.md) SD3, SD9 and SD13, and
[`080-audit.md`](080-audit.md) AE6.

**The one property none of them states: the process in the image does not run
as root**. Every Dockerfile that produces a runnable image sets `USER` to an
unprivileged user before its entrypoint. The filesystem is writable only where
the process declares it needs to write. A container escape from an
unprivileged process is a bounded event; from root it is the host. The checker
that reads `FROM` reads `USER` in the same pass.

### SB10. Security events are audited and notified under the standards that own them

What must be recorded when a security-relevant act happens is
[`080-audit.md`](080-audit.md) AE5's floor. What must be told to the person it
happened to is the [notifications standard](058-notifications.md)'s security
floor. A leaked secret's response, the audit event it emits included, is
[`032-secrets.md`](032-secrets.md)'s. A change to a floor is made in the one
that owns it.

## The artifacts

Per PC3, under
[`contracts/security-baseline/`](../contracts/security-baseline/):

- **`base-image.schema.json`**: SB1's grammar as `$defs`, with a digest, a
  pinned reference, and a pinned `FROM` line in both admitted forms.
- **`acceptance.schema.json`**: SB2's acceptance entry and the file holding a
  list of them.
- **`response-headers.json`**: SB3's set as data, per class, with the
  forbidden headers and the superseded one.
- **`security-md.schema.json`**: SB7's required content in structured form,
  plus the `security.txt` fields.
- **`corpus.json`**: four parts: `headers`, `from-lines`, `scan-acceptance`
  and `security-md`.
