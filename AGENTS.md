# AGENTS.md — the Aurum Alpha agent standard

This is the standard every Aurum Alpha repository's own `AGENTS.md` is
written to, and the rules themselves. A repository's `AGENTS.md` references
this file for everything it does not need to restate and carries only what is
local. An agent working in any Aurum Alpha repository works under this
document, whether or not that repository restates it.

## Why this exists

What a coding agent is told is an input to the codebase, with the same
standing as a lockfile. It gets one source of truth, versioned and reviewed.
Each tool that arrives brings its own rules directory, and a second copy of
the guidance drifts from the first without anything failing.

## The format is AGENTS.md, and the format is not ours

`AGENTS.md` is an open format, published at <https://agents.md/> and stewarded by
the Agentic AI Foundation at the Linux Foundation. It is a README written for a
coding agent rather than for a person. Writing to it is what makes a repository
legible to an agent nobody here configured.

The format fixes four things. Each one is a rule below rather than a preference:

- **The filename and the location.** `AGENTS.md`, at the root of the repository.
- **The syntax.** Markdown, with no required fields. An agent reads the headings
  and the prose it finds.
- **The scope.** A subtree carries its own `AGENTS.md`, and the file nearest the
  edited code wins. A file further up still governs what the nearer one leaves
  unsaid.
- **The precedence.** An instruction typed into a session outranks every file. An
  agent told to work another way says which rule it is setting aside, and still
  stops where rule 5 stops it.

**The six required sections below are ours.** The format asks for none of them.
A conformant file here answers six questions the format never asked.

**A tool that insists on its own filename gets a symbolic link, never a copy:**

```sh
ln -s AGENTS.md AGENT.md
```

A link cannot disagree with its target. A copy disagrees the first time one of
the two is edited, and nothing goes red when it does. `CLAUDE.md` is the one file
here that is not a link, and rule 1 says why.

## Adoption, and what happens at handover

Every repository has an `AGENTS.md` at its root. It is short. It answers the six
required sections below with what is true *of that repository*. For everything
else it points here:

```markdown
This repository follows the Aurum Alpha agent standard:
https://github.com/aurum-alpha/workflows/blob/main/AGENTS.md
Rules below are additional to it, or state where this repository differs.
Nothing below restates it: a paragraph that could be pasted unchanged into
another repository belongs in the standard, not here.
```

The last two lines are part of the block. They are the one sentence every
repository carries about restatement, so the rule is written once, here.

**A repository built for a client vendors this file instead of linking it.** At
handover the client repository can no longer reach `aurum-alpha/workflows`. A
link then becomes a dead reference to a private repo. That is worse than
nothing, because it reads like guidance that exists. Copy this document to
`docs/agent-standard.md` in that repository, and reference the copy. What it
loses is future updates, which is correct: it is no longer ours.

Nothing here depends on reaching this repository at runtime. Every rule below is
stated so a reader outside Aurum Alpha can follow it.

## The six required sections

A repository's `AGENTS.md` answers all six. Where the standard answer is right,
say so in a line and move on. The section still has to be present. A reader
cannot distinguish "the default applies" from "nobody considered it" by
absence.

| Section | Answers |
|---|---|
| **Source of truth** | Which documents govern, and which wins when they disagree |
| **Work queue** | Where work comes from, and where it does not |
| **Commands** | How to build, test, lint and run this thing, verbatim |
| **Quality gates** | What must pass before a commit, and before a push |
| **Approval** | What an agent is permitted to do unattended, and where it stops |
| **Conventions** | What this repository does differently from the standard |

## The rules

### 1. One source of agent guidance

`AGENTS.md` at the repository root is the source. There is no second copy of
it. A subtree carries its own where it needs one, holding what is local to that
subtree and nothing that already stands above it.

**Two agent tools are supported: Cursor and Claude Code.** That is a closed set,
and it is the reason this rule is enforceable at all. Every tool admitted brings
a directory, every directory acquires a copy of the guidance, and no copy
announces itself. A third tool is a decision someone argues for and this
document records. It is never a directory that appears in a repository and is
discovered later.

Cursor reads `AGENTS.md` directly and needs nothing else.

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. So `CLAUDE.md` exists, and its
first line imports the source:

```markdown
@AGENTS.md
```

**The `@` is load-bearing.** It is Claude Code's import syntax, which expands the
target into context at session start. A markdown link, `See [AGENTS.md](AGENTS.md)`,
is *not* an import. It loads a file whose entire content tells the agent to go
read something it will not go and read.

Claude-specific lines can follow the import. A restatement of anything above
it is not permitted to follow.

Parallel rule trees are not created: no `.clinerules/`, `.kiro/steering/`,
`.rulesync/`, `.roo/`, `.windsurfrules`, `.github/copilot-instructions.md`,
`.cursor/rules/`, `WARP.md`. Not one of these belongs to a supported tool. A
tree for a tool nobody runs is guidance nobody maintains, and agents can still
read it.

