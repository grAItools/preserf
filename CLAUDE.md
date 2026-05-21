@AGENTS.md

# Claude Code specifics

- Default to **plan mode** (`shift-tab` to enter) for non-trivial work.
- Use **TodoWrite** liberally; it doubles as harness echo and helps you stay
  on track during long runs.
- **Skills** are under `.claude/skills/` (symlink to `.agents/skills/`).
  Invoke by capability, e.g. "use the verify skill".
- **Subagents** are under `.claude/agents/` (symlink to `.agents/subagents/`).
  Be explicit: "use the explorer subagent to find where X is wired up".
- **Slash commands** are under `.claude/commands/`: `/spec`, `/plan`, `/verify`.
- **Hooks** in `.claude/settings.json` enforce: auto-format on Write/Edit,
  block destructive bash, run `make verify` on Stop. They are deterministic
  and run outside your reasoning chain — don't try to work around them.

# Working with this repo

- Before claiming "done", run `/verify` (or `make verify` directly).
- When you `/compact`, prefer `/compact <focus>` over bare `/compact` so the
  preserved context stays task-relevant.
- Use `/clear` between unrelated tasks — context bleed degrades performance.
