# Developer commands

One of the Aurum Alpha engineering standards. Read
[`../README.md`](../README.md) for the charter it is written under and
[`999-enforcement.md`](999-enforcement.md) for what enforces it.

Rules carry the prefix **DC**.

This standard governs the commands a person types. It covers what they are
called, what they run, and which of them each repository carries. It is the
local half of [`010-ci.md`](010-ci.md) Principle 2, *Local = CI*. It exists
because that principle was true as an intention and false as a fact.

## Why this exists

A gate is reachable two ways: through the pipeline, and through a person's
terminal. The catalog settled the first years ago. Nothing had ever read the
second.

*Measured 2026-09-09, by reading every `package.json`:*

- *Dockerfiles told the reader to run `build` before building
  the image. **The package did not define `build`.** The command existed only
  inside two catalog jobs. Producing the artifact locally meant reading
  workflow YAML and retyping it.*
- *A Dockerfile ran `pnpm run build` against a client with no `build`
  script. So `docker compose build` could not succeed, and that is the local
  development path the repository's own AGENTS.md gives.*
- *A `tools/checks/lint` ran a `lint` script its client does not
  define. It is a row in the gate manifest, so `./tools/check` could not go
  green. CI stayed green throughout, because CI calls the catalog job instead.*
- *A `typecheck` ran `tsc --noEmit` while its gate ran `tsc -b
  --noEmit`. Without `-b` the project references are never built. The two
  commands checked different things and agreed by coincidence.*
- *"Run the tests" had six spellings. "Push the schema" had three.*

Not one of those was reachable by any check. All of them were found by reading.

The pattern is one thing, and it is not carelessness. **A missing command is
indistinguishable from a passing gate, if nobody reads the error.** A command
that exists but runs something else is worse. Somebody does read that output,
and it is green.

## What this reconciles

Two principles in [`010-ci.md`](010-ci.md) pointed opposite ways. Both were
load-bearing.

**Principle 2** was amended on 2026-08-17. It now says the shared job is the
command's single definition, not a per-repo script it wraps. That amendment is
right and it stands. A per-repo script as the source of truth makes the catalog
a wrapper around one opinion per repo.

That has already been paid for once. A whole checker existed to police
byte-identity between copies that kept diverging. A checker of that kind is the
tell that there was only ever one copy to keep.

**Principle 9** said workflow YAML calls only canonical script names. Read as
written, it reverses the amendment. It is the half retired here. That document
records the amendment.

The resolution is neither. **A script is a projection of the catalog command,
not a second copy of it.** The catalog stays the single definition. The script
is what makes that definition reachable from a terminal. A checker derives the
expected body from the same jobs CI calls, with the inputs the repository's own
`ci.yml` passes them. A repository cannot hold a script that disagrees with its
gate, because the disagreement is the finding.

Both principles become true at once. One definition, one command to reach it,
and a machine holding the two together. It is not a convention everyone is
trusted to remember.

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

This is the rule with no room in it. Every other rule here protects a
capability. This one protects the reader, who moves between repositories
without learning a vocabulary per repository.

### DC2 — a script's body is the invocation its gate runs

Not equivalent to it. Not a superset of it. Not a friendlier version of it. It
is the same command, minus the `pnpm exec` prefix a script does not need. The
package manager has already put `node_modules/.bin` on `PATH`.

A flag is part of the command. `--deny-warnings` stays in a `lint` script even
where the lint job runs `warn_only`. `warn_only` is a property of the *job*,
which decides whether a finding fails the build. It is not a property of the
invocation. A local command that drops the flag reports a different set of
findings from the one the repository is burning down.

**The one declared exception is `test:unit`.** It is stated here rather than
hidden. `job-test-unit-js-vitest` generates a coverage-exclusion array per unit,
so its full command line cannot be written as a fixed string.

The script reproduces the *verdict*, not the *telemetry*. `--dir` and
`--passWithNoTests` decide which tests run, and whether an empty unit passes.
The generated excludes only move the denominator of a number the job uploads.
The job never compares that number against a threshold. A rule claiming
byte-equality there would be a rule nobody could satisfy.

### DC3 — the repository's shape decides which commands exist

It is not a fixed list applied to everything. A package that builds a client has
`build`. One that bundles a server has `build:server`. One with a Node server
has `start`, `dev:server` and an orchestrating `dev`. One with drizzle has
`db:push`. A package with none of those has none of them, and that is a pass.

**The rule runs both ways.** The second half was learned the hard way. A
canonical command present while its condition is false is as wrong as one
missing.

The case: a repository's drizzle stack was deleted: `drizzle-kit`, and the
`db:push` that called it. A branch adding the standard commands was open at the
time, against an older base. Merged, the two produced a `db:push` invoking a
binary the repository no longer had.

