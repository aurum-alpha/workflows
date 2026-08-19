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
2. **Local = CI.** A developer must be able to run any gate locally with one
   command, and get what CI gets. **The shared job is that command's single
   definition** — not a per-repo script it wraps.

   *Amended 2026-08-17.* This originally read "every gate is a runnable script
   in the repo (`tools/checks/*`); the workflow job is a thin wrapper with the
   same name." That is backwards under Principle 19: it makes each repo the
   author of its own gate and the catalog a wrapper around eleven opinions.
   Best practice is defined once, in the catalog, per language and framework;
   repos adopt it. Reproducibility was the goal and a per-repo script was only
   ever the mechanism — and a poor one, since B5 existed solely to police
   byte-identity between copies that kept diverging, which is the tell that
   there should have been one copy.

   What the original rule was right about, and still binds: **no logic that
   exists only in YAML.** A shared job runs a tool with flags — `pnpm exec
   eslint client --max-warnings 0` — which a developer can read off the job and
   run verbatim. It must not grow branching, conditionals or computation that
   cannot be reproduced by typing the command. The moment a job needs logic, the
   logic belongs in a committed script that both CI and the developer invoke.

   Repo-specific *policy* still goes in the repo — but as configuration the tool
   reads (`vite.config.ts`, `eslint.config.mjs`), never as a wrapper script whose
   job is to pass a path.
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
   cancel-in-progress on pull requests — but **never cancel a run that can
   publish**, which now means never cancel the default branch:
   `cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}`.
   This rule used to read "except release workflows", which keyed on the file.
   Principle 17 folded publishing into `ci.yml`, and the exemption silently
   stopped applying — the act moved, the carve-out did not follow it.
   *Caught in production 2026-08-16: gha-runner-controller run 31968542199
   carried the first `.version` change, a second merge landed four minutes
   later and cancelled it, and the release never ran. Nothing reported it: a
   cancelled run is not a failed one, so the rollup stayed green and the
   release simply did not exist.* Publish jobs that need stricter
   serialization than the workflow (an image tag several runs race to move)
   take a job-level `concurrency:` group of their own.
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
13. **Every artifact carries its provenance.** Build timestamp and commit SHA
    are baked into every artifact at build time and surfaced by the software
    itself: `-ldflags` for Go, a generated file at a fixed path in `dist/`
    read through one helper for TS and PHP. This is not a version — it is
    metadata, it needs no scheme and no bookkeeping, and it is why the fleet
    does not use CalVer. "How old is this?" and "what commit is this?" are
    questions a timestamp and a SHA answer exactly, for free, on every build.
    A date-shaped version number answers them worse, and demands increment
    rules, format debates and a validator to enforce both.
14. **A version is a commit, not a tag.** Where a repo has a version, it lives
    in a committed file and the build stamps what that file says. Tags are
    mutable pointers — the reason we SHA-pin every third-party action — so
    trusting our own is the same bet with the same downside. A version in a
    file is immutable, reproducible from history, and *reviewable*: the claim
    "this release is 2.0.0" arrives as a diff someone can challenge. CI may
    create a tag afterwards as a human index; the direction is always
    file → build → tag, never tag → build.
15. **The repo is versioned, not the artifact.** Artifacts built from one
    commit share one provenance and therefore one version — a repo shipping
    three images does not give them three version files, for the same reason
    a repo does not pin pnpm twice. Something in the repo that is not built
    from its source (a base image rebuilt on a schedule) is not a versioned
    product at all: it carries provenance metadata and nothing else.
16. **A version exists only where something consumes it.** The test is not
    what kind of application it is, it is whether anything outside the repo
    makes a decision from the version string. apt does, when it compares
    versions to decide upgrade against downgrade. A dependency resolver does.
    `docker compose pull :latest` does not. Where nothing decides, there is no
    version — only provenance — and no release event to maintain.
17. **Release is promotion, not production.** A release publishes bytes that
    already exist and already passed: same artifact, new name, wider audience.
    It never compiles, never re-tests, and cannot change what is shipped. It
    follows that publishing is a conditional job inside the normal CI run, not
    a separate workflow — the run that built and gated the artifact is the run
    that publishes it, so there is no cross-run artifact fetch and no question
    of which build a release came from. It also means the publish path is
    exercised on every pull request with only the final push suppressed,
    instead of being the least-tested code in the repo at the exact moment it
    matters most.

    Two mechanical consequences, because writing the principle was not enough
    to make anyone follow it:

    - **The main-only condition goes on the publishing *step*, never on the
      job.** `if:` at the job level means the job never runs on a pull
      request, so its first execution ever is the one that has to work. Guard
      `docker push` / `gh release create`, and let everything above it —
      artifact downloads, packaging, assertions — run on every PR.
    - **Publish jobs belong in `ci-ok`'s `needs:`.** A publish job outside the
      rollup can fail into a green required check.

    *Learned from gha-runner-controller's `release`, which broke both rules at
    once. It was job-level gated to main, so it had never run before the merge
    that had to cut 0.11.1; it failed there on an artifact download a pull
    request would have caught. And it was missing from `ci-ok`, so the required
    check reported success at 20:06:39 while `release` failed at 20:17:21 —
    eleven minutes later, into a main branch that stayed green. Nobody would
    have noticed except that the release was visibly absent.*

18. **One workflow per repo.** `ci.yml` IS the pipeline. A second workflow file
    cannot be gated by `ci-ok`, so branch protection cannot see it, so nothing
    stops it publishing from a commit that failed — and nothing reviews it
    against the rules the rest of the repo follows. *Learned from
    gha-runner-controller, which carried four workflow files and gated one:
    `controller-image.yaml` published on push to main without waiting for a
    single test, recompiled the binary inside a multi-stage Dockerfile against
    Principles 7 and 8, and still tag-pinned its actions against the SHA-pin
    rule — three violations that survived every sweep because nothing looked
    there.* Work in a repo that genuinely shares no source with the rest (a
    base image rebuilt on a schedule) still lives in `ci.yml`, split by a
    `changes` job so a Dockerfile edit does not compile Go and a code change
    does not rebuild an unrelated image. Where two things need different
    concurrency, use a job-level `concurrency:` group rather than a second
    file.

19. **The catalog is where best practice lives; a repo-local job is a gap in
    it.** `aurum-alpha/workflows` is not a convenience library of things several
    repos happened to need. It is the definition of how this organisation builds,
    lints, tests and ships each language and framework it uses — and repos are
    standardized *onto* those definitions rather than each arriving at its own
    answer.

    The target state is a repo with **no repo-local jobs at all**. Its `ci.yml`
    names its deployable units, wires the DAG, and calls the catalog.

    A repo-local job is therefore not a style violation, it is a **claim about
    the catalog**: *"nothing here covers this case."* That claim is sometimes
    true — gha-runner-controller packages a `.deb` with nfpm and builds a runner
    image from the actions-runner base, and no other repo does either. It is
    often false, and then the fix is a catalog job, not a local one.

    So every local job carries the gap it represents, and closing that gap is
    backlog rather than decoration. `tools/check-caller-thinness` holds the
    allow-list; an entry there is a debt with a name, not a permission.

    *This is what makes the difference between a standard and a suggestion. Two
    repos solving the same problem two ways is not diversity, it is the fleet
    having no opinion — and an organisation with no opinion re-litigates the
    same decision every time someone starts a service.*

