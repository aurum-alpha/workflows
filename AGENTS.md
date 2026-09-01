# AGENTS.md — the Aurum Alpha agent standard

One of the Aurum Alpha engineering standards; read
[`README.md`](README.md) for the charter it is written under and
[`standards/999-enforcement.md`](standards/999-enforcement.md) for what enforces it.

This document is two things at once, deliberately:

1. **The standard** every Aurum Alpha repository's own `AGENTS.md` is written
   to, and
2. **The rules themselves** — so a repository's `AGENTS.md` can reference this
   file for everything it does not need to restate, and carry only what is
   genuinely local.

An agent working in any Aurum Alpha repository is working under this document
whether or not that repository restates it.

## Why this exists

Coding agents write a large and growing share of this organisation's code. What
they are told is therefore not documentation *about* the codebase — it is an
input to the codebase, with the same standing as a lockfile or a lint config.
It gets the same treatment: one source of truth, versioned, reviewed, and the
same across repositories except where a repository genuinely differs.

Left alone, agent guidance fails in one specific way, and it fails quietly.
Each tool that arrives brings its own convention — a rules directory, a dotfile,
a steering folder — and the obvious move is to copy the existing guidance into
the new shape. Nothing announces that a second copy now exists. Nothing fails
when the copies disagree. By the time anyone notices, several of them contradict
each other and nobody knows which one any given agent actually read.

That is Principle 1 of the CI standard — one source of truth per pin — applied
to the one input nobody thought to apply it to.

## Adoption, and what happens at handover

Every repository has an `AGENTS.md` at its root. It is short. It answers the six
required sections below with what is true *of that repository*, and for
everything else it points here:

```markdown
This repository follows the Aurum Alpha agent standard:
https://github.com/aurum-alpha/workflows/blob/main/AGENTS.md
Rules below are additional to it, or state where this repository differs.
```

**A repository built for a client vendors this file instead of linking it.** At
handover the client repository can no longer reach `aurum-alpha/workflows`, so a
link becomes a dead reference to a private repo — worse than nothing, because it
reads like guidance that exists. Copy this document to `docs/agent-standard.md`
in that repository, and reference the copy. What it loses is future updates,
which is correct: it is no longer ours.

Nothing here depends on reaching this repository at runtime. Every rule below is
stated so a reader outside Aurum Alpha can follow it.

## The six required sections

A repository's `AGENTS.md` answers all six. Where the standard answer is right, say
so in a line and move on — the section still has to be present, because a reader
cannot distinguish "the default applies" from "nobody considered it" by absence.

| Section | Answers |
|---|---|
| **Source of truth** | Which documents govern, and which wins when they disagree |
| **Work queue** | Where work comes from, and where it does not |
| **Commands** | How to build, test, lint and run this thing, verbatim |
| **Quality gates** | What must pass before a commit, and before a push |
| **Approval** | What an agent may do unattended, and where it stops |
| **Conventions** | What this repository does differently from the standard |

## The rules

### 1. One source of agent guidance

`AGENTS.md` at the repository root is the source. There is no second copy.

**Two agent tools are supported: Cursor and Claude Code.** That is a closed set,
and it is the reason this rule is enforceable at all. Every tool admitted brings
a directory, every directory acquires a copy of the guidance, and no copy
announces itself. A third tool is a decision someone argues for and this document
records — never a directory that appears in a repository and is discovered later.

Cursor reads `AGENTS.md` directly and needs nothing else.

Claude Code reads `CLAUDE.md`, not `AGENTS.md`. So `CLAUDE.md` exists, and its
first line imports the source:

```markdown
@AGENTS.md
```

**The `@` is load-bearing.** It is Claude Code's import syntax, which expands the
target into context at session start. A markdown link — `See [AGENTS.md](AGENTS.md)` —
is *not* an import: it loads a file whose entire content tells the agent to go
read something it will not go and read. That was this document's own instruction
until it was checked against the tool, and it would have left every adopting repo
with guidance Claude Code never saw. Claude-specific lines may follow the import;
what may not follow is a restatement of anything above it.

Parallel rule trees are not created: no `.clinerules/`, `.kiro/steering/`,
`.rulesync/`, `.roo/`, `.windsurfrules`, `.github/copilot-instructions.md`,
`.cursor/rules/`, `WARP.md`. Not one of these belongs to a supported tool, and a
tree for a tool nobody runs is guidance nobody maintains that agents may still
read.

`.claude/rules/` is the one exception, and it is not a loophole. It is Claude
Code's own path-scoped mechanism: files carrying `paths:` frontmatter that load
only when the agent touches matching code. It exists because guidance that
belongs to one subsystem should not sit in every session's context, and because
adherence falls off past roughly 200 lines in `CLAUDE.md`. It is a **supplement
for a supported tool, never a second copy of `AGENTS.md`** — a rule file
restating what `AGENTS.md` already says is the failure this section exists to
stop, arriving through the one door left open.

*A tool-specific configuration file is not guidance and is out of scope: an MCP
server list, a model selection, an editor setting. The rule governs prose that
tells an agent how to work.*

### 2. The named work queue is the only work queue

Each repository names exactly one tracker — GitHub Issues, or Linear, or
whatever it is — in its **Work queue** section, and says explicitly which
trackers are *not* in use. An issue filed in an unused tracker is invisible to
everyone working from the real one, which is worse than an unfiled issue because
it looks handled.

**Implement one issue at a time.** Do not derive parallel workstreams from a
plan document. A plan says what order things happen in; the tracker says what is
being worked on now.

**One issue per pull request.** Branch names carry the issue reference. Link the
issue in the pull request body, and use closing keywords only where the pull
request actually completes the work.

### 3. The docs win, and a correction lands in the docs