`check-package-scripts` passed it. knip caught it, from a job that is not about
developer commands at all: *"Unlisted binaries (1): drizzle-kit"*. A gate that
only ever adds cannot see a command outliving its reason, which is the
commonest way one goes stale.

**The fix for that case reached one kind of command.** The rule covers every
kind. `db:push` has a fixed name, so the checker could hold a list of names.
`lint:client`, `format:server` and `test:unit:shared` carry a target, so no list
can name them. Those three families stayed exempt from the second half until the
gate was extended to them.

They are identified by body rather than by name. A script running the catalog's
own invocation, with no catalog job calling for it, is a command that outlived
its gate. A repository's own `format:write` runs `prettier --write`, which no
gate runs, so DC6 additions stay untouched.

Shape is read from the repository's own `ci.yml`: which catalog jobs it calls,
with which `workdir` and which `dir`. It is not read from a map of repository
names kept in the catalog. A name map has already gone stale here
through two renames, with nothing noticing.

### DC4 — no second name for a command that already has one

Two names for one string is drift that does not announce itself. Both keep
working, so nothing fails. The repository now has two answers to one question.
Where a name is wrong, rename it. Do not add the right one beside it.

### DC5 — a script never reaches a local binary through the package manager

Examples: `pnpm vitest`, `npm run build` inside another script, `npx
drizzle-kit`. The binary is already on `PATH`. The prefix costs a process. It is
how `pnpm vitest --coverage` and `vitest` come to look like two different
commands, in repositories that meant the same thing.

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
commands. Each one is a claim a reader will act on. More than one
`AGENTS.md` has named a script that was not there. Another warned agents away
from one that had already been deleted.

Where the command is canonical, quote the script name rather than the underlying
tool. The document then keeps working when the tool's flags move.

## The commands

| Command | Body | Present when |
|---|---|---|
| `dev` | `concurrently -k -n client,server -c cyan,magenta "pnpm dev:client" "pnpm dev:server"` | the package owns the whole local stack |
| `dev:client` | `vite dev` | the package builds a client |
| `dev:server` | `NODE_ENV=development PORT=<port> tsx watch server/index.ts` | the package has a Node server |
| `build` | `vite build` | `job-build-js-vite` |
| `build:server` | `esbuild server/index.ts --platform=node --bundle --packages=external --format=esm --define:process.env.NODE_ENV='"production"' --outfile=dist/index.js` | `job-build-js-esbuild` |
| `start` | `NODE_ENV=production node dist/index.js` | the package has a Node server |
| `typecheck` | `tsc -b --noEmit` | `job-typecheck-ts-tsc` |
| `lint` / `lint:<target>` | `oxlint <dir> --type-aware --deny-warnings` | `job-lint-js-oxlint`, one per call |
| `format` / `format:<target>` | `prettier --check <dir>` | `job-fmt-js-prettier`, one per call |
| `test:unit` / `test:unit:<unit>` | `vitest run [--dir <unit>] --passWithNoTests --coverage` | `job-test-unit-js-vitest`, one per call |
| `test:watch` | `vitest` | the package has tests |
| `db:push` | `drizzle-kit push` | drizzle-kit is a dependency |

**`<port>` is the one value that is legitimately per-repository.** Two of these
cannot both bind the same port on one workstation. Everything around it is
fixed.

**`format` checks, and the fix-up command is deliberately not canonical.**
`--check` is the verdict the gate reads. `--write` is a different command, and
no job runs it. A repository that wants one types `prettier --write <dir>`, or
adds its own script under DC6. Naming it in this table would create
a canonical command with no gate behind it.

**A name is suffixed only where there are several of the thing.** One lint
target is `lint`. Three are `lint:client`, `lint:server`, `lint:shared`. A bare
`lint` covering one of three trees is a name that lies.

**`db:push` is a local convenience, and it never points at a deployed
database.** Schema changes reach a deployed database through a generated
migration. That rule belongs to
[`025-structured-data.md`](025-structured-data.md). It is restated here only
because this is the document that says the command exists.

## What the gate proves, and what it does not

`tools/check-package-scripts` runs from `job-ci-conformance.yml`, in each
repository's own CI, against that repository.

It proves DC1 through DC6 mechanically. Every required command is present.
Every body equals the catalog's invocation, with that repository's own inputs.
There are no duplicate names, and no package-manager indirection. `dev` exists
only where there is a stack to bring up.

It does not prove DC7. A checker sees that a script exists. It cannot tell
whether a sentence in a runbook is about that script, or about a command
someone imagined. That stays a review question.
[`999-enforcement.md`](999-enforcement.md) records it as one, rather than
implying coverage it lacks.