## Standard job DAG — build first, per artifact

**Fail fast.** If the thing does not compile, there is nothing worth testing —
so the first gate is always "does it build", and no lint, vet or test runs until
it passes. A broken compile fails one job in seconds instead of ten jobs in
minutes, and it fails with the one error that caused the other nine.

The build job also produces and stores the artifact every later job uses.
Nothing runs beside it; everything runs after it.

```
build ──┬─► lint ──────────┐
        ├─► vet ───────────┤
        ├─► typecheck ─────┼─► integration / e2e ─► image ─► image starts ─► ci-ok
        └─► unit tests ────┘   (uses the build artifacts)      (fire it up)
```

Read as a sequence, because that is what it is:

1. **build** — compile, and upload the artifact. For TS that is `vite build` for
   the client and `esbuild` for the server; for Go, `go build`; for firmware,
   `pio run`. One build per artifact, and it happens once (see BUILD ONCE).
2. **codebase gates** — lint, vet, unit tests, typecheck. These run in parallel
   with each other and only after the build has passed. A repo whose code does
   not compile has nothing worth linting.
3. **integration / e2e** — against the artifacts from step 1, never a rebuild.
   This is the first point at which the thing under test exists.
4. **image / package** — the shippable artifact, assembled from step 1's output.
5. **something runs the image.** A build that links and an image that boots are
   different claims, and only the second one is what ships. Two ways to satisfy
   this, and the requirement is the rule rather than either mechanism:

   - **e2e or integration tests against the container.** Strictly stronger — it
     proves the image runs *and* that it does its job — and where this exists
     nothing else is needed. The image is then built before step 3 rather than
     after it, because the tests need it.
   - **start it.** For a service with no e2e suite, run the container and wait
     for it to listen. `job-image-docker` does this by default.

   A repo taking the first route sets `assert_starts: false` on the image job,
   which is only legitimate when a job actually depends on that image — checked
   by D7, not taken on trust. If the container needs a database to reach the
   point of listening, give it one (`start_services`); an image that cannot
   start without postgres is not exempt from having to start.
6. **`ci-ok`** — the rollup, and the only required check.

**Each artifact gets its own DAG.** A repo with a React client and an Express
server has two of these running side by side — `client-ts-react-build` gating
the client's lint and tests, `server-ts-express-build` gating the server's — and
they converge only where a real artifact contains both. A failing `go vet` must
not hold up the React lint, and a broken `tsc` must not stop the Go tests from
telling you what else is wrong.

- **Quality gates run in parallel with each other, never serialized among
  themselves**, and never beside the build.
- **Every job sets `timeout-minutes`.** A runner that hangs reports the same
  failure a real break does, and takes the default six hours to say so — during
  Phase F one job sat in "Set up job" for ten minutes on a self-hosted runner
  while every other job in the run passed. Ceilings are generous enough never to
  clip honest work (15m for gates, 20m for Go lint and tests, 30m for image
  jobs) and exist only to bound a hang.
- **Hard rule — BUILD ONCE.** The build step produces *every* required artifact
  type (all build-arg variants included) and later steps — packaging, docker,
  release — pull those artifacts from cache/artifact storage. Nothing downstream
  ever rebuilds.
- Stack note: for TS, `tsc --noEmit` is the compile assertion and stays a gate;
  "build" means the real bundle/transpile (vite/esbuild) — this is where the
  production artifact is produced.
- **Every job must also be reachable from `ci-ok`.** Having a `needs:` and
  blocking something are two different properties: a job can sit correctly
  downstream of the build and still be absent from the rollup, in which case its
  failure stops nothing. Both are checked (D1 and D6).
- `ci-ok` (`if: always()`, fails on any failure/cancel in needs) is the single
  required check, so adding/removing gates never touches branch protection.
  The check reports under the job id `ci-ok` (no display-name override) —
  that exact string is what branch protection requires, fleet-wide.
- **`always()` and not `!cancelled()`, deliberately.** A push that supersedes an
  in-flight run cancels its jobs, and `ci-ok` then runs, sees `cancelled`, and
  goes red — so every quick follow-up push leaves a red check behind on a run
  nobody cares about. The tempting fix is `if: !cancelled()`, which skips the
  rollup when the *run* was cancelled while still catching an individual job
  that was cancelled by its own timeout.

  Do not. A skipped required check can satisfy branch protection, so a
  cancelled run would leave a PR mergeable with no gate having reported. The
  noise is the cheaper failure: a stale red is confusing, a silent green is
  dangerous. Read the newest run, not the superseded one.

### Multi-codebase repos — one DAG per stack, converging at packaging

