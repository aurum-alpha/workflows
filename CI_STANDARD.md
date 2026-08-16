# CI Pipeline Standard

Status: **agreed 2026-08-14** (rev 2 after Jared's review). Remaining open items at bottom.

## Principles

1. **One source of truth per pin.** `.node-version`, `go.mod`, `.php-version`,
   `packageManager` — CI *derives* versions (`node-version-file`, `go-version-file`),
   never restates them. A version bump is a one-file diff.
   This binds container images too. A Dockerfile that needs a version at
   build time reads the pin file, it does not get a copy of its own: two
   files naming the same version is a pin that will eventually disagree with
   itself, and the image then bakes a different toolchain than the one
   developers and CI actually run. A validation step comparing the two
   copies is not a fix — it is a second thing to maintain guarding a
   duplication that should not exist. *Learned the hard way 2026-08-16:
   event-manager's pnpm conversion added `.pnpm-version` beside
   `packageManager` so the builder image had something to read, and the two
   promptly disagreed (11.22.0 vs the fleet's 10.34.5). Both now come from
   `packageManager`, and the guard is gone with the duplication.*
   The pin also lives beside what it pins: the node app directory owns its
   `.node-version`, because that is where the shared jobs look
   (`<workdir>/.node-version`).
2. **Local = CI.** Every gate is a runnable script in the repo (`tools/checks/*` pattern);
   the workflow job is a thin wrapper with the same name. No logic that exists only in YAML.
3. **Fail closed.** Nothing publishes unless every gate passes. `continue-on-error` is
   allowed only as a documented stabilization window with a ticket reference and an
   expiry expectation.
4. **Standard runner line**: `runs-on: ${{ vars.RUNNER || 'ubuntu-26.04' }}`.
   Exceptions, deliberately hardcoded to GitHub-hosted: release/publish jobs and
   gha-runner-controller itself (the fleet must not build on the fleet).
5. **Ephemeral-runner assumptions + provisioning tiers.** No workspace-hygiene steps.
   Where a dependency lives is decided by tier:
   - **Tier 1 — runner image** (gha-runner-controller): universal, host-level only —
     docker, git, core libs (libatomic1). Test: *every* repo's jobs would break
     without it. Nothing repo-specific.
   - **Tier 2 — builder image**: the exact toolchain when it is heavy,
     version-critical, or lacks a good setup action (PHP + extensions + composer).
     Self-bootstrapping rebuild when version files / image inputs change.
   - **Tier 3 — job steps**: lightweight toolchains with first-class actions
     (`setup-go`, `setup-node` + lockfile-keyed caches) and *runtime* deps via
     service containers / compose.
   - **Policy: tier 3 is the standard; tier 2 only where actions fall short**
     (builder images existed to work around action deficiencies — that is their
     only justification). Where a gap is small, prefer writing a custom action
     (in aurum-alpha/workflows) over adopting a builder image. Future shared
     stack images (`ci-node`, `ci-go`, `ci-php`) publish from aurum-alpha/workflows
     and are consumed by digest. hiring-tracker migrates tier 2 → tier 3.
6. **Concurrency everywhere**: `${{ github.workflow }}-${{ github.ref }}` +
   cancel-in-progress — except release workflows (cancel-in-progress: false).
7. **BUILD ONCE.** The `build` job is the only compiler anywhere. It produces
   every required artifact variant; packaging, docker, and release steps consume
   those artifacts — nothing downstream rebuilds.
8. **No multi-stage production Dockerfiles.** Shipped images are thin runtime
   images that COPY the prebuilt `dist`/`bin` artifact (gofast pattern). Dev
   images may compile for local HMR; the rule governs shipped images.
9. **Canonical script names, specific not generic** — the *type* of check is in
   the name (`typecheck`, `test:unit`, never `check`). Workflow YAML calls only
   canonical script names; repo specifics live behind them (see Standard job
   catalog).
10. **Lint output goes through standard channels**: default/stylish output +
    setup-node's built-in problem matchers (inline annotations for free), plus
    optional `$GITHUB_STEP_SUMMARY` totals. No custom PR-comment machinery —
    reply-able review-thread annotations are a possible future improvement,
    fleet-wide or not at all.
11. **Registry auth lives in user-level npmrc, never project `.npmrc`.**
    pnpm 10+ deliberately ignores auth settings in project npmrc (supply-chain
    hardening) — a project-level `_authToken` line is silently dead. CI gets it
    via setup-node's `registry-url`; Docker builds and compose commands write
    `~/.npmrc` before install; hosts via dev-init. (Learned the hard way:
    client-manager#22.) Fleet pnpm version: **10.34.5** via `packageManager`,
    confirmed across all pnpm repos including client-manager.

12. **One way per capability.** The unit of CI consistency is the
    *capability*, not the repo: a repo that has a React frontend builds,
    artifacts, and tests it the ONE fleet way; a TS codebase is eslinted
    the ONE way; a Go backend is built/vetted/tested the ONE way; PHP
    likewise. Repos differ only in *which* capabilities they compose and
    in the `needs:` wiring between them — never in how a capability is
    executed. Phase C realizes this as single-job reusable workflows
    (one shared definition per capability job) consumed by every repo
    that has that capability, single- or dual-stack alike.

## Standard job DAG — build first

The cheapest, most fundamental gate is "does it build." A broken compile fails one
job instead of ten, and the build job primes caches and emits artifacts downstream
jobs reuse (e.g. binaries handed to docker packaging).

```
install ──► build ──► lint ─────────┐
                  ──► typecheck ────┤──► integration / e2e ──► package / publish
                  ──► unit tests ───┘         (main + tags only)
                              └──► "ci-ok" rollup job (the only required check)
```

- Quality gates run in parallel *after* build, never serialized among themselves.
- **Hard rule — BUILD ONCE.** The build step produces *every* required artifact
  type (all build-arg variants included) and later steps — packaging, docker,
  release — pull those artifacts from cache/artifact storage. Nothing downstream
  ever rebuilds.
- Stack note: for TS, `tsc --noEmit` is the compile assertion and stays a gate;
  "build" means the real bundle/transpile (vite/esbuild) — this is where the
  production artifact is produced.
- `ci-ok` (`if: always()`, fails on any failure/cancel in needs) is the single
  required check, so adding/removing gates never touches branch protection.
  The check reports under the job id `ci-ok` (no display-name override) —
  that exact string is what branch protection requires, fleet-wide.

## Publishing

- Registry: ghcr. Tags: `<sha>` always; `latest` only on the default branch;
  `pr-N` build-only (no push). Release channel via CalVer tags + `edge` moving tag
  (client-manager pattern) where a repo has real releases.
- **Per-branch images: deferred** until per-branch staging spin-up/teardown infra
  exists. Revisit then.

## Coverage

- **Codecov everywhere it can be supported**: `codecov/codecov-action` **v7**
  (v7.0.0 current as of 2026-06; client-manager already on it), SHA-pinned,
  per-tree flags, `fail_ci_if_error: true`, thresholds in `codecov.yml`.

## Action pinning — SHA everywhere

Version tags are mutable pointers; the tj-actions/changed-files incident (2025-03)
rewrote existing tags to malicious code and SHA-pinned consumers were untouched.

- Pin every action to a full commit SHA with a mandatory trailing `# vX.Y.Z` comment.
- Enable Dependabot (`github-actions` ecosystem) per repo — it maintains SHA+comment
  pairs, making upgrades reviewable PRs instead of silent tag moves.
- Workflow-level least-privilege `permissions:` blocks everywhere.
- Known limits: your SHA does not pin an action's own transitive deps, and a bad
  *new* release still needs review before you bump into it.
- Optional backstop: org-level allowlist of permitted actions.

## Shared infrastructure — aurum-alpha/workflows

**Created 2026-08-14, public** (NOT gha-runner-controller — the fleet controller
consumes shared workflows; hosting them there mixes concerns). Update
2026-08-15: gofast has moved into the org (**aurum-alpha/gofast**), so the
cross-org consumption rationale no longer applies to it and gofast may now use
the aj78-docker runners (adopt the standard runner line when its workflows
next change).

- Reusable **workflows** must live in `.github/workflows/` (GitHub requirement — no
  subdirs), so stacks are organized by filename: `node-ci.yml`, `go-ci.yml`,
  `php-builder-image.yml`, `docker-publish.yml`.
- Composite **actions** may use subdirs: `setup/node/action.yml` →
  `uses: aurum-alpha/workflows/setup/node@<sha>`.
- Callers reference by SHA (same pinning policy).
- Access: resolved — the repo is public.

## Standard job catalog

Convergence plan: **(A)** every repo adopts the standard DAG with these canonical
job ids → **(B)** each job's YAML becomes byte-identical across repos → **(C)**
literal duplicates move to `aurum-alpha/workflows`. Nothing is extracted before
it is identical in at least two repos.

**The indirection rule (what makes B achievable):** workflow YAML may only call
*canonical script names* — never inline tool invocations. Repo-specific flags,
paths, and configs live behind `package.json` scripts, `Makefile` targets, or
`tools/checks/*`. The YAML carries zero repo knowledge beyond the script name,
so identical jobs really are identical.

### Canonical script names (ALL stacks)

Same names everywhere; the runner differs per stack (`npm run` / `pnpm run` /
`composer run` / make targets). Specific names, not generic ones — the *type*
of check is in the name.

| Script | TS | Go (tools/checks or make) | PHP (composer) |
|---|---|---|---|
| `build` | bundle ALL production artifacts into `dist/` | `go build ./...` → `bin/` | asset/app build |
| `lint` | `eslint .` | golangci-lint / vet wrapper | phpcs/pint (when adopted) |
| `typecheck` | `tsc --noEmit` — **rename from `check`** (credit-watch, expense-splitter, flight-watch, jewelry-factory) | `go vet ./...` | `phpstan analyse` |
| `test:unit` | `vitest run --coverage` — non-watch | `go test ./... -cover` | phpunit unit suite |
| `test:integration` / `test:e2e` | where they exist | `-tags=integration` | phpunit integration / playwright |

Tooling convergence (part of phase B): eslint + vitest are the TS standard
(event-manager's React tests are jest — migration decision when its TS jobs
standardize); coverage always through the canonical test scripts.

### TS job catalog

Every job: checkout → setup-node (`node-version-file`) → pm setup → frozen
install (store-cached) → its one script. All SHA-pinned, least-privilege.

| Job id | needs | Does | Emits |
|---|---|---|---|
| `build` | — | frozen install, `run build` | `dist` artifact (1-day) |
| `lint` | build | `run lint` | — |
| `typecheck` | build | `run typecheck` | — |
| `test-unit` | build | `run test` + codecov v7 (flags) | coverage |
| `image` | lint, typecheck, test-unit | docker metadata + build-push; **downloads `dist`** (Dockerfile COPYs prebuilt artifacts — no in-image rebuild) | ghcr image, push on non-PR |
| `ci-ok` | all | `if: always()`, fails on any failure/cancel | the single required check |

### Go job catalog

| Job id | needs | Does |
|---|---|---|
| `go-mod` | — | `go mod download && go mod verify`, saves module cache |
| `build` | go-mod | `go build ./...`, uploads binaries (BUILD-ONCE) |
| `gofmt` / `vet` / `test-unit` / `vuln-scan` | build | parallel: `gofmt -l`, `go vet`, `go test -cover` + codecov, `govulncheck`/osv-scanner |
| `image` | the gates | packages **prebuilt binaries** (gofast pattern) |
| `ci-ok` | all | rollup |

### PHP job catalog (event-manager)

Same ids where meaningful: `builder-image` (tier 2, reusable) → `install`
(composer dev/prod) → `build` → `test-unit` / `static-analysis` in parallel →
`test-integration` (service containers) → `test-e2e` (compose) → `image` →
`ci-ok`. Stays repo-local until a second PHP repo exists.

### Embedded job catalog (lid-firmware — PlatformIO)

| Job id | needs | Does |
|---|---|---|
| `build` | — | `pio run` env matrix → firmware artifacts (BUILD-ONCE) |
| `test-unit` | build | `pio test` native suite (when adopted) |
| `ci-ok` | all | rollup |

### Dual-stack job ids (B4 decision)

A repo hosting two stacks in one pipeline (client-manager: Go + TS;
event-manager: PHP + React) prefixes a canonical id with its stack —
`go-` / `web-` / `php-` — **only when both stacks in that pipeline have
the job** (e.g. `go-test-unit` / `web-test-unit`). Single-owner jobs keep
the bare canonical id (`test-integration`, `static-analysis`, `image`,
`ci-ok`), so bare ids stay meaningful for byte-identity matching (B5) and
prefixes appear only where a collision forces them.

**Display names = job ids** (tightened 2026-08-16, superseding B4's
free-form allowance): no job-level `name:` overrides anywhere — the
lowercase id is what the YAML, the checks UI, and any required-check
string all show. Human context lives in step names and comments.
Executed: event-manager#47, lid-firmware#10; client-manager follows its
B4 rename PR; the Node cohort's redundant `name:` lines drop with C0's
node-ci.yml.

Executed mappings — event-manager (first executed example):
`install-composer-deps` → `php-install`, `install-composer-deps-prod` →
`php-install-prod`, `install-node-deps` → `web-install`, `build-php` →
`php-build`, `build-react` → `web-build`, `test-unit` → `php-test-unit`,
`test-react-unit` → `web-test-unit`. Unchanged: `test-integration`,
`test-e2e`, `static-analysis`, `image`, `ci-ok`, the two builder-image
jobs (repo-specific, not canonical). client-manager's mapping lands after
the `ci-ok` required-check flip (its current ids may be referenced by
branch protection).

Toolchain pins: platform versions in `platformio.ini`; Python via setup-python
(pin a `.python-version` when standardizing). Stays repo-local until a second
embedded repo exists.

### Gap matrix (end of Phase A, 2026-08-15; planning baseline was 2026-08-14)

✓ conforms · Δ exists but drifted · ✗ missing

| Repo | build | lint | typecheck | test-unit | image | ci-ok | Notes |
|---|---|---|---|---|---|---|---|
| client-manager | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Catalog source; dual-stack job-id naming → Phase B |
| credit-watch | ✓ | ✓ | ✓ | ✓ (codecov: Phase B) | ✓ | ✓ | |
| expense-splitter | ✓ | ✓ | ✓ | ✗ (no tests, Phase B) | ✓ | ✓ | |
| flight-watch | ✓ | ✓ | ✓ | ✗ (no tests, Phase B) | ✓ | ✓ | |
| jewelry-factory | ✓ | ✓ | ✓ (in lint job) | ✓ | ✓ | ✓ | |
| hiring-tracker | ✓ | ✓ | ✓ | ✓ (codecov CLI → action: Phase B) | ✓ | ✓ | Tier 3 since A3 |
| gofast | ✓ | ✓ | n/a | ✓ | ✓ | ✓ | On aj78-docker since 2026-08-15 (runner group fixed; main run #163 all-green on fleet) |
| gha-runner-controller | ✓ | n/a (golangci: Phase B) | n/a | ✓ | ✓ (.deb) | ✓ | Deliberately GitHub-hosted (Principle 4) |
| event-manager | ✓ | ✗ (no eslint/prettier — Phase B) | n/a | ✓ | ✓ | ✓ | phpstan advisory until Phase D |
| wardley-mapper | ✓ | ✓ | ✓ | ✗ (no tests, Phase B) | ✓ | ✓ | Born conformant (A0a) |
| lid-firmware | ✓ | n/a | n/a | ✓ (compile-check; on-device: future) | n/a | ✓ | Embedded catalog |

All catalog decisions are resolved and live under **Principles** (rule: decisions,
once made, move to Principles). Phase-A work items arising from them:
`check` → `typecheck` renames (4 repos) · remove jewelry's ESLint PR-annotation
machinery · hiring-tracker tier-2 → tier-3 migration · TS production Dockerfiles
restructured to COPY the `dist` artifact.

### Gap-filling flow

Where the matrix shows ✗, the sequence is: standardize the job across the repos
that HAVE it → extract the byte-identical job to `aurum-alpha/workflows` → fill
the gap by adopting the shared standard job (never by writing a bespoke one).

## Per-stack templates

- **TS app** (npm or pnpm): install (frozen lockfile, cached store) → build
  (vite/esbuild) → eslint / tsc / vitest in parallel → docker (gated, push non-PR).
- **Go service**: go-mod-download → build (artifacts out) → gofmt / vet / tests /
  govulncheck in parallel → docker packaging from build artifacts.
- **PHP monolith**: builder-image first step (tier 2) → composer/npm installs →
  build → unit/static in parallel → integration (service containers) → e2e (compose)
  → prod image.

## Phased build-out

Execution mechanics for every phase: per-repo branch → PR → watch CI → merge →
fix-and-repush on failure; alphabetical repo order; nothing lands red.

### Phase 0 — foundations *(complete)*

Runner line + ephemeral fleet, armor removal, Node 26 / `.node-version` / fnm,
pnpm 10 alignment (client-manager parked), image-publish gating, concurrency,
SHA-pinning + Dependabot, CI junk removal, AUR-565 stabilization round 1.

### Phase A task board (live status — update as items land)

Execution loop per item: branch → PR → watch CI → merge when green → fix and
re-push on failure. Lanes run in parallel; items within a lane are sequential
unless noted.

- [x] **A0a** [TS] Onboard wardley-mapper — **MERGED** (wardley-mapper#1;
      first-ever CI run green 5/5). Follow-ups tracked on the PR: make Replit
      auth optional locally; lint ratchet debt (no-explicit-any ×176,
      no-unused-vars ×51); no tests yet (Phase B).
- [x] **A0b** [embedded] lid-firmware CI baseline — **MERGED**
      (lid-firmware#2; ci-ok green, all three env builds + test pass).
      Runner line, SHA pins + dependabot, concurrency, least-privilege
      permissions, ci-ok rollup; publish-firmware deliberately
      GitHub-hosted (Principle 4).
- [x] **A1** [TS] Script renames — **COMPLETE**, all five repos merged:
      credit-watch #14, expense-splitter #12 (lint indirection fixed too),
      flight-watch #13, jewelry-factory #12 (test:unit now explicitly
      non-watch), hiring-tracker #13 (also removed a broken
      check-server-types chained in its old typecheck script — it
      referenced a deleted tsconfig.server.json).
- [x] **A2** [TS, after A1] jewelry-factory ESLint PR-annotation machinery
      removed — **MERGED** (jewelry-factory#13; −48 lines of YAML,
      `pull-requests: write` gone, plain `pnpm lint`). Code verified
      lint-clean beforehand; no masked violations surfaced.
- [x] **A3** [TS, after A1] hiring-tracker tier-2 → tier-3 — **MERGED**
      (hiring-tracker#14; −138 lines). pipeline-base builder image and the
      event-manager-fork reusable workflow deleted; all jobs on setup-node
      + pnpm + store cache; container/--user-root dance gone.
- [x] **A4** [TS, after A1] Canonical `build` job emitting the `dist`
      artifact — **COMPLETE**: credit-watch #15, expense-splitter #13,
      flight-watch #14 all merged. Gates run after build everywhere.
- [x] **A5** [TS, after A4] Prod Dockerfiles → thin runtime COPY of `dist`
      — **COMPLETE**: credit-watch #16, expense-splitter #14, flight-watch
      #15, hiring-tracker #15, jewelry-factory #14 all merged (the last
      two also wire the dist-artifact upload into their build jobs). All
      five images boot-verified locally against postgres before PR.
      Findings: hiring-tracker's OLD image could build but never boot
      (missing migrations dir; server bundle imports vite at runtime →
      full install kept, noted as app debt); stale pnpm@10.8.1 pins in
      both pnpm Dockerfiles replaced by packageManager-derived installs.
- [x] **A6** [Go] Go 1.26.6 bump — **COMPLETE**: gha-runner-controller
      #41 and gofast #72 both merged. gofast also picked up a real vet
      finding on 1.26.6 (SMTP dial addr broken for IPv6 → net.JoinHostPort)
      and re-pinned its golang image digest. RESOLVED 2026-08-15: Jared added
      gofast to the aj78-docker runner group; the standard vars.RUNNER
      line was already in the merged workflow (the GitHub-hosted pin never
      reached main), and main run #163 ran every job green on
      aj78-docker-* runners.
- [x] **A7** [Go, after A6] Catalog fill — **COMPLETE**: gofast #73
      (dedicated session, [DONE]; full canonical DAG with coverage,
      oxlint wired, scripts/ entrypoints) and gha-runner-controller #60
      (monolithic job split into go-mod → build → gofmt/vet/test-unit/
      test-integration → ci-ok, coverage added, stays GitHub-hosted per
      Principle 4; its own ci-ok ran green on the PR).
- [x] **A8** [PHP] event-manager composer scripts → canonical names —
      **MERGED** (event-manager#42; full pipeline green including
      integration, functional and e2e). Workflows call the scripts
      (indirection rule). Found and fixed en route: composer's default
      300s process-timeout killed the functional suite once invoked via
      `composer run-script` — `config.process-timeout: 0` set in both
      composer.json files.
- [x] **A9** [converges all lanes] Canonical job ids + `ci-ok` rollup in every
      repo — **COMPLETE**, all seven merged with their new ci-ok green on
      first run: credit-watch #17, event-manager #43 (full pipeline incl.
      integration/e2e/image), expense-splitter #15, flight-watch #16,
      hiring-tracker #16, jewelry-factory #15, lid-firmware #7. Already
      conformant: wardley-mapper, gofast (#73), gha-runner-controller
      (#60). client-manager: ci-ok already present; job-id normalization
      deliberately deferred — it is dual-stack (Go + TS), so single
      canonical ids collide (go-unit-tests vs vitest → test-unit); the
      dual-stack naming convention is a Phase B decision (event-manager's
      react jobs got the same treatment). AFTER MERGE (needs admin):
      point each repo's required status check at `ci-ok` (exact string;
      display-name overrides dropped fleet-wide 2026-08-15).

### Phase B task board *(COMPLETE 2026-08-16 — all items landed)*

Same execution loop as Phase A: branch → PR → watch CI → merge when green →
fix and re-push on failure. B0–B1 are in flight; B2→B3→B4→B5 run in order
(B5 is the convergence gate and lands last).

- [x] **B0** `ci-ok` reporting-name sweep (drop `name:` overrides so the
      check reports as the exact string `ci-ok`) — **COMPLETE**, all 11
      merged: workflows#1, wardley-mapper#7, credit-watch#18,
      expense-splitter#16, flight-watch#17, gha-runner-controller#61,
      hiring-tracker#17, jewelry-factory#16, lid-firmware#9,
      client-manager#24, event-manager#44 (full pipeline green — e2e
      passed outright on this run, first since AUR-565 tolerated-red).
      READY FOR ADMIN: enable the required status check — exact string
      `ci-ok` — fleet-wide; replace any earlier `ci ok`-with-space
      entries. B4's job-id renames wait on this flip so rename PRs can't
      strand on old required-check names.
- [x] **B1** hiring-tracker lint/script normalization — **MERGED**
      (hiring-tracker#18). `lint` drops the JSON-report indirection,
      `lint-dev` removed, dead jest script family removed (jest/cross-env
      not installed), `watch:test` → `test:watch` (vitest), duplicate
      `coverage` script dropped; CI lint job calls `pnpm lint`.
- [ ] **B2** Codecov v7 rollout (SHA-pinned action, per-tree flags,
      `fail_ci_if_error: true`) — hiring-tracker#19 (CLI → action),
      credit-watch#19, and event-manager#45 all **MERGED**; remaining:
      gofast#74 BLOCKED on admin — gofast needs adding to the
      CODECOV_TOKEN org secret's repository list (post-transfer gap;
      upload fails "Token required", fail-closed working as designed;
      tests themselves pass). Working uploads exposed two event-manager
      coverage bugs, fixed on #45: jest collected only the legacy
      src/client/js/app tree (react flag read 0.00% — real coverage is
      6.26%), and codecov.yml's absolute 70% project target (repo is at
      ~30%) kept codecov/project permanently red → now target: auto,
      threshold 1% (regression guard); patch keeps 70%.
- [x] **B3** Test scaffolding where none exists — **COMPLETE**, all
      three merged: expense-splitter#17 (27 tests), flight-watch#18
      (26 tests over the real domain logic: ATIS parsing, ATC squawk
      state machine, speech formatting), wardley-mapper#8 (19 tests:
      canvas math, value-chain topological layout, stripe helpers).
      vitest + @vitest/coverage-v8; `test-unit` wired after build with
      the standard codecov block; image/ci-ok gate on it. All verified
      locally pre-PR. Gap matrix: no `test-unit ✗` cells remain.
