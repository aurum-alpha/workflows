# Local development: what a stack binds, and where the numbers live

One of the Aurum Alpha engineering standards. Read
[`../README.md`](../README.md) for the charter it is written under and
[`999-enforcement.md`](999-enforcement.md) for what enforces it.

Rules carry the prefix **LD**.

This standard governs the local development stack. It decides how a process
chooses its listen port (LD1) and what a container binds (LD2). It decides
where host numbers come from (LD3 and LD4). It decides how the development
image is built, mounted and started (LD5 to LD8).

It is the second local half of [`010-ci.md`](010-ci.md) Principle 2. The first
is [`015-commands.md`](015-commands.md), which governs the commands a person
types. This one governs the stack those commands bring up.

**It does not decide how anything is deployed.** Where a service runs and what
fronts it are deployment choices. Which host port a deploy publishes is another
one. Every rule below leaves all three alone. It does not decide what a service
does at start, which belongs to [`030-service.md`](030-service.md). It does not
decide what a shipped image contains, which belongs to
[`010-ci.md`](010-ci.md) Principle 8 and
[`085-security-baseline.md`](085-security-baseline.md) SB1 and SB9.

Artifacts: [`../ports.json`](../ports.json), the host block allocation.

## Why this exists

A listen port is a number that four different files each believe they own.

The client's build config hardcodes one. The server reads one from the
environment, falling back to a constant. The development script overrides that
variable for one of the two processes. The compose file publishes a fourth.

Every one of those files is internally consistent. Nothing compares them, so
nothing fails. The stack then starts cleanly, with a published host port that no
process inside the container is listening on.

That failure is silent in the worst way available. The container is up. Its logs
say the server is serving. A health probe aimed at the published port reports a
problem. So the probe looks broken, and the probe gets changed.

The cause was a rule that split the numbers by audience. Docker-side ports came
from the low end of a block. Native ports came from the top of the same block.
The split is coherent on paper. It cannot survive one script serving both
audiences. That is what a development image does when its entry point runs the
command a person runs natively.

Two rules replace it. Between them they leave one number in one place.

**A process reads its port from the environment, with a default in code.** That
is [`030-service.md`](030-service.md) SC3, applied to the one variable every
service has. A listen port is an optional variable whose default is safe. So the
service starts without it, and logs what it resolved.

**The allocation governs host bindings only.** Nothing inside a container sets
the port. Every process binds the default its own ecosystem already uses, and a
compose file maps the block onto those defaults. A collision was only ever
possible on the host, which is where the allocation still applies.

The gain is not tidiness. No application file and no image definition carries a
number anybody has to remember. The numbers that remain sit in the file whose
job is deployment-varying values.

## The rules

### LD1. A process reads its listen port from the environment, with a default in code

The environment variable is `PORT`. When it is absent or empty, the process
binds a default written as a constant in the code. There is no third source. A
configuration file carrying a listen address is permitted only as a layer the
environment overrides, and the environment always wins.

```ts
const port = parseInt(process.env.PORT || '5000', 10)
```

```go
port := os.Getenv("PORT")
if port == "" {
    port = "8080"
}
```

**A default is required.** A process that refuses to start without `PORT` is
wrong. SC3 says a *required* variable has no default, and that rule governs
variables with no safe value. A database address is one. A signing key is
another.

A listen port has a safe value, so demanding one buys nothing. An operator who
wants a specific port sets the variable. An operator who does not wants the
process to start.

**The default is a constant, not a value read from a file.** A file introduces a
second answer. It is also the answer nobody looks at when the number is wrong.

**This standard fixes the mechanism and not the number.** Each ecosystem has a
default its tooling already assumes. A service keeps whatever number it started
with. Changing one breaks the addresses people have typed, and buys nothing the
mechanism has not already bought.

### LD2. A container binds defaults, so a development compose file sets no port

`PORT` is absent from the `environment:` block of every service in a development
compose file. Each process therefore binds its own default. LD1 made that
default knowable by reading one constant.

