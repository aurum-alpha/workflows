# Secrets: how a secret reaches a process, what never enters a repository, and what happens when one leaks

## Why this exists

Every process holds at least one secret. A secret is the one input a process
cannot be given the way it is given everything else. Code is built once and
copied; a secret must reach exactly the processes that need it and no
artifact that outlives them. Every cheap answer fails on that asymmetry, and
fails quietly. A secret in the wrong place does nothing visibly wrong until
someone else reads it. A repository built for a client is handed
over, so anything in its history at handover is a leak nobody here can
rotate afterwards (SE8).

This standard answers once how a secret arrives, what it is called, and
where it is declared and forbidden. It answers how a secret is recognised at
the log boundary, how old it can get, and what a leak response consists of.
What remains for a repository is the list of secrets its service needs,
which is its domain.

## The rules

### SE1. A secret reaches a process as configuration does, and never through a vendor SDK

**A secret reaches a process in its environment, delivered by the platform
before the process starts; application code never fetches one**. Delivery is
[factor III](https://12factor.net/config), unchanged. The OCI runtime offers
exactly two channels into a container that exist before the process does,
environment variables and mounted files. The declaration (SE2) says which
each secret takes:

| Delivery | The variable holds | Used for |
|---|---|---|
| `env` | The value. | The default: a password, a token, an API key, a connection string, a symmetric key as base64. Anything that is one line. |
| `file` | An absolute path, identical in every environment, at which the platform has mounted the material. The variable ends in `_FILE`. | A private key or any multi-line PEM, which half the tooling that reads environments mangles and the other half prints; a token the platform projects and renews in place. |

A process reads its secrets at start, with the rest of its configuration
(030 SC3). Where a `file` secret's rotation mode is `reissue` it re-reads the
file on each use, because the platform is renewing it underneath. A declared
secret absent or invalid at start is a missing required variable under SC3.
The server reports `fail` on `/readyz` naming it and serves no traffic; a
one-shot exits `78` (035 WK4).

**No vendor SDK, no vault client, no fetch**. The platform's secret store is
where values live at rest; what a process sees is the variable. Fetching in
application code makes the store's client a runtime dependency of every
process (PC1). It needs a credential to the store with no delivery rule, and
adds a network call before serving that SC6 refuses. It tells the code which
store it is in front of, which is environment detection under SC3. A secrets
operator or a volume driver that renders the store into the environment is
the platform's mechanism, on the other side of the variable.

### SE2. Every secret is declared, and the declaration is the source of truth

**A service carries a declaration of every secret any of its processes reads,
in the repository beside its deployables, validated against
[`secret-declaration.schema.json`](../contracts/secrets/secret-declaration.schema.json)**.
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

Four things follow mechanically. An undeclared secret in a process's
environment is a finding, because nothing tested reads it. A declared secret
absent at start blocks serving (SE1). The declared values are what the
redactor recognises (SE5). The declared images are what the image set is
checked against (SE6). The declaration is a committed file, so it carries no
value, and its property set is closed so a `value` field cannot be added.

### SE3. A secret's name states its subject and its kind

**The variable is `<SUBJECT>_<KIND>`**. The subject is the backing service's
logical name in `SCREAMING_SNAKE_CASE`, identical in every environment. The
kind is one of a closed set, and comes last:

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
reviewer agree. They agree on which variables are secrets without the
declaration in hand.

**An environment name is never the leading segment**. `PROD_DATABASE_URL` is
code that knows it is in production. That is the environment detection SC3
forbids, with a variable name for a disguise. Per
[factor III](https://12factor.net/config) a deployment differs in the value
under one name, never in which name is read.

### SE4. No secret value enters the repository, at any point in its history

**No file in the repository carries a secret value, in any commit, ever**.
The rule is about history rather than the working tree because a repository
is copied whole. Every clone, fork, pipeline checkout and handover archive
has every commit, and a later removal removes it from none of them.

- **`.env` and `.env.*` are ignored by name**, with one exception.
  `.env.example` is committed and carries names and placeholders only. A
  placeholder is an empty value,
  `<a description of where the value comes from>`, or a development URL
  whose password component is such a placeholder (SE9).
- **A secret scanner runs on every push and blocks it**. It matches known
  credential shapes and high-entropy strings. It checks the placeholder
  grammar on `.env.example` lines whose names carry a secret kind (SE3). It
  refuses the push, in CI as a gate and, where the host offers it, as push
  protection. An allow-list entry is path-scoped with a reason, and the only
  reason admitted is SE9's development credential.
- **A secret found in history is leaked, not deleted**. The response is
  SE8's: rotate first. Rewriting history removes the value from one copy of a
  repository that has many and destroys the evidence of when it arrived.

### SE5. A secret is never in an image, a log line, a URL or an error body, and it is recognised by declaration

**Not in an image**. Nothing secret is present at build; the secret reaches
the process at start (SE1). A Dockerfile `ENV` or `ARG` naming a variable of
SE3's grammar is a finding whether or not a value follows. A build argument
is recorded in the image's history, and an environment default is a layer
([`010-ci.md`](010-ci.md), Principles 8 and 15). A registry credential a
build needs is a build-time mount that leaves no layer, never a `COPY`.

**Not in a log line, and recognised by declaration**. The log emitter
redacts at the boundary, per
[`redaction.json`](../contracts/secrets/redaction.json), in three layers of
descending authority:

1. **By declared value**. At start the emitter is given the value of every
   declared secret (SE2). Any occurrence of one, in any string at any depth
   of the object about to be emitted, becomes `[redacted:<NAME>]`. That
   covers a message, a nested error, a stack, an argument vector, and a
   query string. So a reader learns which secret reached a log line without
   learning the secret. A connection string registers its password component
   as well as its whole value, because a driver quotes the password without
   the URL around it.
2. **By field name**. The closed list in `redaction.json` is replaced whole
   with `[redacted]`. It holds the credential headers of
   [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) and
   [RFC 6265](https://www.rfc-editor.org/rfc/rfc6265) and the token fields
   of [RFC 6749](https://www.rfc-editor.org/rfc/rfc6749). An inbound
   `Authorization` header or a caller's password is a secret the service
   could not have declared.
3. **By shape**, as a best-effort third layer only: a regex for a known key
   prefix, an entropy threshold. A backstop, never the mechanism.

The order is the rule. A redactor that consults shape *before* honouring the
declaration filters the declared set to values that look like secrets, to
avoid false positives. Such a redactor lets a four-word passphrase through
and passes every test whose secret looks like a key. The corpus carries that
case as its detector. A declared value is a secret because it is declared.
This is SC2's *name the key, never its value* with the mechanism stated.

**Not in a URL, and not in an error body**. A credential in a query string
is in the access log of every proxy, load balancer and browser on the path.
None of them redact it. Credentials travel in headers or bodies, and there
is no signed-URL exception: [`026-blob-storage.md`](026-blob-storage.md) BS5
issues none.

[`050-http.md`](050-http.md) HA3's `detail` is never a secret, a connection
string or a stack. Layer 1's redactor sits in front of the problem+json
serializer as well as the log emitter. A driver's error message is the same
string in both places.

### SE6. One credential per backing service per service, the least per image, and platform-issued before static

**One credential per backing service per service** (the Terms' *credential*).
A second key to the same provider is a second thing to rotate and a second
thing to leak. It is a second answer to which credential this service *is*.
The one designed exception is the migration credential, a stronger role on
the same database ([`025-structured-data.md`](025-structured-data.md) SD3),
declared as its own subject.

**Each image carries the least its jobs declare** ([`035-workers.md`](035-workers.md)
WK8). The server, the pool and the jobs image carry the runtime credential.
The migrate image carries the migration credential and nothing else, and no
other image carries it. No image carries a credential to a backing service
another service owns, which is SD13's edge of a service seen from the
credential's side. The declaration's `images` field states this, and a secret
whose images include `migrate` includes nothing else, by schema.

**Platform-issued before static**. Where a backing service accepts an
identity the platform asserts, the service uses it, declared
`issued_by: platform` with rotation mode `reissue`. Such an identity is
workload identity, an IAM role bound to the process, or OIDC federation from
a pipeline to a cloud or a registry. It is short-lived, never in a store a
person reads, and never in history because nobody ever held it. It is scoped
to the workload that presents it, and renewed without anyone acting.

A static credential is the fallback for backing services that offer nothing
better: a mail relay, most payment providers, a database without identity
integration. It is declared `issued_by: static`, which obliges it to carry
an age (SE7). Static is second and not forbidden because a standard many
backing services cannot meet is a standard ignored there.

### SE7. Every secret has an owner and a maximum age, and rotation never needs a code change

**Every static secret declares who owns it and how old it can get**. The
default is ninety days and the ceiling is a year. A credential older than
that has outlived the people who knew where it was used. The platform's
secret store keeps the date of the last rotation. The check is 057 JB8's
reasoning applied to an operational act: nothing errors when a rotation does
not happen, so two dates are compared. A static secret rotated longer ago
than `max_age_days`, or never, is a finding.

**Rotation is a value change and a restart, never a code change**. A process
reads at start (SE1), so rotating means delivering the new value and
restarting, in one of two modes the declaration names:

| Mode | Sequence | When |
|---|---|---|
| `restart` | Change the value at the backing service; deliver it; restart the processes. | The backing service honours one credential at a time. There is a window of failed authentication between the change and the last restart, and the procedure states how long it is. |
| `dual_window` | Issue a second credential; deliver it; restart the processes; revoke the first. | The backing service honours two at once, as most do. No process ever holds an invalid credential. It is the same overlap 055 AM7 uses for webhook secrets. |

`reissue` is the platform's mode for platform-issued credentials and needs no
procedure of the service's. A static secret's procedure lives in the
repository's operations documentation at the path the declaration names.
That is where AGENTS.md rule 3 puts every procedure a human runs. The
procedure **is exercised by the rotation itself**: the check that catches a
stale secret catches an unrun one.

### SE8. A leak is answered by rotation first, investigation second, and an audit event, and never by rewriting history

**When a secret is known or suspected to have left its declared places, the
first act is to rotate it**. Not to find out how it got there, and not to
assess whether anyone saw it. A leaked value's exposure ends only when it
stops working, and every minute spent investigating first is a minute it is
live. Rotate (or revoke, where nothing needs the replacement yet), then
investigate, then fix whatever put it where it was.

**The rotation is audited**, under [`080-audit.md`](080-audit.md), with the
secret named by declaration and never by value. `action` is a permission the
product declares, `secret.rotate` or `secret.revoke`, per AE3. The `auth.*`
namespace is 080's and is not extended for this. `target` is `{ type:
"secret", id: <the declaration's id>, display: <the variable name> }`, which
is why the declaration mints an id. `actor` is the operator, or `system`
where the platform rotated automatically. `changes`, where present, carries
`{ field: "value", redacted: true }` and no value on either side (AE4).

A rotation event carrying the new value is a leak with the best retention
policy in the system. The corpus refuses it after the schema accepts it.

**History is not rewritten**. A secret in a commit is in every clone,
including the ones nobody here can see. Rewriting the branch removes it from
one copy and destroys the record of when it arrived and who could have taken
it since. The value is dead once rotated; the commit is evidence.

**A repository leaving this organisation triggers rotation of every secret
it ever referenced**. The declaration is that list. Every value ever delivered
against it, in any environment, is rotated at handover. From that day its
history, pipelines and people are outside anyone here's reach. The same
holds for a repository arriving.

### SE9. Local development and the pipeline use their own secrets, and `.env.example` is the contract

**A developer's machine never holds a production secret, and neither does a
pipeline that is not deploying**. Development runs against development
backing services: a database, a cache, a mail sink, a mock provider. The
repository's own tooling starts them on the developer's machine.

The file that starts such a backing service mints its credential. That is a
compose file setting the container's password and the service's connection
string in one place. The credential grants access to nothing that exists
anywhere else. That one file is permitted to carry that one literal, with
the scanner's allow rule scoped to it. The same literal anywhere else is
SE4's finding.

**`.env.example` names every variable a process reads, secrets included,
with placeholders**, and the gate that reads the declaration reads it too. A
declared secret missing from it, or a variable in it missing from the
declaration, is a finding. A developer copies it to `.env`, which is ignored
(SE4), fills the placeholders, and runs the one-shot as 035 WK4 states,
`--env-file .env`. A provider's sandbox key is a personal value, never
shared.

**Pipeline credentials are the CI system's**, held in its secret store,
scoped per repository and per environment. They are granted under the
least-privilege `permissions:` [`010-ci.md`](010-ci.md) requires. OIDC
federation to a cloud or a registry is preferred over a static key (SE6).

A pipeline never prints one and never writes one to an artifact. It never
passes one into an image build except as a build-time mount (SE5). A run
whose context reads a different or empty store (a fork, a dependency bot)
fails for that reason, visibly. It fails in a job that only uploads or
publishes, which is the split 010 draws.

### SE10. The store renders into the environment through the runtime's own mechanism, and there is one store per platform

SE1 says a process sees a variable and never fetches. This rule pins how the
variable gets there: the class of mechanism per runtime, and the properties
any implementation of it must have. A repository then does not invent a
fourth.

**One secret store per platform, chosen by the platform and not by the
repository**. A store is a running service with three properties the
declaration (SE2) relies on. Every value is versioned, so a rotation is a
new version and the previous one is still there for the `dual_window` mode
(SE7). Every read and write is in an access log that names the principal, so
a leak investigation (SE8) has somewhere to look. Access is scoped per
environment and per service. So the production value is readable by the
production workload and by the named owner, and by nothing else.

The platform's own manager meets this, whether it is the hosting provider's,
a hosted manager or a self-hosted one. A repository does not pick a different
one because its author prefers it, for the reason
[`000-platform.md`](000-platform.md) PC1 gives. Which implementations meet
the properties is [`solutions/032-secrets.md`](../solutions/032-secrets.md)'s.

**A file of encrypted values committed to the repository is not a store, and
there is no exception**. That covers values encrypted in place inside a
committed configuration file, and the sealed form whose private key lives in
a cluster controller. Three reasons, any one sufficient:

1. **A repository's history is permanent, and it leaves**. Deleting the file
   removes it from no clone and no fork. A repository built for a client
   leaves at handover carrying every version of every value it ever held.
   The day the key is compromised, the compromise is retroactive across the
   whole history. A store has old versions that can be destroyed.
2. **It keeps the delivery step and adds a second path beside it**. The
   ciphertext is inert without a key, and that key reaches the live system by
   the mechanism this rule already specifies. What it buys is one delivery
   instead of many, at the price of a master key whose compromise is total.
   A second delivery mechanism is the second answer
   [`010-ci.md`](010-ci.md) Principle 12 and PC1 refuse.
3. **A required value is never in the repository** (SC3). A secret is
   required by definition, because a process without it does not serve. So
   no form of its value belongs in code, encrypted or otherwise. The
   repository ships the mapping below and nothing else.

The sealed form fails the same three and also SE7: rotation becomes a commit
indistinguishable from an edit, with nothing noticing one that never
happened.

**The store renders into the environment by the runtime's mechanism, on the
platform's side of the variable, and a repository ships only the mapping**.
The mapping is a deployment manifest naming, per declared secret, the store
path it comes from and the form it takes, never a value. It is committed
beside the deployment configuration, one per environment, so the
declaration's names are what is checked against it (SE2):

| Runtime | Mechanism class | `env` | `file` | Notes |
|---|---|---|---|---|
| An orchestrator with a native secret object | An operator that syncs the store into the orchestrator's native secret objects, which the workload consumes as variables or a projected volume; or a driver that mounts the store directly as files, syncing to a native object where variables are also needed. | The orchestrator's per-variable reference to the synced object | A projected volume at the declared `path`, rotated in place by the driver, which is what `reissue` needs | A native secret object written by hand or by a pipeline is a copy nobody rotates; the operator owns it. Sealed or encrypted secrets in the repository are the file-of-ciphertext above. |
| Managed container services | The service's task or revision definition references the store entry by identifier and the platform injects it at start. | Native | Native where the platform mounts secrets as files; otherwise the process receives the material in `env` and writes it to its declared path itself at start, before serving | Every major provider's container service does this for its own secret manager; a hosted manager reaches it by syncing into that native store. |
| Virtual machines and init-system units | An agent renders the store into the unit's environment file or its credential directory before the unit starts, under the machine's platform identity. | An environment file rendered by the agent, mode `0600`, owned by the service user | The init system's credential directory, with the declared path a symlink to it or the path itself | The agent runs as its own unit with its own credential to the store; the service unit has none. |
| The developer's machine | `.env` per SE9, filled from `.env.example`. | `--env-file .env` | A path under the repository's ignored directory | Never a production value; a hosted manager's per-developer development configuration is admitted as the source of that `.env` and is still not the process's client. |
| The pipeline | The CI system's own secret store, per SE9, preferring OIDC federation to the cloud. | Native | A job step writes the material to the runner's temporary directory and removes it | The pipeline's secrets are for building and publishing; a deploying job hands the platform a reference, never a value. |

**What every mechanism in the table has in common, and what disqualifies
one that is not in it**: four properties. The process's environment is
complete before the process starts (SE1). The component that holds the
store credential is the platform's, runs with its own identity and is not
the application process. Rotation is a new version in the store, picked up
by re-render and restart (`restart`, `dual_window`) or in place (`reissue`),
with no code change (SE7). The store's access log records the platform
component, never an application process, reading a value.

A mechanism in which the application holds a store credential, fetches at
start, or caches values on disk it manages is not in it. That is SE1's
vendor-SDK case with an operator's name on it.

**Rotation runs through the store**: write the new version, let the mechanism
render it, then restart or not as SE7's mode says. The procedure a human runs
is in the repository's operations documentation, and names the store path
and the mechanism, never the value.

## What is a secret

The test is the Terms' ([`000-platform.md`](000-platform.md#terms),
*Secret*): does disclosing this value grant access, or let someone forge
something this service trusts?

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

- **`secret-declaration.schema.json`**: SE2's declaration, with SE3's name
  grammar as a `$defs` pattern and the conditional rules prose states.
- **`redaction.json`**: SE5's mechanism as data: the marker forms, the
  substring and connection-string rules for declared values, and the closed
  field-name list.
- **`corpus.json`**: six parts, `names`, `declarations`, `redaction`,
  `forbidden_locations`, `rotation` and `leak_response`.
