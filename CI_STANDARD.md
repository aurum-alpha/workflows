# CI Pipeline Standard

Status: **agreed 2026-08-14** (rev 2 after Jared's review). Remaining open items at bottom.

## Principles

1. **One source of truth per pin.** `.node-version`, `go.mod`, `.php-version`,
   `packageManager` — CI *derives* versions (`node-version-file`, `go-version-file`),
   never restates them. A version bump is a one-file diff.
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

## Standard job DAG — build first

The cheapest, most fundamental gate is "does it build." A broken compile fails one
job instead of ten, and the build job primes caches and emits artifacts downstream
jobs reuse (e.g. binaries handed to docker packaging).

```
install ──► build ──► lint ─────────┐
                  ──► typecheck ────┤──► integration / e2e ──► package / publish
                  ──► unit tests ───┘         (main + tags only)
                              └──► "ci ok" rollup job (the only required check)
```

- Quality gates run in parallel *after* build, never serialized among themselves.
- **Hard rule — BUILD ONCE.** The build step produces *every* required artifact
  type (all build-arg variants included) and later steps — packaging, docker,
  release — pull those artifacts from cache/artifact storage. Nothing downstream
  ever rebuilds.
- Stack note: for TS, `tsc --noEmit` is the compile assertion and stays a gate;
  "build" means the real bundle/transpile (vite/esbuild) — this is where the
  production artifact is produced.
- `ci ok` (`if: always()`, fails on any failure/cancel in needs) is the single
  required check, so adding/removing gates never touches branch protection.

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
      point each repo's required status check at `ci ok`.

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
