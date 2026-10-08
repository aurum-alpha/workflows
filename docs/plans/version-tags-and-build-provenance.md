# Plan: `latest` = release, `dev` = rolling main, dual build UI

Status: **implemented in tree** (2026-10-07). Rollout tracking: workflows#621.

Tracks the fleet discussion: registry tags must not make `:latest` mean “newest
main,” and every product must show whether the running build is an official
release or a development build—with matching identity on client and server.

## Decisions (locked)

| Topic | Decision |
| --- | --- |
| Rolling main tag | **`dev`** — moves on **every** green push to `main`, release commits included. On a release build, **`dev` and `latest` point at the same digest**. |
| Release tag | **`latest`** — moves **only** on a main push where **`.version` changed** (same gate as `v<semver>` today). **No transition period** for the old “`latest` = head of main” semantics. |
| Immutable pin | **`sha-<short>`** — unchanged; use for one-off pins and forensics. |
| Staging deploys | Portainer stacks on **`aurumalpha.dev`** pin **`sha-<short>`**. Pinning `:dev` was tried and reverted on 2026-10-08: the pin never changed, so no stack redeployed. |
| Production deploys | Portainer stacks for production keep **`:latest`** (now meaning latest **release** only). |
| Settings UI | **Dual UI**: show **client (bundle)** build provenance and **server (API)** build provenance when both exist. |

## Registry semantics (target)

After catalog + 010-ci update:

| Tag | Moves when | Intended consumer |
| --- | --- | --- |
| `dev` | **Every** push to `main` | Staging (`*.aurumalpha.dev`), internal “always main” |
| `latest` | Main push where `.version` changed only | Production default pin (`*.aurumalpha.com`) |
| `v<semver>` | Same as `latest` | Production semver pin (`v*@sha256:…`) |
| `sha-<short>` | Every push to `main` | Exact commit pin |

OCI label `org.opencontainers.image.version` continues to use **`stamp`**
(release version or `MAJOR.MINOR.(patch+1)-dev.<sha7>`), not raw `.version`.

## Deploy repo (`aurum-alpha/deploy`)

**In scope for this program, sequenced last.** CI and product repos must publish
**`:dev`** and **`:latest`** (release-only) correctly before any stack or pin
file switches to those tags. Until then, staging may keep **`sha-<short>`** pins
even though the registry already carries `:dev`.

- **Production** stacks: image references stay on **`:latest`** (new meaning:
  latest release) once CI semantics are live.
- **Staging** (`environments/staging/*/pins.json` today: **`sha-<short>`** per
  service): move to **`:dev`** so `*.aurumalpha.dev` tracks rolling main without
  a pin PR on every merge (optional: keep CI opening pin PRs that refresh digest
  only if you still want immutable records — default is floating `:dev` in
  `pins.json`).
- Document in deploy README / stack comments: production = `latest`, staging =
  `dev`, pin = `sha-…` or digest.

(GHA runner controller runner image may remain `latest`-only with no `v*`; that
repo’s own comments already treat runner tags separately.)

## Build provenance (WC2 + Go)

### Data model (client bundle)

Extend catalog `ClientBuildVersion` / `virtual:app-version-info`:

| Field | Source | Role |
| --- | --- | --- |
| `releaseVersion` | `.version` at build time | Release line (changes on release PRs only). |
| `buildStamp` | Build job `stamp` output | **Primary display string**; matches Go + OCI. |
| `isReleaseBuild` | `version_changed == true` at build time | Badge: Release vs Development. |
| `channel` | `release` \| `development` \| `local` | Copy + WC5 error context. |
| `gitCommit`, `buildDate`, `gitBranch`, `environment`, `isDirty` | unchanged | Support + local dev. |

**CI rule:** `job-build-js-vite` (and other JS build jobs) pass `stamp` and
`version_changed` into the bundler via env (e.g. `AURUM_BUILD_STAMP`,
`AURUM_RELEASE_BUILD`). The Vite plugin must **not** re-implement the Python
stamp algorithm.

Local `pnpm dev`: `channel: local`; show `releaseVersion`, commit, dirty—no fake
release stamp required.

### Server (API) provenance

Go products already stamp `internal/version` with **`stamp`**. Expose the same
facts on an operator-facing read (e.g. small JSON on `/api/config`, system
settings payload, or dedicated build metadata route—product chooses mount,
shape is fleet-common):

