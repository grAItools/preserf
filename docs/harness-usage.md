# Using the agentic harness (Claude Code & OpenCode)

`preserf` ships a single agentic coding harness that both **Claude Code** and
**OpenCode** can drive. This guide explains how it is wired and how to trigger
the configured capabilities (skills, subagents, slash commands, hooks) for
different tasks — and how to phrase prompts so the existing `.agents/`
configuration is used without restating conventions every time.

See also: [`AGENTS.md`](../AGENTS.md) (agent instructions),
[`CLAUDE.md`](../CLAUDE.md) (Claude Code specifics), [`docs/style.md`](style.md),
[`docs/testing.md`](testing.md).

## The shared model

The canonical definitions live once under `.agents/` and are symlinked into each
tool's config directory, so the same roles, commands, and skill serve every tool.
**You edit the files under `.agents/`, never the symlinks.**

```
.agents/subagents/  ─┬─►  .claude/agents/      .opencode/agents/      # 5 role agents
.agents/commands/   ─┼─►  .claude/commands/    .opencode/commands/    # /spec /plan /build /verify
.agents/skills/     ─┴─►  .claude/skills/      .opencode/skills/      # verify skill
```

The design is a **gated four-phase loop** — one slash command per phase, each
backed by a single-purpose subagent that **stops for human review before the
next phase starts**:

```
idea ──/spec──▶ spec.md ──/plan──▶ plan.md + tasks.md ──/build──▶ code ──/verify──▶ GO / NEEDS-WORK
       PO              Architect                     Developer            Reviewer
      (write)          (write)                       (write+bash)         (read+bash)
```

Plus a read-only `explorer` agent any phase can call for codebase Q&A. Each
phase writes fixed artifacts under `specs/<YYYY-MM>-<slug>/`.

The five subagents and their access:

| Subagent        | Writes? | Bash?                        | Job                                             |
| --------------- | ------- | ---------------------------- | ----------------------------------------------- |
| `product-owner` | yes     | no                           | author `spec.md`; stop before planning          |
| `architect`     | yes     | no                           | author `plan.md` + `tasks.md`; stop before code |
| `developer`     | yes     | yes                          | implement phase-by-phase, verify, tick tasks    |
| `reviewer`      | no      | read-only + `pixi`/test/lint | GO / NEEDS-WORK verdict, file:line defects      |
| `explorer`      | no      | read-only search/git         | "where is X / how does Y work" summaries        |

## The three ways capabilities get triggered

### 1. Manual (you type it)

- **Slash commands:** `/spec <slug>`, `/plan [dir]`, `/build [dir]`, `/verify`.
- **Skill by name:** "use the verify skill".
- **Subagent by name:** Claude Code — "use the explorer subagent to find where X
  is wired up"; OpenCode — `@explorer find where X is wired up` (the filename is
  the agent id).

### 2. Automatic by description match (the model decides)

Each subagent and skill has a `description` written as a _trigger_. When your
prompt matches that language, the capability fires without you naming it:

- `verify` skill fires on "verify", "is this ready", "ready to commit", "check
  this", or after any non-trivial edit.
- `explorer` fires on "find where X is implemented", "how does Y work", "what
  calls Z".