Several repos hold two codebases in one tree: React/TS + Go (gofast), React +
Node (client-manager, event-manager's web), React + PHP (event-manager). **Each
stack runs the standard DAG independently, and they converge only at packaging
and integration.** All of it lives in the one `ci.yml` (Principle 18) — a second
stack is not a second workflow.

```
web-build ───► web-lint ──────────┐
          ───► web-typecheck ─────┤
          ───► web-test-unit ─────┤
                                  ├──► image / package ──► test-integration ──► ci-ok
api-build ───► api-lint ──────────┤          (converge)
          ───► api-test-unit ─────┘
```

- A stack's gates depend on **that stack's** build and nothing else. A failing
  Go vet must not hold up the React lint, and a broken `tsc` must not stop the
  Go tests from telling you what else is wrong. Cross-stack `needs:` serialize
  two independent pipelines into one long one and hide half the failures behind
  the other half.
- The convergence point is wherever the two stacks first meet in a real
  artifact: the image that ships the compiled binary *and* the built UI, the
  package that contains both. That job needs every stack's build **and** every
  stack's gates — it is the first place a cross-stack failure legitimately
  blocks something.
- Integration/e2e sits after the converged artifact, because that is the first
  point at which the thing under test exists.
- Naming follows B4 dual-stack rules: a bare `lint` in a two-stack repo reads as
  whichever stack the reader assumes, so both get a prefix (`web-lint`,
  `go-lint`).
- *Learned from event-manager, whose DAG ran backwards — `web-build` needed
  `web-test-unit`, and `php-build` needed four gates plus `web-build` — so the
  cheapest, most fundamental signal in the repo was the last thing to run, and a
  compile break surfaced only after every test had finished. Also from
  lid-firmware, where `publish-firmware` needed `build` alone: firmware
  published from main without unit tests ever having passed.*

## Publishing

- Registry: ghcr. Tags: `<sha>` always; `latest` only on the default branch;
  `pr-N` build-only (no push).
- **Every green build publishes.** A run that passes the gates makes its
  artifacts available — images under `sha-<short>`, build outputs as run
  artifacts — release or not. Anything green is installable and testable
  without ceremony; that availability is the normal state, not a privilege a
  release confers.
- **What a release adds is a name, durability and an audience — never
  different bytes.** Run artifacts expire and are addressed by run id; a
  release republishes the identical artifact under a stable version anyone can
  ask for by name, in the place consumers fetch from (a GitHub Release for the
  `.deb`, a `vX.Y.Z` image tag alongside `latest`). It is also the point where
  a human blessing becomes visible: someone claimed this build is fit to
  consume. That is the whole of it — see Principle 17.
- **SemVer is the only version scheme**, and only for repos that pass the
  Principle 16 test (today: gha-runner-controller's `.deb`, where apt orders
  versions to decide upgrades). CalVer is not used anywhere: provenance
  metadata answers recency better (Principle 13). Repos with no consumer have
  no version file, no release step, and deploy from `latest` or a SHA.
- **Per-branch images: deferred** until per-branch staging spin-up/teardown infra
  exists. Revisit then.

### CI does not commit to the repository it is testing

**Nothing generated by a build gets committed back.** Rule `CM` fails any job
whose steps run `git push`.

hiring-tracker had a job that stamped `version-info.json` after the build, then
committed and pushed it to `main`. Three things follow from that ordering:

- the image built in that run carries the **previous** commit's stamp, because
  the new one is written after the build has already happened;
- the pushed commit is marked `[skip ci]`, so the stamp it contains is never
  built into anything;
- the job needs `contents: write` on the default branch to do it.

It had also stopped running four merges earlier and said nothing. The stamp on
`main` read `8e1ff83` while `main` was at `31752c5`, so the version panel in
production reported a build from four commits ago. A stamp that lies is worse
than no stamp, and this one had no way to report that it had stopped.

The generated file is a build output, so it is produced **during** the build and
emitted into the build output — for hiring-tracker, a vite plugin emitting
`version-info.json` into `dist`, which is the `/version-info.json` the client
already fetches. It describes the commit it was built from because it is built
from it, and there is nothing to commit.

This is the same shape as the five before it: a mechanism keyed on something
adjacent to the thing it is supposed to guarantee. "The stamp is correct" was
implemented as "a job commits a file", and once the job stopped, the file stayed
— still present, still parseable, still wrong.

`contents: write` for `gh release create` is unaffected: publishing a release
adds no commit to a branch. The rule is about commits, not about the permission.

### A start check must not destroy its own evidence

`docker run --rm` removes a container the moment it exits — and a container that
exits is the one failure a start check exists to catch. So the cleanup's
`docker logs` runs against a container that is already gone:

```
##[error]fastgen exited before becoming healthy (state: removing).
Error response from daemon: No such container: a0745cb9ccd6…
```

That is the whole diagnostic. Three checks across two repos reported the exit
and none of the reason, and one of them took two rounds to yield a one-line
nginx error that `docker logs` would have printed immediately.

**Start checks do not use `--rm`.** They remove the container explicitly in the
cleanup trap, after dumping its logs — and the logs of any service container
too, since a service that dies takes the app with it and the app's own logs
rarely name which one.

The same reasoning covers the checks themselves: a check whose failure output
does not distinguish "it exited" from "it exited *because*" costs a round of CI
per failure, which on a starved runner pool is the expensive resource.

### Concurrency is per ref, and a pull request is not its branch

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
```

The group keys on `github.ref`, and what that holds depends on the event:

| event | `github.ref` |
|---|---|
| `push` | `refs/heads/<branch>` |
| `pull_request` | `refs/pull/<n>/merge` |

Three consequences follow, and all three matter:

**A newer commit on a pull request cancels the older run.** Same PR, same ref,
same group. This is what makes `ci-ok` go red on superseded runs — see
`always()` above.

**Different branches and different pull requests never cancel each other.**
Different refs, different groups. Any number of PRs run at once; the only limit
is runners.

**A push run and a pull request run for the same commit are in *different*
groups.** They cannot cancel each other, so if `push:` fires on feature
branches the entire DAG runs twice per commit, for the same answer.
hiring-tracker did exactly that, and its history shows the pairs plainly:

```
1e69b584   #143 push        #144 pull_request
6298dddc   #139 pull_request #140 push
```

Hence rule `TRG`: **`push:` lists the default branch only.** The pull request
run already gates the branch. On a four-runner pool, one repo quietly taking
double capacity is most of a starvation problem.

`main` keeps `cancel-in-progress: false` because a main run can publish, and
cancelling it drops the publish silently.

### Waiving the start check costs a sentence

Some images genuinely cannot boot in CI. wardley-mapper and expense-splitter
need Replit's IdP — `REPLIT_DOMAINS` and OIDC discovery against `replit.com` —
and there is no version of those containers that starts without it.

The tempting answer is to let the check fail and agree to ignore it. That was
tried, and it is how wardley-mapper's `main` came to sit red on a failure
everyone had already accepted. A permanently red default branch is worse than no
check at all: it teaches people that red means nothing, and it hides the next
real failure behind an expected one.

So `job-image-docker` takes `start_blocked_by`, and it is **a string, not a
boolean**, on purpose:

```yaml
    with:
      start_blocked_by: >-
        Replit IdP — needs REPLIT_DOMAINS and OIDC discovery against replit.com
```

The job prints the reason as a warning, skips the start check, and stays green.
Rule `D7` accepts it **only because it is non-empty** — an empty string is
reported as a violation, because a flag would say "this image is exempt" without
ever saying why or until when. A sentence names the blocker, which makes the
waiver visibly stale the moment the blocker is gone, and makes it greppable
across the fleet when someone asks which images nothing starts.

This is the same choice as the govulncheck `allow:` list and the eslint severity
tiers: the honest middle is not "disable the rule" and not "block everything",
it is to record precisely what is accepted, and why, in a form that expires.

### Never write the skip token in a commit message, even to describe it

GitHub reads `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]` and
`***NO_CI***` from **anywhere in the head commit's message, body included**, and
on a match creates no workflow run at all. Not a startup failure, not a skipped
run — nothing. The PR shows zero checks, which reads exactly like a long runner
queue.

The commit that removed hiring-tracker's skip-ci mechanism explained the bug by
quoting the token in its body, and was skipped by it. Seventeen minutes were
spent reading the absence as runner starvation before the cause was found.

**Zero check runs does not tell you which of the two it is.** An earlier version
of this section claimed a queued job always appears as a check run, so an empty
list had to mean the run never existed. That is wrong, and flight-watch
disproved it within the hour: run 57 sat in `pending` and run 56 in `queued` for
27 minutes, both with zero check runs on the pull request, because a run
publishes no check runs until its jobs are assigned to a runner.

The only way to tell is to ask for the runs rather than the checks:

```
actions_list list_workflow_runs --branch <branch>
```

A `pending` or `queued` run with no jobs is starvation. **No run at all** is the
skip token, a trigger that does not match, or a startup failure — and those three
are distinguished by whether a run exists with conclusion `startup_failure`.

Write it as `skip-ci` in prose. Spelling it out in a file is fine — only the
commit message is scanned.

This one cannot be enforced from CI, and the reason is worth stating plainly:
any check that would catch it lives in a run that the token has already
prevented from existing. It goes here because a written rule is the only
mechanism available, not because a written rule is the good one.

### Accepting a vulnerability: an id list, never a warn_only

`job-go-govulncheck` takes an `allow:` input — newline-separated `GO-YYYY-NNNN`
ids — and **not** a `warn_only` flag. The difference is the whole point. A
`warn_only` silences the finding in front of you and every finding after it,
including the one that is exploitable. An allowed id stops blocking; anything
not on the list still fails the job.

The job scans with `-format json` so exemptions key on ids rather than on a grep
over English, and it counts only **symbol-level** findings — those govulncheck
reports with a function in `trace[0]`, meaning code it actually reached. A
module-level finding says "you require this, you do not call it", which is not a
reason to fail a build. It also prints `stale:` for any allowed id no longer
reported, so the list shrinks when the ecosystem catches up instead of
accumulating dead exemptions nobody dares delete.

Every entry needs a reason at the call site. The first two:

```
GO-2026-4887  Moby AuthZ plugin bypass on oversized request bodies
GO-2026-4883  Moby off-by-one in plugin privilege validation
```

Both are daemon-side defects in Moby's request handling. gha-runner-controller
is an API *client* — it talks to a daemon over a socket and runs neither a
daemon nor an AuthZ plugin, so the vulnerable code is never in its process.
Neither has a fixed version in `github.com/docker/docker` at all ("all versions,
no known fixed"; only `moby/moby/v2` ≥ v2.0.0-beta.8 carries the fix), so there
is nothing to upgrade to, and both reports are `unreviewed` — auto-imported from
a third party and unverified by the Go team.

That combination is worth naming, because it is the case an allow-list is for:
a real advisory, correctly reported, against a module we genuinely import, whose
defect is unreachable from how we use it, with no upgrade available. The
alternatives were to block every unrelated change indefinitely, or to stop
scanning. Both are worse than writing down which two we accept and why.

## Coverage

**A CLI `--coverage.exclude` replaces the config's list; it does not extend it.**
That is true of vitest's array options generally, and it has now caused two
regressions in this project from opposite directions:

- `--coverage.include='<unit>/**'` replaced wardley-mapper's curated include and
  took the baseline from 49.46% to 4.24%, turning `codecov/project` red on a
  change that added no code.
- `--coverage.exclude='<sibling>/**'`, the fix for the first, replaced every
  repo's exclude list — so `node_modules`, `dist`, `*.d.ts` and every
  `*.config.*` file re-entered the denominator. hiring-tracker was measuring
  `vite.config.ts` at 0% across 11 lines and counting it against patch coverage.

So the shared job restates the standard exclusions alongside the sibling units,
and the flag adds to a known baseline rather than standing in for the repo's.
A repo needing more than that baseline cannot express it through
`coverage.exclude` in its config and expect it to survive — narrow
`coverage.include` instead.

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

### One-box before the wave — and why it is not a canary

A change to a shared job reaches every consumer at once. So one repo re-pins
first, its CI is watched end to end, and only then does the fleet follow. This
is the **one-box stage**: deploy to a single instance, watch it, proceed.

**It is not a canary.** A canary is ongoing synthetic automation running against
a live production system, whose job is to find issues before customers report
them. Nothing described in this document does that — there is no live system in
the loop and nothing runs continuously. Calling a one-box run a canary inflates
what it proves: a one-box stage retires *integration* risk in the changed
artifact, on one instance, once.

Two consequences that follow from stating it correctly:

- **A one-box repo must be drawn for representativeness, not for ease.** It
  generalises to the fleet only on the axes it shares with the fleet. Pick the
  repo carrying the work the others carry; where no single repo covers every
  axis, the one-box stage is a *set*, not a repo. C2 is the precedent: two
  shared-job bugs surfaced only on the one repo exercising private packages,
  because it was the only repo that could surface them.
- **The fleet has no canary at all.** No repo here runs synthetic checks against
  a deployed system. That is a real gap, and it is outside this document's
  scope — CI proves an artifact is sound, not that a running system is.

## Standard repository layout

The catalog is opinionated about where code lives. A shared job that takes a
path input so each repo can keep its own arrangement is not a standard — it is a
switch statement with the branches spread across eleven repositories.

**Three directory names, and they mean the same thing everywhere:**

| dir | holds | present when |
|---|---|---|
| `client/` | the React app. `vite.config.ts` sets `root: client`, `outDir: ../dist/public` | the repo ships a browser UI |
| `server/` | the backend. Entry is always `server/index.ts` (or the language's equivalent) | the repo ships a service |
| `shared/` | code both sides import | **only when both sides are the same language** |

`shared/` is not a junk drawer and not automatic. A React + Go repo has no
`shared/` — the two halves cannot import each other's source, so a directory
claiming they can is a lie. Where a repo builds two servers in the *same*
language, `shared/` is exactly right, and the rule is unchanged: shared source
requires a shared toolchain.

Build outputs are equally fixed: `dist/public` for the client bundle,
`dist/index.js` for the server bundle. The image copies those two paths and
knows nothing else about the repo.

**A repo that differs is a repo to fix.** `web/` is not an alias for `client/`;
it names a medium rather than a deployable unit.

But the rename alone does not retire the `workdir` input, and an earlier version
of this section claimed it would. There are **two real repo shapes**, and the
directory's name was never the difference:

| shape | package.json | `client/` is | repos |
|---|---|---|---|
| JS repo | at the root | a source directory | the six TS repos |
| JS inside another tree | at `client/` | its own pnpm project | gofast, client-manager |

A Go repo with a React UI has a second `package.json`, a second lockfile and a
second `.node-version` under `client/`, and no rename changes that. `workdir`
distinguishes the two shapes and is legitimate; what is not legitimate is
treating it as a free-form path so each repo can put its UI wherever. It takes
`.` or `client`, and nothing else.

### Dev mode: the server never imports vite

Vite is a dev server and a frontend build tool. Nothing in `server/` may
reference it — not behind `NODE_ENV`, not behind a dynamic import, not at all.

The standard is **`vite dev` on its own port, proxying `/api` to the backend**;
one `dev` script starts both, under `concurrently -k` so Ctrl-C stops the pair.

Ports come from the app-wide plan, not from vite's default. Each repo owns a
20-port block; the docker side clusters at the low end and is not uniform (+0 is
always the ingress, but +2, +3 and +8 are variously postgres, pgadmin and
https), so **native dev takes the top of the block: +10 client, +11 server**.
That way the rule reads the same in every repo instead of being arithmetic
around whatever each one already exposes.

Set **`strictPort: true`**. Vite's default is to increment silently when its
port is taken — during Phase F testing that put it on +11 and left the proxy
pointing at itself, which looks like a backend bug and is not one. The middleware-mode arrangement — Express hosting
vite in-process, branching on `NODE_ENV` — is retired fleet-wide.

That arrangement looked convenient (one process, one port, no CORS) and it cost
six broken production images: `server/index.ts` imported `./vite`, the bundler
followed the import, and `vite` is not installed in the runtime image. Three of
the six had been unable to start for months without anyone noticing, because
nothing in CI ever started the container.

Guarding the import is not the fix — it is the same defect with a condition on
it. Removing the reference is the fix, and it has the side effect of making
`client/` a genuinely independent unit, which is what lets it become its own
package later without touching the server at all.

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

### The Go baseline: every Go codebase runs the same seven

Three repos hold Go codebases and each had picked a different subset. Measured
before Phase F:

| capability | gofast | gha-runner-controller | client-manager |
|---|---|---|---|
| `mod` | yes | yes | yes |
| `build` | yes | yes | yes |
| `fmt` | yes | yes | yes |
| `vet` | yes | yes | yes |
| `test-unit` | yes | yes | yes |
| **`lint`** | — | — | — |
| **`govulncheck`** | — | — | yes |
| `test-integration` | — | yes | yes |

Two things that table makes obvious and nothing else did:

- **`job-go-lint.yml` has existed in the catalog since Phase A and no repo has
  ever called it.** A shared job with zero adopters is not a standard, it is a
  file. Either every Go repo lints or the job should not exist; the first.
- **One repo scans for vulnerabilities.** client-manager did it behind
  `tools/checks/govulncheck`, so it read as a client-manager concern rather than
  a gap in the other two. It is now `job-go-govulncheck` in the catalog.

`test-integration` is the honest exception: it belongs wherever integration
tests exist, and gofast has none. Absence there is a fact about the repo, not a
missing job.

**Anything beyond those seven is repo-specific and needs a reason.**
client-manager carries six — `forbidigo-pgxpool`, `conformance-suite`,
`telemetry-canary`, `migration-expand-only`, `header-definition`,
`header-staleness`. Those are policy about *that* codebase, which is the
legitimate case under Principle 19: a debt with a name. Reviewing whether any of
them generalise is worth doing, and is not the same job as this one.

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

### Job ids name the deployable unit

**`<purpose>-<language>[-<framework>]-<capability>`.**

```
client-ts-react-build          server-go-build            ← no framework slot
server-ts-express-lint         server-php-ci4-test-unit
firmware-cpp-arduino-build     billing-py-django-test-unit
```

**purpose** — what the unit *is*, and the first thing a reader wants. Use the
role when there is one of a kind (`client`, `server`, `service`, `worker`,
`cli`, `firmware`, `lib`); use the unit's **name** the moment there are several
(`billing`, `auth`), because with three Django services the language stops
discriminating and only the name does.

`lib` is the one purpose that is not deployable: shared source compiled into
other units. It earns a place because its tests are otherwise homeless —
wardley-mapper's `shared/stripe-config.test.ts` belongs to neither client nor
server, and pointing per-unit jobs at `client` and `server` alone would silently
stop running it.

**language** — always present, always second. `ts`, `go`, `php`, `cpp`, `py`.

**framework** — optional, and *always beneath a language*, never beside it.
There is no CodeIgniter for Go and no Nest for Python; a framework never floats
free of the language it is written in, so it can never occupy the language slot.
`react`/`express`/`nest` are ts; `ci4`/`laravel` are php; `django`/`fastapi` are
py; `arduino` is cpp. Where a unit has no framework — Go here — the slot is
simply absent, and that absence is accurate rather than missing.

The two middle tokens are not redundant: **they select two different tiers of
tooling.** `client-ts-react` says both the language tier (`tsc`, `eslint`) and
the framework tier (`vite build`) apply to it. `server-go` says only the
language tier does.

**Name the framework whenever there is one, even when it owns no build tool.**
Naming and the job catalog are independent decisions:

- the framework token is *identity* — present whenever a framework is in use
- a framework-tier *job* exists only where the framework owns a tool

So `server-ts-express-build` names Express and calls a language-tier build job;
Express is a request-routing library and owns no bundler. That is not a
contradiction — the name says what the unit **is**, the job says what **runs**
it. Two reasons this matters: replacing Express with Nest is an expensive,
consequential change and the id should show it the day it happens; and an
`express` token tells a reader the build is framework-shaped rather than
bespoke. Which makes the empty slot informative in its own right — `server-ts`
with no framework token means exactly that: no framework, a custom build.

**A job spanning more than one unit takes no purpose prefix** — `image`,
`package`, `release`, `test-e2e`, `changes`, `ci-ok`, and a repo-wide
`typecheck` where a single `tsconfig.json` genuinely covers every unit. The
absence marks the convergence and rollup jobs.

*This supersedes two earlier attempts, and the way each failed is the lesson.
B4 asked for a stack prefix "only where a collision forces them" — keyed on a
**collision** rather than on the code, so the prefix vanished in any repo with
one stack and the fleet grew four names for one capability. The replacement
keyed on the **shared job being called**, which proves only which toolchain
runs, not which source it touches: six repos whose single `build` compiles a
React client and an Express server were renamed `react-build`, and
hiring-tracker's `react-test-unit` ran fourteen server tests and zero client
tests. Naming a thing after the tool that happens to process it is the same
error as naming it after a collision. Name the unit.*

### Capability names: category first, specialisation second

`test-unit`, `test-integration`, `test-e2e` — not `unit-test`. English says
"unit test"; we invert it deliberately, for the same reason purpose comes first
in a job id: **the general category leads, so families group.**

```
test-e2e            e2e-test
test-integration    integration-test      ← scattered
test-unit           unit-test
```

Sorted, listed in a checks UI, or grepped, the inverted form keeps every kind of
test together and makes a missing one visible. The uninverted form scatters them
across the alphabet.

The rule generalises: any capability with variants takes the family name first
and the variant second. Capabilities with no variants stay single words —
`lint`, `build`, `typecheck`, `fmt`, `vet` — and `lint` is not a member of the
test family however much it feels adjacent.

### Two linters, on purpose, for now

`job-lint-js-eslint` and `job-lint-js-oxlint` both exist. That is a deliberate
exception to "one way per capability" and it is written down rather than
allowed to look accidental.

They are not interchangeable. oxlint is Rust, runs 50-100x faster, and
implements a **subset** of the rules: no eslint plugins, and no type-aware
linting at all — every `@typescript-eslint` rule that needs the type checker is
simply absent. A repo on oxlint is getting *less* checking than one on eslint,
not different checking.

gofast is the only oxlint caller. Two jobs exist so that repo is not blocked on
a linter migration nobody asked for, and so the fleet is not blocked on gofast.
The target is one linter; this is the honest way to hold the position until
that is decided, instead of pretending the fleet already agrees.

### Shared job names: `<function>-<language>-<runner|framework>`

A caller names the **unit**; a shared job names the **tool it runs**. Same
three-part discipline, different subject.

```
job-test-unit-js-vitest      job-lint-js-eslint        job-typecheck-ts-tsc
job-build-js-vite            job-bundle-js-esbuild
job-test-unit-go             job-fmt-go                job-vet-go
job-test-unit-php-phpunit    job-build-cpp-pio
```

The third token is the runner or framework that actually executes the function,
and it is **absent where the language is the tool**: `go test`, `go vet` and
`gofmt` are Go itself, so `job-test-unit-go` has nothing to add. Swapping vitest
for jest is then a visible rename — `job-test-unit-js-jest` — rather than a
silent change of behaviour inside a file whose name never moved.

Language here is the **tool's ecosystem**, not the source's: vitest is a
JavaScript runner that happens to read TypeScript, so it is `js`, while
`typecheck-ts-tsc` is `ts` because `tsc` exists only for TypeScript. A caller
written in TypeScript therefore calls a `js` job, and that is correct — the
caller names its source, the job names its tool. This is the same distinction
that broke once already: a shared job proves the language of the tooling, never
which unit the source belongs to.

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

## Enforcement — what actually gates, and what does not

A principle nobody can fail is a preference. Every rule below was written here
first and violated afterwards, in a repo whose CI was green the entire time,
because writing it down and enforcing it are different acts and only the second
one holds. **A phase is not done when the rule is written. It is done when
something fails if the rule is broken.**

`tools/check-ci-conformance` is that something. It runs two ways from one
source — `--repo-root` inside a repo's own CI via `job-ci-conformance.yml`, and
`--fleet` for sweeps — because an audit and a gate that can disagree eventually
will.

| # | Principle | Enforced by | Status |
|---|---|---|---|
| 1 | One source of truth per pin | — | **review only** |
| 2 | Local = CI | — | **review only** |
| 3 | Fail closed | `check-ci-conformance` P3 | gated |
| 4 | Standard runner line | `check-ci-conformance` P4 | gated |
| 5 | Ephemeral-runner assumptions | — | **review only** |
| 6 | Concurrency everywhere | `check-ci-conformance` P6 | gated |
| 7 | BUILD ONCE | — | **review only** |
| 8 | No multi-stage prod Dockerfiles | — | **review only** |
| 9 | Canonical script names | `check-caller-thinness` (sweep) | audit only |
| 10 | Lint output through standard channels | — | **review only** |
| 11 | Registry auth in user-level npmrc | — | **review only** |
| 12 | One way per capability | `check-caller-thinness` (sweep) | audit only |
| 13 | Provenance in every artifact | — | **review only** |
| 14 | A version is a commit, not a tag | — | **review only** |
| 15 | The repo is versioned, not the artifact | — | **review only** |
| 16 | A version exists only where consumed | — | **review only** |
| 17 | Release is promotion, not production | `check-ci-conformance` D4, D5 | gated |
| 18 | One workflow per repo | `check-ci-conformance` P18 | gated |
| — | Standard job DAG (build first) | `check-ci-conformance` D1–D3 | gated |
| — | Every job blocks something | `check-ci-conformance` D6 | gated |
| — | Something runs the image | `check-ci-conformance` D7 | gated |
| — | `needs.<id>` expressions resolve | `check-ci-conformance` D8 | gated |
| — | `workdir` names a shape, not a path | `check-ci-conformance` WD | gated |
| — | Per-stack DAG in multi-codebase repos | — | **review only** |
| — | SHA pinning | `check-ci-conformance` PIN | gated |
| — | `ci-ok` is the only required check | branch protection | gated |
| — | Fleet pnpm version | `check-fleet-versions` (sweep) | audit only |
| — | Caller `with:` matches the shared job's inputs | `check-ci-conformance` IN | gated |
| — | Caller permissions cover shared jobs | `check-caller-permissions` (sweep) | audit only |

Three tiers, and the difference between them matters:

- **gated** — a violation turns that repo's `ci-ok` red. This is enforcement.
- **audit only** — a checker exists but runs from a workstation when someone
  remembers. This is a habit, and habits are what drifted in the first place.
  Every one of these is a candidate for folding into the gate.
- **review only** — nothing mechanical. Some of these resist automation
  honestly (BUILD ONCE needs to know what an artifact is; the per-stack DAG
  needs to know which stack a job belongs to). Saying so is the point: an
  unenforced rule should be visibly unenforced, not quietly assumed.

Rules that resist a checker get the next best thing — a review question
someone has to answer, not a line someone has to remember.

### Why this section exists

Three rules in a row failed the same way, each in a new disguise, and the
pattern only became visible when they were laid side by side:

- `.pnpm-version` — the guard keyed on **a file**, so it stopped applying when
  the duplication moved out of that file.
- Principle 6's release exemption — keyed on **a filename**, so it stopped
  applying when publishing moved into `ci.yml`.
- Principle 17 — keyed on **an outcome** ("the publish path is exercised on
  every pull request") with no mechanism named, so a job could satisfy the
  sentence in prose and violate it in fact for months.

The common shape: *a rule that names anything other than the act itself stops
applying the moment the act moves.* Write rules against acts, then make
something fail when the act is wrong.

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
      the C5 one-box lesson in miniature: (1) pnpm 10+ only honors
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
      on every consumer tracks the shared-workflow SHA; land one one-box
      change in node-ci.yml and verify it arrives everywhere as
      reviewable SHA-bump PRs. Tag releases in this repo so bump PRs
      are readable (SHA pin + tag comment, fleet pinning policy).
      *Proven 2026-08-16. The one-box process ran end to end: merged
      workflows#6 (checkout 4.4.0→7.0.1) alone → re-pinned
      expense-splitter (#21) to that SHA → full run green through all
      five capabilities → then batched #7–#10 (upload-artifact v7,
      buildx v4, download-artifact v8, setup-node v7; artifact
      cross-major compat pre-proven by lid-firmware run 31920424032)
      → fleet re-pin wave to the final SHA. The C2 rollout separately
      demonstrated why single-caller one-box stages matter: two shared-job
      bugs (registry auth, packages: read) only surfaced on the one
      repo exercising private packages. One-box repos should include
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

### Phase F task board — one DAG per deployable unit *(scoped 2026-08-17)*

Phases A–D standardized how code is gated and built; Phase E, how it is
versioned and released. Phase F is about what the pipeline **says it is doing**,
because in six repos it was saying something untrue.

**How it surfaced.** A job-id rename claimed six repos' `build` acted on React.
It does not: each of those repos holds a React client *and* an Express server
under one `package.json`, and one `build` compiles both. hiring-tracker was the
proof — its `test-unit` runs **fourteen server tests and zero client tests**, so
the React label was not merely vague, it was inverted. The DAG showed one
undifferentiated blob where two deployable units live, and nobody could see
whether the server was built, linted or tested at all. It was not.

**F0 — The standard shape of a TS client+server repo.** The variations below
are not constraints to design around; they are the drift Phase F removes. Every
one of the six converges on this, and the shared jobs then need no per-repo
inputs beyond which unit they are pointed at.

| | standard | seen today |
|---|---|---|
| unit source | `client/`, `server/` | already uniform |
| test files | `*.test.ts(x)` colocated under the unit dir | uniform where they exist |
| vitest `include` | **absent** — the job passes `--dir client\|server` | `client/src/lib/**`, `client/src/**`, `**/*.{test,spec}.{js,ts}` — each pins tests to one unit and makes a per-unit split impossible |
| client bundle | `dist/public` (vite default target) | uniform |
| server bundle | `dist/index.js`, esm, `--packages=external` | 3 repos match; 3 emit `dist/index.cjs` via a bespoke script |
| `start` | `node dist/index.js` | follows the bundle |
| build scripts | **none** | `script/build.ts` in 3 repos |

The vitest `include` line is the one that matters most: while it pins every test
to `client/`, pointing a job at `server/` finds nothing no matter how the DAG is
drawn, and the split would be cosmetic.

**F1 — Split the DAG per deployable unit.** Each unit runs its own build and
its own gates, converging at packaging (the multi-codebase rule). For the six
Express repos:

```
client-ts-react-build ──► client-ts-react-lint, client-ts-react-test-unit ────┐
server-ts-express-build ──► server-ts-express-lint, ...-test-unit ────────────┤──► image
typecheck  (one tsconfig.json — genuinely repo-wide, so it stays bare) ───────┘
```

**F2 — Delete the repo-specific build scripts.** `credit-watch`,
`expense-splitter` and `flight-watch` each carry a `script/build.ts` that hand-
curates 28 dependencies to bundle. The other three already use plain
`esbuild --platform=node --bundle --packages=external --format=esm`, which is
the standard and the majority. The shared job owns that invocation; repos keep
only `server/index.ts` as the entry point and no build script at all.

*Known trades, recorded rather than discovered later.* The allowlist exists "to
reduce openat(2) syscalls which helps cold start times"; whether that was
measured is unknown, and standardizing gives it up. The scripts also `minify`,
which the shared job does not — flight-watch's bundle goes 856kb to 66kb because
dependencies stop being inlined, so the minification argument largely dissolves
with them. And the allowlists have rotted: 11 of flight-watch's 25 entries name
packages the repo no longer depends on at all, which is what an unenforced
hand-curated list does over time.

**F3 — Tests exist for every unit.** Splitting the test job makes absence
visible for the first time:

| repo | server tests | client tests |
|---|---|---|
| credit-watch | 0 | 3 |
| flight-watch | 0 | 1 |
| jewelry-factory | 0 | 2 |
| wardley-mapper | 0 | 3 |
| expense-splitter | 1 | 2 |
| hiring-tracker | 14 | 0 |

**A unit with no tests warns, it does not block — for now.** The gap is
pre-existing and predates the standard; failing five of six repos on the day the
split lands would punish repos for a condition this project exists to fix. F3
closes it, and the warning is what makes the debt visible until it does.

The mechanism matters: the job runs with `--passWithNoTests` and a step that
counts test files and emits a warning annotation when the count is zero. **A
real test failure still fails the job.** Blanket `continue-on-error` would
suppress genuine breakage too, which is the trap this avoids.

**F4 — Rename every job id** to `<purpose>-<language>[-<framework>]-<capability>`
once F1 lands, since the split creates the jobs the names describe.

**F5 — Framework-tier shared jobs.** A framework earns a shared job only when
it owns a tool: React does (`vite build`), CodeIgniter 4 does (`spark test`),
Arduino does (`pio run`). Express does not — it routes requests and owns no
bundler, so its build is a language-tier job. The test for admitting a new
framework job is "what command would it run?"; if there is no single answer,
there is no job.

**F6 — Enforce what F1–F5 establish.** Rules with no gate drift; this document
has proved that five times. N1 already checks the language token. Purpose and
framework cannot be proved from the file and stay review-only, and the checker
says so rather than implying coverage it lacks.

**F8 — The artifact must start, and CI must say so.** Adopting the shared
bundle job exposed a defect that every gate in this document was blind to,
because every gate stops at "it built".

The six Express repos guard their dev server one of two ways:

```ts
// three repos — guarded, so a define can eliminate it
if (process.env.NODE_ENV === "production") serveStatic(app);
else { const { setupVite } = await import("./vite"); await setupVite(...); }

