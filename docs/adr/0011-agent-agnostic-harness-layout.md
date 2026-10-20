# 11. Agent-agnostic layout for harness configuration files

## Status

Accepted

## Context

After adopting OpenSpec (ADR 0010), `openspec init --tools
claude,codex,opencode,oh-my-pi` installed its workflow files per harness:
six skill directories in each of `.claude/skills/`, `.agents/skills/`,
`.opencode/skills/`, and `.omp/skills/` (24 committed copies of what is
byte-identical except one invocation-spelling line), plus per-harness command
files. Four copies of the same skills can drift apart — an anti-pattern for
committed agent configuration — and a hand-edit to one copy silently
diverges the other three.

The agent-agnostic repository pattern classifies every piece of agent
configuration into exactly three categories: **portable** assets (same
format across agents) are stored once in `.agents/` and symlinked into
agent-native directories; **generated** assets (same data, different format)
have a canonical source that a tool renders per agent; **agent-specific**
assets stay in their native directory.

## Decision

**Classify every harness file and deduplicate the portable layer.**

- Skills are portable: the canonical copy lives in `.agents/skills/` (which
  Codex reads directly, and which the OpenSpec CLI manages via its
  `.openspec-target` marker). `.claude/skills/<name>`, `.opencode/skills/<name>`,
  and `.omp/skills/<name>` are committed symlinks to
  `../../.agents/skills/<name>`. The canonical copy keeps the tool-agnostic
  invocation spelling, so no harness reads a wrong instruction.
- Per-harness command files (`.claude/commands/opsx/`, `.opencode/commands/`,
  `.omp/commands/`) are generated output: they legitimately differ per
  harness (Claude-specific frontmatter, `$ARGUMENTS` vs `$@` interpolation,
  invocation spelling). Their single source of truth is the `openspec` CLI;
  they are never hand-edited.
- `AGENTS.md` stays the canonical instruction file; `CLAUDE.md` is a pointer
  (`@AGENTS.md`), per the same pattern.
- `.agents/AGENTS.md` documents the layout and rules; `.agents/scripts/
  link-agent-skills.sh` creates/repairs/prunes the symlinks and offers a
  `--check` mode. `pixi run agent-config` runs the sync, and `agent-config-check`
  is part of the `pixi run verify` gate so drift fails CI.
- There is no MCP configuration in this repo, so the generated-config layer
  of the pattern is not applicable; nothing else is agent-specific after
  ADR 0010.

## Consequences

- The 24 skill copies collapse to 6; any skill edit lands in exactly one
  file, and every harness reads it through its symlink.
- `openspec update` writes through the symlinks (last harness wins), so the
  canonical copy may pick up a harness-flavored invocation-spelling line —
  cosmetic, since every rendering also says "or ask me to apply this change";
  `openspec init` on a missing directory recreates real files. In both cases
  the workflow is the same: re-run `pixi run agent-config`, review the diff,
  and commit. The verify gate catches a forgotten re-link.
- The per-harness command files remain four-way-different by design; their
  drift risk is bounded because only the `openspec` CLI writes them.