When code and the governing documents disagree, **the documents are right and
the code is a defect** — until someone changes the documents, in their own
change, saying so.

An agent that discovers a document is wrong updates the document. It does not
encode the correction only in code, where the next agent will not find it, and
it does not leave it only in a chat transcript, a pull request comment, or an
issue thread. **Operational procedures are the sharpest case**: a new or altered
procedure a human has to run lands in the repository's operations documentation
in the *same* change as the code that introduced it, or it does not exist.

### 4. Gates pass before commit, and hooks are never skipped

Every gate in the repository's **Quality gates** section passes before a commit,
and again before a push. A failing gate is not deferred to CI to discover.

**`--no-verify` is not available.** Neither is disabling a check, skipping a
test, or narrowing a lint rule to make a change pass. If a gate is wrong, fix
the gate in its own change and say why. Silencing a gate to land a change is the
one act that makes every other rule here unenforceable.

The commands themselves live in the repository's **Commands** section, verbatim
and runnable. An agent should never have to reconstruct a command from a CI
workflow file — and per the CI standard's Principle 2, a gate a developer cannot
reproduce locally with one command is a defect in the gate.

**A green that has gone stale is not a green.** Branch protection requires a
pull request's branch to be up to date with the default branch before it can
merge — on, org-wide. A pull request that passed and then fell behind cannot
land until it is updated and CI has run again, so that the tree which was proved
and the tree which lands are the same tree.
[`standards/010-ci.md`](standards/010-ci.md) carries the reasoning and the throughput
cost; what follows is only the part an agent gets wrong.

**Bring the branch up to date by merging the default branch into it, not by
rebasing.** Both satisfy the check. A rebase rewrites pushed history and needs a
force-push, which invalidates every existing checkout of that branch, a human's
included. The usual argument for rebasing — keeping trunk history clean — does
not apply here, because **squash is the merge method**: the branch's history,
merge commits and all, is discarded at merge and the default branch still gets
exactly one commit. Merging costs nothing and breaks nothing, so it is the
default; rebase only where a repository's **Conventions** section says to.

**Do not report a pull request as landed while it is green but behind.** It is
not mergeable yet. Sitting through the update and the re-run is part of landing
it, not an optional extra, and with several pull requests open against one
repository each merge stales the rest — so they land one at a time, and the
order is a decision rather than an accident.

### 5. The human approval gate

**An agent does not merge, deploy, or close an issue on its own verification.**
Tests passing is evidence the change did not break what was already covered. It
is not evidence the change does what was asked.

**The gate is at merge, and pushing is not the gate.** Every repository takes
changes into its default branch through a pull request, so a push releases
nothing — it is how the work reaches CI. An agent commits, pushes, and opens or
updates a pull request as soon as the work is coherent, and does not wait to be
told to. What it never does without explicit sign-off is merge that pull
request, deploy it, or close the issue behind it.

Holding a push until someone asks for one buys no safety, because the pull
request is the safety. What it costs is the earliest signal available: a branch
nobody has built is a branch nobody knows is broken, and the failure surfaces
after the review rather than before it.

A repository may set an *additional* gate earlier, on a named class of change —
workflow files that publish images, a plan that must be agreed before
implementation — and says so in its own **Approval** section. That is a narrower
hold on specific work, never a reason to sit on an ordinary change.

An agent reaching the gate posts a handoff and stops. The handoff carries three
things, every time, without being asked:

- **What changed**, in a sentence or two.
- **The exact commands to run** to see it.
- **What to look for** — the expected output, the log line, the field, the
  screen. A reviewer should not have to work out what "working" looks like.

An agent may comment on the tracked issue while working — progress, blockers, a
link to the pull request. It never closes one on its own say-so.

### 6. Scope discipline

**Change only what the task requires.** Adjacent improvements, tempting
refactors, and cleanups that are obviously correct are still out of scope: they
enlarge the diff a reviewer has to hold in their head, and they hide the change
that was actually requested inside changes that were not.

Where an agent sees a real problem outside the task, it **says so and does not
fix it** — a line in the handoff, or an issue in the named tracker. That is not
timidity. A reviewer approving a five-file diff for a one-file task is approving
the one file and skimming the rest, and everyone involved knows it.

**Prefer extending what exists to adding something parallel.** A second helper
that does what the first one nearly does is how a codebase acquires two answers
to one question — the same failure this whole standards repository exists to
prevent, at a smaller scale.

### 7. These standards apply to agent-written code

An agent working in an Aurum Alpha repository is bound by the same standards a
person is. The CI standard in particular is not advisory background: it governs
what a pipeline may look like, how versions are pinned, what may publish, and
what a job may contain. Read [`standards/010-ci.md`](standards/010-ci.md) — or the
vendored copy, in a handed-over repository — before changing anything under
`.github/`.

## Enforcement

`tools/check-agent-docs` is the gate, running from `job-ci-conformance.yml`
alongside the existing checkers — so adopting it is a checker change, not twelve
workflow changes. What it proves mechanically: that `AGENTS.md` exists, that the
six sections are present, that the Aurum Alpha standard is referenced or vendored,
that no unsupported rule tree exists, and that `CLAUDE.md` opens by importing
`AGENTS.md`.

That last check is written against the act — *does this file import the
source* — rather than against length. A pointer rule phrased as "keep it short"
would have passed the broken markdown-link version of itself, because that
version was one line and wrong.

What the checker cannot prove: that the work queue is honoured, that the approval
gate is respected, that a correction reached the docs. Those stay review
questions, and [`standards/999-enforcement.md`](standards/999-enforcement.md) says so in
the row rather than implying coverage it lacks.

Repos are held to it by name. A repository not yet listed still has its findings
printed on every run — a known gap with somewhere to read it, which is what
distinguishes it from a repository nobody has looked at.
