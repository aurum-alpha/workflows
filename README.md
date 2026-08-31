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
| [standards/ci.md](standards/ci.md) | Pipeline doctrine, the shared job catalog, build and release |
| [standards/platform.md](standards/platform.md) | The platform contract: application-layer opinions as protocols and interface specs |
| [standards/identifiers.md](standards/identifiers.md) | Identifiers and primitive representations: ids, timestamps, dates, money |
| [standards/observability.md](standards/observability.md) | Observability transport and context propagation: trace context, id vocabulary, OTLP |
| [standards/enforcement.md](standards/enforcement.md) | Every rule, its gate, and the tier it actually reaches |

Consult the relevant standard before any change it governs, in any repository.

## Rule ids — what `PC1` or `IP4` means

Every rule in every standard has a short id: the CI standard's principles are
bare numbers, and each other standard carries a mnemonic prefix. The id names a
section in the standard's own document (the rule and its reasoning) and a row
in [`standards/enforcement.md`](standards/enforcement.md) (the mechanism that
enforces it and the tier it actually holds). This table is the prefix map;
the ledger, not this table, is the register of the rules themselves.

| Prefix | Standard | Rules govern |
|---|---|---|
| 1–18 | [`standards/ci.md`](standards/ci.md) | Pipelines: what a job may be, how versions pin, what may publish |
| A | [`AGENTS.md`](AGENTS.md) | How coding agents work: one guidance source, the work queue, the approval gate |
| PC | [`standards/platform.md`](standards/platform.md) | The platform contract doctrine: opinions as protocols and interface specs, never tools |
| IP | [`standards/identifiers.md`](standards/identifiers.md) | Identifiers and primitives: public vs internal ids, id formats, timestamps, dates, money |
| OC | [`standards/observability.md`](standards/observability.md) | Context propagation and telemetry: W3C trace context, the id vocabulary, OTLP |

Each new capability standard from the platform contract's roster adds its own
prefix here as it lands.

## What is here

- `.github/workflows/job-*.yml` — the shared job catalog. One reusable workflow
  per capability, consumed by every repository that has that capability.
- `tools/check-*` — the conformance checkers. Each runs both inside a
  repository's own CI and as a fleet sweep, from one source.
- `config/`, `setup/` — shared configuration and composite actions.
- `fleet-versions.json` — toolchain versions the fleet standardizes on.

## Where work is tracked

Gaps in the standards or the catalog are issues **in this repository**. A
repository that does not yet meet a standard has work in **its own** tracker —
see the charter's "Non-compliance is tracked where the code is".
