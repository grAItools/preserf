# Using OpenCode in `preserf`

This repo is configured to be driven by **OpenCode** as well as Claude Code.
The two tools share a single set of agent definitions, so you get the same
roles, commands, and verification gate in either. This guide explains how to
_drive_ OpenCode here: how to trigger the four-phase loop, the role subagents,
and the `verify` skill, and how to phrase prompts so the existing configuration
is used without spelling it out.

> New to the harness? Read [`AGENTS.md`](../AGENTS.md) first — it is the
> canonical instructions file and OpenCode loads it automatically.

## How this repo is wired for OpenCode

The canonical definitions live in `.agents/` and are symlinked into `.opencode/`
(and `.claude/`). You never edit the `.opencode/` symlinks directly — edit the
files under `.agents/`.

| `.opencode/…`              | symlink target          | what it holds                             |
| -------------------------- | ----------------------- | ----------------------------------------- |
| `.opencode/agents/`        | `../.agents/subagents/` | the five role subagents                   |
| `.opencode/commands/`      | `../.agents/commands/`  | the `/spec /plan /build /verify` commands |
| `.opencode/skills/`        | `../.agents/skills/`    | the `verify` skill                        |
| `.opencode/opencode.jsonc` | _(real file)_           | OpenCode config (below)                   |

`.opencode/opencode.jsonc` sets three things:

- **`instructions`** — loads [`AGENTS.md`](../AGENTS.md),
  [`docs/architecture.md`](architecture.md), and [`docs/style.md`](style.md) as
  always-on context for the primary agent.
- **`default_agent: "build"`** — the session starts in the full-access `build`
  agent.
- **`permission.bash`** — an allow/deny policy for shell commands (mirrors the
  Claude Code deny list).
