# Secrets: how a secret reaches a process, what never enters a repository, and what happens when one leaks

One of the Aurum Alpha engineering standards, written under the platform
contract ([`000-platform.md`](000-platform.md)) — a per-capability standard
from its roster. Read [`999-enforcement.md`](999-enforcement.md) for the tier
each rule below actually holds. Artifacts:
[`contracts/secrets/`](../contracts/secrets/); what is known to satisfy SE10,
and when that was last checked, is
[`solutions/032-secrets.md`](../solutions/032-secrets.md), which states no rule
of its own. The words *process*, *image*, *backing service*, *credential*,
*configuration* and *environment* are used in the senses [`000-platform.md`](000-platform.md#terms) defines. This leans on
[`030-service.md`](030-service.md) SC2 and SC3, [`010-ci.md`](010-ci.md),
[`025-structured-data.md`](025-structured-data.md) SD3,
[`035-workers.md`](035-workers.md) WK8,
[`040-observability.md`](040-observability.md) and
[`080-audit.md`](080-audit.md).

This document governs **the secret**: a configuration value whose disclosure
grants access — a credential to a backing service, a signing or encryption
key, the shared secret behind a webhook. It defines how one reaches a process,
how it is declared and named, where it may never be, how it is rotated, and
what happens when one leaks. **What it does not define is the configuration
surface, the identity chain, or the image**, which are SC3's,
[`060-auth.md`](060-auth.md)'s and [`010-ci.md`](010-ci.md)'s.

## Why this exists

Every process holds at least one secret, and the secret is the one input a
process cannot be given the way it is given everything else: code is built
once and copied, while a secret must reach exactly the processes that need it
and no artifact that outlives them. Every cheap answer fails on that
asymmetry, and fails quietly, because a secret in the wrong place does nothing
visibly wrong until someone else reads it.

**A value in the repository** is in every clone and fork ever taken, and
deleting it in a later commit removes it from none of them. **A value baked
into an image** is in a layer, in every registry and on every host that
pulled it. **A fetch from a vault through the vendor's SDK** makes the vault
a runtime dependency of every process (PC1), needs an undelivered credential
to the vault, and adds a startup gate SC6 forbids. **A secret in a log line**
is in a system built to copy, index, retain and search everything it
receives. **A secret nobody rotates** has a permanent exposure, and nothing
fails on the day it should have been rotated, because absence is not an event.

Two properties make this sharper than the general case. A repository built
for a client leaves the portfolio, so anything in its history at handover is
a leak into an estate nobody here can rotate afterwards. And a secret is the
one class of defect where the remedy is not a fix: a leaked value is not made
unleaked by removing it, so the response is a rotation by a named person.

This standard answers once how a secret arrives, what it is called, where it
is declared, where it is forbidden, how it is recognised at the log boundary,
how old it may get, and what a leak response consists of. What remains for a
repository is the list of secrets its service needs, which is its domain.

### The standards evaluated first, per PC2

**Delivery is [factor III](https://12factor.net/config), unchanged.** A
secret is configuration and reaches a process in the environment. The OCI
runtime offers exactly two channels into a container that exist before the
process does, environment variables and mounted files, and every runtime the
platform could sit on populates both from its own secret store. SE1 adopts
both. **The step between the store and the environment has no standard**,
only an established mechanism per runtime; SE10 pins the class per runtime
and what qualifies one.

**Redaction borrows HTTP's own list.** The field names SE5 redacts by name
are the ones [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) and
[RFC 6265](https://www.rfc-editor.org/rfc/rfc6265) define for carrying
credentials, plus the token fields of
[RFC 6749](https://www.rfc-editor.org/rfc/rfc6749). Recognition by declared
value is invented, because no standard states how an emitter knows which of
its own strings are secrets.

**Short-lived credentials are OIDC and the platform's identity mechanisms**,
adopted by SE6 as the preferred form. **The leak response reuses the audit
event** of [`080-audit.md`](080-audit.md) AE2 and AE3. **Secret scanning has
an established class of tool and no standard**; SE4 names the class and the
posture, never a vendor.

**What no standard covers** is what this document invents: the declaration
(SE2), the name grammar (SE3), recognition by declaration and never by shape
(SE5), the age and rotation modes (SE7), the order of a leak response (SE8),
and the properties a store and a delivery mechanism must have (SE10).

## The rules

### SE1. A secret reaches a process as configuration does, and never through a vendor SDK

**A secret reaches a process in its environment, delivered by the platform
before the process starts; application code never fetches one.** There are
two forms, and the declaration (SE2) says which each secret takes:

| Delivery | The variable holds | Used for |
|---|---|---|
| `env` | The value. | The default: a password, a token, an API key, a connection string, a symmetric key as base64 — anything that is one line. |
| `file` | An absolute path, identical in every environment, at which the platform has mounted the material. The variable ends in `_FILE`. | A private key or any multi-line PEM, which half the tooling that reads environments mangles and the other half prints; a token the platform projects and renews in place. |

A process reads its secrets at start, with the rest of its configuration
(030 SC3); where a `file` secret's rotation mode is `reissue` it re-reads the
file on each use, because the platform is renewing it underneath. A declared
secret absent or invalid at start is a missing required variable under SC3:
the server reports `fail` on `/readyz` naming it and serves no traffic; a
one-shot exits `78` (035 WK4).

**No vendor SDK, no vault client, no fetch.** The platform's secret store is
where values live at rest; what a process sees is the variable. Fetching in
application code makes the store's client a runtime dependency of every
process (PC1), needs a credential to the store with no delivery rule, adds a
network call before serving that SC6 refuses, and tells the code which store
it is in front of, which is environment detection under SC3. A secrets
operator or a volume driver that renders the store into the environment is
the platform's mechanism, on the other side of the variable.

### SE2. Every secret is declared, and the declaration is the source of truth

**A service carries a declaration of every secret any of its processes reads,
in the repository beside its deployables, validated against
[`secret-declaration.schema.json`](../contracts/secrets/secret-declaration.schema.json).**
It is the secret half of the configuration declaration SC3's gate reads:

| Field | Values | What it decides |
|---|---|---|
| `id` | UUIDv7 (020 IP2), minted once | The target an audit event names when the secret is rotated (SE8), stable across a rename of the variable. |
| `name` | SE3's grammar | The variable the process reads. |
| `kind` | `password` · `secret` · `token` · `api_key` · `connection_string` · `signing_key` · `encryption_key` · `private_key` | The name's suffix, the delivery, and what the redactor registers. |
| `delivery`, `path` | `env` · `file`, with the mount path | SE1. |
| `purpose` | one sentence | Lets a reviewer ask whether each image that carries it needs it. |
| `backing_service` | logical name, or `self` | SE6's one-credential rule is counted over this. |
| `owner` | team or role | Who rotates it and answers for it (SE7, SE8). |
| `issued_by` | `platform` · `static` | Whether the platform renews it or a person must (SE6). |
| `max_age_days` | 1–365, required for `static` | The rotation policy (SE7). |
| `rotation` | `mode` (`restart` · `dual_window` · `reissue`) and `procedure` | How it is rotated without a code change, and where that is written (SE7). |
| `images` | subset of `server` · `pool` · `jobs` · `migrate` | Which images carry it; `migrate` shares with none (SE6). |

Four things follow mechanically: an undeclared secret in a process's
environment is a finding, because nothing tested reads it; a declared secret
absent at start blocks serving (SE1); the declared values are what the
redactor recognises (SE5); the declared images are what the image set is
checked against (SE6). The declaration is a committed file, so it carries no
value, and its property set is closed so a `value` field cannot be added.

### SE3. A secret's name states its subject and its kind

**The variable is `<SUBJECT>_<KIND>`**: the subject is the backing service's
logical name in `SCREAMING_SNAKE_CASE`, identical in every environment, and
the kind is one of a closed set, last:

| Kind suffix | The material | Delivery |
|---|---|---|
| `_PASSWORD` | A password to a backing service. | `env` |
| `_SECRET` | A shared secret that authenticates the other side: a webhook signing secret (055 AM7, AM8), an OIDC client secret. | `env` |
| `_TOKEN`, `_TOKEN_FILE` | A bearer credential. | `env`; `file` when the platform projects it |
| `_API_KEY` | A provider's key. | `env` |
| `_URL`, `_DSN` | A connection string carrying a credential. | `env` |
| `_SIGNING_KEY`, `_ENCRYPTION_KEY` | Symmetric key material the service holds itself; the subject is what it signs or encrypts and `backing_service` is `self`. | `env` |
| `_PRIVATE_KEY_FILE` | Asymmetric private key material. | `file`, always |

`DATABASE_URL`, `SMTP_PASSWORD`, `STRIPE_WEBHOOK_SECRET`; never `PASSWORD`,
`DB_PASS`, `SECRET_KEY`. A bare kind names a password to nothing, and an
abbreviation is a kind a scanner does not recognise. The closed suffix set is
what lets a Dockerfile scanner (SE5), the `.env.example` check (SE4) and a
reviewer agree on which variables are secrets without the declaration in hand.

**An environment name is never the leading segment.** `PROD_DATABASE_URL` is
code that knows it is in production, the environment detection SC3 forbids
with a variable name for a disguise; per [factor III](https://12factor.net/config)
a deployment differs in the value under one name, never in which name is read.

### SE4. No secret value enters the repository, at any point in its history

**No file in the repository carries a secret value, in any commit, ever.**
The rule is about history rather than the working tree because a repository
is copied whole: every clone, fork, pipeline checkout and handover archive has
every commit, and a later removal removes it from none of them.

- **`.env` and `.env.*` are ignored by name**, with one exception:
  `.env.example` is committed and carries names and placeholders only — an
  empty value, `<a description of where the value comes from>`, or a
  development URL whose password component is such a placeholder (SE9).
- **A secret scanner runs on every push and blocks it**: one that matches
  known credential shapes and high-entropy strings, checks the placeholder
  grammar on `.env.example` lines whose names carry a secret kind (SE3), and
  refuses the push — in CI as a gate and, where the host offers it, as push
  protection. An allow-list entry is path-scoped with a reason, and the only
  reason admitted is SE9's development credential.
- **A secret found in history is leaked, not deleted.** The response is
  SE8's: rotate first. Rewriting history removes the value from one copy of a
  repository that has many and destroys the evidence of when it arrived.

### SE5. A secret is never in an image, a log line, a URL or an error body, and it is recognised by declaration

**Not in an image.** Nothing secret is present at build; the secret reaches
the process at start (SE1). A Dockerfile `ENV` or `ARG` naming a variable of
SE3's grammar is a finding whether or not a value follows, because a build
argument is recorded in the image's history and an environment default is a
layer ([`010-ci.md`](010-ci.md), Principles 8 and 15). A registry credential a
build needs is a build-time mount that leaves no layer, never a `COPY`.

**Not in a log line, and recognised by declaration.** The log emitter
redacts at the boundary, per
[`redaction.json`](../contracts/secrets/redaction.json), in three layers of
descending authority:

1. **By declared value.** At start the emitter is given the value of every
   declared secret (SE2). Any occurrence of one, in any string at any depth
   of the object about to be emitted — a message, a nested error, a stack, an
   argument vector, a query string — becomes `[redacted:<NAME>]`, so a reader
   learns which secret reached a log line without learning the secret. A
   connection string registers its password component as well as its whole
   value, because a driver quotes the password without the URL around it.
2. **By field name.** The closed list in `redaction.json` — the HTTP
   credential headers and the OAuth token fields — is replaced whole with
   `[redacted]`, because an inbound `Authorization` header or a caller's
   password is a secret the service could not have declared.
3. **By shape**, as a best-effort third layer only: a regex for a known key
   prefix, an entropy threshold. A backstop, never the mechanism.

The order is the rule. A redactor that consults shape *before* honouring the
declaration — filtering the declared set to values that look like secrets, to
avoid false positives — lets a four-word passphrase through and passes every
test whose secret looks like a key; the corpus carries that case as its
detector. A declared value is a secret because it is declared. This is SC2's
*name the key, never its value* with the mechanism stated.

**Not in a URL, and not in an error body.** A credential in a query string is
in the access log of every proxy, load balancer and browser on the path, none
of which redact it; credentials travel in headers or bodies, and there is no
signed-URL exception: [`026-blob-storage.md`](026-blob-storage.md) BS5 issues none. [`050-http.md`](050-http.md)
HA3's `detail` is never a secret, a connection string or a stack; layer 1's
redactor sits in front of the problem+json serializer as well as the log
emitter, because a driver's error message is the same string in both places.

### SE6. One credential per backing service per service, the least per image, and platform-issued before static

**One credential per backing service per service** (the Terms' *credential*).
A second key to the same provider is a second thing to rotate, a second thing
to leak, and a second answer to which credential this service *is*. The one
designed exception is the migration credential, a stronger role on the same
database ([`025-structured-data.md`](025-structured-data.md) SD3), declared
as its own subject.

**Each image carries the least its jobs declare** ([`035-workers.md`](035-workers.md)
WK8): the server, the pool and the jobs image carry the runtime credential;
the migrate image carries the migration credential and nothing else, and no
other image carries it; no image carries a credential to a backing service
another service owns, which is SD13's edge of a service seen from the
credential's side. The declaration's `images` field states this, and a secret
whose images include `migrate` includes nothing else, by schema.

**Platform-issued before static.** Where a backing service accepts an
identity the platform asserts — workload identity, an IAM role bound to the
process, OIDC federation from a pipeline to a cloud or a registry — the
service uses it, declared `issued_by: platform` with rotation mode `reissue`:
short-lived, never in a store a person reads, never in history because nobody
ever held it, scoped to the workload that presents it, renewed without anyone
acting. A static credential is the fallback for backing services that offer
nothing better — a mail relay, most payment providers, a database without
identity integration — declared `issued_by: static`, which obliges it to
carry an age (SE7). Static is second and not forbidden because a standard many
backing services cannot meet is a standard ignored there.

### SE7. Every secret has an owner and a maximum age, and rotation never needs a code change

**Every static secret declares who owns it and how old it may get.** The
default is ninety days and the ceiling is a year: a credential older than
that has outlived the people who knew where it was used. The platform's
secret store keeps the date of the last rotation, and the check is 057 JB8's
reasoning applied to an operational act: nothing errors when a rotation does
not happen, so two dates are compared, and a static secret rotated longer ago
than `max_age_days`, or never, is a finding.

**Rotation is a value change and a restart, never a code change.** A process
reads at start (SE1), so rotating means delivering the new value and
restarting, in one of two modes the declaration names:

| Mode | Sequence | When |
|---|---|---|
| `restart` | Change the value at the backing service; deliver it; restart the processes. | The backing service honours one credential at a time. There is a window of failed authentication between the change and the last restart, and the procedure states how long it is. |
| `dual_window` | Issue a second credential; deliver it; restart the processes; revoke the first. | The backing service honours two at once, as most do. No process ever holds an invalid credential — the same overlap 055 AM7 uses for webhook secrets. |

`reissue` is the platform's mode for platform-issued credentials and needs no
procedure of the service's. A static secret's procedure lives in the
repository's operations documentation at the path the declaration names, where
AGENTS.md rule 3 puts every procedure a human runs, and **is exercised by the
rotation itself**: the check that catches a stale secret catches an unrun one.

### SE8. A leak is answered by rotation first, investigation second, and an audit event, and never by rewriting history

**When a secret is known or suspected to have left its declared places, the
first act is to rotate it.** Not to find out how it got there, not to assess
whether anyone saw it: a leaked value's exposure ends only when it stops
working, and every minute spent investigating first is a minute it is live.
Rotate (or revoke, where nothing needs the replacement yet), then investigate,
then fix whatever put it where it was.

**The rotation is audited**, under [`080-audit.md`](080-audit.md), with the
secret named by declaration and never by value: `action` is a permission the
product declares, `secret.rotate` or `secret.revoke`, per AE3 — the `auth.*`
namespace is 080's and is not extended for this; `target` is `{ type:
"secret", id: <the declaration's id>, display: <the variable name> }`, which
is why the declaration mints an id; `actor` is the operator, or `system`
where the platform rotated automatically; `changes`, where present, carries
`{ field: "value", redacted: true }` and no value on either side (AE4) — a
rotation event carrying the new value is a leak with the best retention
policy in the system, and the corpus refuses it after the schema accepts it.

**History is not rewritten.** A secret in a commit is in every clone,
including the ones nobody here can see; rewriting the branch removes it from
one copy and destroys the record of when it arrived and who could have taken
it since. The value is dead once rotated; the commit is evidence.

**A repository leaving the portfolio triggers rotation of every secret it
ever referenced.** The declaration is that list, and every value ever
delivered against it, in any environment, is rotated at handover, because from
that day its history, pipelines and people are outside anyone here's reach.
The same holds for a repository arriving.

### SE9. Local development and the pipeline use their own secrets, and `.env.example` is the contract

**A developer's machine never holds a production secret, and neither does a
pipeline that is not deploying.** Development runs against development
backing services — a database, a cache, a mail sink, a mock provider —
started by the repository's own tooling on the developer's machine. The
credential to such a backing service is minted by the file that starts it, a
compose file setting the container's password and the service's connection
string in one place, and grants access to nothing that exists anywhere else.
That one file may carry that one literal, with the scanner's allow rule
scoped to it; the same literal anywhere else is SE4's finding.

**`.env.example` names every variable a process reads, secrets included,
with placeholders**, and the gate that reads the declaration reads it too: a
declared secret missing from it, or a variable in it missing from the
declaration, is a finding. A developer copies it to `.env`, which is ignored
(SE4), fills the placeholders, and runs the one-shot as 035 WK4 states,
`--env-file .env`. A provider's sandbox key is a personal value, never shared.

**Pipeline credentials are the CI system's**, held in its secret store,
scoped per repository and per environment, granted under the least-privilege
`permissions:` [`010-ci.md`](010-ci.md) requires, and preferred as OIDC
federation to a cloud or a registry over a static key (SE6). A pipeline never
prints one, never writes one to an artifact, and never passes one into an
image build except as a build-time mount (SE5). A run whose context reads a
different or empty store — a fork, a dependency bot — fails for that reason,
visibly, in a job that only uploads or publishes, which is the split 010 draws.

### SE10. The store renders into the environment through the runtime's own mechanism, and there is one store per platform

SE1 says a process sees a variable and never fetches. This rule says how the
variable gets there, because that is where "the platform delivers it" has
been left to each repository to discover. There is no industry standard for
the step between a secret store and a process's environment; there is an
established set of mechanism *classes*, one per runtime, and this rule pins
the class and the properties any implementation of it must have, so that a
repository does not invent a fourth.

**Which implementations meet those properties today is
[`solutions/032-secrets.md`](../solutions/032-secrets.md)'s**, because the
products in this space are renamed, acquired and superseded on a timescale
this document is not written to track. The rule is the class and the test
below; the register is the survey, dated.

**One secret store per platform, chosen by the platform and not by the
repository.** A store is a running service with three properties the
declaration (SE2) relies on: every value is versioned, so a rotation is a
new version and the previous one is still there for the `dual_window` mode
(SE7); every read and write is in an access log that names the principal, so
a leak investigation (SE8) has somewhere to look; and access is scoped per
environment and per service, so the production value is readable by the
production workload and by the named owner, and by nothing else. The
platform's own manager meets this, whether it is the hosting provider's, a
hosted manager or a self-hosted one; a repository does not pick a different
one because its author prefers it, for the reason
[`000-platform.md`](000-platform.md) PC1 gives. A file of encrypted values
committed to the repository is **not** a store: it has no access log, it
puts ciphertext into a history that leaves the portfolio at handover under a
key nobody there controls, and the day the key is compromised every version
ever committed is readable at once.

**The store renders into the environment by the runtime's mechanism, on the
platform's side of the variable, and a repository ships only the mapping.**
The mapping is a deployment manifest naming, per declared secret, the store
path it comes from and the form it takes — never a value — committed beside
the deployment configuration, one per environment, so the declaration's
names are what is checked against it (SE2):

| Runtime | Mechanism class | `env` | `file` | Notes |
|---|---|---|---|---|
| An orchestrator with a native secret object | An operator that syncs the store into the orchestrator's native secret objects, which the workload consumes as variables or a projected volume; or a driver that mounts the store directly as files, syncing to a native object where variables are also needed. | The orchestrator's per-variable reference to the synced object | A projected volume at the declared `path`, rotated in place by the driver, which is what `reissue` needs | A native secret object written by hand or by a pipeline is a copy nobody rotates; the operator owns it. Sealed or encrypted secrets in the repository are the file-of-ciphertext above. |
| Managed container services | The service's task or revision definition references the store entry by identifier and the platform injects it at start. | Native | Native where the platform mounts secrets as files; otherwise the process receives the material in `env` and writes it to its declared path itself at start, before serving | Every major provider's container service does this for its own secret manager; a hosted manager reaches it by syncing into that native store. |
| Virtual machines and init-system units | An agent renders the store into the unit's environment file or its credential directory before the unit starts, under the machine's platform identity. | An environment file rendered by the agent, mode `0600`, owned by the service user | The init system's credential directory, with the declared path a symlink to it or the path itself | The agent runs as its own unit with its own credential to the store; the service unit has none. |
| The developer's machine | `.env` per SE9, filled from `.env.example`. | `--env-file .env` | A path under the repository's ignored directory | Never a production value; a hosted manager's per-developer development configuration is admitted as the source of that `.env` and is still not the process's client. |
| The pipeline | The CI system's own secret store, per SE9, preferring OIDC federation to the cloud. | Native | A job step writes the material to the runner's temporary directory and removes it | The pipeline's secrets are for building and publishing; a deploying job hands the platform a reference, never a value. |

**What every mechanism in the table has in common, and what disqualifies
one that is not in it:** the process's environment is complete before the
process starts (SE1); the component that holds the store credential is the
platform's, runs with its own identity and is not the application process;
rotation is a new version in the store picked up by re-render and restart
(`restart`, `dual_window`) or in place (`reissue`) with no code change (SE7);
and the store's access log records the platform component, never an
application process, reading a value. A mechanism in which the application
holds a store credential, fetches at start, or caches values on disk it
manages, is SE1's vendor-SDK case with an operator's name on it.

**Rotation runs through the store.** SE7's modes describe the backing
service's side; on the delivery side, a rotation is: write the new version
to the store, let the mechanism render it — the operator's refresh interval,
the driver's rotation poll, the agent's next run, each declared beside the
mapping — then restart or not as the mode says. The procedure a human runs
is in the repository's operations documentation, per the agent standard's
rule that a procedure not in the docs does not exist, and it names the store
path and the mechanism, never the value.

## What is a secret

The test is one question: *does disclosing this value grant access, or let
someone forge something this service trusts?*

| Value | Secret? | Kind and delivery | Why |
|---|---|---|---|
| Database connection string with a password | yes | `connection_string`, `env` | The password inside grants access; the whole string is declared and redacted, and the password component with it. |
| Migration connection string | yes | `connection_string`, `env`, `migrate` only | A stronger role; a second credential by design (SD3). |
| The proxy's identity-token signing key (060 AU2) | yes | `private_key`, `file` | Forges every identity the backend trusts. The backend holds the public key or a JWKS URL, which is configuration. |
| Webhook signing secret, either direction (055 AM7, AM8) | yes | `secret`, `env` | Forges deliveries or verifies them. |
| Session cookie signing key; field-level encryption key | yes | `signing_key` / `encryption_key`, `env`, `self` | Forges sessions; reads what it protects. |
| A CA bundle, a TLS certificate, an OIDC client id | no | configuration | Public material. The private key beside a certificate and the client secret beside a client id are secrets. |

## The artifacts

Per PC3, under [`contracts/secrets/`](../contracts/secrets/):

- **`secret-declaration.schema.json`** — SE2's declaration, with SE3's name
  grammar as a `$defs` pattern and the conditional rules prose states: suffix
  agrees with kind, a private key is a file, a file names its path, a static
  secret carries an age and a static rotation mode, a platform-issued one is
  `reissue`, the migrate image shares no secret. The id `$ref`s the
  identifiers contract.
- **`redaction.json`** — SE5's mechanism as data: the two marker forms, the
  substring rule and connection-string components for declared values, and
  the closed list of field names redacted by name.
- **`corpus.json`** — six parts. `names`: variables the grammar accepts and
  refuses. `declarations`: declarations the schema and the runner's two
  cross-entry checks accept and reject, each rejection naming its rule.
  `redaction`: declared secrets and an object about to be emitted, with the
  object that must leave the process, including the passphrase that separates
  a declaration-honouring redactor from a shape-filtering one.
  `forbidden_locations`: Dockerfile lines, tracked paths, `.env.example`
  lines, source, compose files and history, each with its finding and
  response, including the low-entropy value that separates a
  placeholder-grammar scanner from an entropy one. `rotation`: age policy
  against a last rotation. `leak_response`: audit events the audit schema and
  SE8's checks accept and refuse.

## Enforcement

Every SE rule lands **review only** and is registered in
[`999-enforcement.md`](999-enforcement.md) with its gate named. Mechanically
checkable, and first to move to a gate: the declaration's validity and its two
cross-entry counts (SE2, SE6); the name grammar over every variable a process
reads (SE3); the scanner on every push and the `.env` ignore rule (SE4); a
Dockerfile `ENV`/`ARG` line naming a secret variable (SE5, a grep with no
false positives once SE3 holds); the redaction corpus against a service's
emitter, black-box, by feeding it a declared value and reading stdout (SE5);
the image set against `images` (SE6); the freshness comparison (SE7); the
audit event's shape (SE8). Review questions, said so in the ledger row: that
a process fetches nothing in code (SE1, a call-graph fact PC4 keeps a gate
out of), that a subject names a real backing service (SE3), that rotate came
before investigate (SE8), that a development credential grants nothing
outside the developer's machine (SE9), and that the mapping names a store
path and a mechanism from the table and no value (SE10 — the presence of a
value is SE4's scanner; the mechanism's class is a review question).

## Decisions

- **The variable is the contract; the store is the platform's** (2026-09-02).
  A vault client in application code makes the store a runtime dependency of
  every process, needs an undelivered credential to the store, and adds a
  startup gate. Factor III answers delivery; the store renders into it.
- **One store per platform; the runtime's own mechanism renders it; the
  repository ships the mapping and never the value** (2026-09-03). The step
  from store to environment had been left as "the platform delivers it",
  which each repository resolved differently. There is no standard for it,
  so the rule pins the class per runtime — operator or CSI driver on
  Kubernetes, native injection on managed container services, an agent
  rendering `EnvironmentFile=` or `LoadCredential=` under systemd — and the
  four properties any mechanism must have. Encrypted files in the repository
  are refused because they are a history of ciphertext leaving the portfolio
  at handover and have no access log. Examples are named because a class
  with no example is a class each reader guesses at; the class is what binds.
- **A secret is declared, with an id and a `<SUBJECT>_<KIND>` name**
  (2026-09-02). Without a declaration there is no list to redact by, rotate
  from, check an image against, or hand over. The id gives a rotation's audit
  event a public id for its target, as 080 AE2 requires, that survives a
  rename. The closed suffix set is the only grammar a scanner, an
  `.env.example` check and a reviewer can all apply without the declaration
  in hand; environment prefixes are refused as environment detection.
- **Recognition by declaration, not by shape** (2026-09-02). A shape-based
  redactor is a list of the secrets someone has already seen leak; the
  declaration is the list of the secrets this service has, the only list that
  includes the passphrase-shaped one. Shape stays as a third layer because it
  costs nothing and catches a caller's key the service never declared.
- **Ninety days default, one year ceiling, static only** (2026-09-02). A
  number is required because "rotate regularly" is a preference; ninety days
  keeps the procedure exercised while its authors are present, and a year is
  the point past which nobody can say where a credential is used. The
  platform renews its own credentials on a shorter schedule than either.
- **Rotate first, investigate second; history is never rewritten**
  (2026-09-02). Exposure ends when the value stops working and not before;
  investigation informs the fix, not the response. A rewrite removes the
  value from the least dangerous copy and destroys the record of the window
  in which it was exposed.
- **A development credential minted by the compose file is admitted there**
  (2026-09-02). It grants access to a container that exists only while that
  file runs it; forbidding it makes every developer invent one and produces
  `.env.example` files with values in them. The admission is scoped to that
  file and nowhere else.
- **Handover rotates everything** (2026-09-02). The repository's history,
  pipelines and people leave the portfolio's reach on that day, and any value
  ever delivered against its declaration may be in that history. The
  declaration makes the list complete rather than remembered.

## Out of scope, deliberately

- **Response headers, TLS posture, image digest pinning, dependency
  scanning.** The [`085-security-baseline.md`](085-security-baseline.md)'s, which points here.
- **The identity tier's key material and how verifiers learn of a rotation.**
  [`060-auth.md`](060-auth.md)'s; here it is a file-delivered private key.
- **Backup encryption keys and the backup credential.** The [`028-backup-and-recovery.md`](028-backup-and-recovery.md)'s; secrets under
  every rule here, held by the backup system and never by a service image.
- **What a browser may hold, and which algorithms are used.**
  [`090-web-client.md`](090-web-client.md) WC1 and WC2 for the first; the
  backing service or the protocol for the second.