- The role agents fire on their phase cues (see [per-phase prompting](#writing-prompts-so-the-right-phase-config-is-used)).

### 3. Deterministic (the harness runs it, not the model)

Each tool runs format / block / verify behaviour outside the model's reasoning.
The mechanism differs per tool — see [Claude Code specifics](#claude-code-specifics)
and [OpenCode specifics](#opencode-specifics) — but the intent is the same: you
never need to ask for formatting or for the gate to run.

## Claude Code specifics

Hooks and permissions are configured in `.claude/settings.json` (not symlinked;
Claude Code only). You cannot prompt around the hooks:

- **PostToolUse (`Write|Edit|MultiEdit`)** auto-formats `*.py` and
  `*.f90/.F90/.f/.F` after every write (ruff / fprettify).
- **PreToolUse (`Bash`)** hard-blocks `rm -rf`, `push --force`, `reset --hard`,
  `DROP TABLE` (exit 2).
- **Stop** runs `pixi run verify` before the agent is allowed to stop; non-zero
  blocks the stop. This is why "done" means "the gate is green".

Permissions allowlist `pixi:*`, read-only git (`status/diff/log/show`), and
`rg/ls/cat/head/tail/find`; destructive operations are denied. `.claude/rules/`
holds path-scoped rule fragments (currently empty). Default to **plan mode**
(`shift-tab`) for non-trivial work.

## OpenCode specifics

OpenCode reads `.opencode/opencode.jsonc`, which sets:

- **`instructions`** — loads [`AGENTS.md`](../AGENTS.md),
  [`docs/architecture.md`](architecture.md), [`docs/style.md`](style.md) as
  always-on context.
- **`default_agent: "build"`** — the session starts in the full-access `build`
  primary. OpenCode has two built-in **primary** agents, cycled with **Tab**:
  `build` (all tools) and `plan` (read-only: edits/bash set to `ask`). The five
  role agents above are **subagents**, reached via the slash commands or an
  `@mention`, not by Tab.
- **`permission.bash`** — allow/deny policy mirroring the Claude Code deny list.
- **`experimental.hook`** — the deterministic-behaviour parity layer:
  - `file_edited` → auto-format the edited Python/Fortran file (mirrors Claude
    Code's PostToolUse formatter).
  - `session_completed` → run `pixi run verify` at session end.

**Caveats vs Claude Code (documented so you rely on the right gate):**

- `session_completed` is **best-effort** — unlike Claude Code's `Stop` hook it
  does not block the session or feed failures back to the agent. Treat `/verify`
  run **during** the session, plus CI, as the enforcing gate.
- Destructive-bash blocking is matched as command **prefix globs** (e.g.
  `rm -rf*`), weaker than Claude Code's substring regex — `cd x && rm -rf y`
  slips past. A `.opencode/plugin` with a `tool.execute.before` hook is the
  optional hardening for true substring parity.

| Capability             | Claude Code                         | OpenCode                                                        |
| ---------------------- | ----------------------------------- | --------------------------------------------------------------- |
| Instructions           | `CLAUDE.md` (`@AGENTS.md`)          | `instructions` → `AGENTS.md` + docs                             |
| Subagent invocation    | "use the X subagent"                | `@mention` / auto-delegation (Task tool)                        |
| Auto-format            | `PostToolUse` hook                  | `experimental.hook.file_edited`                                 |
| Verify gate            | `Stop` hook (blocking)              | `experimental.hook.session_completed` (best-effort) + `/verify` |
| Block destructive bash | `PreToolUse` hook (substring regex) | `permission.bash` deny (prefix glob)                            |
| Path-scoped rules      | `.claude/rules/`                    | _(no equivalent)_                                               |

## Decision guide — which capability for which task

| If you want to…                             | Trigger                   | Backed by         |
| ------------------------------------------- | ------------------------- | ----------------- |
| Start a brand-new feature/bug/change        | `/spec <slug>`            | product-owner     |
| Turn an approved spec into a phased plan    | `/plan`                   | architect         |
| Implement an approved plan                  | `/build`                  | developer         |
| Review a finished phase / get a GO verdict  | `/verify`                 | reviewer          |
| Just run the gate and triage failures       | "verify" / verify skill   | —                 |
| Understand existing code before changing it | explorer (name / @)       | explorer          |
| One-off trivial fix (typo, one-liner)       | plain prompt, then verify | — (skip the loop) |

**Rule of thumb:** net-new feature → run the full loop; small isolated fix →
edit directly, then say "verify"; pure question about the code → explorer.

## Writing prompts so the right phase config is used

The agents are matched on description language. Phrase the request in that
language and the correct agent + output format is selected automatically.

### Phase 1 — Spec (product-owner)

- **Trigger words:** "new feature", "spec out", "I want to add…", or `/spec append-mode`.
- **What you get:** `spec.md` with Problem / Goal / Users & stakeholders /
  Success criteria / Non-goals / Open questions. WHAT and WHY only — no file
  paths or libraries.
- **Prompt tips:** Give the user-facing intent and at least one observable
  success condition. Don't prescribe implementation — the PO strips it. Expect
  _one_ clarifying question if ambiguous, then it stops for your review.

### Phase 2 — Plan (architect)

- **Trigger:** `/plan` after the spec is reviewed (defaults to most recent `specs/*`).
- **What you get:** `plan.md` (Architecture-decisions block + numbered phases,
  each ≤1 day with explicit Tests and Exit criteria) and a mirrored checkbox
  `tasks.md`.
- **Prompt tips:** Run only once the spec is approved. New
  dependency/persistence/protocol choices are surfaced in the **Architecture
  decisions** block and flagged "ADR needed". It writes no code and stops.

### Phase 3 — Build (developer)

- **Trigger:** `/build` after the plan is approved.
- **Behaviour baked in:** works one phase at a time; **writes the failing test
  first** (tests are the spec); makes the smallest change to green; runs
  `pixi run verify` at every phase boundary; ticks `tasks.md` in the same commit;
  **stops at each phase boundary** and asks you to `/verify` before continuing.
- **Prompt tips:** You usually just say `/build`. If the plan touches unfamiliar
  code, it runs an explorer pass first and drops notes in `scratch.md`. Don't ask
  it to "skip the test" — it refuses and drafts an ADR instead. It never edits
  `*/generated/*`.

### Phase 4 — Verify / review (reviewer)

- **Trigger:** `/verify`.
- **What you get:** a **GO / NEEDS-WORK** verdict across three axes — spec
  conformance (each criterion has observable evidence), plan conformance (no
  undocumented detours), implementation quality — plus a citation-rich defect
  list (`path/file.ext:LINE`). It runs the gate; a red gate is automatic
  NEEDS-WORK.
- **Loop back:** NEEDS-WORK → `/build` to fix; GO → ship/next phase. The reviewer
  is read-only — it never fixes, only reports.

### The `verify` skill vs the `/verify` command

These are distinct:

- **verify skill** = "run `pixi run verify`, triage failures, propose smallest
  fix." Use mid-work: "verify", "is this ready". It does _not_ do the spec/plan
  review.
- **/verify command** = full reviewer pass against spec + plan + diff with a GO
  verdict. Use at a phase boundary.

## Conventions the agents already know (don't re-specify)

These are enforced by docs + hooks; restating them in prompts is noise:

- **Formatting** — automatic (ruff / fprettify / dprint) via the format hook.
- **Verification gate** — `pixi run verify` = fmt-check + lint + typecheck +
  `test-py-with-fortran`. Fast loop is `pixi run test-py` (<60s); full slow suite
  is `pixi run test-all` (not in the gate).
- **Tests are the spec** — a behaviour change means changing/adding a test first.
- **Commits** — Conventional Commits 1.0.0 in the **PR title** (squash-merge);
  branch commits can be freeform.
- **ADRs** — any new dependency/persistence/protocol/auth decision gets an ADR in
  `docs/adr/` (Nygard format, append-only). The architect flags these.
- **CHANGELOG.md** — Keep-a-Changelog entries under `[Unreleased]`.
- **Working memory** — `scratch.md` is gitignored; promote durable notes into
  spec/plan/ADR/docs.

## Quick-start cheatsheet

```
# Net-new feature (full gated loop, review between each):
/spec my-feature        # PO → spec.md, stops
# (review spec.md)
/plan                   # Architect → plan.md + tasks.md, stops
# (review plan.md)
/build                  # Developer → implements phase 1, runs gate, stops
/verify                 # Reviewer → GO / NEEDS-WORK
/build                  # next phase (or fix NEEDS-WORK) … repeat

# Understand code first:
#   Claude Code: "use the explorer subagent to find where !$SER is parsed"
#   OpenCode:    @explorer find where !$SER directives are parsed

# Small fix, no ceremony:
"fix the int32 cast guard in m_preserf"  → then  "verify"
```

Three habits that make the harness work for you:

1. Match the phase vocabulary ("spec", "plan", "build", "verify") so the right
   agent and output format are auto-selected.
2. Respect the stop boundaries — review each artifact before triggering the next
   phase.
3. Trust the deterministic behaviour — don't ask for formatting or for the gate
   to be run manually; the harness already does both (blocking in Claude Code,
   best-effort + `/verify` in OpenCode).