The mapping is the block on the left and the default on the right:

```yaml
ports:
  - "2900:5173"   # the client development server
  - "2901:5000"   # the API
  - "2902:5432"   # the database
```

**The exception is a deployment, and it is why LD1 exists.** A deploy on host
networking has no port mapping to hide behind. It sets `PORT`, and the process
obeys. That is one mechanism working in both directions, rather than a carve-out.

**Nothing in the stack detects where it is running.** SC3 already forbids that,
and a development stack is where the temptation is strongest. No variable
announces that a process is inside a container. No code branches on one.
Differences between a laptop and a deploy are values.

### LD3. Host bindings come from one aligned block of twenty

Every host port a development stack publishes falls inside a single block of
twenty consecutive ports. The base is a multiple of twenty. The block runs from
the base to the base plus nineteen, inclusive.

**No host binding is privileged.** Nothing below 1024, for any service, ever. A
container serving TLS on 443 publishes on the block's offset eight.

**The block is an allocation.** [`../ports.json`](../ports.json) is where
allocations are recorded. That file states how a base is chosen. It also states
why it keeps no list of who is subject to this standard. A project absent from it
is unallocated, never exempt.

**Container-side ports are not in the block and never were.** They are whatever
the image already binds. Service-to-service addressing on the compose network
uses those, not the block.

### LD4. Offset zero is what a person opens in a browser

The offsets are fixed, so a reader moving between stacks reads one convention
rather than one per project.

| Offset | Role | Offset | Role |
|---|---|---|---|
| +0 | main ingress, over HTTP | +8 | ingress over TLS |
| +1 | the API, where separately addressable | +9 | debugger |
| +2 | primary database | +10 / +11 | mail, SMTP and its UI |
| +3 | database admin UI | +12 | observability UI |
| +4 | object storage API | +13 / +14 | telemetry, gRPC and HTTP |
| +5 | object storage console | +15 | health check |
| +6 | identity provider | +16 to +19 | spare, project-specific |
| +7 | identity management and health | | |

**Offset zero is defined by what a person types into a browser.** Nothing else
defines it. Where a client development server hosts the pages and proxies the
API, that server takes offset zero. The API then takes offset one. Where one
process serves both, it takes offset zero and offset one stays vacant.

That reading is worth stating, because the alternative is available and wrong.
Offset zero could go to the backend, on the grounds that the backend is the
deployed thing. The result is a stack whose documented main ingress answers
nothing in local development.

**Offsets ten and eleven belong to mail.** An earlier rule handed them to the
client and the server, for native runs. It contradicted this table, and it broke
every stack whose development image ran the native command.

There is no separate native allocation now. Native and containerised runs bind
the same defaults. A person running two projects natively sets `PORT` for one of
them.

### LD5. The development image is `Dockerfile.dev`, and it never ships

One name, so a reader knows which file builds the thing they are running. The
shipped image stays in `Dockerfile`. It is thin, and
[`010-ci.md`](010-ci.md) Principle 8 governs it.

The two images have opposite jobs and share nothing:

| | `Dockerfile` | `Dockerfile.dev` |
|---|---|---|
| Contents | a built artifact, copied in | a toolchain, and no source |
| Source | never present | bind-mounted at run time |
| Dependencies | runtime only | the full tree, build tools included |
| A code change | rebuilds through CI | is visible without a restart |

**A development compose file names `Dockerfile.dev` explicitly.** A compose file
that builds the shipped image is running a deployment, whatever it is called.
Its contents make that claim, rather than its file name.

### LD6. The development image installs from the lockfile, with the pinned package manager

The version comes from the pin the repository already declares, read at build
time. It is never a second literal in the image.

```dockerfile
RUN npm i -g "pnpm@$(node -p "require('./package.json').packageManager.split('@')[1]")" \
    && pnpm install --frozen-lockfile
```

**A development image that resolves dependencies differently from CI proves
nothing.** Installing with a different package manager produces a tree nobody
else has. So does installing against a lockfile that is not in the repository.
The failure that hides is the one a developer most wants caught before a push.

