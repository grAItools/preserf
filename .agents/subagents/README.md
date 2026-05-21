# Subagents

Cross-tool subagent definitions live here. Each subagent is a single Markdown
file with YAML frontmatter (`name`, `description`, optional `tools`, `model`).

The same files are read by Claude Code (symlinked at `.claude/agents/`) and
OpenCode (symlinked at `.opencode/agents/`). The symlinks are created by the
post-generation hook; if you copy this layout manually, recreate them with:

```sh
ln -s ../.agents/subagents .claude/agents
ln -s ../.agents/subagents .opencode/agents
```

A subagent runs in its own context window. Use them to keep heavy
exploration or repetitive review out of the main session's context.
