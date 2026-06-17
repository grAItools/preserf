# Using Claude Code in this repo

This guide explains how the agentic coding harness in `preserf` is wired and how
to drive it: how to trigger the configured capabilities (skills, subagents,
slash commands, hooks) for different tasks, and how to phrase prompts so the
existing configuration is used without restating it every time.

See also: [`AGENTS.md`](../AGENTS.md) (agent instructions), [`CLAUDE.md`](../CLAUDE.md)
(Claude Code specifics), [`docs/style.md`](style.md), [`docs/testing.md`](testing.md).

## The shape of the harness

Everything lives under `.agents/` and is symlinked into `.claude/` (and
`.opencode/`) so the same definitions serve every tool:

```
.claude/agents    -> ../.agents/subagents   # 5 role agents
.claude/commands  -> ../.agents/commands     # /spec /plan /build /verify
.claude/skills    -> ../.agents/skills       # verify skill
.claude/settings.json                        # hooks + permissions (not symlinked)
.claude/rules/                               # path-scoped rules (currently empty)
```

The design is a **gated four-phase loop** — one slash command per phase, each
backed by a single-purpose subagent that **stops for human review before the
next phase starts**:

```
idea ──/spec──▶ spec.md ──/plan──▶ plan.md + tasks.md ──/build──▶ code ──/verify──▶ GO / NEEDS-WORK
       PO              Architect                     Developer            Reviewer
      (write)          (write)                       (write+bash)         (read+bash)
```

Plus a read-only `explorer` agent any phase can call for codebase Q&A, and three
deterministic hooks that run *outside* the model's reasoning (format, block,
verify).

## The three ways capabilities get triggered

### Manual (you type it)

- **Slash commands**: `/spec <slug>`, `/plan [dir]`, `/build [dir]`, `/verify`.
- **Skill by name**: "use the verify skill".
- **Subagent by name**: "use the explorer subagent to find where X is wired up".

### Automatic by description match (the model decides)

Each subagent and skill has a `description` written as a *trigger*. When your
prompt matches that language, the capability is invoked without you naming it:

- `verify` skill fires on "verify", "is this ready", "ready to commit", "check this", or after any non-trivial edit.
- `explorer` fires on "find where X is implemented", "how does Y work", "what calls Z".
- The role agents fire on their phase cues (see below).

### Deterministic (the harness runs it, not the model)

Configured in `.claude/settings.json`; you cannot prompt around these:

- **PostToolUse (Write|Edit|MultiEdit)** auto-formats `*.py` and `*.f90/.F90/.f/.F` after every write. You never need to ask for formatting.
- **PreToolUse (Bash)** hard-blocks `rm -rf`, `push --force`, `reset --hard`, `DROP TABLE` (exit 2).
- **Stop** runs `pixi run verify` before the agent is allowed to stop; non-zero blocks the stop. This is why "done" means "the gate is green".

Permissions allowlist `pixi:*`, read-only git (`status/diff/log/show`), and
`rg/ls/cat/head/tail/find`; destructive operations are denied.

## Decision guide — which capability for which task

| If you want to… | Trigger | Backed by |
| --- | --- | --- |
| Start a brand-new feature/bug/change | `/spec <slug>` | product-owner |
| Turn an approved spec into a phased plan | `/plan` | architect |
| Implement an approved plan | `/build` | developer |
| Review a finished phase / get a GO verdict | `/verify` | reviewer |
| Just run the gate and triage failures | "verify" / verify skill | — |
| Understand existing code before changing it | "use explorer to …" | explorer |
| One-off trivial fix (typo, one-liner) | plain prompt, then verify | — (skip the loop) |

**Rule of thumb:** net-new feature → run the full loop; small isolated fix →
edit directly, then say "verify"; pure question about the code → explorer.

## Writing prompts so the right phase config is used

The agents are matched on description language. Phrase the request in that
language and the correct agent + output format is selected automatically. Each
phase produces fixed artifacts in `specs/<YYYY-MM>-<slug>/`.

### Phase 1 — Spec (product-owner)