- `build_stamp`, `release_version`, `commit`, `built_at` (names TBD in contract).

### Dual UI (`platform-web`)

Add a shared **Build provenance** block (two sections when both sides exist):

1. **Web client** — from `virtual:app-version-info` (`buildStamp`, badge, commit).
2. **API** — from server endpoint above (`buildStamp`, badge, commit).

Copy rules:

- Headline: **`buildStamp`** (so dev builds always show `-dev.<sha>` when not release).
- Badge: **Release** if `isReleaseBuild`, else **Development build** (WC6-friendly).
- Subline when `buildStamp !== releaseVersion`: “Release line {releaseVersion}”.

Mount on existing Settings / System / Admin screens (090 WC2); no new route
unless a product has no suitable surface.

## Implementation phases

Order is fixed: **registry behavior and products first; deploy repo last.**

### Phase 1 — Standards + catalog (workflows)

1. Update **`standards/010-ci.md`**: `latest` = release only; `dev` = every main
   build; document `sha-` and `v*`.
2. Update **`job-image-publish`**: default tags — `dev` on default branch;
   `latest` gated on `version_changed` (caller passes enable rule or catalog
   adds shared input wired from build job outputs).
3. Conformance: ensure no repo reintroduces unconditional `latest` via
   `extra_tags`.
4. **`job-deploy-pin`**: defer staging `:dev` pin shape until Phase 4 (or gate
   new behavior behind catalog version repos have adopted).
5. **`tools/templates/client-build-version/`**: env injection + extended
   `resolveVersionInfo`; update README and 090 WC2 cross-reference.

### Phase 2 — Shared UI (platform-web)

1. Types for extended provenance + **`BuildProvenanceBlock`** (client-only and
   client+server variants).
2. Contract test or fixture for display copy (optional).

### Phase 3 — Products (checklist)

Per image-shipping repo (after Phase 1 is merged and main publishes `:dev` /
release-only `:latest`):

- [ ] CI still passes `version_changed` for `v*` (unchanged).
- [ ] Green main builds: verify tags (`dev` every push; `latest`/`v*` on release only).
- [ ] Resync client-build-version template; wire dual UI on settings.
- [ ] Go API: expose server build metadata; settings fetch + render second block.
- [ ] Product `OPERATIONS.md`: document new tag meanings (staging will use `:dev`
  after Phase 4; prod `:latest` = release).

Repos: client-manager, credit-watch, expense-splitter, event-manager,
hiring-tracker, jewelry-factory, wardley-mapper, lead-qualifier,
gha-runner-controller (controller image; runner image policy unchanged),
others on GHCR as discovered.

### Phase 4 — Deploy (aurum-alpha/deploy) **last**

Only after Phase 1 is live fleet-wide and Phase 3 repos prove tags on main:

1. Update **`job-deploy-pin`** (workflows) if needed: staging pins **`:dev`**
   instead of **`sha-<short>`**.
2. Audit Portainer stack files and **`environments/staging/*/pins.json`**.
3. Switch staging to **`:dev`**; verify production stacks remain **`:latest`**
   (release-only registry meaning).
4. **`README.md` / `AGENTS.md` / `tools/pin`**: staging = `dev`, production =
   `latest`, forensics = `sha-…` or digest.
5. Ops note: after a release, staging `dev` and production `latest` may match;
   the next non-release merge moves `dev` ahead while `latest` stays on the
   release until the next version bump.

## Verification

- **CI:** On a non-release main push, published tags include `dev` and `sha-*`
  but not `latest` or `v*`. On a release push, `dev`, `latest`, `v*`, and
  `sha-*` all point at the **same** digest.
- **Staging:** Pull `:dev` after a merge; UI shows Development + `-dev.` stamp.
- **Production:** Pull `:latest` only after release; UI shows Release + clean semver.
- **Dual UI:** client stamp and server stamp both visible; mismatch visible after
  partial deploy (intentional diagnostic).

## Open detail (not blocking decisions)

- Exact JSON field names for API build metadata (add to a small contracts
  fragment vs ad hoc per product until converged).
- Whether `job-build-js-esbuild` (event-manager server bundle, platform-reference
  services/ts) gets the same env injection pattern as Vite.
