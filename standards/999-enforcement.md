# Enforcement ledger

Every rule in every Aurum Alpha standard, the mechanism that enforces it, and
the tier that mechanism actually reaches today. One table, across all standards,
because the question "is this rule real?" has to have one answer and one place
to look it up.

The tiers, **gated**, **audit only** and **review only**, and the law they serve
are defined in [`../README.md`](../README.md). Read that first; this
document is the register, not the argument.

**Proposed gate** is a commitment, not a wish. A rule landing review-only names
the mechanism it is eventually getting, and promoting it is a change that moves
its row. A rule that genuinely resists automation says so there instead, and
stays review-only honestly.

This ledger claims what a mechanism *can* do, not what every repository has
taken up. Adoption is tracked in each repository's own issue tracker.

## CI standard

Rules from [`010-ci.md`](010-ci.md). `tools/check-ci-conformance` runs two ways
from one source: `--repo-root` inside a repo's own CI via
`job-ci-conformance.yml`, and `--portfolio` for sweeps. An audit and a gate that
can disagree eventually will.

| # | Principle | Enforced by | Status |
|---|---|---|---|
| 1 | One source of truth per pin | — | **review only** |
| 2 | Local = CI | `check-package-scripts` (TS); Go and PHP unchecked | mixed⁶ |
| 3 | Fail closed | `check-ci-conformance` P3 | gated |
| 4 | Standard runner line | `check-ci-conformance` P4 | gated |
| 5 | Ephemeral-runner assumptions | — | **review only** |
| 6 | Concurrency everywhere | `check-ci-conformance` P6 | gated |
| 7 | BUILD ONCE | — | **review only** |
| 8 | No multi-stage prod Dockerfiles | — | **review only** |
| 9 | Canonical script names | `check-package-scripts` | gated¹ |
| 10 | Lint output through standard channels | — | **review only** |
| 11 | Registry auth in user-level npmrc | — | **review only** |
| 12 | One way per capability | `check-ci-conformance` | gated¹ |
| 13 | Provenance in every artifact | — | **review only** |
| 14 | A version is a commit, not a tag | `job-version-gate` + `job-version-release` (partly) | mixed² |
| 15 | The repo is versioned, not the artifact; images are cut on dependency closure, credential and configuration surface, and an image does one thing | the image set per repository is readable from the catalog calls; the three criteria are a review question | **review only** |
| 16 | A version exists only where consumed | — | **review only** |
| 17 | Release is promotion, not production | `check-ci-conformance` D4, D5 | gated |
| 18 | One workflow per repo | `check-ci-conformance` P18 | gated |
| 19 | The catalog is the default; a local job is a claim | `check-ci-conformance` ADOPT (half) | mixed⁴ |
| — | A job's kind is read off the workflow it calls | `check-ci-conformance` ROLE, DECL | gated |
| — | A job id ends in the capability it calls | `check-ci-conformance` ID | gated |
| — | With two callers of one catalog job, neither id is bare | `check-ci-conformance` ID | gated |
| — | The catalog's own job ids follow the same grammar | — | **review only**⁵ |
| — | Standard job DAG (build first) | `check-ci-conformance` D1–D3 | gated |
| — | Every job blocks something | `check-ci-conformance` D6 | gated |
| — | Something runs the image | `check-ci-conformance` D7 | gated |
| — | `needs.<id>` expressions resolve | `check-ci-conformance` D8 | gated |
| — | `workdir` names a shape, not a path | `check-ci-conformance` WD | gated |
| — | Every upload declares `retention-days` | `check-ci-conformance` RET | gated⁹ |
| — | Per-stack DAG in multi-codebase repos | — | **review only** |
| — | Third-party actions SHA-pinned with a version comment | `check-ci-conformance` PIN | gated |
| — | First-party catalog referenced at `@main`, never pinned | `check-ci-conformance` PIN | gated |
| — | `ci-ok` is the only required check | — | **review only**⁸ |
| — | Branches up to date before merging | — | **review only**⁸ |
| — | Squash is the merge method, and merge commits are disabled | — | **review only**⁸ |
| — | A merged pull request's head branch is deleted | — | **review only**⁸ |
| — | The `ci-ok` body is the one the pull request ships | — | **review only** |
| — | Standard pnpm version | `check-dependency-versions` | gated¹ |
| — | Shared lint and format configs unedited (`.oxlintrc.json`, `.prettierrc.yaml`) | `check-lint-configs` | gated¹ |
| — | Caller `with:` matches the shared job's inputs | `check-ci-conformance` IN | gated |
| — | One shared `ci-ok` rollup, not eleven copies | `check-ci-conformance` RU | gated |
| — | The version moves forward, or not at all | `job-version-gate` | gated² |
| — | A release pull request changes only the version file and prose | `job-version-gate` | gated² |
| — | The version file is never deleted | `job-version-gate` | gated² |
| — | Only a version change mints the tag and the GitHub release | `job-version-release` | gated³ |
| — | Only a version change mints a `v<version>` image tag or package version | — | **review only** |
| — | Caller permissions cover shared jobs | `check-caller-permissions` | gated¹ |
| — | Overrides use pnpm's key alone, not npm's or yarn's | `check-overrides` | gated¹ |
| — | Every override carries a reason, and no reason outlives its override | `check-overrides` | gated¹ |
| — | The reason is true, still true, and names a real retirement condition | — | **review only** |

¹ Gated in every repository whose `ci.yml` calls `job-ci-conformance`, which
runs these checkers. The row claims what the mechanism can do. This repository
keeps no register of who calls it; read a repository's own `ci.yml`.

² Gated in every repo whose `ci.yml` calls `job-version-gate`, and in no
other. Unlike the ¹ checkers this one is not carried by
`job-ci-conformance`. It needs the pull request's base commit and its own
`pull-requests: write` grant, so it is a job a repo adds deliberately. A repo
with no version file passes it trivially and is right to call it anyway. The
job is what makes adding one later safe.

Row 14 reads **mixed** because the principle is two claims and one has a
mechanism. That the version moves forward, alone, in its own pull request is
gated. That no tag, release or artifact is minted except by a commit changing
the file is each repository's own `ci.yml`, and nothing checks it.

³ Gated in every repository whose `ci.yml` calls `job-version-release`. It
covers the two emissions the job itself produces and nothing else. A
`v<version>` image tag comes from the caller's own `job-image-publish` stub,
and a package version from whatever renders it, so both stay review questions.
A `v<version>` tag applied on `is_default_branch` alone is re-pointed at new
bytes by every merge.

⁴ Two halves, and one of them is gated. What a stub must look like once it
calls the catalog is checked: the pin, the stub keys, `secrets: inherit`, the
rollup. What is **not** checked is the half that decides which jobs are stubs
at all. That half says a job id naming a catalog capability must call that
catalog job.

Rule ID is the near half of that and now gated. A job that *does* call the
catalog must be named for the capability it calls. The far half, a job that
names a capability and calls nothing, stays a review question. The checker
reaches a job through its `uses:` line, and a local body has none to follow.
So a local body whose id names a covered capability still passes.

⁵ Rule ID resolves a job through an `aurum-alpha/workflows/...@main`
reference, so it is silent on `workflows` itself, which calls its own jobs by
local path.

The local path is the price of testing a catalog change with its own rules. A
catalog pull request must run the rules as it changes them, not the rules on
`main`. [`010-ci.md`](010-ci.md) carries the argument. The catalog's own job
ids are held to the grammar by review.

⁶ Two halves, and the TypeScript one is now gated. `check-package-scripts`
proves that every command a person runs is present, and equal to what the gate
runs. It derives that from the catalog jobs the repo's own `ci.yml` calls. Go
and PHP have no equivalent. Their commands live in `Makefile` targets,
`tools/checks/*` and composer scripts, which no checker reads, so Principle 2
stays a review question there.

⁸ These four are repository settings, not files, so no checker in this
repository reads them. Nothing goes red when a setting drifts, and nothing goes
red when it was never applied. The gate they are getting is a scheduled audit
that reads the settings through the organisation's GitHub App and reports
drift. It never turns a required check red, because a pull request author
cannot change a repository setting.

⁹ Presence only. `RET` proves an upload states a retention, never that the
number is the right one. One day is correct for a hand-off between jobs and
ninety is correct for firmware that has no other durable home. No checker can
tell those apart. Whether a long retention is earned stays a review question,
and so does whether the deliverable needs a release instead.

## Developer commands standard