**Path-scoped rules for one tool are not created.** `.claude/rules/` is Claude
Code's own mechanism, and a rule written there binds Claude Code alone. Cursor
never reads it, so the next session breaks a rule it was never shown. The pair below
answers the same need and reaches both tools.

**Guidance belonging to one subtree lives in that subtree, as another
`AGENTS.md`.** That is the format's own mechanism, and it does two things at
once. A rule about one package reaches an agent working in that package, and it
stays out of every other session's context. Context is the reason it matters:
adherence falls off past roughly 200 lines in one file.

A nested `AGENTS.md` carries the same pair the root carries, for the same reason:

```text
src/server/api/AGENTS.md    the guidance
src/server/api/CLAUDE.md    one line, @AGENTS.md
```

Claude Code loads a directory's `CLAUDE.md` when it reads a file in that
directory. It does not go looking for a nested `AGENTS.md`. Without the second
file the guidance binds one supported tool and not the other.

**A nested file carries only what is local.** That is the root file's own
relationship to this document, one level down. A paragraph true of the whole
repository belongs at the root. A paragraph true of another repository belongs
here.

**A rule reaching several sibling trees sits where its subject sits.** The root's
table then records what else it governs. Three copies under three directories is
the failure rule 1 exists to stop. The root file is read in every session, so one
line there reaches an agent working in any of them.

**Vendoring a dependency's source drops its agent guidance.** A copied
`AGENTS.md` is another repository's instructions. The nearest-file rule hands
them to an agent editing the copy. They name a work queue, a gate and an approval
path that are not this repository's. The copy is not edited here at all: a
correction moves the pin and re-copies. The tool that vendors the tree excludes
those files the way it excludes git metadata.

*A tool-specific configuration file is not guidance and is out of scope: an MCP
server list, a model selection, an editor setting. The rule governs prose that
tells an agent how to work.*

### 2. The named work queue is the only work queue

Each repository names exactly one tracker in its **Work queue** section: GitHub
Issues, or Linear, or whatever it is. It says explicitly which trackers are
*not* in use. An issue filed in an unused tracker is invisible to everyone
working from the real one. That is worse than an unfiled issue, because it
looks handled.

**Implement one issue at a time.** Do not derive parallel workstreams from a
plan document. A plan says what order things happen in; the tracker says what is
being worked on now.

**One issue per pull request.** Branch names carry the issue reference. Link the
issue in the pull request body. Use closing keywords only where the pull request
actually completes the work.

### 3. The docs win, and a correction lands in the docs

When code and the governing documents disagree, **the documents are right and
the code is a defect**. That holds until someone changes the documents, in
their own change, saying so.

An agent that discovers a document is wrong updates the document. It does not
encode the correction only in code, where the next agent will not find it. It
does not leave the correction only in a chat transcript, a pull request
comment, or an issue thread. **Operational procedures are the sharpest case.**
A new or altered procedure a human has to run lands in the repository's
operations documentation. It lands in the *same* change as the code that
introduced it, or it does not exist.

**A document carries no history of its own drafting.** It states the rule and
the reason. Where an alternative was considered and not taken, it says so and
why, under Decisions. It does not say what the text said before, when a
sentence changed, or which incident taught the rule. The pull request and
the commit message hold that. A correction replaces the wrong sentence; it
does not annotate it. `tools/check-doc-style` flags the phrases history
arrives in.

### 4. Gates pass before commit, and hooks are never skipped

Every gate in the repository's **Quality gates** section passes before a commit,
and again before a push. A failing gate is not deferred to CI to discover.

**`--no-verify` is not available.** Neither is disabling a check, skipping a
test, or narrowing a lint rule to make a change pass. If a gate is wrong, fix
the gate in its own change and say why. Silencing a gate to land a change is the
one act that makes every other rule here unenforceable.

The commands themselves live in the repository's **Commands** section, verbatim
and runnable. An agent never has to reconstruct a command from a CI workflow
file. Per the CI standard's Principle 2, a gate a developer cannot reproduce
locally with one command is a defect in the gate.

**A green that has gone stale is not a green**. Branch protection requires the
branch to be up to date with the default branch before it can merge, org-wide.
A pull request that passed and then fell behind is updated, and CI runs again.
Then the tree that was proved is the tree that lands.
[`standards/010-ci.md`](standards/010-ci.md) carries the throughput cost.

**Bring the branch up to date by rebasing onto the default branch. Merging it
in is also acceptable.** Squash is the merge method, so the branch's history is
discarded either way. A rebase leaves a reviewer a series of commits that are
the change and nothing else; merging leaves a merge commit per update. A rebase
rewrites pushed history and needs a force-push, which costs nobody on a branch
one person or one agent works. Where a branch is shared, merge instead. Never
rewrite history on a branch belonging to someone else.

**Do not report a pull request as landed while it is green but behind.** It is
not mergeable yet. Sitting through the update and the re-run is part of landing
it, not an optional extra. With several pull requests open against one
repository, each merge stales the rest. So they land one at a time, and the
order is a decision rather than an accident.

