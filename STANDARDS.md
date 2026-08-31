# Aurum Alpha engineering standards

This is the index and the constitution. It says what a standard is, what makes
one binding, and where the individual standards live. It states no engineering rules itself — every rule belongs to a
document under `standards/`.

## What this repository is

`aurum-alpha/workflows` is the definition of how this organisation builds
software. Not a convenience library of things several repos happened to need —
the answer, per language and per capability, that repos are standardized *onto*
rather than each arriving at independently.

That was already true of continuous integration, and the CI standard is the
worked example the rest of this follows: a document that states the rule and
the reasoning, a catalog that implements it once, and a checker that fails the
build when a repo drifts. The scope is now every layer of a product, not just
its pipeline.

**Two repos solving the same problem two ways is not diversity, it is the fleet
having no opinion — and an organisation with no opinion re-litigates the same
decision every time someone starts a service.**

## Scope: internal and client work alike

These standards bind everything Aurum Alpha builds — the products we operate and
the systems we build for clients. A client engagement is not an exemption. It is
the case that matters most, because it is the code that leaves.

**A standard must survive handover.** A client repository follows these rules and
then, at handover, stops being able to reach this repository at all: no shared
job to call, no checker to run, no catalog to resolve. A standard that only works
while `aurum-alpha/workflows` is reachable is not a standard, it is a dependency.

Three consequences, and they constrain how every document here is written:

1. **State the rule, not just the mechanism.** A reader with no access to this
   repo must be able to read the rule, understand why it exists, and comply. The
   shared job is how *we* comply cheaply; it is never the only description of
   what compliance is.
2. **Every standard must be satisfiable without this repo.** Where a rule is
   normally met by calling a shared workflow, the document says what the
   workflow does in terms a person could reimplement.
3. **Handover is a copy, not a link.** A repository leaving the fleet vendors the
   standards it was built to, so the rules travel with the code. What it loses is
   the updates, which is correct — it is no longer ours.

## The law

**A rule is not done when it is written. It is done when something fails if it
is broken.**

Every rule in the CI standard was written down first and violated afterwards, in
a repo whose CI was green the entire time, because writing a rule and enforcing
it are different acts and only the second one holds. A principle nobody can fail
is a preference.

That history also taught what *kind* of rule survives. Three rules failed the
same way in three disguises: one keyed on a file, one keyed on a filename, one
keyed on an outcome with no mechanism named. The common shape is that **a rule
naming anything other than the act itself stops applying the moment the act
moves.** Write rules against acts, then make something fail when the act is
wrong.

### Three tiers, and the difference between them matters

- **gated** — a violation turns that repo's required check red. This is
  enforcement.
- **audit only** — a checker exists but runs from a workstation when someone
  remembers. This is a habit, and habits are what drifted in the first place.
  Every one of these is a candidate for folding into the gate. A checker nothing
  runs does not degrade to weaker enforcement — it degrades to a checker that is
  itself wrong, silently.
- **review only** — nothing mechanical. Some rules resist automation honestly.
  Saying so is the point: an unenforced rule should be visibly unenforced, not
  quietly assumed. A rule that resists a checker gets the next best thing — a
  review question someone has to answer, not a line someone has to remember.

### A new standard's rules start review-only and name their gates

Landing a standard and landing its enforcement in one change is how standards
stall. So the sequence is fixed:

1. The standard lands with every rule registered in
   [`standards/enforcement.md`](standards/enforcement.md), at the tier that
   rule actually holds — for a new standard, usually **review only**.
2. Each rule names, in that ledger, **the gate it is eventually getting** — or
   states plainly that it resists one and will stay review-only.
3. Promoting a rule to gated is its own change, and the ledger row moves with it.

A rule that lands review-only with no proposed gate and no admission that it
cannot have one is not finished. That is exactly the failure the law above
describes, arriving one document earlier.

**The tier describes the rule's enforcement, never the document's standing.** A
merged document is binding — see the writing conventions below.

## The foundation: twelve-factor

