# preserf — Agent Instructions

> README for agents. Read by Codex, OpenCode, Cursor, Amp, Factory, Gemini CLI,
> GitHub Copilot, and (via the `@AGENTS.md` import in `CLAUDE.md`) Claude Code.
> Closest AGENTS.md to the file being edited wins.

A preprocessor for Fortran data serialization directives

## Stack

- Language: **python**
- Package / build manager: **pixi**
- License: MIT
- Tool versions live in `pixi.toml` / `pixi.lock` (single source of truth)

## Commands (prefer these over guessing)

- `make test` — fast unit tests (= `pixi run -e dev pytest`)
- `make lint` — static checks (= `pixi run -e dev lint`)
- `make fmt`  — auto-format (= `pixi run -e dev fmt`)
- `make verify` — full verification gate (what the Claude Code `Stop` hook runs)

If a command above is wrong for your environment, **fix the Makefile**, not
this file.

## Where things live (capabilities, not paths)

- Architecture overview: [`docs/architecture.md`](docs/architecture.md)
- Style guide: [`docs/style.md`](docs/style.md)
- Testing strategy: [`docs/testing.md`](docs/testing.md)
- ADRs (decisions of record): [`docs/adr/`](docs/adr/)
- Per-feature specs: [`specs/<YYYY-MM>-<slug>/`](specs/)

For Claude Code users:

- Skills: `.claude/skills/` (symlinked from `.agents/skills/`)
- Subagents: `.claude/agents/` (symlinked from `.agents/subagents/`)
- Slash commands: `.claude/commands/` (symlinked from `.agents/commands/`) — `/spec`, `/plan`, `/verify`

## Do

- Run `make verify` before claiming a task is done.
- For a net-new feature, create `specs/<YYYY-MM>-<slug>/` and write `spec.md`
  and `plan.md` **before** writing code. See `.agents/commands/spec.md`.
- For a new architectural choice (dependency, framework, persistence, auth),
  add an ADR in `docs/adr/`. ADRs are append-only; supersede with a new file.
- When investigating a large codebase, prefer the `explorer` subagent (read-only)
  over loading large files into the main context.

## Don't

- Don't add a runtime dependency without an ADR.
- Don't run destructive Git: `push --force`, `reset --hard origin/*`,
  history rewrites on shared branches.
- Don't put secrets, hostnames, or per-developer paths in this file —
  they belong in `CLAUDE.local.md` (gitignored).
- Don't auto-generate or expand this file beyond ~200 lines. The instruction
  budget is finite; adding rules degrades adherence to *all* rules.

## Conventions

- Code style: see `docs/style.md`. One worked example > a page of prose.
- Tests are the spec. If you change behaviour, change a test first.
- Commit messages: imperative mood, first line ≤72 chars, no trailing period.
- Branch names: `<initials>/<slug>` for personal branches; bare slug for
  shared feature branches.

## Working memory

Per-feature spec directories use this layout:

```
specs/<YYYY-MM>-<slug>/
├─ spec.md     # WHAT and WHY; no implementation detail
├─ plan.md     # numbered phased plan; each phase has tests
├─ tasks.md    # checkbox list the agent ticks off
└─ scratch.md  # agent's working notes; cleared on completion (gitignored)
```

`scratch.md` is gitignored by default. Promote anything durable into `spec.md`,
`plan.md`, an ADR, or `docs/`.