### 5. The human approval gate

**An agent does not merge, deploy, or close an issue on its own verification.**
Tests passing is evidence the change did not break covered behaviour. It is not
evidence the change does what was asked.

**The gate is at merge, and pushing is not the gate.** Every repository takes
changes into its default branch through a pull request. So a push releases
nothing; it is how the work reaches CI. An agent commits, pushes, and opens or
updates a pull request as soon as the work is coherent. It does not wait to be
told to. What it never does without explicit sign-off is merge that pull
request, deploy it, or close the issue behind it.

Holding a push until someone asks for one buys no safety, because the pull
request is the safety. What it costs is the earliest signal available. A branch
nobody has built is a branch nobody knows is broken, and the failure surfaces
after the review rather than before it.

A repository is permitted to set an *additional* gate earlier, on a named class
of change. Examples: workflow files that publish images, a plan that must be
agreed before implementation. It says so in its own **Approval** section. That
is a narrower hold on specific work, never a reason to sit on an ordinary
change.

An agent reaching the gate posts a handoff and stops. The handoff carries three
things, every time, without being asked:

- **What changed**, in a sentence or two.
- **The exact commands to run** to see it.
- **What to look for**: the expected output, the log line, the field, the
  screen. A reviewer does not have to work out what "working" looks like.

An agent is permitted to comment on the tracked issue while working: progress,
blockers, a link to the pull request. It never closes one on its own say-so.

### 6. Scope discipline

**Change only what the task requires.** Adjacent improvements, tempting
refactors, and cleanups that are obviously correct are still out of scope. They
enlarge the diff a reviewer has to hold in their head. They hide the change
that was actually requested inside changes that were not.

Where an agent sees a real problem outside the task, it **says so and does not
fix it**. The saying is a line in the handoff, or an issue in the named
tracker. That is not timidity. A reviewer approving a five-file diff for a
one-file task is approving the one file and skimming the rest. Everyone
involved knows it.

**Prefer extending what exists to adding something parallel.** A second helper
that nearly duplicates the first gives a codebase two answers to one question.
That is the same failure this whole standards repository exists to prevent, at
a smaller scale.

**An error another product would also raise belongs in the platform log
package.** Add it in `platform-go`, `platform-ts` and `platform-php` together.
One wire `type` lives in `contracts/platform/vocabulary.json`. Add that type
the first time any product needs it. A type stays in one product only when a
second product would not log that failure.

A token refusal keeps its existing name. A denial reason keeps its existing
name. A Keycloak code keeps its existing name.

### 7. Agent guidance carries no mutable state

`AGENTS.md` says how to work in a repository. It never says what that
repository is currently failing. **No count of lint findings, test failures,
open violations or coverage owed appears in agent guidance**, as a total or by
directory, dated or not. The same holds for `CLAUDE.md` and for anything under
`.claude/rules/`.

Three reasons:

- **The number is stale the moment it is written.** A gate re-measures on every
  run. A document does not.
- **Nothing makes it disagree loudly.** A wrong command fails the first person
  who runs it. A wrong count is read, believed, and never tested.
- **An agent reads a measurement as a fact.** Told a tree carries hundreds of
  findings, it plans for hundreds of findings.

State the standing rule instead, which does not expire. Introduce no new
findings. Fix pre-existing ones in files you are already editing. Never silence
one. **Run the gate to learn the number**.

Stating that a job carries `warn_only: true` is fine. That is a line in a
file, and it changes only when someone changes it.

### 8. These standards apply to agent-written code

An agent working in an Aurum Alpha repository is bound by the same standards a
person is. The CI standard in particular is not advisory background. It governs
what a pipeline can look like, how versions are pinned, what can publish, and
what a job can contain. Read [`standards/010-ci.md`](standards/010-ci.md)
before changing anything under `.github/`. In a handed-over repository, read
the vendored copy.

## Enforcement

`tools/check-agent-docs` is the gate, running from `job-ci-conformance.yml`
alongside the other checkers. It proves eight facts:

- `AGENTS.md` exists at the root.
- The six sections are present.
- The Aurum Alpha standard is referenced or vendored.
- No unsupported rule tree exists, `.claude/rules/` included.
- `CLAUDE.md` opens by importing `AGENTS.md`.
- Every nested `AGENTS.md` has a `CLAUDE.md` beside it that imports it, so a
  subtree's guidance reaches both supported tools.
- No vendored tree carries agent guidance of its own.
- No file in the guidance surface states a count of findings, errors,
  warnings or failures. The check reads a number standing immediately before
  a countable defect noun; a backlog described without a figure passes.

The import check is written against the act, *does this file import the
source*, not against length.

What the checker cannot prove stays a review question. That is whether the
work queue is honoured, the approval gate respected, and a correction landed
in the docs. The gate runs inside each repository's own CI, so calling the job is the
adoption. A repository with standing debt says so through the job's `warn_only`
input, in its own `ci.yml`.
