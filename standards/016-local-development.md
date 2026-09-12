# Local development: what a stack binds, and where the numbers live

## Why this exists

A listen port is a number that four files each believe they own. They are the
client's build config, the server's fallback constant, the development script
and the compose file. Every one is internally consistent and nothing compares
them. So the stack starts cleanly, with a published host port that no process
inside the container is listening on. The container is up, its logs say it is
serving, and the probe aimed at the published port looks broken. The rules
below leave one number in one place, in the file whose job is
deployment-varying values.

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

**The block does not appear in application code.** A client build config naming
a port from the block is the defect. A container-side port outside the block is
not: LD3 already says those are whatever the image binds. A reverse proxy in
front of a development server names one in its own configuration, and getting
that pair wrong fails on the first request.

**Nothing in the stack detects where it is running**
([`030-service.md`](030-service.md) SC3). No variable announces that a process
is inside a container, and no code branches on one. Differences between a
laptop and a deploy are values.

### LD3. Host bindings come from one aligned block of twenty

Every host port a development stack publishes falls inside a single block of
twenty consecutive ports. The base is a multiple of twenty. The block runs from
the base to the base plus nineteen, inclusive.

**No host binding is privileged.** Nothing below 1024, for any service, ever. A
container serving TLS on 443 publishes on the block's offset eight.

**The block is an allocation**, recorded in [`../ports.json`](../ports.json). A
project absent from it is unallocated, never exempt.

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
process serves both, it takes offset zero and offset one stays vacant. Giving
offset zero to the backend, as the deployed thing, leaves a documented main
ingress that answers nothing in local development.

**There is no separate native allocation.** Native and containerised runs bind
the same defaults. A person running two projects natively sets `PORT` for one
of them. A client development server needs no `strictPort`. Ecosystem defaults
are not adjacent and the proxy target is read from `PORT`, so the failure it
guarded against cannot happen. The silent increment instead lets two client
servers run natively at once.

### LD5. The development image says so in its name, and it never ships

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

**What `docker compose up` leaves running builds a development image.** The file
name says which of the two you have. A compose file whose long-running service
builds the shipped image is running a deployment, whatever it is called. Its
contents make that claim, rather than its file name.

**Two shapes are not that, and both are correct.** A one-shot declares
`restart: "no"`, runs a command and exits. A migration or a seed has nothing for
a watcher to watch, and building it the runtime way keeps `up` exercising the
shipped artifact. A profiled service is opt-in, so a plain `up` never starts it.
That is how a repository offers its shipped image locally without making it the
thing you get by default.

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

**A source edit is visible without a container restart.** Where file events do
not cross a virtual machine boundary, polling is turned on. The switch is a
value in the compose file, never code that guesses.

**The whole repository is mounted, not a chosen list of directories.** A list
goes stale the first time somebody adds a directory. The symptom is a file the
container cannot see, which reads as a caching problem.