- **Trigger words:** "new feature", "spec out", "I want to add…", or just `/spec append-mode`.
- **What you get:** `spec.md` with Problem / Goal / Users & stakeholders / Success criteria / Non-goals / Open questions. WHAT and WHY only — no file paths or libraries.
- **Prompt tips:** Give the user-facing intent and at least one observable success condition. Don't prescribe implementation — the PO strips it. Expect it to ask *one* clarifying question if ambiguous, then stop for your review.
- **Example:** `/spec zarr-backend` → "Users need `!$SER` output to optionally land in a Zarr store instead of NetCDF4; success = an existing scenario round-trips through Zarr unchanged."

### Phase 2 — Plan (architect)

- **Trigger:** `/plan` after the spec is reviewed (defaults to most recent `specs/*`).
- **What you get:** `plan.md` (Architecture-decisions block + numbered phases, each ≤1 day with explicit Tests and Exit criteria) and a mirrored checkbox `tasks.md`.
- **Prompt tips:** Run only once the spec is approved. New dependency/persistence/protocol choices are surfaced in the **Architecture decisions** block and flagged "ADR needed" — call that out if you already know the decision. It writes no code and stops for review.

### Phase 3 — Build (developer)

- **Trigger:** `/build` after the plan is approved.
- **Behavior baked in:** works one phase at a time; **writes the failing test first** (tests are the spec); makes the smallest change to green; runs `pixi run verify` at every phase boundary; ticks `tasks.md` in the same commit; **stops at each phase boundary** and asks you to `/verify` before continuing.
- **Prompt tips:** You usually just say `/build`. If the plan touches unfamiliar code, ask it (or do it yourself) to run an explorer pass first and drop notes in `scratch.md`. Don't ask it to "skip the test" — it refuses and drafts an ADR instead. It never edits `*/generated/*`.

### Phase 4 — Verify / review (reviewer)

- **Trigger:** `/verify`.
- **What you get:** a **GO / NEEDS-WORK** verdict checking three axes — spec conformance (each criterion has observable evidence), plan conformance (no undocumented detours), implementation quality — plus a citation-rich defect list (`path/file.ext:LINE`). It runs the gate; a red gate is automatic NEEDS-WORK.
- **Loop back:** NEEDS-WORK → `/build` to fix; GO → ship/next phase. The reviewer is read-only — it never fixes, only reports.

### The `verify` skill vs the `/verify` command

These are distinct:

- **verify skill** = "run `pixi run verify`, triage failures, propose smallest fix." Use mid-work: "verify", "is this ready". It does *not* do the spec/plan review.
- **/verify command** = full reviewer pass against spec + plan + diff with a GO verdict. Use at a phase boundary.

## Conventions the agents already know (don't re-specify)

These are enforced by docs + hooks; restating them in prompts is noise:

- **Formatting** — automatic via the PostToolUse hook (ruff / fprettify / dprint).
- **Verification gate** — `pixi run verify` = fmt-check + lint + typecheck + `test-py-with-fortran`; runs on Stop. Fast loop is `pixi run test-py` (<60s). Full slow suite is `pixi run test-all` (not in the gate).
- **Tests are the spec** — a behavior change means changing/adding a test first.
- **Commits** — Conventional Commits 1.0.0 in the **PR title** (squash-merge); branch commits can be freeform.
- **ADRs** — any new dependency/persistence/protocol/auth decision gets an ADR in `docs/adr/` (Nygard format, append-only). The architect flags these.
- **CHANGELOG.md** — Keep-a-Changelog entries under `[Unreleased]`.
- **Working memory** — `scratch.md` is gitignored; promote durable notes into spec/plan/ADR/docs.

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
"use the explorer subagent to find where !$SER directives are parsed"

# Small fix, no ceremony:
"fix the int32 cast guard in m_preserf"  → then  "verify"
```

Three habits that make the harness work for you:

1. Match the phase vocabulary ("spec", "plan", "build", "verify") so the right agent and output format are auto-selected.
2. Respect the stop boundaries — review each artifact before triggering the next phase.
3. Trust the deterministic hooks — don't ask for formatting or for the gate to be run manually before stopping; the harness already does both.
