# preserf — Agent Instructions

`preserf` is a preprocessor for Fortran data serialization directives
implemented in Python. It expands `!$SER` directives in Fortran
source into explicit serialization calls implemented in helper modules.

The source code is split into two main parts:

- `src/preserf/`: the preprocessor engine and CLI.
- `src/preserf/fortran/`: Fortran helper modules that provide the runtime API
  targeted by generated code.

## Stack

- Language: **python**
- Package / build manager: **pixi**
- License: MIT
- Tool versions live in `pixi.toml` / `pixi.lock` (single source of truth);
  for `pixi` install steps and environment setup see:
  [`docs/tool-bootstrap.md`](docs/tool-bootstrap.md).

## Commands (prefer these over guessing)

- `pixi run test-py` — fast Python test suite (unit + integration; integration skips without the Fortran binary)
- `pixi run test-all` — Python + Fortran ctest + examples (slow; not in `verify`)
- `pixi run lint` — static checks
- `pixi run fmt` — auto-format
- `pixi run verify` — full verification gate (what the Claude Code `Stop` hook runs)

If a command above is wrong for your environment, **fix the pixi.toml file**, not
this file.

## Where things live (capabilities, not paths)

- Architecture overview: [`docs/architecture.md`](docs/architecture.md)
- Style guide: [`docs/style.md`](docs/style.md)
- Testing strategy: [`docs/testing.md`](docs/testing.md)
- ADRs (decisions of record): [`docs/adr/`](docs/adr/) — Nygard format
- Reference docs (specs / schemas too detailed for `docs/`): [`docs/references/`](docs/references/)
- Per-feature specs: [`specs/<YYYY-MM>-<slug>/`](specs/)
- Per-PR release history: [`CHANGELOG.md`](CHANGELOG.md)
- Supported agents & how to add one: [`.agents/README.md`](.agents/README.md)

## Do

- `pixi` is bootstrapped automatically at session start by
  [`.agents/hooks/ensure-pixi.sh`](.agents/hooks/ensure-pixi.sh); if you land in a
  bare shell without it, run that script (details in `docs/tool-bootstrap.md`).
- Run `pixi run verify` before claiming a task is done.
- For a net-new feature, follow the four-phase loop:
  `/spec` (Product Owner) → `/plan` (Architect) → `/build` (Developer)
  → `/verify` (Reviewer). Each phase stops for review before the next
  begins. See `.agents/commands/` and `.agents/subagents/`.
- For a new architectural choice (dependency, framework, persistence, auth),
  add an ADR in `docs/adr/`. ADRs are append-only; supersede with a new file.
- When investigating a large codebase, prefer the `explorer` subagent (read-only)
  over loading large files into the main context.

## Don't

- Don't add a runtime dependency without an ADR.
- Don't run destructive Git: `push --force`, `reset --hard origin/*`,
  history rewrites on shared branches.
- Don't put secrets, hostnames, or per-developer paths in this file —
  they belong in a git-ignored file (e.g `AGENTS.local.md` or `CLAUDE.local.md`).
- Don't auto-generate or expand this file beyond ~200 lines. The instruction
  budget is finite; adding rules degrades adherence to _all_ rules.

## Conventions

- Code style: see `docs/style.md`. One worked example > a page of prose.
- Tests are the spec. If you change behaviour, change a test first.
- Commit messages: **Conventional Commits 1.0.0** — apply the format to the **PR title** (squash-merge).
  See [`docs/style.md`](docs/style.md#commit-messages) for the format,
  type list, breaking-change syntax, examples, and full merge-strategy
  guidance.
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