**[The Twelve-Factor App](https://12factor.net/) is the ground these standards
are built on**, not a reference we consulted. Config in the environment, logs
as event streams, strict build/release/run separation, disposable processes
that shut down gracefully — most of what the CI standard and the platform
contract say about how a service behaves is twelve-factor, applied to this
fleet with the open choices pinned.

Two consequences for how these documents are written:

- **Where a rule restates a factor, the document cites the factor as its
  justification.** "Logs go to stdout because we said so" is a preference;
  "logs go to stdout per [factor XI](https://12factor.net/logs), because the
  application must not concern itself with routing or storage" is an argument
  a reader can check against a source older and more tested than we are.
  Claiming a well-known idea as a house invention also costs credibility with
  exactly the engineers we want reading these documents.
- **Where a rule departs from a factor, the document says so, in the rule,
  with the reason.** A silent departure is worse than a stated one: the next
  reader assumes we did not know.

What a standard here adds on top of a factor is the part twelve-factor
deliberately leaves open — the *specific* names, formats and endpoints that
make a polyglot fleet interoperable. Factor III says config lives in the
environment; it does not say what the variables are called. That pinning is
ours, and it is the only part that is.

**Known departures: none today.** One tension is open and unsettled rather
than assumed: [factor XII](https://12factor.net/admin-processes) says
admin and management tasks run as one-off processes, while the maintenance
jobs capability on the platform roster is heading toward a registered Job
interface inside the service. Whichever way that lands, the maintenance jobs
standard states the choice against factor XII rather than around it.

## How these documents are written

Two conventions, because both failures are quiet ones.

**A merged document is binding, and says nothing about its own status.** No
document carries a `Status: proposed` or `Status: agreed` header. Review happens
in the pull request; merging it is the approval. A status line on a merged
document is either wrong (it still says "proposed") or noise (it says "agreed",
which every merged document is). What varies per rule is how it is *enforced*,
and that lives in one place: the ledger.

**A document references other documents, never a tracker.** Relative markdown
links between `.md` files, always — a reference a reader can click and open,
not a name they have to go hunting for. An issue or pull request number in
doctrine is a citation to something a reader outside this repository cannot
open, that says nothing once merged, and that ages into a dead reference — a
document citing its own paperwork.

Where a rule depends on a standard **not yet written**, the reference still
has to be a working link, so it points at the row that tracks it:
`[the data-layer standard](standards/platform.md#the-capability-roster)`.
That link resolves today, lands the reader on a row that says "not yet
written", and becomes a direct link to the document when one lands. A bare
name is not a reference and a link to a file that does not exist is a 404;
this is the form that is neither. Pending work is still tracked as issues
here; the documents just do not cite them.

## Non-compliance is tracked where the code is

This repository holds the standard. **It does not hold the list of who is
failing it.**

A repo that does not yet comply has work to do in *its own* issue tracker,
against its own code, prioritized against its own roadmap. Recording that here
turns the standard into a scoreboard, gives every standards change a second
diff to maintain, and puts a client repository's shortcomings in a repository it
will never own.

The rule, therefore: **no document under `standards/` names a repository in
order to describe its state.** Two things are deliberately not covered by that:

- **Incident citations.** "Learned the hard way" evidence naming the repo and
  the run that proved a rule necessary is what makes these documents arguments
  rather than assertions. A citation is history, not a status report.
- **Checker allow-lists.** `tools/` carries per-repo entries because a gate has
  to know what it is currently letting through. Each entry states the gap it
  represents — a debt with a name, not a permission — and the target state for
  every list is empty.

## The standards

Every standard here is binding. The **Enforcement** column says how much of it
is held mechanically today; the ledger says which rule is which.

| Standard | Covers | Enforcement |
|---|---|---|
| [`standards/ci.md`](standards/ci.md) | Pipeline doctrine, the shared job catalog, build/release/publish | largely gated |
| [`standards/enforcement.md`](standards/enforcement.md) | The ledger: every rule, its gate, its tier | — it is the register |
| [`AGENTS.md`](AGENTS.md) | How coding agents work in an Aurum Alpha repository | rules 1-5 gated, rest review |
| [`standards/platform.md`](standards/platform.md) | The platform contract: application-layer opinions as protocols and interface specs, never tools | review, gates named |
| [`standards/identifiers.md`](standards/identifiers.md) | Identifiers and primitive representations: public vs internal ids, the format table, timestamps, money | review, corpus written |
| [`standards/observability.md`](standards/observability.md) | Observability transport and context propagation: W3C trace context, the id vocabulary, OTLP | review, corpus written |
| [`standards/service.md`](standards/service.md) | The service contract: health and readiness, structured logging, configuration, graceful shutdown, runtime provenance | review, live gate available |
| [`standards/http.md`](standards/http.md) | HTTP API conventions: OpenAPI, RFC 9457 errors, cursor pagination, versioning, idempotency, backpressure | review, corpus written |

Standards still to be written are tracked as issues in this repository, and the
platform contract's capability roster names which capability is waiting on one.
Each issue carries the reasoning it was raised with, so the document can be
written from the argument rather than from memory.

## Adding or changing a standard

1. **Open an issue first**, stating the rule and the reasoning. A standard
   arriving as a finished document with no argument attached is a preference
   with formatting.
2. **Write the document under `standards/`.** State the rule, the reasoning, and
   what compliance looks like to a reader outside this repo.
3. **Register every rule in the ledger**, at the tier it actually holds today
   and with the gate it is getting.
4. **Add the row to the index above.**

Changing an existing rule follows the same path. A rule that has been violated
in production gets its incident written into the document beside it — that
evidence is the reason these documents get followed, and the reason the next
person does not re-litigate a decision already paid for once.
