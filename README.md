# aurum-alpha/workflows

The definition of how Aurum Alpha builds software — the standards themselves,
and the shared CI infrastructure that implements them: reusable workflows,
composite actions, conformance checkers and shared configuration.

Start with **[STANDARDS.md](STANDARDS.md)** — the charter. It says what a
standard is here, what makes one binding, and indexes the rest.

| | |
|---|---|
| [STANDARDS.md](STANDARDS.md) | The charter: scope, the enforcement law, the tiers, how a standard is added |
| [AGENTS.md](AGENTS.md) | How coding agents work in an Aurum Alpha repository |
| [standards/000-platform.md](standards/000-platform.md) | The platform contract: application-layer opinions as protocols and interface specs |
| [standards/010-ci.md](standards/010-ci.md) | Pipeline doctrine, the shared job catalog, build and release |
| [standards/020-identifiers.md](standards/020-identifiers.md) | Identifiers and primitive representations: ids, timestamps, dates, money |
| [standards/030-service.md](standards/030-service.md) | The service contract: health, logging, config, shutdown, provenance |
| [standards/040-observability.md](standards/040-observability.md) | Observability transport and context propagation: trace context, id vocabulary, OTLP |
| [standards/050-http.md](standards/050-http.md) | Service interfaces: protocol selection, OpenAPI, problem+json errors, pagination, idempotency, wire naming |
| [standards/060-auth.md](standards/060-auth.md) | Authentication: identity tier, identity token, linkage, provisioning, sessions, topologies |
| [standards/070-rbac.md](standards/070-rbac.md) | Authorization: permissions, roles, grants, scope containment, the check operation |
| [standards/080-audit.md](standards/080-audit.md) | Audit events: actor and target, the action vocabulary, what must emit, retention and erasure |
| [standards/090-web-client.md](standards/090-web-client.md) | The web client: browser auth, runtime config, the API client, presentation and i18n, error reports |
| [standards/999-enforcement.md](standards/999-enforcement.md) | Every rule, its gate, and the tier it actually reaches |

Consult the relevant standard before any change it governs, in any repository.

## Rule ids — what `PC1` or `IP4` means

Every rule in every standard has a short id: the CI standard's principles are
bare numbers, and each other standard carries a mnemonic prefix. The id names a
section in the standard's own document (the rule and its reasoning) and a row
in [`standards/999-enforcement.md`](standards/999-enforcement.md) (the mechanism that
enforces it and the tier it actually holds). This table is the prefix map;
the ledger, not this table, is the register of the rules themselves.

| Prefix | Standard | Rules govern |
|---|---|---|
| PC | [`standards/000-platform.md`](standards/000-platform.md) | The platform contract doctrine: opinions as protocols and interface specs, never tools |
| 1–18 | [`standards/010-ci.md`](standards/010-ci.md) | Pipelines: what a job may be, how versions pin, what may publish |
| IP | [`standards/020-identifiers.md`](standards/020-identifiers.md) | Identifiers and primitives: public vs internal ids, id formats, timestamps, dates, money |
| SC | [`standards/030-service.md`](standards/030-service.md) | What a running service exposes: health and readiness, log lines, config, shutdown, provenance |
| OC | [`standards/040-observability.md`](standards/040-observability.md) | Context propagation and telemetry: W3C trace context, the id vocabulary, OTLP |
| HA | [`standards/050-http.md`](standards/050-http.md) | Service interfaces: which protocol, then the HTTP surface — description, error envelope, pagination, versioning, idempotency, retries |
| AU | [`standards/060-auth.md`](standards/060-auth.md) | Authentication: which process is the OAuth client, what identity crosses to a backend, how a user is created and how a session ends |
| RB | [`standards/070-rbac.md`](standards/070-rbac.md) | Authorization: what a permission is, how a grant is scoped, and what `check` must decide |
| AE | [`standards/080-audit.md`](standards/080-audit.md) | Audit events: what a record of a consequential act contains, what must produce one, how long it is kept |
| WC | [`standards/090-web-client.md`](standards/090-web-client.md) | Code running in a browser: authentication pattern, runtime configuration, the API client module, presentation and i18n, error reporting |
| A | [`AGENTS.md`](AGENTS.md) | How coding agents work: one guidance source, the work queue, the approval gate |

Each new capability standard from the platform contract's roster adds its own
prefix here as it lands.

## What is here

- `.github/workflows/job-*.yml` — the shared job catalog. One reusable workflow
  per capability, consumed by every repository that has that capability.
- `tools/check-*` — the conformance checkers. Each runs both inside a
  repository's own CI and as a portfolio-wide sweep, from one source.
- `config/`, `setup/` — shared configuration and composite actions.
- `dependency-versions.json` — the package versions every adopting repository
  is held to: the package manager, the dev/build toolchain, and the handful of
  runtime packages that have converged. It names versions, never repositories.

## Where work is tracked

Gaps in the standards or the catalog are issues **in this repository**. A
repository that does not yet meet a standard has work in **its own** tracker —
see the charter's "Non-compliance is tracked where the code is".