Rules from [`015-commands.md`](015-commands.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| DC1 | A command name means the same thing in every repository | `check-package-scripts` S5 | gated¹ |
| DC2 | A script's body is the invocation its gate runs | `check-package-scripts` S2 | gated¹ |
| DC3 | The repository's shape decides which commands exist, in both directions | `check-package-scripts` S1 | gated¹ |
| DC4 | No second name for a command that already has one | `check-package-scripts` S3 | gated¹ |
| DC5 | A script never reaches a local binary through the package manager | `check-package-scripts` S4 | gated¹ |
| DC6 | An added command follows the same rules | `check-package-scripts` S3, S4 | gated¹ |
| DC7 | A document naming a command names one that exists | — | **review only**⁷ |
| — | `test:unit` reproduces the gate's verdict, not its coverage telemetry | `check-package-scripts` S2 | gated¹ |
## Local development standard

Rules from [`016-local-development.md`](016-local-development.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| LD1 | A process reads its listen port from the environment, with a default in code | — **not in the checker, which shipped without it**. The read and the fallback take a different shape in each language, so a check per language is its own change. Review question: *does the process start with no `PORT` set* | **review only** |
| LD2 | A container binds defaults, so a development compose file sets no port | `check-dev-stack` DS1: `PORT` under any service's `environment:` is the finding | **gated** |
| LD3 | Host bindings come from one aligned block of twenty | `check-dev-stack` DS2, reading the development compose file and nothing else. It needs no allocation record, because alignment is a property of a single clone | **gated** |
| LD4 | Offset zero is what a person opens in a browser | — **resists a checker**: which service a person opens is not written down anywhere a machine reads. Review question: *does the base port serve pages, or does it answer nothing* | **review only** |
| LD5 | The development image says so in its name, and it never ships | `check-dev-stack` DS3, over the compose `build` key. A one-shot and a profiled service are outside it, and LD5 says why | **gated** |
| LD6 | The development image installs from the lockfile, with the pinned package manager | `check-dev-stack` DS5: a hand-written package-manager version, or an install naming no lockfile | **gated** |
| LD7 | The dependency tree is a named volume the container populates | `check-dev-stack` DS4: an anonymous volume over the dependency directory is the finding | **gated** |
| LD8 | A clean clone reaches a working stack in one command | — **resists a checker**: proving it means running the stack, which no conformance job does. Review question: *did you run `docker compose down -v && docker compose up` on a clean tree, and did an edit show up* | **gated nowhere, and the row says so** |
| — | No two recorded blocks overlap | `check-dev-stack --registry`, reading [`../ports.json`](../ports.json). **This one runs in this repository alone**, because it is the only question a single clone cannot answer | **gated** |
| — | No client build config names a port from the block | `check-dev-stack` DS6, over the client build config, comparing against the block DS2 derives from the same clone. It covers the port the server binds and the port the browser is told to reach | **gated** |
## Agent standard

Rules from [`../AGENTS.md`](../AGENTS.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| A1 | Every repository has an `AGENTS.md` at its root | `check-agent-docs` A1 | gated¹ |
| A2 | It answers all six required sections | `check-agent-docs` A2 | gated¹ |
| A3 | It references the Aurum Alpha standard, or vendors it | `check-agent-docs` A3 | gated¹ |
| A4 | No rule tree outside the two supported tools | `check-agent-docs` A4 | gated¹ |
| A5 | `CLAUDE.md` opens by importing `AGENTS.md` | `check-agent-docs` A5 | gated¹ |
| A6 | The named work queue is the only work queue | — | **review only** |
| A7 | Gates pass before commit; hooks are never skipped | — | **review only** |
| A8 | The human approval gate is honoured | — | **review only** |
| A9 | Docs win over code, and a correction lands in the docs | — | **review only** |
| A10 | Agent guidance states no count of findings, errors, warnings or failures | `check-agent-docs` A6 | gated¹ |
## Platform standard

Rules from [`000-platform.md`](000-platform.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| PC1 | An opinion is a contract, never a tool | — resists honestly | **review only** |
| PC2 | Standard protocol first, profile second, internal contract last | — resists honestly | **review only** |
| PC3 | A contract is stated in artifacts, not prose alone | `check-contract-artifacts` (proposed) | **review only** |
| PC4 | Gates check the boundary, never the implementation | `job-contract-conformance` (proposed) | **review only** |
| PC5 | A package conforms to the spec, never the reverse | corpus run + manifest check in package CI (proposed) | **review only** |
| PC6 | Contracts evolve additively | `check-contract-evolution` (proposed) | **review only** |
## Identifiers standard

Rules from [`020-identifiers.md`](020-identifiers.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| IP1 | Internal keys never leave the service | schema-level column check, buildable once the [structured-data standard](025-structured-data.md) defines a readable schema; until then the stated review question | **review only** |
| IP2 | The public id format table | `job-contract-conformance` running `contracts/identifiers/corpus.json` (proposed) | **review only** |
| IP3 | Ids are opaque | — resists honestly; review question on consumers | **review only** |
| IP4 | Timestamps are RFC 3339 UTC, and a date is not a timestamp | corpus validity + canonical cases (proposed, same job) | **review only** |
| IP5 | Money is integer minor units plus an explicit currency | corpus validity cases (proposed, same job) | **review only** |
## Observability standard

Rules from [`040-observability.md`](040-observability.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| OC1 | Context propagates as W3C trace context, across every boundary | propagation corpus under `job-contract-conformance` (proposed); the envelope half is met by the CloudEvents tracing extension, gated by [`055-messaging.md`](055-messaging.md)'s schema | **review only** |
| OC2 | One id vocabulary, the same named fields everywhere | corpus validity cases (same job, proposed) | **review only** |
| OC3 | Telemetry leaves the process as OTLP, to an endpoint from config | env presence checkable; wire half proven where the corpus runs live; vendor-exporter half a review question | **review only** |
| OC4 | The context block is required, not decorative | startup-line assertion in `job-image-starts` (proposed) + propagation corpus | **review only** |
## Charter: document conventions

Rules from [`../README.md`](../README.md)'s "How these documents are
written", "The foundation: twelve-factor" and "Acceptable solutions: the
register of what satisfies a standard". D5 to D9 govern the registers under
`solutions/`, which state no rules of their own and are therefore governed
entirely from here.

| # | Rule | Enforced by | Status |
|---|---|---|---|
| D1 | No document carries a status header; a merged document is binding | `check-standards-docs` (proposed): no `Status:` line in a standard | **review only** |
| D2 | Documents reference documents by working relative link — never a tracker number, never a bare name; a standard not yet written is linked at its roster row | `check-standards-docs` (proposed): no issue or pull-request reference in a standard's prose, and every relative link resolves | **review only** |
| D3 | A rule restating a twelve-factor factor cites it; a rule departing from one says so, in the rule, with the reason | — resists honestly: whether a citation is apt, or a departure argued, is judgment | **review only** |
| D4 | A rule is argued from principle, never from precedent. A standard names no repository, ever: not as justification, motivation, colour, example or incident. It counts no repositories and describes no repository's state or distance from the rule. Compliance is tracked where the code is, never in a standard. A failure mode is stated as the general property it is | `tools/check-doc-style` holds the countable half: a repository name (any `aurum-alpha/<name>` other than this repository, or a portfolio repository slug) or an inventory phrase (a count of repositories, an *existing* or *prior* implementation, a phrase locating the rule inside the estate, a measurement across it) in a standard is a finding. It runs in this repository's CI beside D10, warn-only until the count is zero. The fallacy itself, a reason that rests on what one repository did, is the review question on every rule and every Decisions entry: *would this reason hold if no current repository existed?* | **audit only** |
| D5 | An acceptable solutions register states no rule: delete it and every rule still stands, with every repository still able to comply | the citation half is **static and decidable**: `check-solutions` (proposed) checks that every rule id a register cites exists in the standard it shares a number with. That catches the drift that turns a claim into an orphan when a standard is renumbered. Whether a sentence is a claim or a rule in the wrong document resists honestly, and is the review question on every register diff | **review only** |
| D6 | Absence from a register is not refusal; what is refused is refused by a rule in the standard, which the register cites | — resists honestly. The observable half: a register's refusals table cites a rule id for every row, checked with D5's citation pass | **review only** |
| D7 | A register entry is a technical claim on a date — never an endorsement, a price, a contract term or a vendor ranking | `check-solutions` (proposed): a currency symbol, or the pricing vocabulary, in a register is a finding. Close to no false positives, because the vocabulary has no other use on a page this class admits | **review only** |
| D9 | A register may name at most one default route, argued, and says what would change it | — resists honestly: that an argument is good is judgment. That there is at most one is a review question a reader answers by reading the page | **review only** |
| D10 | A document is written in Simplified Technical English: one idea per sentence; at most 25 words in a descriptive sentence and 20 in an instruction; at most six sentences in a paragraph; active voice; no *should*, *may* or *ensure*; no dash joining two clauses | `tools/check-doc-style` measures the mechanical half: sentence length, paragraph length, the banned words, dashes in prose. It runs in this repository's CI in warn-only mode. It gates when the documents are under the threshold, and that promotion is its own change. One idea per sentence, active voice and one meaning per word are review questions | **audit only** |
| D11 | A document carries no history of its own drafting; the pull request holds that | `tools/check-doc-style` D11: the phrases history arrives in (*an earlier draft*, *used to read*, *amended on*, *learned the hard way*) are findings, warn-only beside D4 and D10. Whether a sentence is history or reason is the review question on every diff | **audit only** |

## Service standard

Rules from [`030-service.md`](030-service.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SC1 | Two endpoints, fixed paths, fixed shapes | `job-image-starts` with an `http` probe on `/readyz`, asserting the schema (proposed); `check-service-contract` (proposed) for route registration | **review only** |
| SC2 | One structured log line, to stdout | corpus validity cases against captured stdout, incl. the `error` object required on error and fatal lines and the insufficient-message list, matched by equality and never by containment (proposed) | **review only** |
| SC3 | Configuration comes from the environment, and absence blocks serving | `check-service-contract` (proposed) for declared variables; the fail-loud behaviour is a lifecycle corpus case | **review only** |
| SC4 | SIGTERM means drain | lifecycle corpus case under a live harness (proposed) | **review only** |
| SC5 | The running service says which build it is | `job-image-starts` asserting the startup line (proposed) | **review only** |
| SC6 | Start fast, degrade rather than block, and never crashloop | `job-image-starts` with every dependency absent: the image must answer `/healthz` and stay running (proposed) | **review only** |
## Service interfaces standard

Rules from [`050-http.md`](050-http.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| HA1 | The protocol is chosen for the interaction, and HTTP is the default | — resists honestly: whether a reason is good is judgment. Two reviewable acts: a repository choosing a non-default protocol states why in its **Conventions**, and one serving gRPC or SSE states there where HTTP/2 terminates and that the backend hop carries it | **review only** |
| HA2 | The API is described by a committed OpenAPI document | static and decidable: the document exists, lints, declares `openapi: 3.1.x` or later, and declares 3.2 if any response is `text/event-stream` (proposed). That it still *matches* resists a checker: the mechanism is the repository's own contract tests, and the review question is whether they exist | **review only** |
| HA3 | Errors are RFC 9457 problem+json, profiled | `job-image-starts` requesting an unroutable path and validating the body against the schema (proposed) | **review only** |
| HA4 | Collections are paginated by opaque cursor | corpus behaviour case under a live harness (proposed) | **review only** |
| HA5 | One major version in the path, and change is additive until it cannot be | — resists honestly: whether a change is breaking is judgment | **review only** |
| HA6 | Mutating endpoints accept an idempotency key | corpus behaviour cases, two requests under a live harness (proposed) | **review only** |
| HA7 | Backpressure is stated, and retries are bounded | server half is a corpus behaviour case; the client half resists a checker | **review only** |
| HA8 | Wire field names are snake_case, and the rule stops at the wire | **the one mechanically decidable rule here**: a checker walks the committed OpenAPI document's schema property names and parameter names, and fails on any that is not `[a-z][a-z0-9_]*` (proposed `check-wire-naming`). The wire/code split needs no gate, because a gate reading source would itself be the violation | **review only** |
## Web client standard

Rules from [`090-web-client.md`](090-web-client.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| WC1 | The browser holds no tokens, and is not part of the authentication exchange | the storage half is a corpus behaviour case reading all three stores after a login (proposed). The central claim, that no token reaches JavaScript, **resists a checker entirely**: proving it means proving a negative about a running program, and a gate that read the source would be the PC4 violation. Review question: *what credential does this page hold, and what could read it* | **review only** |
| WC2 | Configuration is fetched at load, never baked into the bundle | **the cheapest gate in this standard and the one to build first**: a static grep of the build output for any environment's API origin, provider hostname or `surface_settings` value, needing no browser and no running service (proposed `check-bundle-config`). The served document validates against its schema under `job-image-starts`, and a static host's deploy step is checked the same way against the artifact directory. The no-secrets half is held by the schema's closed property set; the per-repository `surface_settings` keys are held by that repository's own declared schema. Thirteen `validity` cases, including the version 2 shape rejected | **review only** |
| WC3 | One API client module, generated, owning the boundary rules | corpus behaviour case for key reuse across a retry (proposed). That the module is generated rather than hand-written correct **must not** be gated. A checker failing a build for a direct `fetch` would be enforcing an implementation choice, which PC4 forbids | **review only** |
| WC4 | Presentation is the client's job, and it is done with `Intl` | corpus behaviour cases for the two that are actually got wrong: a zero-exponent currency, and an instant whose calendar day differs by zone (proposed). The server half is reviewable in the OpenAPI document: a response field typed as a formatted string is visible there | **review only** |
| WC5 | The browser does not originate the server's trace, and reports errors with the request id | schema validation of emitted reports, and the conditional requirement that an `api_error` carries a `request_id` (proposed). What a report must *not* contain is held by `additionalProperties: false` rather than by a denylist, which is the only version of that rule that holds against a field nobody predicted | **review only** |
## Authentication standard

Rules from [`060-auth.md`](060-auth.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| AU1 | Authentication is a tier in front of the application, not a library inside it | — **resists a checker entirely**: whether authentication sits in a tier or in the application is an architecture question, and a gate reading source to answer it would be the PC4 violation. Review question: *which process is the OAuth client, and what holds the tokens* | **review only** |
| AU2 | One signed identity token crosses the proxy to the backend | **the strongest gate here**: the token is a wire shape, so the corpus validates it. *Verified rather than decoded* is testable by presenting a token signed with an untrusted key and requiring refusal (proposed) | **review only** |
| AU3 | An application stores a reference to the subject, never adopts it as a key | corpus rejects a subject without its issuer. That an application did not key its user table on the subject is a schema review question, not something a boundary shows | **review only** |
| AU4 | Users are created in the application, and the application creates the identity | two corpus behaviour cases: a second application reusing an identity, and revocation in one application leaving another unaffected (proposed). The rest governs who can change what, which no boundary reveals | **review only** |
| AU5 | Sessions end, and revocation does not wait for them to | live gates are available for the observable half: a session refusing service after its absolute cap, and logout ending the provider session too (proposed) | **review only** |
| AU6 | An authenticated subject the application does not know is refused, and logged out | **a clean live behaviour case**: authenticate as an unknown subject, require 403 with the session ended. The `entitlements` block is schema-decided by `me.schema.json`. That the server also enforces every permission and entitlement resists a checker and is the review question | **review only** |
| AU7 | The topology is one of three, and each states its cookie and CORS posture | **observable from outside**: a login response's `Set-Cookie` and a preflight's answer either carry what the tables require or they do not (proposed) | **review only** |
| AU8 | A session is an authentication into exactly one tenant | **two live behaviour cases** (proposed): a session made on one tenant's entry presented to another tenant's resource is refused with `403` and audited, and a login response on a tenant host carries a `Set-Cookie` with no `Domain=`. That there is no switch-tenant path in the application resists a checker, because a gate reading routes for it would be the PC4 violation. It stays the review question: *how does a request's tenant get chosen, and by whom* | **review only** |
## Authorization standard

Rules from [`070-rbac.md`](070-rbac.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| RB1 | Permissions are a closed set, declared in code | corpus rejection case for the error behaviour. That the declaration is genuinely complete is a judgment about content | **review only** |
| RB2 | A permission is `resource.action` | **static and decidable**: every declared permission matches `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`, which also catches the three-segment form (proposed `check-permission-names`) | **review only** |
| RB3 | A role is a named set of permissions, and every permission in it is real | three corpus rejection cases: an undeclared permission in a role, a tenant editing or deleting a system role, and a tenant role shadowing a system role's name | **review only** |
| RB4 | Code never branches on a role name | **one corpus case is a mechanical detector**: a subject holding a tenant-defined role that carries exactly the permissions of a code-declared one. An implementation gating on the name refuses a subject the permission model allows, and fails that case while passing every other. A grep for role-name comparisons is a weak second gate with real false positives: display and seeding are legitimate | **review only** |
| RB5 | A grant binds a subject to a role within a scope | **decided entirely by the decision corpus**: five containment cases including the two an implementation gets wrong, upward and sibling | **review only** |
| RB6 | Deny by default, additive only, and no permission means "everything" | **decided entirely by the decision corpus**, plus a rejection case covering all four surfaces a wildcard could enter by | **review only** |
| RB7 | `check` is a pure function of its arguments | the corpus is only writable *because* of this rule, so passing it is the evidence. Purity itself resists a checker. A gate reading source for it would be the PC4 violation | **review only** |
| RB8 | A decision carries its reason | the reason's presence and shape are corpus-checked; whether it is *informative* is a judgment, like SC2's | **review only** |
| RB9 | A cached decision is keyed by everything the decision depends on | **one corpus case catches the whole failure**: the same permission checked in two scopes, allowed in the first and denied in the second. A cache keyed without scope fails it | **review only** |
| RB10 | The scope of a request comes from the authenticated session, never from the request | **one live behaviour case** (proposed): a request carrying a tenant header or hostname for a tenant the session is not bound to, against a resource the subject would be allowed in that tenant, must be refused. An implementation reading scope from the request passes every single-tenant test and fails this one. Where the argument is actually read from resists a static checker honestly and is the review question | **review only** |
## Audit standard

Rules from [`080-audit.md`](080-audit.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| AE1 | An audit event is data, not a log line | resists a checker honestly: whether a store is the system of record or a convenience is intent, not shape. The review question is whether a history screen could be built from it | **review only** |
| AE2 | One event shape, and actor is not target | **schema-decided**: `event.schema.json` under `job-contract-conformance`; sixteen validity cases already reach their stated verdict against it | **review only** |
| AE3 | The action names the permission that authorized it | the format half is schema-decided. The identity half gets **a static check worth writing early**: read the product's declared permission set, assert every emitted action is one of them or a reserved `auth.*` action (proposed `check-audit-actions`) | **review only** |
| AE4 | An audit event is self-contained, immutable, and outlives its subject | the shape half is schema-decided. That the store is genuinely append-only and uncascaded is a schema fact once the [structured-data standard](025-structured-data.md) gives a checker a schema to read; that no credential reaches `changes` is SC2's judgment again | **review only** |
| AE5 | The floor: what must emit an event | **the generative gate, and the one worth the most here**: enumerate the routes guarded by a destructive permission, exercise each, assert an event carrying that permission as its action. Fourteen `floor` cases in the corpus describe the acts; two of them are negative | **review only** |
| AE6 | Append-only discipline is required; hash chaining is not | the grant is a schema fact, readable against [`025-structured-data.md`](025-structured-data.md) SD3's credential split. That the request path holds no update is a review question | **review only** |
| AE7 | Retention has a floor, a ceiling, and survives erasure | the erasure half is corpus-decided by `redaction` cases; `erased_at` and `erased_subjects` travelling together is schema-decided. That a retention period was chosen rather than defaulted is a judgment | **review only** |
| AE8 | The event is written with the change, or the failure is loud | **resists a checker at the rule's own level**: whether a write shares a transaction is a fact about a call graph, and a gate reading source for it is the PC4 violation. The corpus reaches the observable half: a failed change produces no event, a successful one produces exactly one | **review only** |
## Structured data standard

Rules from [`025-structured-data.md`](025-structured-data.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SD1 | SQL is the query language, and what runs is what was written | **resists a clean gate honestly**: checking imports is checking the implementation (PC4). The boundary gate is a driver-level capture in the conformance job asserting every executed statement matches committed text; it does not exist yet. Until then: *can I paste this into a console?* | **review only** |
| SD2 | A migration is an ordered `.sql` file, and never code | **three greps with no false positives**: only `*.sql` in the migrations directory, no merged file's bytes changed (from history), no push command reachable. Plus a static, partial fourth for unguarded common forms. Ten corpus cases (proposed `check-migrations`); the live replay in SD3's gate is the proof of convergence | **review only** |
| SD3 | Migrations ship in their own image and run as a step before rollout | **live gate**: apply from empty, apply from the previous release's image, then replay every file against the migrated database bypassing the version record and require exit zero and an unchanged schema. It runs as a sibling of `job-image-starts` (proposed `job-migrate`). Boot-time migration is a review question | **review only** |
| SD4 | Migrations expand; contraction is a later release | a regex over each file's up section for the three statement kinds and the marker; the corpus covers the violation, the marker, and the marker with no release named (proposed `check-migrations`) | **review only** |
| SD5 | Isolation levels are declared, and they are the RBAC scope types | schema-decided by the isolation corpus; **one case is a verified detector**: a table carrying the inner column but not the outer one, which a suite checking only the innermost column passes wrongly | **review only** |
| SD6 | Isolation is a behaviour, proven by enumeration | **the generative gate worth the most here**: discover scoped tables from `information_schema`, assert columns, types, keys and coverage; a table added tomorrow is covered the day it lands, and a table added without its columns is the finding | **review only** |
| SD7 | Identifiers and primitives in storage, per engine | **catalog check against the profile** (proposed `check-storage-profile`). This is the check IP1's row has been waiting for | **review only** |
| SD8 | Seed data is a migration; fixture data is never a production row | seeds: the from-previous-release run applies them twice, so a non-idempotent seed fails SD3's gate. Fixtures: reachability is a grep; that a fixture carries no real personal data is a judgment | **review only** |
| SD9 | The database is an attached resource, reached with the least the service needs | role privileges are a catalog fact once a checker connects as the runtime role and attempts `ALTER`; the rest is review | **review only** |
| SD10 | The schema carries its invariants | **catalog-decided by the `schema` corpus** for the mechanical half (unindexed FK, missing timestamps, native enum, non-snake identifier, isolation column not leading an index; proposed `check-schema`); `NOT NULL` intent and the JSON rule stay review questions | **review only** |
| SD11 | One request, one transaction, and nothing waits inside it | timeout and lock are configuration facts a checker reads; transaction span is a review question on every handler | **review only** |
| SD12 | A deleted row is gone | the Conventions declaration is a grep; the default is a review question on every delete path | **review only** |
| SD13 | The database is private to its service, and is tested as the real thing | privacy is a credential fact (no second role on the database); the real-engine rule is a CI fact: the test job starts the real engine or data-access tests do not run | **review only** |
## Messaging standard

Rules from [`055-messaging.md`](055-messaging.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| AM1 | A message is a CloudEvent, under this profile | **schema-decided**: `envelope.schema.json` under `job-contract-conformance`; ten validity cases. Past tense is the one half the schema cannot tell and stays a review question | **review only** |
| AM2 | The transport is not the contract | review question, and SD13's credential check covers the shared-table half | **review only** |
| AM3 | Delivery is at-least-once, and the consumer is idempotent | **decided by the `delivery` corpus**: deliver the sequence, count the effects. **One case is a verified detector**: the same id from two sources, which a consumer keyed on id alone collapses to one effect | **review only** |
| AM4 | A message is produced in the transaction that caused it | resists a boundary gate honestly: transaction sharing is a call-graph fact (PC4). The observable half (change without message, message without change, each provoked) is a live test | **review only** |
| AM5 | Failure is bounded and visible | the dead-letter shape is schema-checkable; the rest is review | **review only** |
| AM6 | Work outside a request is a consumer, in a worker | **static check with no false positives**: no `setInterval`/ticker/cron in the request-serving entrypoint (proposed `check-no-timers`); the worker image is built, started and published like any other image | **review only** |
| AM7 | A webhook leaving is a signed CloudEvent | **decided by the `signing` corpus**: computed signature values an implementation reproduces byte for byte | **review only** |
| AM8 | A webhook arriving is verified, recorded, and then processed | the rejections are `signing` corpus cases; the re-envelope dedupe is a `delivery` case; the order of the four steps is a review question | **review only** |
## Workers standard

Rules from [`035-workers.md`](035-workers.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| WK1 | There are two worker models, and the trigger picks one | the timer half is AM6's proposed `check-no-timers`; the relay's placement and the boot path are review questions | **review only** |
| WK2 | A worker is packaged as the platform packages everything, and a job is not an image | the image set is read from the CI catalog calls (a migrate image and a jobs image where one-shot jobs exist, a pool image where per-event jobs exist); the one-repository rule is a credential fact (one database's credential in one repository's deployables), checkable once credentials are declared per image; the three-reasons rule is review | **review only** |
| WK3 | One pool per service by default; partitioning is a measured optimisation | review question: the recorded reason | **review only** |
| WK4 | The one-shot's interface is one command, and it constructs the invocation | **decided by the `one_shot` corpus** against the repository's one-shot image: nine cases, each an exit code and a run-record outcome | **review only** |
| WK5 | The runner is the platform's, and it satisfies seven verbs | the rendered runner configuration is compared to the contract's settings per runner; a runner that cannot satisfy a verb is a review finding | **review only** |
| WK6 | The declaration is rendered to the runner at deployment, and the rendered form is an artifact | every periodic declaration has a rendered counterpart in the deployment output and the two agree: a diff, once the renderer exists | **review only** |
| WK7 | A worker exposes what scales it and what stops it | the metric names and the log fields are checkable against the 040 shape; the readiness meaning is review | **review only** |
| WK8 | A worker's configuration and credential are the least its jobs need | a credential fact, checkable once credentials are declared per image; SD13's row covers the shared-database half | **review only** |
## Jobs standard

Rules from [`057-jobs.md`](057-jobs.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| JB1 | A job is a function from an input to an outcome | **schema-decided** for the invoked input under `job-contract-conformance`; the name grammar is in `declaration.schema.json`; "knows nothing of its trigger" is a review question | **review only** |
| JB2 | Every job has a key and a declared duplicate policy, and no run repeats an effect silently | **decided by the `keys` and `policies` corpus parts**: five key derivations, eight run sequences. **Two cases are verified detectors**: an implementation that acts before claiming fails `at-most-once-crash-between-act-and-record` and its sibling and passes everything else; an implementation that ignores `valid_for` fails exactly the two validity-window cases. Whether a declared `idempotent` job's effect really has a dedup handle stays a review question | **review only** |
| JB3 | Every job declares its class beside its code | **schema-decided**: twelve declaration cases, eight of them rejections each naming its rule; the worker's refusal to load an undeclared job is a `one_shot` corpus case | **review only** |
| JB4 | A run ends in one of five outcomes, and each has an owner | the enumeration is in `run-record.json` and the exit mapping in `exit-codes.json`; that `unknown` rows are resolved is a review question | **review only** |
| JB5 | Every run leaves a record, and the record is the authority | the table shape is checkable against the storage profile; the log fields against the OC4 block; the authority claim is review | **review only** |
| JB6 | Single-flight is enforced by the job, whatever runs it | a held lock ending `skipped` is a `one_shot` corpus case; that the lock is taken before any work is review | **review only** |
| JB7 | Every job has a deadline, honours cancellation, and a long job resumes | the checkpoint-and-resume behaviour is a `one_shot` corpus case; one-transaction-per-batch is a review question | **review only** |
| JB8 | For a periodic job, absence is the failure | the declaration requires `stale_after` on every periodic job (schema); the alert itself is platform configuration read from the declaration | **review only** |
| JB9 | A job produces through the outbox and reads only its own service's database | AM4's and SD13's rows | **review only** |
| JB10 | A backfill is a long, single-flight, on-demand, idempotent job, and never a migration | SD4's expand-only gate keeps data movement out of `migrate`; the rest is review | **review only** |
## Blob storage standard

Rules from [`026-blob-storage.md`](026-blob-storage.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| BS1 | The S3 API is the storage protocol, behind a boundary module | the profile's configuration half is readable (`BLOB_ENDPOINT`, `BLOB_REGION`, `BLOB_BUCKET` declared per SC3); the boundary-module half **resists a checker honestly**: a gate reading source for an SDK type would be the PC4 violation. Review question on every diff that imports the client | **review only** |
| BS2 | One bucket per service per environment, private, reachable from the service alone | bucket configuration facts a checker reads from the platform: public-access block on, no anonymous ACL or policy, website hosting off, endpoint on the private network or under a policy admitting the service's credential alone (proposed `check-bucket-posture`); the one-credential rule is WK8's and SD13's credential check | **review only** |
| BS3 | The key is tenant, entity and object id, and carries nothing else | **schema-decided**: `key.schema.json` under `job-contract-conformance`; twelve `keys` corpus cases | **review only** |
| BS4 | The application stores a reference, and the row is the source of truth | **schema-decided** for the shape (`object-reference.schema.json`, closed, fourteen `references` cases), plus the two equalities the corpus states (key tail is the id, key head is the tenant); that the row genuinely owns the object is a schema review question once a checker reads foreign keys | **review only** |
| BS5 | Reads are served by the server, by object id, after the authorization check | decided by the `reads` corpus against a live service (proposed, `job-contract-conformance`): every served case expects the bytes, so an implementation answering a redirect fails all six served cases; that the boundary module has no URL-returning operation is a grep and a review question on every diff touching it | **review only** |
| BS6 | Uploads pass through the server, which verifies what the client declared | the policy is **schema-decided** (`upload-policy.schema.json`, ten `policies` cases, one of which refuses a read lifetime under any name); the sequence is decided by the `uploads` corpus against a live service. **One case is a verified detector**: a declared `image/png` over PDF bytes with size and checksum agreeing. An implementation that trusts the declared type, or sniffs and silently overwrites it, stores it and fails exactly that case | **review only** |
| BS7 | What one person uploads for another is scanned before it is served | the posture is **schema-decided**: `others` without `scan` does not validate; the gate is decided by the `reads` corpus. **One case is a verified detector**: a stored object with `scan: pending` for a permitted subject in the right tenant. An implementation treating the verdict as advisory serves it and fails exactly that case | **review only** |
| BS8 | Deleting the row deletes the object, and the purge job catches what slips | the outbox-and-delete sequence and the three purge findings are `uploads` corpus cases; the purge job's declaration is JB3's schema; the lifecycle rule is a bucket configuration fact. That the row delete and the outbox write share a transaction **resists a boundary gate**, exactly as AM4's does | **review only** |
| BS9 | Encryption at rest is on, and versioning belongs to backup | bucket configuration facts (default encryption, versioning state) readable by the same proposed `check-bucket-posture`; the version-id rule is a review question on the boundary module | **review only** |
| BS10 | The key prefix is a convenience; the row and the check are the boundary | decided by the `reads` corpus: another tenant's row with a valid grant, and a missing tenant context, are each refused; the enumeration form (every tenant's objects requested in every other tenant's context) is the proposed live gate in SD6's shape | **review only** |
## JSON document storage standard

Rules from [`027-json-document-storage.md`](027-json-document-storage.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| DS1 | The relational store is the system of record, and a document store is admitted by declaration | **schema-decided** for the declaration: `admission.schema.json` under `job-contract-conformance`, sixteen `admissions` cases; that a store exists without an admission is a credential fact (a document-store connection variable in a service's configuration with no admission beside it) checkable once credentials are declared per image (035 WK8); whether the stated reason is true is a review question | **review only** |
| DS2 | A document store is derived or primary, and most are derived | the role's conditional fields are schema-decided (four `admissions` rejections); the profile's admitted roles are a runner cross-check; **whether a derived store is genuinely rebuildable resists a checker** and is the first review question on every admission | **review only** |
| DS3 | Which structured-data rules transfer, and which do not | each transferred rule is gated by its own row above where a gate exists; the authored-query half **resists a clean gate for SD1's reason**: a gate reading source for a mapper is the PC4 violation. It stays the review question *can I paste this into the engine's shell?* | **review only** |
| DS4 | A document is identified and scoped the way a row is | `id_source` is schema-decided; the leading-index rule is a runner check over the admission (one `admissions` case); the enumeration gate is SD6's, walking the admission instead of a catalog (proposed, same suite); that the engine's identifier is not in use is a sample of documents against the envelope plus the review question | **review only** |
| DS5 | Every document carries the envelope | **schema-decided**: `document-envelope.schema.json` under `job-contract-conformance`, ten `envelopes` cases; the scoped-needs-tenant judgment is a runner check against the admission; one case is recorded as passing because a 24-hex engine identifier is a well-formed nanoid and no schema can tell them apart | **review only** |
| DS6 | The schema lives in the documents, and a reader honours a version window | **decided by the `evolution` and `rollouts` corpus parts**: eight reader cases and four release sequences. **One case is a verified detector**: a current-version document carrying an unknown optional field, which a reader that closes its schema refuses while passing the other seven | **review only** |
| DS7 | A rewrite is a backfill job, and the declaration is applied at deployment | the credential split is a runner check on the admission (two distinct names) and a credential fact per image once declared (WK8); that `documents.declare` runs as a deployment step is readable from the deployment's step order (035 WK6's renderer); that no script rewrites documents is a review question | **review only** |
| DS8 | A derived store is rebuilt by a job, its freshness is watched, and it is not backed up | the three job names and `backup: rebuild` are schema-decided; the reconcile job's `stale_after` is JB8's alert read from its own declaration; the drill is 028's row; **that the projection is the only writer resists a checker** and is a review question | **review only** |
| DS9 | An engine is admitted by a storage-profile entry | the admission's engine enumeration and the profile's keys are asserted equal by the runner; the profile's admitted roles are a runner check (one `admissions` case); the native-type half is a catalog check per engine (proposed, alongside SD7's `check-storage-profile`) | **review only** |
| DS10 | A document is not a blob, and a blob is not a document | the ceiling is schema-decided (`maximum: 262144`, one `admissions` rejection) and the over-ceiling document is a runner check (one `envelopes` case); that the writer refuses rather than truncates, and that no field carries base64 file content, are review questions | **review only** |
## Backup and recovery standard

Rules from [`028-backup-and-recovery.md`](028-backup-and-recovery.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| BR1 | Every stateful backing service a service owns carries a recovery declaration | **schema-decided** for the declaration's shape under `job-contract-conformance`, sixteen `declarations` cases; that every store the configuration attaches appears in it is a review question until a checker compares the declaration to the declared configuration variables (030 SC3) | **review only** |
| BR2 | The role decides whether there is a backup, and the engine's mechanism is the backup | the role and kind rules are **schema-decided**: a derived store with retention or a drill, a primary store with a rebuild, a cache declared primary, a relational store under snapshot are all rejections in the `declarations` part; that a store declared derived is genuinely rebuildable, and that no job of the service dumps a table, are review questions | **review only** |
| BR3 | The backup credential is not the service's credential | — resists a repository-side checker honestly: where a credential lives is a fact about the platform's configuration and the destination's policy, not about the repository. The recovery image standing alone is readable from the CI catalog calls (035 WK2's row); the rest is a review question on the deployment | **review only** |
| BR4 | Restore is exercised, and a stale drill blocks a deployment | **decided by the `drills` corpus**: five `freshness` cases and three `objectives` cases; one freshness case separates an implementation reading the newest succeeded row from one reading the newest row of any outcome. The deployment gate is a blocking deployment-step job with a run record, so it is gated in every service that puts it in its deployment order; the alert is platform configuration read from the declaration, as JB8's is | **review only** |
| BR5 | Backups are encrypted, out of the source's failure domain, and retained between a floor and a ceiling | encryption and failure domain are **schema-decided**; the two retention relations and the cadence relation are **arithmetic rules the runner checks**, each with its own rejection case; that the declared failure domain is the deployed one is BR3's review question again | **review only** |
| BR6 | Erasure survives a restore | the entry is **schema-decided**, seven `ledger` cases. The replay is **decided by the `restore` scenario** and **both restore cases are verified detectors**: an implementation that reports ready before replaying fails exactly the at-readiness case; one that reads the ledger from the restored table fails both. That the table row shares the erasure's transaction is a call-graph fact (PC4) and stays a review question | **review only** |
| BR7 | A restore is a deployment | the order is observable at the boundary: the restore case asserts the schema is at the release's version when replay runs and that erased rows are absent at readiness. It is the same `restore` scenario; the audit event is 080 AE5's enumeration; the reconciliation of post-`as_of` effects is a review question on the runbook | **review only** |
| BR8 | The runbook is in the repository, and the drill runs it | the path's presence is a file-exists check beside the schema (proposed, same job); that the runbook's steps and the drill's steps are the same steps resists a checker and is the review question stated in the rule | **review only** |
## Secrets standard

Rules from [`032-secrets.md`](032-secrets.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SE1 | A secret reaches a process as configuration does, and never through a vendor SDK | the absent-at-start half is SC3's lifecycle corpus case and WK4's `one_shot` case (`missing variable exits 78`); the no-fetch half **resists a checker honestly**: a call-graph fact PC4 keeps a gate away from. Review question: *what process talks to the secret store, and is it the application?* | **review only** |
| SE2 | Every secret is declared, and the declaration is the source of truth | **schema-decided**: thirteen `declarations` corpus cases under `job-contract-conformance`; the environment-vs-declaration diff is a live check in `job-image-starts` (proposed `check-secret-declaration`) | **review only** |
| SE3 | A secret's name states its subject and its kind | **static and decidable**: the `secretName` pattern over every variable the declaration and `.env.example` list (fifteen `names` cases, one recorded as passing because the grammar cannot know a subject is vague); whether the subject names a real backing service is a review question | **review only** |
| SE4 | No secret value enters the repository, at any point in its history | the scanner is the gate (class of tool, run in CI and as push protection); `forbidden_locations` corpus cases for tracked paths and `.env.example` lines, **one a verified detector**: a low-entropy real value an entropy-only scanner passes | **review only** |
| SE5 | A secret is never in an image, a log line, a URL or an error body, and it is recognised by declaration | the Dockerfile half is **a grep with no false positives** (`ENV`/`ARG` naming a secret-grammar variable; proposed `check-image-secrets`); the log half is the `redaction` corpus against a running emitter under `job-contract-conformance`, **one case a verified detector**: a passphrase-shaped secret a shape-filtering redactor misses. The URL and error-body halves are HA3's problem+json validation plus review | **review only** |
| SE6 | One credential per backing service per service, the least per image, and platform-issued before static | the migrate-alone rule is **schema-decided**; the one-credential count is a runner check over the declaration (corpus case); the image set against `images` is checkable once credentials are declared per image, which this declaration is (the row WK8 and SD13 were waiting on); platform-before-static is a review question on each `issued_by: static` | **review only** |
| SE7 | Every secret has an owner and a maximum age, and rotation never needs a code change | the age and mode are schema-decided; the freshness comparison is four `rotation` corpus cases and, live, a check reading the platform store's rotation dates against the declaration (proposed `check-secret-freshness`); that the procedure is followed rather than worked around is review | **review only** |
| SE8 | A leak is answered by rotation first, investigation second, and an audit event, and never by rewriting history | the event shape is **decided by `leak_response` corpus cases** against `contracts/audit/event.schema.json` plus the no-value scan; the order of operations and the handover rotation are review questions, stated as such | **review only** |
| SE9 | Local development and the pipeline use their own secrets, and `.env.example` is the contract | the `.env.example`-matches-declaration diff is a static check beside SE2's; the compose admission is two `forbidden_locations` cases; that a development credential grants nothing outside the developer's machine is review | **review only** |
| SE10 | The store renders into the environment through the runtime's own mechanism, and there is one store per platform | the mapping's names against the declaration is the same gate as `.env.example`'s (SE2, SE9); a value in the mapping is SE4's scanner; that the mechanism is one from the table and that the application process holds no store credential are review questions (a call-graph and a platform fact, PC4). Which implementations meet the four properties is [`../solutions/032-secrets.md`](../solutions/032-secrets.md)'s and carries a date, not a gate | **review only** |
## Feature flags standard

Rules from [`038-feature-flags.md`](038-feature-flags.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| FF1 | OpenFeature is the evaluation API, and the provider is configuration | **resists a checker at its own level**: whether domain code imports a provider is a fact about source, and a gate reading source for it is the PC4 violation. The observable halves are live: the startup line names the provider (`job-image-starts`, proposed), and `/readyz` stays `200` with the provider unreachable (SC6's gate) | **review only** |
| FF2 | Every flag is declared in the repository, and the declaration says what exists | **schema-decided** for the file: fifteen `declarations` cases. **One `evaluation` case is a verified detector**: a provider holding a flag no declaration names, which an implementation that asks the provider first answers from the provider and passes every other case. Disjointness is an intersection of two committed sets (proposed `check-flag-names`) | **review only** |
| FF3 | A flag has one of three kinds, and every kind has an end | the kind-conditional fields are **schema-decided**; both horizons and the date comparison are decided by the `expiry` corpus part, ten cases, **two of them verified detectors**: a sweep with no forward ceiling on `review_by` fails exactly the century-date case. One bounding `review_by` from `created` rather than from the reading date fails exactly the long-lived-but-recently-reviewed case (proposed `check-flag-declarations`, static over one committed file). That a kind was chosen honestly is a review question | **review only** |
| FF4 | Every boolean flag defaults to `false`, and evaluation failure returns the default | the boolean default is **schema-decided**. **One `evaluation` case is a verified detector**: the provider unavailable, which a fail-open implementation answers `true` and passes every case in which the provider is up. A call-site default disagreeing with the declaration is an `evaluation` finding case. Whether a non-boolean default is the shipped variant is a review question | **review only** |
| FF5 | A flag is not authorization | **decided by the `gating` corpus**: four cases. **One is a verified detector**: flag on and permission denied, which an implementation treating the flag as authorization serves and passes the other three. `check-flag-names` (FF2's) catches a flag name in the permission set | **review only** |
| FF6 | The evaluation context is the platform's id vocabulary, and nothing personal travels in it | **schema-decided** by `evaluation-context.schema.json` at the platform hook: ten `contexts` cases, including the key denylist, the `@`-in-value rule and a nested object. The denylist catches spellings and not the property, so *would this attribute identify a person* stays the review question on every new attribute | **review only** |
| FF7 | Flags are evaluated by the server, and the browser receives an evaluated set | the served document is **schema-decided** (four `evaluated_sets` cases) under `job-image-starts`; the no-credential half is WC2's proposed `check-bundle-config` grep for a provider hostname or SDK key in the build output. That the client renders from the set rather than evaluating rules is a review question | **review only** |
| FF8 | Every evaluation is observable on the span, and none is a log line at volume | the attribute names are checkable against the semantic conventions where the propagation corpus runs live (040's `job-contract-conformance`); the no-line-per-evaluation rule is a review question on every diff that logs | **review only** |
| FF9 | Flag state lives with the provider, and the provider is attached by configuration | the Conventions declaration is a grep; the credential half is the per-image credential fact WK8's row waits on. That no bespoke flag machinery or provider has grown beside the service is a review question. The refused shape is defined by what a value can do rather than by a file a checker could name | **review only** |
| FF10 | An experiment assigns deterministically, records exposure once, and ends with a decision | the `experiments` corpus part decides determinism and once-per-subject recording against a repository's assigner; that the event goes through the outbox is AM4's row; the decision is a review question at expiry | **review only** |
| FF11 | A flag is removed in one change, and the sweep that finds an overdue one is a job | the CI half is `check-flag-declarations` (FF3's, proposed); the job's declaration is JB3's schema and its staleness is JB8's alert. A declaration with no call site resists a checker honestly: a grep for the name finds the common case and misses a generated accessor. It stays a review question | **review only** |
## Notifications standard

Rules from [`058-notifications.md`](058-notifications.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| NF1 | A notification is a message to a person, through a channel, about an event | — resists honestly: whether a message is to a person or to a rota is judgment. Review question: *who is the recipient's identity record, and which event caused this* | **review only** |
| NF2 | The pipeline is three jobs and two messages, under 055 and 057 | the job declarations are JB3's schema and WK2's image set; `status-events.json` fixes the event types and transitions; that decide writes rows and messages in one transaction is AM4's call-graph question | **review only** |
| NF3 | The record is the source of truth for *did we tell them*, and it is the service's | **schema-decided** by `notification.schema.json` under `job-contract-conformance`: sixteen `records` cases including the address, body, missing-provider, missing-reason and security-by-preference rejections. Log fields are checkable against the OC4 block; the alert is platform configuration | **review only** |
| NF4 | The recipient is a public id, and the address is resolved at send time | the no-address half is schema-decided (closed property set); `channelAddress` shape is schema-decided; the verified rule is decided by three `decide` cases. That the send job resolves rather than caches the address is a review question | **review only** |
| NF5 | Two classes, declared categories, and consent per category per channel | **decided by three corpus parts**: `category-declaration.schema.json` and `preference.schema.json` for the declarations, eight `decide` cases for consent and the switch, nine `unsubscribe` header cases and four endpoint cases. **One endpoint case is a verified detector**: an implementation that withdraws consent on `GET` fails `a-get-on-the-unsubscribe-link-changes-nothing` and passes everything else. Whether a category's class was chosen honestly is a review question | **review only** |
| NF6 | The security floor notifies regardless of preference | **decided by the `decide` corpus, and its case is the verified detector**: `a-preference-cannot-suppress-the-security-floor` fails an implementation that treats `security` as one more transactional category and channel-switches it, which passes every other case. The schema refuses a `security` row suppressed by preference and a `security` preference row. That the product's list of privileged roles is complete is a review question | **review only** |
| NF7 | Suppression is a state on the address, and erasure leaves nothing | five `decide` cases (bounce on the floor and on optional, complaint on each class, erased subject) and the `channelAddress` schema. That the status-event consumer sets suppression is a live test against the webhook endpoint (proposed) | **review only** |
| NF8 | Templates are files in the repository, rendered at send time in the recipient's locale and zone | locale and zone formats are schema-decided (two `records` rejections); the render-in-CI rule is a test job a checker can see exists (proposed `check-templates`); purity of the render and the limits table are review questions | **review only** |
| NF9 | Authorization is checked at render time, and links require authentication | **decided by the `render_authorization` corpus**: four cases including the required-field refusal. Link targets and token lifetimes are a review question on every template | **review only** |
| NF10 | Repeats collapse, optional is rate-limited, and quiet hours are the recipient's | **decided by the `decide` corpus**: seven cases, including the Berlin/Los Angeles pair at one instant that fails an implementation evaluating quiet hours in UTC or the server's zone | **review only** |
| NF11 | The provider is behind one adapter, and a vendor swap is configuration | the credential placement is WK8's credential fact; the webhook handling is AM8's `signing` and `delivery` corpora; the no-SDK rule **must not** be gated, because a checker reading imports is the PC4 violation, and is the review question | **review only** |
| NF12 | The in-app channel is the service's API, with cursor paging and SSE | HA4's pagination and HA1/HA2's SSE rows cover the API shape; the `in_app` schema rules (no provider, `read_at`) are `records` cases; that the list is the truth and the stream a hint is a review question | **review only** |
## Data subject rights standard

Rules from [`082-data-subject-rights.md`](082-data-subject-rights.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| DR1 | The data inventory is the precondition, and it is a declaration | **schema-decided** for the declaration (eight `inventory` cases) and **catalog-decided** for completeness: the `coverage` corpus part enumerates tables the way 025 SD6's gate does and names the undeclared table, the unknown column, the dangling `via`, the duplicate membership entry and the column with no tombstone (proposed `check-data-inventory`) | **review only** |
| DR2 | Both rights are request resources under one status machine | the resource is **schema-decided** (eight `requests` cases: each status requires and forbids its fields); the `transitions` part decides the step-up refusal, the open-request `200`, the cancellation rules and the download route under `job-contract-conformance` (proposed); that the deadline alert is wired is platform configuration read from the request table | **review only** |
| DR3 | The export: a job-built package, tenant-bounded, delivered as a blob | the manifest is **schema-decided** (four `export` manifest cases); the package contents are decided by the `export` build cases — file list, counts, column sets — against a repository's builder (proposed, same job); whether an `export: false` has one of the three admitted reasons is a review question | **review only** |
| DR4 | Erasure is a grace period, then a job that walks the inventory in order | the treatment order and the tenant-and-membership boundary are **decided by the `erasure` corpus** (`entries-are-treated-children-before-parents`, `erasure-is-bounded-by-tenant-…`); the grace mechanics by the `transitions` dispatch cases; that suppression runs first and revocation runs last is a sequence a boundary does not show, and stays a review question | **review only** |
| DR5 | Three treatments, and anonymisation is an allowlist | **decided by the `erasure` corpus, and two cases are verified detectors**: an implementation that scrubs identifying columns by name fails exactly `anonymise-is-an-allowlist-not-a-denylist`, and one that deletes every dependent row fails exactly `audit-rows-survive-redacted-by-subject`; the retain and purge cases cover the rest. Whether a treatment is the right one for its data and whether a basis is real are judgments | **review only** |
| DR6 | A legal hold suspends deletion, is audited, and is visible | **decided by the `hold` corpus** (four lifecycle sequences) and the `held` conditionals of `request.schema.json`; that a hold is reviewed is a review question, stated as one | **review only** |
| DR7 | Every erasure leaves two records: the audit event and the ledger entry | the `result` requirement is **schema-decided** (`a-completed-erasure-without-its-result-is-rejected`); that the two writes share the last batch's transaction is a call-graph fact PC4 keeps out of a gate, and is the review question on the job | **review only** |
| DR8 | A tenant leaving takes its subjects' data with it | the row-level half is the same enumeration SD6's gate performs and the same treatments the `erasure` corpus decides; the one-database half is an operator runbook, and that it exists is a review question | **review only** |
## Security baseline standard

Rules from [`085-security-baseline.md`](085-security-baseline.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| SB1 | Base images are pinned by digest, and the checker reads `FROM` | **static and decidable with no false positives**: an extension of `check-ci-conformance` PIN reading every `FROM` in every Dockerfile against `base-image.schema.json`'s grammar (proposed `check-ci-conformance` FROM); thirteen `from-lines` corpus cases, one a verified detector for a checker that reads only the first `FROM` | **review only** |
| SB2 | Every repository scans its dependencies and its images, and an acceptance expires | the entry shape is **schema-decided** by `acceptance.schema.json` read from each scanner's native file (proposed `check-scan-acceptances`); the calendar half is two `scan-acceptance` corpus cases; `job-osv-scan` and `job-go-govulncheck` exist, `job-image-scan` is proposed between `job-image-build` and `job-image-starts`. Whether a reason is true stays a review question | **review only** |
| SB3 | Every response carries the header set for its class, and the start check asserts it | **live and cheap**: `job-image-starts` already requests `/readyz`; asserting the API-class set on that response and the document-class set on `/` is one more assertion in a job every repository calls (proposed). Twenty-one `headers` corpus cases, **two verified detectors**: `X-Frame-Options` without `frame-ancestors`, and HSTS without `includeSubDomains`. A header delegated to the edge is declared in Conventions and is a live check against the deployed environment, and whether it is actually set there is the review question | **review only** |
| SB4 | TLS on every hop that leaves a private network, and the platform holds the certificate | the protocol floor and cipher profile are observable from outside with one handshake per listener (proposed live check); a private key in an image is a secret-scanning finding under the secrets standard; whether a hop declared private is private **resists a checker honestly** and stays the review question on the Conventions entry | **review only** |
| SB5 | Unauthenticated and authentication routes are rate limited, and the refusal is HA7's | the refusal shape is 050 HA7's corpus case under a live harness; that a limit exists on an unauthenticated route is a live test that sends more than the floor (proposed); whether the floors were chosen rather than defaulted is a review question | **review only** |
| SB6 | Input is validated by schema at the boundary and bounded in size | the size bounds and the unknown-field refusal are live behaviour cases (proposed, same harness as HA6/HA7); that the schemas the service enforces are the ones the document publishes is HA2's unfixable half and stays a review question | **review only** |
| SB7 | `SECURITY.md` and `security.txt` state the channel, the commitment and the scope | **schema-decided** by `security-md.schema.json` over the sections a checker extracts (proposed `check-security-md`); six corpus cases; `security.txt` presence and `Expires` within a year are a live request against the started image; that the channel is monitored is a review question | **review only** |
| SB8 | Every release carries a CycloneDX SBOM per image | presence is a release fact: `job-version-release` can assert one asset per image the run built (proposed); that it was generated from the image rather than the source is a provenance fact the job itself controls once it generates it | **review only** |
| SB9 | Least privilege is already stated, and the process in the image runs unprivileged | `USER` is read from the same file SB1's checker reads, in the same pass (proposed, same extension); not yet in the corpus and this row says so; the writable-filesystem half is a runtime configuration fact | **review only** |
| SB10 | Security events are audited and notified under the standards that own them | — a pointer rule; enforced by the rows it points at | **review only** |
## Web estate standard

Rules from [`091-web-estate.md`](091-web-estate.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| WE1 | A surface belongs to one of three classes, and the class fixes its identity posture | — **resists a checker**: which class a surface is in is an arrangement of processes and hosts, and a gate reading source to decide would be the PC4 violation. Review question: *what identity does this surface hold, and which population can reach it* | **review only** |
| WE2 | The host convention is the class boundary, and the class is decidable from the name | a per-repository host declaration checked against the edge configuration and the certificate list (proposed). The declaration does not exist yet; until it does the review question is *which zone is this host in, and could a product cookie reach it* | **review only** |
| WE3 | The front door is a built directory, not a service, and it has environments | **the one to build first, and mostly already named**: the WC2 static check of the build output (proposed `check-bundle-config`) applies to the front door's directory unchanged, and the served document validates against its schema. This standard adds one live assertion on the same origin: no `Set-Cookie` on any response (proposed) | **review only** |
| WE4 | Content is data in the repository, and nothing is live without a build and a record | a build from a clean checkout with the network closed proves the build reads only the repository (proposed, shared with WE5). That the diff is *readable as prose* is a review question | **review only** |
| WE5 | Every surface is maintainable from its repository alone | the test is a job — clean checkout, build, gates, no other access — and it stays review-only until such a job exists; a gate running with the pipeline's own access would not be asking the question | **review only** |
| WE6 | The seams are the existing contracts, named, and no other route crosses one | — **resists a checker**: a route between surfaces is visible only in deployment topology. The front door's half is reviewable in its build output (no form action pointing at the product's API, no personal field on the sign-up link), and that is the review question | **review only** |
| WE7 | An automated actor on any surface is a workload identity | the pipeline half is 032's gate: a static deploy credential in the CI secret store where the host accepts federation is a finding there. The borrowed-session half resists a checker; review question: *whose name is on the audit event this automation writes* | **review only** |
| WE8 | Campaign pages live in the front door's zone | the same host declaration as WE2, once it exists: a front-door build deployed to a host declared product is the finding. Until then, review | **review only** |
## Tenant hostnames standard

Rules from [`092-tenant-hostnames.md`](092-tenant-hostnames.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| TH1 | A tenant is an authentication boundary, and a role is an authorization boundary within one | — **resists a checker**: where a decision is made is architecture. Review question: *where does this handler get its tenant, and could a request have supplied it* | **review only** |
| TH2 | Before login the hostname chooses the tenant; after login it only agrees | the agreement half is a live behaviour case: a session for tenant A presented on tenant B's host is refused (proposed, with TH3). That nothing reads `Host` as an authorization input resists a checker for PC4's reason and is TH1's review question | **review only** |
| TH3 | A host that names no tenant is `404` at the edge, and the four invalid cases each have one answer | **the one to build first, with TH4, as one live check**: request an unknown host and require `404` with no `Set-Cookie`; present a tenant-A session to a tenant-B host and require `403` and the audit event (proposed) | **review only** |
| TH4 | The session cookie is host-only, and `Domain=` is never set | **observable from outside**: a login response's `Set-Cookie` either carries `__Host-` and no `Domain=` or it does not, in the shape 060 AU7's own cookie check takes (proposed) | **review only** |
| TH5 | One callback host per topology, and the session lands on the tenant host without the browser holding a token | the observable half (no token in any URL the browser is redirected through) is a 090 WC1 corpus case, not a new gate. That the handle is single-use and bound to the host is a behaviour case (proposed): redeem it twice and require the second to fail | **review only** |
| TH6 | Subdomains are covered by a pre-issued wildcard, and a custom domain walks a state machine the product implements | the declaration half is 057's gate — the job exists, `periodic`, with `stale_after`. The transitions are a fixture against a fake zone (proposed); the drift case needs a customer's DNS to move and stays review | **review only** |
| TH7 | No certificate is ever requested for a host the tenant table does not hold | a periodic comparison of certificate transparency for the product's zones and ACME account against the tenant table (proposed); any certificate naming a host the table does not hold is the finding. Review-only until that job exists | **review only** |
| TH8 | A tenant host is `noindex`, on the header and in the document | a header check on every tenant-host response in the shape 085 SB3's start check already asserts its header set (proposed): one more header, on hosts of one class | **review only** |
## Billing standard

Rules from [`075-billing.md`](075-billing.md).

| # | Rule | Enforced by | Status |
|---|---|---|---|
| BL1 | The catalog is a file in the repository, and the provider is provisioned from it | **schema-decided** for the file, plus two corpus rejections the schema cannot express: a plan missing a declared metric, a plan listing an undeclared capability (proposed `check-billing-catalog`, static over one committed file). That the provider was provisioned from it and not edited by hand is BL6's finding; a price typed into content is a review question | **review only** |
| BL2 | The subscription is a projection of an append-only ledger | the closed sets and the single `pending_change` are **schema-decided**; the fold is **decided by the corpus**: the plan before the last upgrade, the pending downgrade, the last and first day of a cancelled period, the superseded cancellation, two of them verified detectors. The `INSERT`/`SELECT`-only grant is AE6's proposed grant check applied to a second table | **review only** |
| BL3 | An entitlement is one of four kinds, and nothing is per user | ids are **static and decidable**: every declared id matches `^[a-z][a-z0-9_]*$` and intersects neither the permission set nor the flag declaration (extends RB2's proposed `check-permission-names`); a per-user entitlement is a schema rejection; no-ceiling-is-not-zero and a quota at its ceiling are corpus cases. That a term is genuinely unchecked is a review question | **review only** |
| BL4 | The check is a pure function, run in a fixed order, and its decision carries a reason | **decided entirely by the decision corpus**: twenty-eight cases across seven operations. **One corpus case is a verified detector for the cache rule**: the same capability inside and then outside a grace period with no row between, which a cache keyed on the ledger alone answers twice. The problem shape is schema-decided against `problem.schema.json` and the extension def. Purity and the request-path order resist a checker, because a gate reading source for either is the PC4 violation, and stay review questions | **review only** |
| BL5 | One provider adapter, chosen by configuration | the startup line names the adapter (`job-image-starts`, proposed) and the credential half is WK8's per-image fact. Whether domain code imports the SDK is a fact about source and resists a checker at its own level; that no card field posts to our server is a review question on every payment route | **review only** |
| BL6 | Provider events arrive as webhooks and are reconciled by a job | the endpoint order is 055's corpus; the duplicate-event rejection is a corpus case; the job's declaration is JB3's schema and its staleness JB8's alert. That a disagreement became a finding and not a quiet row is a review question on the job's body | **review only** |
| BL7 | Plan changes are made in the product, under stated policies | the timings and the over-quota rule are **corpus-decided**: the pending downgrade before and after its effective time, the exceeded quota after it. A dashboard change is BL6's finding. That a route deletes nothing to fit a plan is a review question | **review only** |
| BL8 | A trial is a subscription state with an end date | the trial-contributes-the-full-plan and expired-trial-is-suspended cases are in the corpus; the job's declaration is JB3's schema; the Conventions declaration is a grep. That the notification category exists is NF5's row | **review only** |
| BL9 | Sign-up creates the tenant, its first administrator and its subscription in one transaction | resists a checker honestly: one transaction is a property of a code path, and a gate proving it would read source. The observable half (a tenant row with no subscription row) is a proposed schema invariant under SD10 (a foreign key the migration carries) | **review only** |
| BL10 | Money events are audit events, and billing history is exportable | the event-per-row is AE8's transaction test and AE5's proposed floor check over the `subscription.*` permissions; the inventory entries are DR1's schema. That the retention basis is genuine is a review question | **review only** |
