# preserf — Agent Instructions

`preserf` is a preprocessor for Fortran data serialization directives
implemented in Python: it expands `!$SER` directives in Fortran source into
explicit serialization calls. Two parts: `src/preserf/` (preprocessor engine

- CLI) and `src/preserf/fortran/` (the Fortran runtime those calls target).

## Toolchain

`pixi` is the single entry point (conda-forge, pinned in `pixi.toml` /
`pixi.lock`). Do not install Python/Fortran tools by hand. If `pixi` is
missing from your shell:

```sh
curl -fsSL https://pixi.sh/install.sh | sh   # then reload $PATH (~/.pixi/bin)
```

Commands (prefer these over guessing):

- `pixi run test-py` — fast Python test suite
- `pixi run test-all` — Python + Fortran ctest + examples (slow)
- `pixi run lint` / `pixi run fmt` — static checks / auto-format
- `pixi run verify` — full verification gate; run before claiming done

## Spec-driven development (OpenSpec)

This repo uses [OpenSpec](https://openspec.dev/). The system's behavior is
specified in `openspec/specs/` (living capability specs: preprocessor, cli,
fortran-runtime, storage, packaging-distribution); project context and rules
for the workflows live in `openspec/config.yaml` and are injected into every
workflow run.

Every non-trivial change goes through the loop, in any harness:

- Explore (optional): think the idea through before planning
- **Propose**: draft `openspec/changes/<change>/` (proposal, delta specs,
  design, tasks) — no code yet
- Review the artifacts, correct them while they are still words
- **Apply**: implement `tasks.md`, checking off each task
- **Archive**: merge the delta specs into `openspec/specs/` and move the
  change to `changes/archive/`

Invoke it by name in your tool (`/opsx:propose` in Claude Code,
`/opsx-propose` in OpenCode and OMP, `$openspec-propose` in Codex) or just
ask in plain language ("propose a change to ..."). The skills are installed
for Claude Code (`.claude/`), Codex (`.agents/skills/`), OpenCode
(`.opencode/`), and OMP (`.omp/`).

One-time per-machine setup (the generated workflow files are committed; the
CLI and its profile are not):

```sh
npm install -g @fission-ai/openspec@latest   # Node >= 20.19 required
openspec config profile                       # optional: add verify/onboard workflows
openspec update                               # refresh installed skills/commands
```

Validate specs and changes headlessly with `openspec validate --all --strict`
(CI runs this too). The expanded profile (adds `verify` and `onboard`) is
per-machine global config; a fresh clone works with the core six workflows.

## Conventions

- Tests are the spec. If you change behaviour, change a test first.
- Code style: see [`docs/style.md`](docs/style.md). Testing strategy:
  [`docs/testing.md`](docs/testing.md).
- Errors carry context: raise `DirectiveError` with file/line, never a bare
  `ValueError` from the preprocessor.
- Commit messages: Conventional Commits 1.0.0, applied to the PR title
  (squash-merge).
- Changelog: log user-facing changes under `[Unreleased]` in `CHANGELOG.md`,
  one concise bullet each, leading with the file/behaviour.
- Architecture decision records live in [`docs/adr/`](docs/adr/) (Nygard
  format, append-only; supersede with a new file, never edit history).
  A new architectural choice (dependency, framework, persistence, auth)
  requires an ADR as part of the change that makes it.
- No new runtime dependency without an ADR.
- Don't run destructive Git on shared branches: no `push --force`, no
  `reset --hard origin/*`, no history rewrites.

## Where things live

- Directive grammar: [`docs/references/directives_specification.md`](docs/references/directives_specification.md)
- Storage model mapping: [`docs/references/storage_mapping.md`](docs/references/storage_mapping.md)
- Fortran runtime README: [`src/preserf/fortran/README.md`](src/preserf/fortran/README.md)
- Per-change history: `openspec/changes/archive/`
