# 10. Adopt OpenSpec as the spec-driven development layer

## Status

Accepted (supersedes ADR 0009)

## Context

[ADR 0009](0009-slash-commands-over-opencode-integration.md) built a
comment-triggered slash-command framework on the opencode GitHub integration,
the tip of a larger in-repo coding harness: the four-phase `/spec` → `/plan`
→ `/build` → `/verify` loop with role subagents under `.agents/`, per-tool
wiring (`.claude/` settings/hooks, `.gemini/`, `.opencode/`), per-feature
spec directories under `specs/`, and a grumpy-reviewer bot. The harness grew
its own maintenance burden: five GitHub workflows with auth gates and model
maps, a lockfile-protected reviewer, hook scripts bootstrapping the
toolchain, and per-tool symlink farms that must stay in sync.

Meanwhile the repo's knowledge was split across `docs/architecture.md`,
`dev/style.md`, `dev/testing.md`, nine ADRs, and a `specs/` tree whose
per-feature directories recorded planning history rather than current
behavior — nothing merged a completed feature's spec back into a living
description of the system.

The maintainer wants one lightweight, harness-agnostic spec layer that any
coding agent can drive, working out of the box with Claude Code, OpenCode,
Codex, and OMP.

## Decision

**Replace the entire harness with OpenSpec (Fission-AI/OpenSpec, CLI
v1.14.x), the lightweight spec-driven development framework.**

- Remove: `.agents/` (commands, subagents, skills, hooks), `.claude/`,
  `.gemini/`, `.opencode/`, `CLAUDE.md`, root `opencode.json`, the
  comment-driven GitHub workflows (`opencode*.yml`, `cmd-*.yml`,
  `grumpy-reviewer*`, `aw/actions-lock.json`, their parser script and test),
  `.copier-answers.yml`, `docs/harness-usage.md`,
  `docs/opencode-commands.md`.
- Adopt: `openspec init --tools claude,codex,opencode,oh-my-pi` installs the
  workflow skills/commands into `.claude/`, `.agents/skills/` (Codex),
  `.opencode/`, and `.omp/`; `openspec/` holds `config.yaml` (project
  context + per-artifact rules + apply/archive guidance), living capability
  specs in `specs/`, and change folders in `changes/` (+ `archive/`).
- Capture the system's current behavior as five capability specs
  (preprocessor, cli, fortran-runtime, storage, packaging-distribution),
  distilled from `docs/architecture.md`, `dev/references/`, and the legacy
  `specs/` tree, which is retired. Deferred work survives as active change
  folders: the 1D string-array metainfo gap (`add-string-array-metainfo`)
  and append mode (`add-append-mode`, speced in the legacy
  `specs/2026-05-fortran-append-mode/` and deferred past v1.0). String data
  fields remain deferred without a spec; open an OpenSpec change when demand
  emerges.
- Every future change runs propose → apply → archive; archiving merges the
  change's delta specs into the living specs, so the code merge and the spec
  merge land in the same PR. CI runs `openspec validate --all --strict`.

Accepted regressions, consciously:

- The deterministic Claude Code Stop-hook verify gate and the Bash
  deny/allow lists (`.claude/settings.json`,
  `.agents/hooks/block-destructive.sh`, OpenCode's `permission.bash`) are
  gone. `openspec/config.yaml` guidance and `AGENTS.md` prose are advisory
  prompt injection, not enforcement; **CI becomes the only hard gate**.
  Agents must run `pixi run verify` before claiming done.
- OpenCode's native formatter config (auto-format on save) is gone; drift
  is caught by `fmt-check` inside `pixi run verify`.
- The grumpy-reviewer and comment-triggered agent bots are gone.
- Root `opencode.json` leaves the repo; the maintainer's provider wiring
  lives in an untracked `opencode.local.json` instead.

Kept: `dev/adr/` (append-only, per Nygard), `dev/references/`,
`dev/style.md`, `dev/testing.md` (project documentation, not harness
configuration), `ci.yml`, `dependabot.yml`, `.devcontainer/`, `CHANGELOG.md`,
and the full `pixi` task surface including the `verify` gate.

## Consequences

- Harness configuration shrinks to: generated OpenSpec skill/command files
  (refreshed by `openspec update`), a slim `AGENTS.md`, `openspec/`, and one
  CI validate job.
- Per-machine setup is real but small: Node ≥ 20.19, `npm install -g
  @fission-ai/openspec`, and optionally `openspec config profile` to enable
  the `verify`/`onboard` workflows (the profile is global machine config,
  not repo state). Documented in `AGENTS.md`.
- Nothing mechanically forces a change folder per PR; the norm lives in
  `AGENTS.md` and `config.yaml` context, and `--skip-specs` exists for pure
  infrastructure changes.
- `openspec validate` catches structural rot, not semantic drift; humans
  and reviewers still own the latter.
- Dropping the harness history is accepted: the legacy `specs/` tree and the
  removed workflows remain recoverable in git history, and ADRs 0008/0009
  stay on disk as the record of what was tried.