- [x] **B4** Dual-stack job-id naming — **COMPLETE 2026-08-16**:
      principle recorded; event-manager renames merged (#46);
      client-manager renames + matching tools/checks script moves
      merged (#25) after Jared flipped the fleet required check to
      `ci-ok`. Display-name follow-ups (names = ids) rode behind:
      lid-firmware#10 merged, event-manager#47 / client-manager#26 in
      flight.
- [x] **B5** Byte-identity checker + normalization — **COMPLETE
      2026-08-15**: `tools/check-job-identity` reports **PASS on merged
      mains — every shared canonical job block byte-identical in both
      cohorts**. All six normalization PRs merged: npm cohort on the
      wardley template + version build-args (wardley-mapper#9,
      credit-watch#20 — dropped its separate install job,
      expense-splitter#18, flight-watch#19; all on build-push v6.19.2,
      tag-event rule, latest tag); pnpm cohort on the cleaned
      hiring-tracker template (hiring-tracker#20 — version info folded
      into the build script per the indirection rule,
      update-version-info no longer gates ci-ok; jewelry-factory#17 —
      typecheck split into its own job, image job shed dead
      version-info/pnpm setup). image and ci-ok blocks are additionally
      byte-identical ACROSS cohorts (pm-agnostic — the Phase C
      extraction seed). Wiring the checker as this repo's CI gate needs
      cross-repo checkout and waits for Phase C.

### Phase C task board (planned 2026-08-15 — awaiting go)

Starting position (from B5): the four npm repos share an entirely
byte-identical ci.yml; the two pnpm repos share every canonical block;
`image` and `ci-ok` are identical across all six. The two cohorts differ
only in the package-manager prelude. Execution loop as ever; wardley
(npm) and hiring-tracker (pnpm) go first as templates, then alphabetical.

**The sharing unit is the JOB, not the workflow** (decision 2026-08-16):
single-job reusable workflows — `job-node-build.yml`, `job-node-lint.yml`,
`job-node-typecheck.yml`, `job-node-test-unit.yml`, `job-docker-image.yml`
(flat filenames; GitHub requires reusable workflows directly under
.github/workflows/). The caller's ci.yml keeps only what is genuinely
repo-specific — job id, `needs:` edges, inputs — and the shared repo owns
the entire job body (runner line, permissions, steps). This works
identically for single-stack and dual-stack repos, so no monolithic
node-ci.yml exists at all. Rules: `ci-ok` stays a plain LOCAL job
everywhere (repo-specific needs list; preserves the exact required-check
string — a called job would report nested); inputs are minimal (one knob:
`workdir`, default `.` — client-manager passes `web`); callers use
`secrets: inherit` (org CODECOV_TOKEN) and `vars.RUNNER` resolves in the
caller's context. Cosmetic cost, accepted: called jobs report as
`<caller id> / <inner name>` (e.g. `build / build`) — uniform, and
irrelevant to branch protection.

- [x] **C0** Author the five job-sized reusable workflows in this repo —
      **LANDED** (job-node-build, job-node-lint, job-node-typecheck,
      job-node-test-unit, job-docker-image; single `workdir` input,
      default `.`). C-pre note: all four npm repos migrated to pnpm
      first (wardley-mapper#10, credit-watch#21, expense-splitter#19,
      flight-watch#20) — single Node cohort, no package-manager input
      needed. pnpm's strict resolution surfaced real latent bugs:
      phantom deps nanoid ×3, @types/pg ×2, js-tiktoken; wardley on
      vite 5 vs vitest 4 (now vite 7 like the fleet); credit-watch's
      npm-style overrides silently ignored (now pnpm.overrides).
- [x] **C1** Convert the six Node repos to thin stub callers pinned by
      SHA (header + five 4-line job stubs + local ci-ok) — **COMPLETE
      2026-08-16**: all six landed (wardley-mapper#11, credit-watch#22,
      flight-watch#21, hiring-tracker#21, jewelry-factory#18,
      expense-splitter#20), every one green through the shared jobs on
      first run — zero job-body fixes needed after the showcase proved
      the contract (caller-context vars.RUNNER, secrets: inherit, dist
      artifact flow, `build / build`-style check names, flat required
      ci-ok). Repo-specific extras (hiring-tracker's
      update-version-info) stay caller-side. Each repo's stale
      github-actions Dependabot bump PRs closed post-merge (27 total) —
      pins now live here only. tools/check-caller-thinness passes all
      six.
      Tag note (Jared, 2026-08-16): release tags (v1.0.0 on the C0
      commit) deferred until the C wave is done and working — one
      tagging pass over a stable repo; tag pushes are admin-side (the
      session's git proxy scopes writes to refs/heads/*).
- [x] **C2** client-manager's web jobs adopt the SAME shared jobs with
      `workdir: web` (`lint`, `typecheck`, `web-test-unit`; prereq: A1
      script rename `test` → `test:unit` in web/package.json). Its
      bespoke web gates (prettier, golden-corpus) and changes-gating
      stay local. Go-side `job-go-*` definitions follow the same
      pattern once gofast + client-manager converge on shapes (their
      Go jobs are not yet block-identical — a mini-B5 for the Go
      cohort precedes extraction there). *Landed 2026-08-16
      (client-manager#27). Two shared-job fixes were required and are
      the C5 canary lesson in miniature: (1) pnpm 10+ only honors
      registry auth from the user-level npmrc, so the shared install
      became registry-aware for @aurum-alpha (workflows#12); (2) an
      explicit job-level permissions block REPLACES the caller's token
      grant — packages: read had to be added or private installs 403
      (workflows#13). Web coverage now uploads under the fleet's
      `unittests` flag (was `web`; history freezes, new flag starts).
      client-manager stays partial-thin (dual-stack) until Go
      extraction.*
- [ ] **C2b** Capability convergence: event-manager's react side — the
      last React frontend not built the fleet way (jest not vitest, npm
      not pnpm, tier-2 container jobs). Migrate its react tests to
      vitest, node side to pnpm + tier-3, canonical scripts; then its
      web jobs adopt the same shared `job-node-*` definitions
      (`workdir` input). Heavier than pure CI work (test-framework
      migration touches the suite) — sequenced after C1/C2, allowed to
      slip behind C4/C5 without blocking them. *Scoped 2026-08-16,
      deferred to daytime by design: the vitest half is small (6 test
      files, only 2 using jest-specific APIs); the real work is
      npm→pnpm + tier-3 conversion and reconciling the webpack build
      output with the shared build job's dist/ artifact contract.*
- [x] **C3** Composite action `setup/node-pnpm` for the steps-level
      prelude, consumed by the shared jobs internally AND by bespoke
      caller-side jobs (client-manager's prettier/golden-corpus) — one
      definition of the Node toolchain setup fleet-wide even where the
      job shape is local. *Landed 2026-08-16 with one deliberate
      deviation: the shared job-node-* workflows keep the prelude
      INLINE rather than calling the composite. They execute in the
      caller's checkout, so a self-reference would need its own SHA pin
      and every prelude change would take two commits (chicken-and-egg).
      The composite serves bespoke caller-side jobs only; caller
      adoption (client-manager setup-web replacement) is follow-up.*
- [x] **C4** This repo's CI grows real gates, replacing the exit-0
      stub: actionlint over the shared workflows + a caller-thinness
      check (byte-identity is enforced by construction once extraction
      lands, so tools/check-job-identity retires in favor of "callers
      contain no inline job logic"). *Landed 2026-08-16: `lint` job runs
      actionlint 1.7.7 (docker, tag-pinned) with shellcheck over every
      workflow in this repo; `tools/check-caller-thinness` replaces
      `tools/check-job-identity` — verifies each converted caller's jobs
      are pure `uses:` stubs (SHA-pinned to this repo, `secrets:
      inherit`, no non-stub keys) with a local `ci-ok` whose `needs:`
      covers every stub; repo-local exceptions are an explicit
      allow-list (hiring-tracker `update-version-info`). Runs locally
      against fleet clones (`--root`), not in CI — cross-repo checkout
      is out of scope for the repo-scoped GITHUB_TOKEN. First actionlint
      run caught SC2086 (unquoted `$GITHUB_ENV`) in all four node jobs —
      fixed same commit.*
- [x] **C5** Propagation proof: Dependabot (github-actions ecosystem)
      on every consumer tracks the shared-workflow SHA; land one canary
      change in node-ci.yml and verify it arrives everywhere as
      reviewable SHA-bump PRs. Tag releases in this repo so bump PRs
      are readable (SHA pin + tag comment, fleet pinning policy).
      *Proven 2026-08-16. The canary process ran end to end: merged
      workflows#6 (checkout 4.4.0→7.0.1) alone → re-pinned
      expense-splitter (#21) to that SHA → full run green through all
      five capabilities → then batched #7–#10 (upload-artifact v7,
      buildx v4, download-artifact v8, setup-node v7; artifact
      cross-major compat pre-proven by lid-firmware run 31920424032)
      → fleet re-pin wave to the final SHA. The C2 rollout separately
      demonstrated why single-caller canaries matter: two shared-job
      bugs (registry auth, packages: read) only surfaced on the one
      repo exercising private packages. Canary sets should include
      client-manager's web stubs for that reason. Tags remain
      admin-side (git proxy scopes writes to refs/heads/*): one pass
      at the end per Jared.*
- [x] **C6** event-manager's tier-2 builder-image workflow moves here
      (the hiring-tracker fork died in A3; this centralizes the
      remaining copy); event-manager becomes a caller. Its main ci.yml
      stays repo-local until a second PHP repo exists. *Shared half
      landed 2026-08-16 (workflows#17): the create-docker-build-image /
      create-docker-prod-base-image pair generalized into ONE
      `job-image-cached.yml` (inputs image_name/dockerfile/
      file_patterns/build_args/force_rebuild → outputs changed/image;
      build-push normalized v5.4.0→v6.19.2). event-manager caller flip
      rides the D9 PR.* *Caller flip landed 2026-08-16 (event-manager#49
      merged): both image jobs are now SHA-pinned stubs of
      job-image-cached (v1.4.0), local workflow copies deleted. C6
      complete.*

**Exit criteria** (unchanged from the phase plan): a fix to a shared job
lands once and propagates by Dependabot SHA-bump PRs to every consumer.
**MET 2026-08-16, repeatedly, in production**: five distinct shared-job
changes tonight (GITHUB_ENV quoting, registry-aware install,
packages: read, checkout v7, D7 junit analytics) each landed once and
reached all seven consumers as mechanical SHA re-pins; the fleet wave
merged 7/7 green and tools/check-caller-thinness passes every converted
caller against main. Phase C is COMPLETE except C2b (event-manager
react convergence, tracked below — deliberate daytime work); the C6
caller flip landed with event-manager#49.
Dependabot-authored bump PRs (vs tonight's scripted re-pins)
arrive with its next daily run now that the callers reference this
repo — the propagation mechanism itself is proven either way.

### Phase D task board (GO 2026-08-16 — Jared: "run all night work on
Phase D"; overnight execution in progress)

Sequencing: Phase C (extraction, as specified below) remains the natural
next execution phase — its payoff compounds into everything after. D0–D2
are event-manager-local and small enough to run before or alongside C;
D3–D6 are independent of C. Same execution loop as A/B.

- [x] **D0** [event-manager] Integration + e2e become hard gates —
      remove `continue-on-error` from test-integration and test-e2e
      (three sites in ci.yml). Evidence for flipping now: four
      consecutive fully-green full-pipeline runs on 2026-08-15 (#44,
      #45 ×2, #46), including e2e. The AUR-565 round-2 hardening list
      (static bundle serve, globalTeardown sweep, scoped guards,
      keycloak-init hardening) becomes ordinary bugfix work under a
      hard gate — red is real signal once the gate is closed.
      RECOMMENDATION: flip first, harden under the gate. (Alternative:
      harden first — Jared's call.) *Flipped 2026-08-16 per the
      overnight go (event-manager#48, merged): test-integration and
      test-e2e drop continue-on-error; PHPStan's advisory step stays
      until D1.* *The gate earned its keep within hours. First red
      06:57 UTC: 3/67 auth-adjacent Playwright failures (AUR-565
      class). The persistent one was then root-caused as a
      test-authorship bug, not infra: event-registration-config's
      cleanup clicked through the Delete confirm dialog, which can
      commit and close between the isVisible() check and the button
      click, stranding the locator until the 60s test timeout —
      identical trace on both attempts across two PRs. Fixed by moving
      cleanup to DELETE /api/events/{id}/questions/{qid}
      (event-manager#49/#50). Lesson: e2e cleanup paths belong on the
      API, not the UI.*
- [x] **D1** [event-manager] PHPStan hard gate — fix the phpstan.neon
      bootstrap (the documented blocker), then remove
      `continue-on-error` from static-analysis. Principle 3's last
      documented stabilization window closes. *Landed 2026-08-16
      (event-manager#50): constants-only tools/phpstan-bootstrap.php
      (defines FCPATH/APPPATH/etc. without booting the framework),
      blanket ignores retired down to the two CI4 magic-method
      patterns, 277-finding baseline checked in
      (phpstan-baseline.neon), continue-on-error removed. The gate
      caught two config follow-ons on its own first enforced run —
      a non-ignorable unknown-class (runtime-only JWTAuthentication →
      excludePaths per PHPStan's own guidance) and stale unmatched
      ignores (PHPStan fails on those) — both fixed same night.
      Debt burns down by shrinking the baseline.*
- [ ] **D2** [event-manager] Web lint gates — the gap matrix's last ✗:
      eslint + prettier for the react tree (deferred out of Phase B).
      New canonical `lint` job (no collision — PHP side has none; the
      dual-stack rule keeps it bare) wired needs: web-install → gates
      ci-ok. Ratchet config so current code passes; debt burns down
      like wardley's.
- [ ] **D3** [fleet] Build-tooling consistency sweep (the shelved Make
      question) — inventory ALL per-repo build/check tooling
      (tools/checks/*, scripts/*.sh, tools/testing/*, package scripts,
      Makefiles), classify each as native-toolchain / thin canonical
      wrapper / black-box one-off, then converge: native toolchains
      where they suffice, Make used as designed (file sets, dependency
      edges) where a real build system earns its place — including the
      decision on converting the Go repos to Make and whether Make
      becomes tier 1. Fleet-wide assessment, not repo by repo.
      *Node-tooling matrix surveyed 2026-08-16 — two cohorts: (A)
      credit-watch/expense-splitter/flight-watch/wardley on TS 5.6.3 +
      vite 7 + vitest 4 + eslint 8 (legacy eslintrc); (B)
      hiring-tracker/jewelry-factory (+ client-manager web) on TS
      5.7-5.8 + vite 6 + vitest 3 + eslint 9 (flat config). Minor
      alignment inside cohort A rides the C5 wave; the real remainder —
      one fleet standard of eslint 9 flat + vitest 4 + vite 7 + one TS
      version — is deliberate daytime work (flat-config migration ×4
      repos + vitest major ×3 repos), not an overnight bulk edit.*
- [x] **D4** [fleet] Coverage policy normalization — codecov.yml in
      every repo with the event-manager pattern (project: target auto,
      threshold 1% — regression guard; patch: 70% for new code).
      Known app-level debt flagged for engineering backlog, NOT CI
      scope: jewelry-factory's 0.25% suite, wardley-mapper's lint
      ratchet (no-explicit-any ×176), hiring-tracker's runtime vite
      import. *Rolling out 2026-08-16 with the C5 fleet wave: standard
      is target auto / threshold 1% for BOTH project and patch (auto
      patch tracks project coverage — an absolute 70% would block the
      low-coverage young repos outright; ratchet over wall). Survey:
      five node repos had NO codecov.yml (silent defaults),
      hiring-tracker's was toothless (1%/0%). client-manager keeps its
      deliberate config (project off, patch 48% historical baseline) —
      documented exception, Jared's call to converge.* *ROLLED OUT
      2026-08-16 with the fleet wave — [x] for the six node repos; the
      auto ratchet passed jewelry-factory's 0.25% suite on first
      contact exactly as designed.*
- [ ] **D5** [decisions] Held items resolved explicitly: reply-able
      review-thread lint annotations — fleet-wide or not at all
      (decide, don't drift); per-branch images — re-affirm deferred
      until per-branch staging spin-up/teardown exists.
- [x] **D9** [event-manager] E2E stack-image caching — measured on run
      31900653354: "Build stack images" is 15m42s of the 31m53s e2e job
      (49%), a plain `docker compose build` on an empty ephemeral dind
      while the prod-image job builds the same app in ~70s via buildx +
      gha cache. BUILD ONCE applies: build the e2e stack images with
      `cache-from: type=registry` (inline cache), push stack images to
      ghcr on main pushes so PR runs hit a warm cache. Also fold the
      pre-migrated-DB idea from D10 into the stack db image. Expected:
      e2e drops from ~32 to ~17 min. *Landed 2026-08-16
      (event-manager#49): server + webpack get ghcr
      e2e-cache-{server,webpack}:latest image/cache_from refs with
      BUILDKIT_INLINE_CACHE, main runs push them, e2e build list
      trimmed to the two services that actually build. First
      cache-seeding main run follows the merge; warm-build timing vs
      the 15m42s baseline measurable on the next PR run after it.
      Pre-migrated DB image NOT folded in yet — stays with D10.*
- [ ] **D10** [event-manager] Functional-suite wall time — 22m48s of
      the 36m44s integration job (62%) is `composer test:functional`;
      this is PHP time, not infrastructure. Cheapest first: shard via
      matrix (2-3 shards, suite split by directory; wall ~8-11 min at
      the cost of extra runner slots, which exist); or paratest for
      in-process parallelism. Plus: nightly pre-migrated database
      image kills the 2m54s migrations step in every run. Profile for
      pathological tests before deeper surgery.
- [ ] **D8** [decision] Package-ecosystem Dependabot — every repo
      currently watches github-actions ONLY; npm/pnpm, gomod, and
      composer dependencies get no bumps anywhere (audit 2026-08-16).
      Enabling is a noise-policy decision: these dependency trees will
      produce a large initial burst, so it wants `groups` config
      (batch minor/patch into one PR), weekly cadence, and sequencing
      after the C wave. Security-only alerts are already on via GitHub
      defaults; this decision is about version currency.
- [ ] **D7** [fleet] Codecov Test Analytics — test-run times, failure
      rates, flaky-test detection. Two-part rollout per capability:
      (a) canonical test scripts emit JUnit XML (vitest:
      `--reporter=default --reporter=junit --outputFile=test-report.junit.xml`;
      Go: gotestsum --junitfile; PHP: phpunit --log-junit), (b) the
      SHA-pinned `codecov/test-results-action` step with
      `if: ${{ !cancelled() }}` lands ONCE in the shared
      job-node-test-unit.yml and propagates to every caller — the
      Phase C payoff in action; Go/PHP test jobs get the same step
      where they live. Sequence after C1/C2. *Node side landed
      2026-08-16 (workflows#14): the shared test-unit job passes
      `--reporter=default --reporter=junit --outputFile.junit=...`
      through pnpm and uploads via test-results-action (0fa95f0e #
      v1.2.1) even on test failure — no caller or package.json changes,
      arrives fleet-wide with the C5 re-pin. Go/PHP repos remain.*
      *VERIFIED IN PRODUCTION 2026-08-16 on all seven node consumers
      ('All tests successful' Test Analytics lines in every wave PR's
      codecov comment). One field lesson, fixed in workflows#16: pnpm
      10 forwards script args directly and SWALLOWS a literal `--` —
      the flags never reached vitest until the `--` was dropped.
      Remaining: Go (gotestsum --junitfile) + PHP (phpunit --log-junit)
      test jobs.*
- [ ] **D6** [fleet health] Runner assignment latency + mid-job losses.
      REFRAMED 2026-08-16 (Jared: aj78 has 24 slots, never fully
      filled, more available): capacity is NOT the constraint, so the
      observed 10-25 min "queued" waits are assignment-path latency —
      investigate gha-runner-controller's ephemeral spin-up time,
      scale-trigger/webhook lag, and label matching against idle slots.
      Five runner losses on 2026-08-15/16 (job dies at exactly the
      10-min communication timeout, logs 404) on an unsaturated fleet
      point at runner lifecycle/host issues (runner reaped or wedged
      mid-job), not contention — correlate controller logs at the loss
      timestamps (~14:38-14:43 x3, 16:20, 23:42 UTC). Consider
      controller-side watchdog/alerting. Interim runbook (documented):
      empty-commit re-trigger; the rerun API returns 403 for this
      integration.
      More evidence 2026-08-16 early UTC: (a) expense-splitter#20 image
      job wedged queued 34 min (01:07-01:41) while sibling jobs
      scheduled; (b) sustained 10-25 min assignment waits across the
      whole 01:00-02:15 window on an unsaturated fleet; (c) NEW failure
      mode — a *started* job hung mid-step: event-manager
      test-integration (job 95091214278, runner aj78-docker-9eed654c)
      sat 96+ min inside "Run functional tests" (norm ~23 min, started
      00:36:40) with the runner still heartbeating — not the 10-min
      timeout/404 signature; cancel API also 403, cleared 02:13 by
      empty-commit push (concurrency-group cancel). Suggests wedged
      dind/container I/O rather than runner death — worth checking that
      host's dockerd/dind sidecar logs around 00:36-02:13.
      Losses #6 and #7 (2026-08-16, both classic 10-min/404, both died
      near job start): expense-splitter job 95109897071 on
      aj78-docker-35742fc2, died inside "Set up job" 03:33:58-03:43:59;
      event-manager job 95113009982 on aj78-docker-20654a1c,
      04:05:57-04:15:58. Three lifecycle deaths in one night on an
      unsaturated fleet — controller-log correlation at these
      timestamps is the highest-value D6 next step.

### Phase E task board — versioning and releases *(DRAFT 2026-08-16)*

Phases A–D standardized how code is *gated* and *built*. Nothing has ever
standardized how it is *versioned and released*, and it shows: the fleet runs
four schemes, and the one line of guidance we have contradicts a repo that
follows it. This phase closes that.

**What the standard says today, in full.** Principle 7 already binds releases
("packaging, docker, and release steps consume those artifacts — nothing
downstream rebuilds"), Principle 4 hardcodes release jobs to GitHub-hosted, and
Principle 6 exempts release workflows from cancel-in-progress. Image tagging is
well specified under Publishing: ghcr, `<sha>` always, `latest` only on the
default branch, `pr-N` build-only. That is the whole of it. Everything else
rests on one sentence — "Release channel via CalVer tags + `edge` moving tag
(client-manager pattern) where a repo has real releases" — which names a
pattern without defining it, leaves "real releases" undefined, and says CalVer
while gha-runner-controller ships semver `v*` tags. It has never been reconciled.

**Current state, surveyed 2026-08-16:**

| repo | how a version is derived | who consumes it |
|------|--------------------------|-----------------|
| gha-runner-controller | `git describe --tags` + monotonic `DEB_VERSION` (`0.1.0+git3.ab12cd3`); semver `v*` tags | apt (ordering decides upgrade vs downgrade) |
| client-manager | CalVer tags + `edge` moving tag, `VERSION=${GITHUB_REF_NAME#v}` | operators |
| gofast | no tags: `build-<run_number>` + `sha-*` + `latest` | homelab compose pull |
| event-manager | none — versions read from toolchain pin files only | nothing |
| lid-firmware | none detected, but `publish-firmware` ships artifacts | devices / whoever flashes |
| wardley-mapper, credit-watch, expense-splitter, flight-watch, hiring-tracker, jewelry-factory | none detected | nothing |

- [ ] **E0** [decision] **Does a version have a consumer?** The discriminator
      is not application type, it is whether anything outside the repo makes a
      decision from the version string. apt does. A dependency resolver does.
      A human choosing a firmware image does. `docker compose pull` of
      `:latest` does not. Classify every repo against that test first —
      everything below follows from it.
- [ ] **E1** [decision] **How many schemes.** Proposal: two, not one and not
      five. (a) *Traceable build identity* as the default — `sha-<short>` plus
      `latest` on main, no hand-maintained product version, no release
      ceremony. (b) *Ordered release version* — derived from tags via
      `git describe`, monotonic and sortable — only where E0 found a real
      consumer. A third, true semver with human judgement per release, applies
      only if the fleet publishes a library whose dependents' resolver reads it
      (today: the `@aurum-alpha/*` packages client-manager consumes).
- [ ] **E2** [decision] **semver or CalVer** for scheme (b), and reconcile the
      standard with whichever loses. They answer different questions: semver
      promises compatibility, CalVer reports recency. A repo that cannot keep
      the compatibility promise should not make it.
- [ ] **E3** Release workflows consume CI artifacts. *This is Principle 7,
      not new policy — gha-runner-controller's release.yaml recompiles and
      re-runs the tests, a fourth build of the same code. Audit every repo's
      release path for the same violation.*
- [ ] **E4** [decision] **Moving tags vs the pinning principle.** We SHA-pin
      every third-party action because "version tags are mutable pointers",
      then ship ourselves `latest` and `edge`, which are exactly that. Either
      the risk is different for first-party images (state why) or deploys
      should pin digests. Currently unexamined.
- [ ] **E5** Once E0–E2 land: write the rule into Publishing, replacing the
      CalVer sentence, and add a checker where it is mechanizable (a repo
      claiming scheme (b) has tags; a repo on (a) has no stale version file).

**Exit criteria:** every repo's version scheme is a deliberate choice traceable
to a named consumer, the standard states the rule without contradicting any
repo that follows it, and no release path rebuilds what CI already built.

### Phase A — per-repo catalog conformance *(COMPLETE 2026-08-15)*

**Exit criteria met 2026-08-15**: every gap-matrix row shows ✓ for jobs that
exist; remaining ✗/deferrals (test scaffolding for expense-splitter,
flight-watch, wardley-mapper; codecov rollout; dual-stack job-id naming;
event-manager eslint) are Phase B work by design.

Each repo converges on the catalog **in place** — no shared repo involvement yet.

| Work item | Repos |
|---|---|
| Onboard to full standard in one pass (A0a — done, PR open) | wardley-mapper |
| CI baseline: runner line, SHA pins + Dependabot, concurrency, `ci-ok` (A0b) | lid-firmware |
| Script renames: `check`/`tsc` → `typecheck`; `test` → `test:unit` (non-watch) | credit-watch, expense-splitter, flight-watch, jewelry-factory, hiring-tracker |
| Remove ESLint PR-annotation machinery (Principle 10) | jewelry-factory |
| Tier-2 → tier-3 migration (drop pipeline-base builder) | hiring-tracker |
| Add missing `build` job; emit `dist` artifact (BUILD-ONCE) | credit-watch, expense-splitter, flight-watch |
| Prod Dockerfile → thin runtime COPY of artifact (Principle 8); `image` job downloads artifact | all TS repos |
| Canonical job ids + `ci-ok` rollup | every repo (incl. wardley-mapper, lid-firmware) |
| Go catalog fill: dedupe double build, add `vet`, lint, coverage | gofast, gha-runner-controller |
| Composer scripts renamed to canonical names | event-manager |
| Go 1.26.6 bump (stdlib advisories, matches client-manager) | gofast, gha-runner-controller |

**Exit criteria**: every gap-matrix row shows ✓ for jobs that exist; only known
deferrals (missing test suites) remain ✗.

### Phase B — byte-identical jobs across repos

- Normalize same-id jobs to identical YAML (step order, names, everything);
  verify mechanically (diff/checksum of job blocks across repos).
- Codecov v7 rollout to every repo with tests (adds: credit-watch, gofast;
  converts: hiring-tracker CLI → action).
- Test scaffolding where none exists (expense-splitter, flight-watch: vitest +
  starter suites) so `test-unit` stops being ✗.
- Tooling convergence decisions executed (eslint/vitest as TS standard; jest and
  oxlint holdouts resolved per repo).

**Exit criteria**: for each catalog job id, the YAML block is byte-identical in
every repo that has it.

### Phase C — extraction to aurum-alpha/workflows

- Move byte-identical jobs to reusable workflows / composite actions; repos
  become thin callers pinned by SHA (same pinning policy as third-party actions).
- Gap-filling flow activates: repos missing a job adopt the shared one.
- Custom actions written where marketplace actions fall short (Principle 5);
  shared stack images (`ci-node`, `ci-go`, `ci-php`) published from this repo
  if/when tier-2 need arises.
- event-manager's reusable builder workflow moves here (ends the fork drift
  with hiring-tracker's copy for good).

**Exit criteria**: a fix to a shared job lands once and propagates by Dependabot
SHA-bump PRs to every consumer.

### Phase D — hard gates and held improvements

- AUR-565 round 2 (static bundle serve, globalTeardown sweep, scoped guards,
  keycloak-init hardening) → e2e/integration `continue-on-error` comes OFF.
- PHPStan bootstrap fixed → static analysis hard-gates.
- ~~client-manager pnpm 10/11~~ **resolved** (user-level npmrc — Principle 11).
- Held for future consideration: reply-able review-thread lint annotations
  (fleet-wide or not at all); per-branch images once per-branch staging
  spin-up/teardown exists.
- **Held: build-tooling consistency sweep (Make question).** Audit of
  2026-08-15: Make exists in event-manager (genuine fileset builder with
  file-target dependencies — the model use; runs in the tier-2 container),
  gha-runner-controller (.PHONY task runner + the `deb` packaging chain;
  GitHub-hosted so make is present), and gofast (local-dev wrapper only —
  CI calls scripts/). client-manager uses tools/checks/* executables, no
  Make; TS repos use package scripts. Nothing today needs make on the
  fleet runner image, so it stays out of tier 1 FOR NOW — but Make MAY
  become a tier-1 dependency if repos adopt it properly. Direction of
  travel, deliberately shelved as a later cleanup: per-repo one-off build
  scripts accumulate drift and black-box logic; prefer native toolchains
  or a real build system (Make used as designed — file sets, dependency
  edges), possibly converting the Go repos to Make. When picked up, do it
  as a fleet-wide assessment of ALL per-repo tools/scripts (tools/checks/*,
  scripts/*.sh, tools/testing/*, package scripts) for consistency,
  black-box one-offs, and drift — not repo by repo.

## Decisions log

| Question | Decision |
|---|---|
| Make on the runner image | Not tier-1 today (no repo needs it there); revisit with the held build-tooling sweep — Make may become tier-1 if repos adopt it as a real build system |
| Action pinning | SHA-pin everything + `# vX.Y.Z` comment + Dependabot |
| Coverage | Codecov v7 everywhere supportable |
| Per-branch images | Deferred until staging infra exists |
| Shared workflows home | New `aurum-alpha/workflows` repo |
| Build vs gates order | Build first, then parallel gates |

## Open items

Tracked inside the phase plan above: AUR-565 round 2 and PHPStan bootstrap
(Phase D), Go 1.26.6 bumps (Phase A), test scaffolding
for expense-splitter/flight-watch (Phase B).