// three repos — unconditional, so nothing can eliminate it
import { setupVite, serveStatic, log } from "./vite";   // -> imports "vite"
```

`vite` is a devDependency. The runtime image runs `pnpm install --prod`. So the
bundle top-level-imports a package the image does not contain, and
`node dist/index.js` dies at module resolution with `ERR_MODULE_NOT_FOUND`
before a line of application code runs.

Verified by bundling all six and starting each one against a dependency tree
containing only its declared `dependencies`:

| repo | as bundled today | with `--define` | why |
|---|---|---|---|
| credit-watch | fails to load | starts | guarded import |
| expense-splitter | fails to load | starts | guarded import |
| flight-watch | fails to load | starts | guarded import |
| hiring-tracker | fails to load | **fails to load** | `server/index.ts:14` static |
| jewelry-factory | fails to load | **fails to load** | `server/index.ts:5` static |
| wardley-mapper | fails to load | **fails to load** | `server/index.ts:3` static |

**This is not something Phase F introduced.** The three static-import repos
already build with `--packages=external` on `main` and already ship an image
that cannot start; Phase F inherited it. What Phase F would have introduced is
the other three: their `script/build.ts` inlines dependencies and eliminates
the dev branch, so deleting it without the define regresses a working image.

Three changes follow:

1. `job-bundle-js-esbuild` passes
   `--define:process.env.NODE_ENV='"production"'`. A production bundle built
   without a production NODE_ENV is a contradiction, and it fixes the guarded
   three.
2. The same job then **asserts the property instead of trusting the flag**:
   every bare specifier the bundle imports must appear in `dependencies`. No
   flag can fix a static import, so the check does not depend on one. It agreed
   with the twelve start-up simulations in all twelve cases and needs no
   install.
3. The static-import three move `serveStatic`/`log` into a production-safe
   module and leave `setupVite` behind the dynamic import — one line each.

**The general lesson, because it outlives Phase F.** A green pipeline here meant
the artifact compiled, was linted, was typechecked, was tested, and was packaged
into an image. Not one of those steps ever started the thing. Six repos held a
full row of green ticks over an image that could not boot, and the standard had
no rule that was even capable of noticing — which is the failure mode Principle
17 describes, arriving somewhere new. `ci-ok` is a rollup of gates, and a rollup
is only as honest as the weakest claim underneath it.

**F9 — The two `.cjs` repos change module format, and that is not cosmetic.**
`credit-watch` and `expense-splitter` both declare `"type": "module"` in
package.json while their `script/build.ts` emits `format: "cjs"` to
`dist/index.cjs`. The `.cjs` extension is what makes Node read it as CommonJS
despite the type field, so it works today by extension alone.

The catalog emits `--format=esm` to `dist/index.js`. Under `"type": "module"`
that is ESM — correct, and it breaks both repos, because `server/static.ts` in
each resolves the client bundle with a bare `__dirname`:

```ts
const distPath = path.resolve(__dirname, "public");   // undefined under ESM
```

`__dirname` exists in those repos only as a side effect of the CJS bundle. The
server throws on startup the moment the format changes — the same class of
break as the vite import, arriving by a different route, and invisible to every
gate we have because nothing starts the container (see F8).

So the wave for these two is not a re-wire. It carries, per repo:

- `server/static.ts` → `import.meta.dirname` (or `fileURLToPath(import.meta.url)`,
  which is what the two pilot repos use)
- `start` script → `dist/index.js`
- a local boot of the built artifact before the PR opens, not after

`jewelry-factory` is not affected — it already builds `dist/index.js` — but it
does carry the unguarded static `vite` import that hiring-tracker had.

*Found by reading the three remaining repos before touching them rather than by
a red pipeline, which is the only reason it is written here and not in a
post-mortem.*

**F7 — Rollout order.** wardley-mapper went first (#15, twelve checks green on
workflows `684617a9`). What that run proved, stated precisely: **the catalog
works.** All three defects it caught live in `workflows`, not in the repo —
a job-level `permissions:` block that replaced the caller grant and produced a
`startup_failure` with no jobs and no logs; coverage scoped repo-wide while
`--dir` scoped the tests; and the `--coverage.include` fix that replaced the
curated set and dropped the project number 49.46% → 4.24%. Zero of the three
were migration defects.

It therefore does **not** generalise to the wave, because it is unrepresentative
on the two axes the wave turns on: it has no `script/build.ts` (F2 ran zero
times) and no server tests (its server job took the warn path, so per-unit
coverage never had to produce a number on the server side).

So the one-box stage is a *pair*, chosen for coverage of those axes:

| repo | why it is in the set | axis it proves |
|---|---|---|
| flight-watch | `script/build.ts`, 0 server tests, smallest surface | F2 deletion, warn path |
| hiring-tracker | 14 server tests, 0 client tests, no build script | F1 split, per-unit coverage on a real suite |

Between them every axis credit-watch, expense-splitter and jewelry-factory vary
on is covered, so those three follow as interpolation rather than new risk.

### Phase E task board — versioning and releases *(scoped 2026-08-16)*

Phases A–D standardized how code is *gated* and *built*. Nothing had ever
standardized how it is *versioned and released*, and it showed: four schemes
across the fleet, and the single line of guidance we had (CalVer + an `edge`
tag) contradicted gha-runner-controller, which ships semver and follows the
standard in every other respect.

**How the decision was reached**, because the reasoning matters more than the
rule. We started by asking which scheme suits which kind of application and
got nowhere — two container-deployed web apps can want opposite things. The
question that actually discriminates is *who consumes the version*: a version
is either identity ("what exactly is running") or a promise ("you can upgrade
safely"). Identity is needed everywhere and is free — it is the SHA and the
build timestamp. A promise is only worth maintaining if something reads it and
acts, and where nothing acts, a hand-maintained number is ceremony that
eventually drifts or lies. That became Principle 16.

CalVer then fell out entirely. It had been the candidate for "how old is
this", but a build timestamp baked into the artifact answers that precisely,
for free, with no format debate, no increment bookkeeping and no validator —
and it answers "which commit" at the same time. CalVer was a lossy encoding of
metadata we should carry directly (Principle 13). Its removal also deleted the
CalVer-compliance checker the design had been about to require.

That leaves SemVer as the only version scheme, used only where a machine
consumes it. Automation was considered as a way to keep semver honest, and it
helps mechanically — format, monotonicity, no skipped numbers — but it cannot
decide whether a change is breaking. Conventional-commit tooling only
relocates that judgement to a commit-message prefix typed by whoever wrote the
change. Putting the version in a reviewed file is the better mitigation: the
claim becomes a diff someone can challenge (Principle 14).

- [ ] **E1** Build provenance everywhere (Principle 13). Timestamp + SHA baked
      in at build time and surfaced by the software. Go is solved and is the
      reference: gofast stamps `internal/version` via `-ldflags` and shows it
      on `/healthz` and Status → System. TS and PHP need one agreed generated
      file at a fixed path in `dist/` plus one read helper. The generation
      step is identical across repos, so it belongs in the shared build jobs,
      not per repo.
- [ ] **E2** `.version` file + publish-as-CI-job for gha-runner-controller —
      the only repo that passes the Principle 16 test today. Replaces the
      `git describe` derivation, which reads tags as authority. Includes the
      `workflow_dispatch` re-run path: a failed publish must be retryable
      without inventing a new version, which is also why the publish job has
      to stay trivial.
- [ ] **E3** Release paths consume CI artifacts. *Principle 7 and 17, not new
      policy — gha-runner-controller's release.yaml recompiles and re-runs the
      tests, a fourth build of the same code. Audit every repo's release path.*
- [x] **E4** Release-risk PR comment — **shared job, every repo gets it.**
      A version bump may ride along with the change that justifies it (no
      added friction, and the semver judgement stays next to the code that
      motivated it), but a reviewer must not approve a feature and cut a
      release without noticing. *Landed 2026-08-16 as
      `job-release-risk.yml`: reads the version file at the PR base and at
      HEAD, and when they differ posts old → new, states that merging
      publishes, calls out separately when the PR carries code as well as a
      version, and on a major bump names the breaking-change claim as the
      reviewer's to confirm. Updates one marker-keyed comment in place rather
      than adding one per push — a comment that reappears is a comment people
      learn to ignore. Never fails the build: blocking would be friction for
      something a reviewer is entitled to do deliberately, and the job's
      purpose is only to make sure it IS deliberate. Carries job-level
      `pull-requests: write`, the one escalation above the read-only floor.*
- [ ] **E4b** Adopt the release-risk stub in every repo, not only versioned
      ones. A repo with no version file is a no-op today and correctly
      flags the day someone adds one — which is exactly when a reviewer has
      never seen a release from that repo before. Wire it as an ordinary stub
      in each caller; it is not part of `ci-ok`, since it reports rather than
      gates.
- [ ] **E5** [decision, deferred] Digest pinning for first-party images. We
      SHA-pin third-party actions because tags are mutable, then ship
      ourselves `latest`. *Resolved for the runner image 2026-08-16: the
      controller's config.yaml already allows pinning, the repo is public and
      operators may run whatever runner image they choose, so `latest` stays.
      The general question is open for the rest of the fleet.*

- [ ] **E6** Cross-repo rollout order, once E1's generator exists. Go first
      (gofast is already the reference implementation, so the shared job only
      has to generalize what works); then TS across the six converted repos
      plus the two web halves, which share one build job and so land as a
      single re-pin wave; PHP last, since event-manager is the only consumer
      and has no second repo to prove the shape against. Each stack is a
      one-box-then-wave, the C5 process: one repo green end to end before the
      rest re-pin.
- [ ] **E7** Retire what the new rules obsolete: gha-runner-controller's
      `git describe` version derivation (reads tags as authority, contrary to
      Principle 14) and the `fetch-depth: 0` it forces on jobs that only need
      a version. client-manager's CalVer + `edge` tag is the other case —
      under Principle 16 it needs a named consumer or it collapses into
      provenance metadata like everything else.

**Exit criteria:** every artifact reports its own build timestamp and commit;
the only version numbers left are semver ones with a named machine consumer;
no release path rebuilds what CI already built; and a version bump is visible
to a reviewer before it ships.


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