- **`experimental.hook`** — auto-format on edit and a verification run at
  session end (see [Hooks & enforcement](#hooks--enforcement)).

> OpenCode loads `.opencode/opencode.json{,c}` as a config source. The main
> [config docs](https://opencode.ai/docs/config/) emphasise the project-root
> `opencode.json`, but a `.opencode/` config file works too.

## Primary agents & modes

OpenCode has two built-in **primary** agents. Cycle between them with **Tab**.

- **`build`** (default) — all tools enabled; use it to execute work.
- **`plan`** — read-only posture (file edits and bash are set to `ask`); use it
  for investigation and planning sessions where you don't want changes landing.

The five role agents in this repo are **subagents**, not primaries — you don't
Tab to them, you reach them through the slash commands or an `@mention` (below).

## The four-phase loop (slash commands)

Type these in the OpenCode TUI. Each command's body tells the primary agent to
delegate to the matching role subagent, then **stop for your review** before the
next phase — the loop is gated, not automatic.

| Command        | Role subagent   | Produces                                     | Stops after         |
| -------------- | --------------- | -------------------------------------------- | ------------------- |
| `/spec <slug>` | `product-owner` | `specs/<YYYY-MM>-<slug>/spec.md` (WHAT/WHY)  | spec written        |
| `/plan [dir]`  | `architect`     | `plan.md` + `tasks.md` (phased, testable)    | plan written        |
| `/build [dir]` | `developer`     | code + ticked `tasks.md`, verified per phase | each phase boundary |
| `/verify`      | `reviewer`      | **GO** / **NEEDS-WORK** verdict              | verdict given       |

`[dir]` is optional and defaults to the most recently modified `specs/*`
directory. A typical feature run:

```
/spec serialize-real-arrays      # product-owner writes spec.md, stops
# …review the spec…
/plan                            # architect writes plan.md + tasks.md, stops
# …review the plan…
/build                           # developer implements phase 1, verifies, stops
/verify                          # reviewer judges phase 1: GO or NEEDS-WORK
/build                           # …next phase, and so on
```

If `/build` finds the plan touches unfamiliar code, it runs an `explorer` pass
first and leaves the summary in `scratch.md` for the developer.

## Triggering subagents directly

You rarely need to name a subagent — the `build` primary auto-delegates via the
Task tool by matching your request against each subagent's `description`. The
descriptions are written so that natural phrasing routes correctly:

| You say…                                      | …routes to      |
| --------------------------------------------- | --------------- |
| "find where the directive parser is wired up" | `explorer`      |
| "how does the `!$SER` expansion work?"        | `explorer`      |
| "turn this idea into a spec"                  | `product-owner` |
| "expand the spec into a plan"                 | `architect`     |
| "implement phase 2"                           | `developer`     |
| "review this diff against the spec"           | `reviewer`      |

To force a specific subagent, **`@mention`** it by file name (the filename is
the agent id):

```
@explorer where is the CLI entry point and what calls the expander?
@reviewer check the current diff against specs/2026-06-…/spec.md
```

Use `@explorer` liberally for read-only investigation — it keeps heavy file
reading out of your main session's context and returns a citation-rich summary.

The five subagents and their access:

| Subagent        | Writes? | Bash?                        | Job                                             |
| --------------- | ------- | ---------------------------- | ----------------------------------------------- |
| `product-owner` | yes     | no                           | author `spec.md`; stop before planning          |
| `architect`     | yes     | no                           | author `plan.md` + `tasks.md`; stop before code |
| `developer`     | yes     | yes                          | implement phase-by-phase, verify, tick tasks    |
| `reviewer`      | no      | read-only + `pixi`/test/lint | GO / NEEDS-WORK verdict, file:line defects      |
| `explorer`      | no      | read-only search/git         | "where is X / how does Y work" summaries        |

## Triggering the `verify` skill

The repo ships one skill, `verify` (`.agents/skills/verify/SKILL.md`). OpenCode
loads it from `.opencode/skills/` and the model fires it on its own when your
message matches the skill's description. You **don't** invoke it by path — you
use one of its trigger phrases:

> "verify", "is this ready", "ready to commit", "check this", or just after a
> non-trivial change.

It runs `pixi run verify`, summarises failures with `file:line` evidence, and
proposes the smallest fix — it never silently skips or disables a failing test.
`/verify` (the Reviewer command) is the heavier, spec-aware cousin: use the
skill for a quick "is the gate green?", use `/verify` to judge a diff against
the spec and plan.

## Writing prompts so the config triggers itself

The whole point of the setup is that you describe intent and the right
command / subagent / skill is selected for you. Phrase per phase:

- **Plan / investigate (read-only):** Tab to the `plan` agent, or just ask
  "how does the Fortran helper module get selected at expansion time?" — this
  lands on `@explorer`. For design, "draft a plan for adding savepoint
  metadata" routes to `architect` (or run `/plan` once a spec exists).
- **Spec:** "I want a feature that lets users serialize derived-type fields —
  write it up as a spec" → `product-owner` (or `/spec derived-type-fields`).
- **Develop:** "implement the next phase from the plan" → `developer` (or
  `/build`). Avoid telling it _how_ to verify or tick tasks — that behavior is
  already in the developer subagent and the hooks.
- **Evaluate:** "is this ready?" fires the `verify` skill; "review the diff
  against the spec and give me a verdict" → `reviewer` (or `/verify`).

Things you do **not** need to say (they're already configured): which files are
the instruction files, where specs live, to run `pixi run verify`, to format
after editing, or to avoid `rm -rf` / force-push.

## Hooks & enforcement

`.opencode/opencode.jsonc` adds an `experimental.hook` block that mirrors the
Claude Code hooks — with two important limits.

- **`file_edited` → auto-format.** After OpenCode edits a `.py`/`.f90`/`.F90`/
  `.f`/`.F` file, it runs `pixi run fmt-py-src` / `pixi run fmt-f-src` on that
  file (OpenCode appends the path). This matches Claude Code's PostToolUse
  auto-format.
- **`session_completed` → verify.** When the session ends, OpenCode runs
  `pixi run verify`. **Caveat:** unlike Claude Code's `Stop` hook, this is
  best-effort — it does **not** block the session or feed failures back into the
  agent so it can fix them. So in OpenCode, the real enforcing gate is running
  **`/verify` during the session** (and CI on the PR), not the end-of-session
  run.
- **Destructive-bash blocking** is handled by `permission.bash` deny rules
  (`git push --force*`, `git reset --hard origin*`, `rm -rf*`). **Caveat:** these
  are matched as command **prefix globs**, so they are weaker than Claude Code's
  substring regex — e.g. `cd x && rm -rf y` would not match `rm -rf*`. For true
  substring-level blocking, add a `.opencode/plugin` with a `tool.execute.before`
  hook that throws on a regex match; the config-only approach above is the
  lighter default.

## Claude Code ↔ OpenCode capability map

| Capability             | Claude Code                         | OpenCode                                                        | Shared source        |
| ---------------------- | ----------------------------------- | --------------------------------------------------------------- | -------------------- |
| Instructions           | `CLAUDE.md` (`@AGENTS.md`)          | `instructions` → `AGENTS.md` + docs                             | `AGENTS.md`          |
| Subagents              | `.claude/agents/`                   | `.opencode/agents/`, `@mention` / Task                          | `.agents/subagents/` |
| Slash commands         | `.claude/commands/`                 | `.opencode/commands/`                                           | `.agents/commands/`  |
| Skills                 | `.claude/skills/`                   | `.opencode/skills/`                                             | `.agents/skills/`    |
| Permissions            | `.claude/settings.json` allow/deny  | `permission.bash` allow/deny                                    | (kept in sync)       |
| Auto-format            | `PostToolUse` hook                  | `experimental.hook.file_edited`                                 | `pixi run fmt-*-src` |
| Verify gate            | `Stop` hook (blocking)              | `experimental.hook.session_completed` (best-effort) + `/verify` | `pixi run verify`    |
| Block destructive bash | `PreToolUse` hook (substring regex) | `permission.bash` deny (prefix glob)                            | —                    |
| Path-scoped rules      | `.claude/rules/`                    | _(no equivalent)_                                               | —                    |

Tool-specific bits (`.claude/rules/`, the `.claude/settings.json` hook
mechanics) live only on the Claude Code side; everything in the **Shared source**
column is edited once under `.agents/` and picked up by both tools.
