# Developer commands

## Why this exists

A gate is reachable two ways: through the pipeline, and through a person's
terminal. The catalog settles the first. This standard settles the second, so
that the command a person types is the command the gate runs. **A missing
command is indistinguishable from a passing gate, if nobody reads the error.**
A command that exists but runs something else is worse. Somebody does read
that output, and it is green.

## The rules

### DC1 — a command name means the same thing in every repository

`dev:client` starts the client's development server. It does that in a
repository whose backend is Express, in one whose backend is Go, and in one
whose backend is PHP. The name says what the command does. It does not describe
what else the repository happens to contain.

A package holding only a client does **not** call that `dev`, on the grounds
that it is the only thing there. `dev` means *bring up the whole local stack*.
A package with one process has no stack to bring up. Where the whole stack is
Docker Compose or a Makefile, it is not a `package.json` concern, and no `dev`
is defined.

The rule protects the reader, who moves between repositories without learning
a vocabulary per repository.

### DC2 — a script's body is the invocation its gate runs

Not equivalent to it. Not a superset of it. Not a friendlier version of it. It
is the same command, minus the `pnpm exec` prefix a script does not need. The
package manager has already put `node_modules/.bin` on `PATH`.

A script is a projection of the catalog command, not a second copy of it. The
catalog stays the single definition ([`010-ci.md`](010-ci.md) Principle 2),
and the script is what makes that definition reachable from a terminal.

A flag is part of the command. `--deny-warnings` stays in a `lint` script even
where the lint job runs `warn_only`. `warn_only` is a property of the *job*,
which decides whether a finding fails the build. It is not a property of the
invocation. A local command that drops the flag reports a different set of
findings from the one the repository is burning down.

**The one declared exception is `test:unit`.** `job-test-unit-js-vitest`
generates a coverage-exclusion array per unit, so its full command line cannot
be written as a fixed string. The script reproduces the *verdict*, not the
*telemetry*. `--dir` and `--passWithNoTests` decide which tests run, and
whether an empty unit passes. The generated excludes only move the denominator
of a number the job never compares against a threshold.

### DC3 — the repository's shape decides which commands exist

It is not a fixed list applied to everything. A package that builds a client has
`build`. One that bundles a server has `build:server`. One with a Node server
has `start`, `dev:server` and an orchestrating `dev`. One with drizzle has
`db:push`. A package with none of those has none of them, and that is a pass.

**The rule runs both ways.** A canonical command present while its condition is
false is as wrong as one missing. A gate that only ever adds cannot see a
command outliving its reason, which is the commonest way one goes stale.

Shape is read from the repository's own `ci.yml`: which catalog jobs it calls,
with which `workdir` and which `dir`. A script running a catalog invocation no
job calls for is a command that outlived its gate. A repository's own
`format:write` runs `prettier --write`, which no gate runs, so DC6 additions
stay untouched.

### DC4 — no second name for a command that already has one

Two names for one string is drift that does not announce itself. Both keep
working, so nothing fails. The repository now has two answers to one question.
Where a name is wrong, rename it. Do not add the right one beside it.

### DC5 — a script never reaches a local binary through the package manager

Examples: `pnpm vitest`, `npm run build` inside another script, `npx
drizzle-kit`. The binary is already on `PATH`. The prefix costs a process, and
makes one command look like two.

Calling *another script* is the one legitimate case, because it is the only way
to reach one. The orchestrating `dev` invoking `pnpm dev:client` and `pnpm
dev:server` is correct.

### DC6 — a repository is permitted to add commands, under the same rules

Nothing here forbids a repository-specific script. `generate-erd` is real work
that belongs to one repository. Three things it cannot do. It cannot take a
canonical name for something else. It cannot duplicate a canonical command
under a different name. It cannot reach a binary through the package
manager.

### DC7 — a document naming a command names one that exists

An `AGENTS.md`, a `README`, a Dockerfile comment or an operations runbook prints
commands. Each one is a claim a reader will act on.

Where the command is canonical, quote the script name rather than the underlying
tool. The document then keeps working when the tool's flags move.

## The commands

| Command | Body | Present when |
|---|---|---|
| `dev` | `concurrently -k -n client,server -c cyan,magenta "pnpm dev:client" "pnpm dev:server"` | the package owns the whole local stack |
| `dev:client` | `vite dev` | the package builds a client |
| `dev:server` | `NODE_ENV=development tsx watch server/index.ts` | the package has a Node server |
| `build` | `vite build` | `job-build-js-vite` |
| `build:server` | `esbuild server/index.ts --platform=node --bundle --packages=external --format=esm --define:process.env.NODE_ENV='"production"' --outfile=dist/index.js` | `job-build-js-esbuild` |
| `start` | `NODE_ENV=production node dist/index.js` | the package has a Node server |
| `typecheck` | `tsc -b --noEmit` | `job-typecheck-ts-tsc` |
| `lint` / `lint:<target>` | `oxlint <dir> --type-aware --deny-warnings` | `job-lint-js-oxlint`, one per call |
| `format` / `format:<target>` | `prettier --check <dir>` | `job-fmt-js-prettier`, one per call |
| `test:unit` / `test:unit:<unit>` | `vitest run [--dir <unit>] --passWithNoTests --coverage` | `job-test-unit-js-vitest`, one per call |
| `test:watch` | `vitest` | the package has tests |
| `db:push` | `drizzle-kit push` | drizzle-kit is a dependency |

**`dev:server` carries no port.** The server reads `PORT` and falls back to a
constant ([`016-local-development.md`](016-local-development.md) LD1). A
person who needs a specific port sets the variable.

**`format` checks, and the fix-up command is not canonical.** `--check` is the
verdict the gate reads. `--write` is a different command, and no job runs it.
A repository that wants one types `prettier --write <dir>`, or adds its own
script under DC6. Naming it in this table would create a canonical command
with no gate behind it.

**A name is suffixed only where there are several of the thing.** One lint
target is `lint`. Three are `lint:client`, `lint:server`, `lint:shared`. A bare
`lint` covering one of three trees is a name that lies.

**`db:push` is a local convenience, and it never points at a deployed
database** ([`025-structured-data.md`](025-structured-data.md) SD2). Schema
changes reach a deployed database through a migration.
