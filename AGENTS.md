# AGENTS.md — the Aurum Alpha agent standard

Status: **agreed 2026-08-21, review only.** One of the Aurum Alpha engineering
standards; read [`STANDARDS.md`](STANDARDS.md) for the charter it is written
under and [`standards/enforcement.md`](standards/enforcement.md) for what
enforces it.

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
stated so a reader outside the fleet can follow it.

## The six required sections

A repository's `AGENTS.md` answers all six. Where the fleet answer is right, say
so in a line and move on — the section still has to be present, because a reader
cannot distinguish "the default applies" from "nobody considered it" by absence.

| Section | Answers |
|---|---|
| **Source of truth** | Which documents govern, and which wins when they disagree |
| **Work queue** | Where work comes from, and where it does not |
| **Commands** | How to build, test, lint and run this thing, verbatim |
| **Quality gates** | What must pass before a commit, and before a push |
| **Approval** | What an agent may do unattended, and where it stops |
| **Conventions** | What this repository does differently from the fleet |

## The rules

### 1. One source of agent guidance

`AGENTS.md` at the repository root is the source. There is no second copy.

Per-tool files that a tool will only find at its own path — `CLAUDE.md`,
`.github/copilot-instructions.md`, and whatever arrives next — are **pointers**,
not copies:

```markdown
See [AGENTS.md](AGENTS.md).
```

That is the whole file. A pointer that grows a second paragraph of real guidance
has become a copy, and copies diverge — that is not a prediction, it is the
observed failure this rule exists to stop.

Parallel rule trees are not created: no `.clinerules/`, `.kiro/steering/`,
`.rulesync/`, `.roo/`, `.windsurfrules`, `.cursor/rules/` holding content of
their own. Where a tool cannot be pointed at `AGENTS.md` and can only read its
own directory, that directory is **generated** from `AGENTS.md` by a committed
script and never hand-edited — and the generator's existence is a gap worth
closing, not a pattern worth spreading.

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

### 5. The human approval gate

**An agent does not merge, deploy, or close an issue on its own verification.**
Tests passing is evidence the change did not break what was already covered. It
is not evidence the change does what was asked.

Each repository states where its line sits — some stop before commit, some
before push, some before merge. Wherever it sits, an agent reaching it posts a
handoff and stops. The handoff carries three things, every time, without being
asked:

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

### 7. Fleet standards apply to agent-written code

An agent working in an Aurum Alpha repository is bound by the same standards a
person is. The CI standard in particular is not advisory background: it governs
what a pipeline may look like, how versions are pinned, what may publish, and
what a job may contain. Read [`standards/ci.md`](standards/ci.md) — or the
vendored copy, in a handed-over repository — before changing anything under
`.github/`.

## Enforcement

The whole standard lands **review only**, per the charter's sequence: a standard
and its gate are separate changes, and coupling them is how standards stall.

The proposed gate is `tools/check-agent-docs`, running from
`job-ci-conformance.yml` alongside the existing checkers — so adopting it is a
checker change, not twelve workflow changes. What it can prove mechanically:
that `AGENTS.md` exists, that the six sections are present, that the fleet
standard is referenced or vendored, that no unlisted rule tree has appeared, and
that per-tool pointer files are still pointers rather than copies.

What it cannot prove: that the work queue is honoured, that the approval gate is
respected, that a correction reached the docs. Those stay review questions, and
[`standards/enforcement.md`](standards/enforcement.md) says so in the row rather
than implying coverage it lacks.

Rules 1 and 5 are the two most worth gating early, for opposite reasons. Rule 1
fails by silent accumulation and is trivially checkable. Rule 5 fails once,
expensively, and cannot be checked at all.