**The pin is read, not restated.** A hand-written version in the image is a
second source of truth. The copies then drift, in the direction nobody watches.
This is [`010-ci.md`](010-ci.md) Principle 1, inside a Dockerfile.

### LD7. The dependency tree is a named volume the container populates

The repository is bind-mounted into the container. A named volume is mounted
over the dependency directory, so the host's copy never reaches the container.
The container installs into that volume on first start.

```yaml
volumes:
  - .:/app
  - app_node_modules:/app/node_modules
```

**The reason is architecture, not speed.** A container often runs a different
operating system or processor architecture from its host. A dependency tree
holding compiled binaries is valid only where it was built.

Letting the host's tree show through gives the container binaries it cannot
execute. The error then names a module, rather than the mismatch.

**Named rather than anonymous.** An anonymous volume works, and cannot be
addressed afterwards. Copies accumulate. Clearing one takes
`docker compose down -v`, which never says what it cleared.

### LD8. A clean clone reaches a working stack in one command

`docker compose up` on a fresh clone yields a stack that serves. No manual step,
no file a person has to create first, and no command run in a particular order.
Every provisioning step is idempotent. Each belongs to whichever service owns the
thing provisioned.

**An environment file the repository does not contain fails the whole stack.**
A compose file naming one fails before anything starts. Where local values are
needed, they are committed as an example file.
[`032-secrets.md`](032-secrets.md) SE9 already makes that the contract, and the
compose file tolerates the absence.

**A source edit is visible without a container restart.** That is the whole
purpose of the bind mount in LD7. Where file events do not cross a virtual
machine boundary, polling is turned on by a value in the compose file. It is
never turned on by code that guesses.

**The whole repository is mounted, not a chosen list of directories.** A list
goes stale the first time somebody adds a directory. The symptom is a file the
container cannot see, which reads as a caching problem.

## Enforcement

Every rule here lands review-only.
[`999-enforcement.md`](999-enforcement.md) records which gate each one is
getting. The charter fixes that sequence, and the gates arrive in their own
change.

The proposed gate is `tools/check-dev-stack`, running from
`job-ci-conformance.yml` in each repository's own CI, against that repository.
What it can settle mechanically:

- A development image exists and carries the name LD5 fixes.
- No development compose file sets `PORT`.
- Every host binding falls inside one aligned block of twenty, and none is
  privileged. **This needs no allocation record**, because alignment is a
  property of a single clone.
- No client build config hardcodes a port.

One check reads [`../ports.json`](../ports.json), and it runs in this repository
alone: no two recorded blocks overlap. That is the one question a single clone
cannot answer.

Three things resist a checker. Whether offset zero is what a person actually
opens. Whether a clean clone truly reaches a working stack. Whether an edit is
visible without a restart. The ledger records each as a review question, rather
than implying coverage.

## Decisions

**2026-09-10. The allocation moved off a workstation.** It was cited by two
rules and by several compose files. It lived as a file on one person's laptop. A rule keyed on a document nobody else can open is a rule with no
content.

**2026-09-10. The split between docker-side and native ports is retired.** It
gave the low end of a block to containers. Native runs took offsets ten and
eleven. It contradicted the offset table, which gives those two to mail. It also
broke every stack whose development image ran the native command. Both audiences
now bind the same defaults.

**2026-09-10. `strictPort` is no longer required of a client development
server.** It was required because the client and the server sat on adjacent
offsets. The client's silent increment landed it on the server's port, and the
proxy then targeted itself.

Ecosystem defaults are not adjacent, and the proxy target is read from `PORT`
rather than from a neighbouring number. The failure it guarded against has no
way to happen now. The silent increment becomes useful instead: two client
servers can run natively at once.

**2026-09-10. A listen port gets a default, even where a project decided
otherwise.** Refusing to start without `PORT` is a defensible reading of SC3.
LD1 overrides it deliberately. SC3 distinguishes variables with a safe
default from variables without one. It does not distinguish variables that
matter from variables that do not.
